#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="<YOUR_VM_IP>"  # Replace with your VM IP
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

# CA configuration
CA_NAME="${1:-device-intermediate-ca}"
COMMON_NAME="${2:-Device PKI Intermediate CA}"
ROOT_CA_NAME="device-root-ca"
VALIDITY_YEARS=5

echo "========================================="
echo "Create Intermediate CA"
echo "========================================="
echo "CA Name:      $CA_NAME"
echo "Common Name:  $COMMON_NAME"
echo "Root CA:      $ROOT_CA_NAME"
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

echo "[2/2] Creating intermediate CA..."

# Prepare JSON payload
PAYLOAD=$(cat <<EOF
{
    "ca_name": "$CA_NAME",
    "common_name": "$COMMON_NAME",
    "root_ca_name": "$ROOT_CA_NAME",
    "validity_years": $VALIDITY_YEARS
}
EOF
)

# Call function app via SSH (required for private endpoints)
RESPONSE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s -X POST 'https://$FUNCTION_APP.azurewebsites.net/api/create-intermediate-ca?code=$MASTER_KEY' \
    -H 'Content-Type: application/json' \
    -d '$PAYLOAD'")

# Check if response contains error
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Error:"
    echo "$RESPONSE" | jq -r '.error'
    exit 1
fi

echo "✅ Intermediate CA created successfully"
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

# Verify certificate was created
echo "========================================="
echo "Verification"
echo "========================================="
echo ""
echo "Fetching certificate from Key Vault..."
./get-intermediate-ca.sh $CA_NAME | head -30
