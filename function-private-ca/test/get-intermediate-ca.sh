#!/bin/bash

# Get Intermediate CA certificate from PKI Function App via VM
# Usage: ./get-intermediate-ca.sh [ca-name]

set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
check_vm_config

# Default CA name
CA_NAME="${1:-device-intermediate-ca}"
VM_USER="azureuser"

echo "========================================="
echo "Retrieve Intermediate CA Certificate"
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

# Get Intermediate CA via VM
echo "[2/2] Retrieving Intermediate CA certificate via VM..."
INTERMEDIATE_CA_RESULT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o LogLevel=ERROR "$VM_USER@$VM_IP" \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-intermediate-ca?ca_name=$CA_NAME' -H 'x-functions-key: $MASTER_KEY'")

# Check if successful
if echo "$INTERMEDIATE_CA_RESULT" | grep -q "BEGIN CERTIFICATE"; then
    echo "✅ Intermediate CA retrieved successfully"
    echo ""
    echo "========================================="
    echo "Certificate Details:"
    echo "========================================="
    echo "$INTERMEDIATE_CA_RESULT" | jq -r '
        "Name:        \(.certificate_name)",
        "Thumbprint:  \(.thumbprint)",
        "Created:     \(.created_on)",
        "Expires:     \(.expires_on)",
        "Key ID:      \(.key_id)",
        "Signed By:   \(.signed_by // "N/A")"
    '
    
    echo ""
    echo "========================================="
    echo "Certificate PEM:"
    echo "========================================="
    echo "$INTERMEDIATE_CA_RESULT" | jq -r '.certificate_pem'
    
    echo ""
    echo "To save certificate to file:"
    echo "  ./get-intermediate-ca.sh $CA_NAME | grep -A 100 'BEGIN CERTIFICATE' | grep -B 100 'END CERTIFICATE' > intermediate-ca.pem"
    
else
    echo "❌ Failed to retrieve Intermediate CA"
    echo ""
    echo "Response:"
    echo "$INTERMEDIATE_CA_RESULT" | jq '.' 2>/dev/null || echo "$INTERMEDIATE_CA_RESULT"
    exit 1
fi
echo ""
