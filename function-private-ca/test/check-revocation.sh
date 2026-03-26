#!/bin/bash
set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
check_vm_config

# Certificate name
CERT_NAME="$1"

if [ -z "$CERT_NAME" ]; then
    echo "Usage: $0 <certificate-name>"
    exit 1
fi

echo "========================================="
echo "Check Certificate Revocation Status"
echo "========================================="
echo "Certificate: $CERT_NAME"
echo ""

# Get master key
echo "[1/2] Retrieving function master key..."
MASTER_KEY=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "az functionapp keys list -g rg-dev-aue-dcert-poc -n $FUNCTION_APP --query 'masterKey' -o tsv" 2>/dev/null)

if [ -z "$MASTER_KEY" ]; then
    echo "❌ Failed to retrieve master key"
    exit 1
fi
echo "✅ Master key retrieved"

# Check revocation status
echo ""
echo "[2/2] Checking revocation status..."

RESPONSE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/check-revocation?code=$MASTER_KEY&certificate_name=$CERT_NAME'" 2>/dev/null)

# Check response
if echo "$RESPONSE" | grep -q '"revoked"'; then
    echo "✅ Revocation status retrieved"
    echo ""
    echo "========================================="
    echo "Revocation Status:"
    echo "========================================="
    echo "$RESPONSE" | jq .
else
    echo "❌ Failed to check revocation status"
    echo ""
    echo "Response:"
    echo "$RESPONSE"
    exit 1
fi
