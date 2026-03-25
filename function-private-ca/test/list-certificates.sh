#!/bin/bash

# List all certificates via PKI Function App endpoint
# Shows both CA certificates and issued device certificates

set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="10.140.34.6"
VM_USER="azureuser"
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

echo "========================================="
echo "Certificate Inventory"
echo "========================================="
echo ""
echo "Function App: $FUNCTION_APP"
echo "Accessing via VM: $VM_IP"
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

# List certificates via function endpoint
echo "[2/2] Retrieving certificate list..."

# Execute API call via SSH
RAW_OUTPUT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o LogLevel=ERROR "$VM_USER@$VM_IP" \
  "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/list-certificates?type=all' \
    -H 'x-functions-key: $MASTER_KEY'" 2>&1)

# Extract JSON from output (find line starting with { and take everything from there)
RESULT=$(echo "$RAW_OUTPUT" | sed -n '/{/,$p')

# Check if we got valid JSON
if echo "$RESULT" | jq . >/dev/null 2>&1; then
    echo "✅ Certificate list retrieved"
    echo ""
    
    # Display CA Certificates
    echo "========================================="
    echo "CA Certificates (Root & Intermediate)"
    echo "========================================="
    CA_COUNT=$(echo "$RESULT" | jq -r '.ca_certificates.count // 0')
    echo "Count: $CA_COUNT"
    echo ""
    
    if [ "$CA_COUNT" -gt 0 ]; then
        echo "$RESULT" | jq -r '.ca_certificates.items[] | 
            "Name:       \(.name)",
            "Thumbprint: \(.thumbprint)",
            "Created:    \(.created_on)",
            "Expires:    \(.expires_on)",
            "Enabled:    \(.enabled)",
            ""'
    else
        echo "No CA certificates found"
        echo ""
    fi
    
    # Display Device Certificates
    echo "========================================="
    echo "Device Certificates"
    echo "========================================="
    DEVICE_COUNT=$(echo "$RESULT" | jq -r '.device_certificates.count // 0')
    echo "Count: $DEVICE_COUNT"
    echo ""
    
    if [ "$DEVICE_COUNT" -gt 0 ]; then
        echo "$RESULT" | jq -r '.device_certificates.items[] | 
            "Name:       \(.name)",
            "Thumbprint: \(.thumbprint)",
            "Created:    \(.created_on)",
            "Expires:    \(.expires_on)",
            "Enabled:    \(.enabled)",
            ""'
    else
        echo "No device certificates found"
        echo ""
    fi
    
    # Summary
    echo "========================================="
    echo "Summary"
    echo "========================================="
    TOTAL=$(echo "$RESULT" | jq -r '.total_certificates // 0')
    echo "CA Certificates:     $CA_COUNT"
    echo "Device Certificates: $DEVICE_COUNT"
    echo "Total Certificates:  $TOTAL"
    echo ""
    
else
    echo "❌ Failed to retrieve certificate list"
    echo ""
    echo "Response:"
    echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
    exit 1
fi
