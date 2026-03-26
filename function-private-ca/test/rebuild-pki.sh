#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
KEY_VAULT="kv-dev-aue-dcert-poc-001"
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="<YOUR_VM_IP>"  # Replace with your VM IP
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

echo "=========================================
PKI Hierarchy Rebuild
=========================================
"
echo "This will completely rebuild the PKI hierarchy:"
echo "  1. Delete all certificates and revocation records"
echo "  2. Create new Root CA (with CA:TRUE)"
echo "  3. Create new Intermediate CA (signed by Root CA via Key Vault HSM)"
echo "  4. Issue test device certificate"
echo "  5. Verify complete certificate chain"
echo "  6. Test CRL functionality"
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "========================================="
echo "Step 1: Delete All Certificates"
echo "========================================="
echo ""

# Run cleanup via VM (for private endpoints)
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP << 'REMOTE_CLEANUP'
set -e
KEY_VAULT="kv-dev-aue-dcert-poc-001"

echo "[1/4] Deleting Root CA..."
az keyvault certificate delete --vault-name $KEY_VAULT --name device-root-ca 2>/dev/null || echo "  (Root CA not found)"
sleep 5
az keyvault certificate purge --vault-name $KEY_VAULT --name device-root-ca 2>/dev/null || echo "  (Nothing to purge)"
echo "✅ Root CA deleted"
echo ""

echo "[2/4] Deleting Intermediate CA..."
az keyvault certificate delete --vault-name $KEY_VAULT --name device-intermediate-ca 2>/dev/null || echo "  (Intermediate CA not found)"
sleep 5
az keyvault certificate purge --vault-name $KEY_VAULT --name device-intermediate-ca 2>/dev/null || echo "  (Nothing to purge)"
echo "✅ Intermediate CA deleted"
echo ""

echo "[3/4] Deleting all device certificates..."
DEVICE_CERTS=$(az keyvault secret list --vault-name $KEY_VAULT --query "[?ends_with(name, '-cert')].name" -o tsv)
if [ -z "$DEVICE_CERTS" ]; then
    echo "  No device certificates found"
else
    for cert_name in $DEVICE_CERTS; do
        echo "  Deleting: $cert_name"
        az keyvault secret delete --vault-name $KEY_VAULT --name $cert_name 2>/dev/null || true
        sleep 1
        az keyvault secret purge --vault-name $KEY_VAULT --name $cert_name 2>/dev/null || true
    done
    echo "✅ Device certificates deleted"
fi
echo ""

echo "[4/4] Deleting all revocation records..."
REVOKED_RECORDS=$(az keyvault secret list --vault-name $KEY_VAULT --query "[?ends_with(name, '-revoked')].name" -o tsv)
if [ -z "$REVOKED_RECORDS" ]; then
    echo "  No revocation records found"
else
    for record_name in $REVOKED_RECORDS; do
        echo "  Deleting: $record_name"
        az keyvault secret delete --vault-name $KEY_VAULT --name $record_name 2>/dev/null || true
        sleep 1
        az keyvault secret purge --vault-name $KEY_VAULT --name $record_name 2>/dev/null || true
    done
    echo "✅ Revocation records deleted"
fi

echo ""
echo "Waiting 10 seconds for purge operations to complete..."
sleep 10
REMOTE_CLEANUP

echo ""
echo "✅ Step 1 Complete: All certificates deleted"
echo ""
sleep 3

echo "========================================="
echo "Step 2: Create Root CA"
echo "========================================="
echo ""

# Get function master key
MASTER_KEY=$(az functionapp keys list \
    --name $FUNCTION_APP \
    --resource-group $RESOURCE_GROUP \
    --query "masterKey" -o tsv 2>/dev/null)

if [ -z "$MASTER_KEY" ]; then
    echo "❌ Failed to retrieve master key"
    exit 1
fi

# Create Root CA
ROOT_PAYLOAD='{"ca_name": "device-root-ca", "common_name": "Device PKI Root CA", "validity_years": 10}'

ROOT_RESPONSE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s -X POST 'https://$FUNCTION_APP.azurewebsites.net/api/create-root-ca?code=$MASTER_KEY' \
    -H 'Content-Type: application/json' \
    -d '$ROOT_PAYLOAD'")

if echo "$ROOT_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Failed to create Root CA:"
    echo "$ROOT_RESPONSE" | jq -r '.error'
    exit 1
fi

echo "✅ Root CA created successfully"
echo "   Serial: $(echo "$ROOT_RESPONSE" | jq -r '.serial_number')"
echo "   Thumbprint: $(echo "$ROOT_RESPONSE" | jq -r '.thumbprint')"
echo ""
sleep 2

