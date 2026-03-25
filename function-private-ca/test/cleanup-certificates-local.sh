#!/bin/bash

# Cleanup certificates (LOCAL VERSION)
# Usage: ./cleanup-certificates-local.sh
#
# PREREQUISITES:
# - Azure CLI logged in with appropriate permissions
#
# This will delete:
#   - Intermediate CA certificate
#   - All device certificates (secrets)
#   - All revocation records
#
# Root CA will be preserved.

set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
KEY_VAULT="kv-dev-aue-dcert-poc-001"

echo "========================================="
echo "Certificate Cleanup (Local)"
echo "========================================="
echo ""
echo "Key Vault: $KEY_VAULT"
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
echo "[1/3] Deleting intermediate CA certificate..."

# Delete intermediate CA certificate
az keyvault certificate delete \
    --vault-name $KEY_VAULT \
    --name device-intermediate-ca 2>/dev/null && echo "  Deleted: device-intermediate-ca" || echo "  (Intermediate CA not found or already deleted)"

# Wait a moment for delete to propagate
sleep 2

# Purge it (soft delete recovery)
az keyvault certificate purge \
    --vault-name $KEY_VAULT \
    --name device-intermediate-ca 2>/dev/null && echo "  Purged: device-intermediate-ca" || echo "  (Nothing to purge)"

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
    CERT_COUNT=$(echo "$DEVICE_CERTS" | wc -l | tr -d ' ')
    echo "  Found $CERT_COUNT device certificate(s)"
    echo ""
    
    for cert_name in $DEVICE_CERTS; do
        echo "  Deleting: $cert_name"
        az keyvault secret delete \
            --vault-name $KEY_VAULT \
            --name $cert_name 2>/dev/null || echo "    Failed to delete $cert_name"
        
        # Small delay to avoid rate limiting
        sleep 1
        
        # Purge soft-deleted secret
        az keyvault secret purge \
            --vault-name $KEY_VAULT \
            --name $cert_name 2>/dev/null || echo "    Nothing to purge for $cert_name"
    done
    echo ""
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
    RECORD_COUNT=$(echo "$REVOKED_RECORDS" | wc -l | tr -d ' ')
    echo "  Found $RECORD_COUNT revocation record(s)"
    echo ""
    
    for record_name in $REVOKED_RECORDS; do
        echo "  Deleting: $record_name"
        az keyvault secret delete \
            --vault-name $KEY_VAULT \
            --name $record_name 2>/dev/null || echo "    Failed to delete $record_name"
        
        # Small delay to avoid rate limiting
        sleep 1
        
        az keyvault secret purge \
            --vault-name $KEY_VAULT \
            --name $record_name 2>/dev/null || echo "    Nothing to purge for $record_name"
    done
    echo ""
    echo "✅ Revocation records deleted"
fi

echo ""
echo "========================================="
echo "✅ Cleanup Complete"
echo "========================================="
echo ""
echo "Current state:"
echo "  ✅ Root CA:           Preserved"
echo "  ❌ Intermediate CA:   Deleted"
echo "  ❌ Device Certs:      Deleted"
echo "  ❌ Revocation Records: Deleted"
echo ""
echo "Next steps:"
echo "1. Recreate intermediate CA: ./create-intermediate-ca-local.sh"
echo "2. Issue new device certificates: ./issue-certificate-local.sh device-001"
echo ""
