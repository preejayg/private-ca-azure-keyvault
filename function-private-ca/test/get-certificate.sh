#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="<YOUR_VM_IP>"  # Replace with your VM IP
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

# Certificate name
CERT_NAME="$1"

if [ -z "$CERT_NAME" ]; then
    echo "Usage: $0 <certificate-name>"
    echo ""
    echo "Example: $0 device-001"
    exit 1
fi

echo "========================================="
echo "Get Device Certificate"
echo "========================================="
echo "Certificate: $CERT_NAME"
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

echo "[2/2] Calling /api/get-certificate endpoint..."
echo ""

# Call function app via SSH (required for private endpoints)
RESPONSE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-certificate?cert_name=$CERT_NAME&code=$MASTER_KEY'")

# Check if response contains error
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Error:"
    echo "$RESPONSE" | jq -r '.error'
    exit 1
fi

# Display certificate metadata
echo "========================================="
echo "Certificate Metadata"
echo "========================================="
echo ""
echo "Certificate Name: $(echo "$RESPONSE" | jq -r '.certificate_name')"
echo "Serial Number:    $(echo "$RESPONSE" | jq -r '.serial_number')"
echo "Subject:          $(echo "$RESPONSE" | jq -r '.subject | to_entries | map("\(.key)=\(.value)") | join(", ")')"
echo "Issuer:           $(echo "$RESPONSE" | jq -r '.issuer | to_entries | map("\(.key)=\(.value)") | join(", ")')"
echo "Not Before:       $(echo "$RESPONSE" | jq -r '.not_before')"
echo "Not After:        $(echo "$RESPONSE" | jq -r '.not_after')"
echo "Algorithm:        $(echo "$RESPONSE" | jq -r '.signature_algorithm')"
echo "Version:          $(echo "$RESPONSE" | jq -r '.version')"
echo "Created:          $(echo "$RESPONSE" | jq -r '.created_on')"
echo ""

# Extract and display certificate
echo "========================================="
echo "Certificate PEM"
echo "========================================="
echo ""
echo "$RESPONSE" | jq -r '.certificate'

# Optional: Save to file
OUTPUT_FILE="/tmp/${CERT_NAME}.pem"
echo "$RESPONSE" | jq -r '.certificate' > "$OUTPUT_FILE"
echo ""
echo "Certificate saved to: $OUTPUT_FILE"
echo ""

# Verify certificate with OpenSSL
echo "========================================="
echo "OpenSSL Verification"
echo "========================================="
echo ""
openssl x509 -in "$OUTPUT_FILE" -text -noout | head -30
