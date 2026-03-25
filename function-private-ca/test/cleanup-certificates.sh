#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
KEY_VAULT="kv-dev-aue-dcert-poc-001"
VM_IP="10.140.34.6"
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

echo "========================================="
echo "Certificate Cleanup"
echo "========================================="
echo ""
echo "This will delete:"
echo "  - Intermediate CA certificate"
echo "  - All device certificates (secrets)"
echo "  - All revocation records"
echo ""
echo "Root CA will be preserved."
echo ""
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Running cleanup on VM (required for private endpoints)..."
echo ""

# Create cleanup script on VM
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP << 'REMOTE_SCRIPT'
set -e

RESOURCE_GROUP="rg-dev-aue-dcert-poc"
KEY_VAULT="kv-dev-aue-dcert-poc-001"

echo "[1/3] Deleting intermediate CA certificate..."

# Delete intermediate CA certificate
az keyvault certificate delete \
    --vault-name $KEY_VAULT \
    --name device-intermediate-ca 2>/dev/null || echo "  (Intermediate CA not found or already deleted)"

# Purge it (soft delete)
az keyvault certificate purge \
    --vault-name $KEY_VAULT \
    --name device-intermediate-ca 2>/dev/null || echo "  (Nothing to purge)"

echo "✅ Intermediate CA deleted"
echo ""

echo "[2/3] Deleting all device certificates..."

# List all secrets ending with -cert (device certificates)
DEVICE_CERTS=$(az keyvault secret list \
    --vault-name $KEY_VAULT \
    --query "[?ends_with(name, '-cert')].name" -o tsv)

if [ -z "$DEVICE_CERTS" ]; then
    echo "  No device certificates found"
else
    for cert_name in $DEVICE_CERTS; do
        echo "  Deleting: $cert_name"
        az keyvault secret delete \
            --vault-name $KEY_VAULT \
            --name $cert_name 2>/dev/null || echo "    Failed to delete $cert_name"
        
        # Purge soft-deleted secret
        az keyvault secret purge \
            --vault-name $KEY_VAULT \
            --name $cert_name 2>/dev/null || echo "    Nothing to purge for $cert_name"
    done
    echo "✅ Device certificates deleted"
fi

echo ""
echo "[3/3] Deleting all revocation records..."

# List all secrets ending with -revoked
REVOKED_RECORDS=$(az keyvault secret list \
    --vault-name $KEY_VAULT \
    --query "[?ends_with(name, '-revoked')].name" -o tsv)

if [ -z "$REVOKED_RECORDS" ]; then
    echo "  No revocation records found"
else
    for record_name in $REVOKED_RECORDS; do
        echo "  Deleting: $record_name"
        az keyvault secret delete \
            --vault-name $KEY_VAULT \
            --name $record_name 2>/dev/null || echo "    Failed to delete $record_name"
        
        az keyvault secret purge \
            --vault-name $KEY_VAULT \
            --name $record_name 2>/dev/null || echo "    Nothing to purge for $record_name"
    done
    echo "✅ Revocation records deleted"
fi

echo ""
echo "========================================="
echo "✅ Cleanup Complete"
echo "========================================="
REMOTE_SCRIPT

echo ""
echo "Next steps:"
echo "1. Recreate intermediate CA: ./create-intermediate-ca.sh"
echo "2. Issue new device certificates: ./issue-certificate.sh device-001"
echo ""
