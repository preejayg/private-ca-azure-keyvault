#!/bin/bash

# Revoke a device certificate (LOCAL VERSION)
# Usage: ./revoke-certificate-local.sh <certificate-name> [reason]
#
# PREREQUISITES:
# - VPN connection to Azure virtual network  
# - Hosts file entry: 10.140.34.4  func-devicepki-dev-001.azurewebsites.net
# - Azure CLI logged in

set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
FUNCTION_HOST="${FUNCTION_APP}.azurewebsites.net"

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
    echo ""
    echo "Examples:"
    echo "  $0 device-001                    # Revoke with default reason (unspecified)"
    echo "  $0 device-001 keyCompromise      # Revoke due to key compromise"
    echo "  $0 device-001 superseded         # Revoke because cert was renewed"
    exit 1
fi

echo "========================================="
echo "Revoke Device Certificate (Local)"
echo "========================================="
echo "Certificate: $CERT_NAME"
echo "Reason:      $REVOCATION_REASON"
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

# Revoke certificate
echo ""
echo "[2/2] Revoking certificate..."

PAYLOAD=$(jq -n \
    --arg cert_name "$CERT_NAME" \
    --arg reason "$REVOCATION_REASON" \
    '{
        certificate_name: $cert_name,
        reason: $reason
    }')

RESPONSE=$(curl -s -X POST "https://${FUNCTION_HOST}/api/revoke-certificate" \
    -H "x-functions-key: $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>&1)

# Check response
if echo "$RESPONSE" | grep -q 'revoked successfully'; then
    echo "✅ Certificate revoked successfully"
    echo ""
    echo "========================================="
    echo "Revocation Details:"
    echo "========================================="
    echo "$RESPONSE" | jq '.'
    echo ""
else
    echo "❌ Failed to revoke certificate"
    echo ""
    echo "Response:"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    exit 1
fi