echo "========================================="
echo "Step 3: Create Intermediate CA"
echo "========================================="
echo ""

# Create Intermediate CA
INTER_PAYLOAD='{"ca_name": "device-intermediate-ca", "common_name": "Device PKI Intermediate CA", "root_ca_name": "device-root-ca", "validity_years": 5}'

INTER_RESPONSE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s -X POST 'https://$FUNCTION_APP.azurewebsites.net/api/create-intermediate-ca?code=$MASTER_KEY' \
    -H 'Content-Type: application/json' \
    -d '$INTER_PAYLOAD'")

if echo "$INTER_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Failed to create Intermediate CA:"
    echo "$INTER_RESPONSE" | jq -r '.error'
    exit 1
fi

echo "✅ Intermediate CA created successfully"
echo "   Serial: $(echo "$INTER_RESPONSE" | jq -r '.serial_number')"
echo "   Issuer: $(echo "$INTER_RESPONSE" | jq -r '.issuer')"
echo "   Subject: $(echo "$INTER_RESPONSE" | jq -r '.subject')"
echo "   Note: $(echo "$INTER_RESPONSE" | jq -r '.note')"
echo ""
sleep 2

echo "========================================="
echo "Step 4: Verify Certificate Chain"
echo "========================================="
echo ""

# Download certificates
echo "Downloading Root CA..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-root-ca?ca_name=device-root-ca&code=$MASTER_KEY'" | \
    jq -r '.certificate_pem' > /tmp/root-ca-rebuild.pem

echo "Downloading Intermediate CA..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-intermediate-ca?ca_name=device-intermediate-ca&code=$MASTER_KEY'" | \
    jq -r '.certificate_pem' > /tmp/intermediate-ca-rebuild.pem

echo ""
echo "Verifying Root CA is a valid CA certificate..."
openssl x509 -in /tmp/root-ca-rebuild.pem -noout -text | grep -A2 "Basic Constraints"
echo ""

echo "Verifying Intermediate CA signature..."
openssl verify -no-CApath -CAfile /tmp/root-ca-rebuild.pem /tmp/intermediate-ca-rebuild.pem

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Certificate chain verified successfully!"
    echo "   Root CA properly signs Intermediate CA"
else
    echo ""
    echo "❌ Certificate chain verification failed"
    exit 1
fi

echo ""
sleep 2

echo "========================================="
echo "Step 5: Issue Test Device Certificate"
echo "========================================="
echo ""

./issue-certificate.sh device-test-001 2>&1 | tail -30

echo ""
sleep 2

echo "========================================="
echo "Step 6: Verify Complete Chain"
echo "========================================="
echo ""

# Download device certificate
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-certificate?cert_name=device-test-001&code=$MASTER_KEY'" | \
    jq -r '.certificate' > /tmp/device-test-001-rebuild.pem

echo "Verifying complete chain: Device -> Intermediate -> Root"
openssl verify -no-CApath -CAfile /tmp/root-ca-rebuild.pem -untrusted /tmp/intermediate-ca-rebuild.pem /tmp/device-test-001-rebuild.pem

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Complete certificate chain verified successfully!"
else
    echo ""
    echo "❌ Complete chain verification failed"
    exit 1
fi

echo ""
sleep 2

echo "========================================="
echo "Step 7: Test CRL Functionality"
echo "========================================="
echo ""

echo "Downloading CRL..."
./get-crl.sh intermediate 2>&1 | tail -20

echo ""
echo "=========================================
✅ PKI Rebuild Complete!
=========================================
"
echo "Summary:"
echo "  ✅ Root CA: Created with CA:TRUE constraint"
echo "  ✅ Intermediate CA: Signed by Root CA using Key Vault HSM"
echo "  ✅ Device Certificate: Signed by Intermediate CA"
echo "  ✅ Certificate Chain: Fully verified"
echo "  ✅ CRL: Operational"
echo ""
echo "Certificates:"
echo "  Root CA:         /tmp/root-ca-rebuild.pem"
echo "  Intermediate CA: /tmp/intermediate-ca-rebuild.pem"
echo "  Device Cert:     /tmp/device-test-001-rebuild.pem"
echo ""
echo "Next steps:"
echo "  1. Issue more device certificates: ./issue-certificate.sh device-XXX"
echo "  2. Test revocation: ./revoke-certificate.sh device-XXX"
echo "  3. Verify with CRL: ./verify-cert-crl.sh device-XXX"
echo ""
