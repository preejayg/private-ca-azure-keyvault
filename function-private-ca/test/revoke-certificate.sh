#!/bin/bash
set -e

# Configuration
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="10.140.34.6"
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

# Certificate name and revocation reason
CERT_NAME="$1"
REVOCATION_REASON="${2:-unspecified}"

if [ -z "$CERT_NAME" ]; then
    echo "Usage: $0 <certificate-name> [reason]"
    echo ""
    echo "Valid reasons (camelCase):"
    echo "  unspecified, keyCompromise, caCompromise, affiliationChanged,"
    echo "  superseded, cessationOfOperation, certificateHold,"
    echo "  removeFromCRL, privilegeWithdrawn, aaCompromise"
    exit 1
fi

echo "========================================="
echo "Revoke Device Certificate"
echo "========================================="
echo "Certificate: $CERT_NAME"
echo "Reason:      $REVOCATION_REASON"
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

# Revoke certificate
echo ""
echo "[2/2] Revoking certificate..."

RESPONSE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s -X POST 'https://$FUNCTION_APP.azurewebsites.net/api/revoke-certificate?code=$MASTER_KEY' \
    -H 'Content-Type: application/json' \
    -d '{\"certificate_name\": \"$CERT_NAME\", \"reason\": \"$REVOCATION_REASON\"}'" 2>/dev/null)

# Check response
if echo "$RESPONSE" | grep -q 'revoked successfully'; then
    echo "✅ Certificate revoked successfully"
    echo ""
    echo "========================================="
    echo "Revocation Details:"
    echo "========================================="
    echo "$RESPONSE" | jq .
else
    echo "❌ Failed to revoke certificate"
    echo ""
    echo "Response:"
    echo "$RESPONSE"
    exit 1
fi
