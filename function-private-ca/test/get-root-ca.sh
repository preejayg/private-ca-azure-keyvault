#!/bin/bash

# Get Root CA certificate from PKI Function App via VM
# Usage: ./get-root-ca.sh [ca-name]

set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="<YOUR_VM_IP>"  # Replace with your VM IP
VM_USER="azureuser"
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

# Default CA name
CA_NAME="${1:-device-root-ca}"

echo "========================================="
echo "Retrieve Root CA Certificate"
echo "========================================="
echo ""
echo "CA Name: $CA_NAME"
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

# Get Root CA via VM
echo "[2/2] Retrieving Root CA certificate via VM..."
ROOT_CA_RESULT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o LogLevel=ERROR "$VM_USER@$VM_IP" \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-root-ca?ca_name=$CA_NAME' -H 'x-functions-key: $MASTER_KEY'")

# Check if successful
if echo "$ROOT_CA_RESULT" | grep -q "BEGIN CERTIFICATE"; then
    echo "✅ Root CA retrieved successfully"
    echo ""
    echo "========================================="
    echo "Certificate Details:"
    echo "========================================="
    echo "$ROOT_CA_RESULT" | jq -r '
        "Name:        \(.certificate_name)",
        "Thumbprint:  \(.thumbprint)",
        "Created:     \(.created_on)",
        "Expires:     \(.expires_on)",
        "Key ID:      \(.key_id)"
    '
    
    echo ""
    echo "========================================="
    echo "Certificate PEM:"
    echo "========================================="
    echo "$ROOT_CA_RESULT" | jq -r '.certificate_pem'
    
    echo ""
    echo "To save certificate to file:"
    echo "  ./get-root-ca.sh $CA_NAME | grep -A 100 'BEGIN CERTIFICATE' | grep -B 100 'END CERTIFICATE' > root-ca.pem"
    
else
    echo "❌ Failed to retrieve Root CA"
    echo ""
    echo "Response:"
    echo "$ROOT_CA_RESULT" | jq '.' 2>/dev/null || echo "$ROOT_CA_RESULT"
    exit 1
fi
echo ""
