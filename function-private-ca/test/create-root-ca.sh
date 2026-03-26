#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="<YOUR_VM_IP>"  # Replace with your VM IP
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

# CA configuration
CA_NAME="${1:-device-root-ca}"
COMMON_NAME="${2:-Device PKI Root CA}"
VALIDITY_YEARS="${3:-10}"

echo "========================================="
echo "Create Root CA"
echo "========================================="
echo "CA Name:      $CA_NAME"
echo "Common Name:  $COMMON_NAME"
echo "Validity:     $VALIDITY_YEARS years"
echo ""

# Get function master key
echo "[1/2] Retrieving function master key..."
MASTER_KEY=$(az functionapp keys list \
    --name $FUNCTION_APP \
    --resource-group $RESOURCE_GROUP \
    --query "masterKey" -o tsv 2>/dev/null)

if [ -z "$MASTER_KEY" ]; then
    echo "❌ Failed to retrieve master key"
    exit 1
fi
echo "✅ Master key retrieved"
echo ""

echo "[2/2] Creating root CA..."

# Prepare JSON payload
PAYLOAD=$(cat <<EOF
{
    "ca_name": "$CA_NAME",
    "common_name": "$COMMON_NAME",
    "validity_years": $VALIDITY_YEARS
}
EOF
)

# Call function app via SSH (required for private endpoints)
RESPONSE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s -X POST 'https://$FUNCTION_APP.azurewebsites.net/api/create-root-ca?code=$MASTER_KEY' \
    -H 'Content-Type: application/json' \
    -d '$PAYLOAD'")

# Check if response contains error
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Error:"
    echo "$RESPONSE" | jq -r '.error'
    
    # Check if CA already exists
    if echo "$RESPONSE" | grep -q "already exists"; then
        echo ""
        echo "To recreate the root CA, delete it first:"
        echo "  az keyvault certificate delete --vault-name <vault-name> --name $CA_NAME"
        echo "  az keyvault certificate purge --vault-name <vault-name> --name $CA_NAME"
    fi
    exit 1
fi

echo "✅ Root CA created successfully"
echo ""

# Display certificate details
echo "========================================="
echo "Certificate Details"
echo "========================================="
echo ""
echo "Certificate ID:   $(echo "$RESPONSE" | jq -r '.certificate_id')"
echo "Certificate Name: $(echo "$RESPONSE" | jq -r '.certificate_name')"
echo "Thumbprint:       $(echo "$RESPONSE" | jq -r '.thumbprint')"
echo "Serial Number:    $(echo "$RESPONSE" | jq -r '.serial_number')"
echo "Issuer:           $(echo "$RESPONSE" | jq -r '.issuer')"
echo "Subject:          $(echo "$RESPONSE" | jq -r '.subject')"
echo "Expires On:       $(echo "$RESPONSE" | jq -r '.expires_on')"
echo ""
echo "Note: $(echo "$RESPONSE" | jq -r '.note')"
echo ""
echo "Security: Private key is HSM-protected and non-exportable"
echo ""

# Verify certificate was created
echo "========================================="
echo "Verification"
echo "========================================="
echo ""
echo "Verifying root CA certificate with OpenSSL..."
echo ""

# Get the certificate and verify
CERT_RESPONSE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-root-ca?ca_name=$CA_NAME&format=certificate&code=$MASTER_KEY'")

if echo "$CERT_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "⚠️  Could not retrieve certificate for verification"
else
    echo "$CERT_RESPONSE" | jq -r '.certificate_pem' > /tmp/${CA_NAME}-verify.pem
    
    echo "Subject:"
    openssl x509 -in /tmp/${CA_NAME}-verify.pem -noout -subject
    echo ""
    
    echo "Issuer (should match subject for root CA):"
    openssl x509 -in /tmp/${CA_NAME}-verify.pem -noout -issuer
    echo ""
    
    echo "Validity:"
    openssl x509 -in /tmp/${CA_NAME}-verify.pem -noout -dates
    echo ""
    
    echo "CA Extensions:"
    openssl x509 -in /tmp/${CA_NAME}-verify.pem -noout -text | grep -A 10 "X509v3 extensions:"
    echo ""
    
    rm -f /tmp/${CA_NAME}-verify.pem
    echo "✅ Root CA verification complete"
fi
