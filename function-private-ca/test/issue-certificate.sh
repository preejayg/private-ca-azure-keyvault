#!/bin/bash

# Issue device certificate from CSR via PKI Function App
# Usage: ./issue-certificate.sh [certificate-name] [intermediate-ca-name] [validity-days]

set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="<YOUR_VM_IP>"  # Replace with your VM IP
VM_USER="azureuser"
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

# Parse arguments
CERT_NAME="${1:-device-test-$(date +%s)}"
INTERMEDIATE_CA="${2:-device-intermediate-ca}"
VALIDITY_DAYS="${3:-365}"

# Validate arguments
if [ -z "$CERT_NAME" ]; then
    echo "Usage: $0 [certificate-name] [intermediate-ca-name] [validity-days]"
    echo ""
    echo "Example:"
    echo "  $0 device-002-cert device-intermediate-ca 365"
    echo ""
    echo "Note: A CSR will be generated automatically using OpenSSL"
    exit 1
fi

# Generate CSR automatically
echo "========================================="
echo "Generating CSR with OpenSSL"
echo "========================================="
echo ""

# Create temp directory for CSR and key
TEMP_DIR=$(mktemp -d)
CSR_FILE="$TEMP_DIR/device.csr"
KEY_FILE="$TEMP_DIR/device.key"

# Generate private key and CSR
openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$KEY_FILE" \
    -out "$CSR_FILE" \
    -subj "/C=US/ST=WA/L=Redmond/O=Example/CN=$CERT_NAME.example.com" \
    -addext "subjectAltName=DNS:$CERT_NAME.local,DNS:$CERT_NAME.example.com" \
    2>/dev/null

echo "✅ CSR generated:"
echo "   Private Key: $KEY_FILE"
echo "   CSR File:    $CSR_FILE"
echo ""

echo "========================================="
echo "Issue Device Certificate from CSR"
echo "========================================="
echo "Certificate Name: $CERT_NAME"
echo "Intermediate CA:  $INTERMEDIATE_CA"
echo "Validity (days):  $VALIDITY_DAYS"
echo ""

# Get function master key
echo "[1/3] Retrieving function master key..."
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

# Read and encode CSR
echo "[2/3] Reading CSR file..."
CSR_CONTENT=$(cat "$CSR_FILE")
CSR_JSON=$(echo "$CSR_CONTENT" | jq -Rs .)
echo "✅ CSR loaded ($(echo "$CSR_CONTENT" | wc -l) lines)"
echo ""

# Issue certificate via VM
echo "[3/3] Issuing certificate via VM..."

# Build JSON payload properly using jq
JSON_PAYLOAD=$(jq -n \
  --arg csr "$CSR_CONTENT" \
  --arg intermediate_ca "$INTERMEDIATE_CA" \
  --arg cert_name "$CERT_NAME" \
  --argjson validity "$VALIDITY_DAYS" \
  '{
    csr: $csr,
    intermediate_ca_name: $intermediate_ca,
    certificate_name: $cert_name,
    validity_days: $validity
  }')

# Escape single quotes in JSON for shell command
JSON_ESCAPED=$(echo "$JSON_PAYLOAD" | sed "s/'/'\\\\''/g")

# Execute via SSH - filter output to extract only JSON (skip SSH banner)
RAW_OUTPUT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o LogLevel=ERROR "$VM_USER@$VM_IP" \
  "curl -s -X POST 'https://$FUNCTION_APP.azurewebsites.net/api/issue-certificate' \
    -H 'Content-Type: application/json' \
    -H 'x-functions-key: $MASTER_KEY' \
    -d '$JSON_ESCAPED'" 2>&1)

# Extract JSON from output (find line starting with { and take everything from there)
CERT_RESULT=$(echo "$RAW_OUTPUT" | sed -n '/{/,$p')

# Check if successful
if echo "$CERT_RESULT" | grep -q "BEGIN CERTIFICATE"; then
    echo "✅ Certificate issued successfully"
    echo ""
    echo "========================================="
    echo "Certificate Details:"
    echo "========================================="
    echo "$CERT_RESULT" | jq -r '
        "Name:        \(.certificate_name)",
        "Subject:     \(.subject)",
        "Issuer:      \(.issuer)",
        "Serial:      \(.serial_number)",
        "Not Before:  \(.not_before)",
        "Not After:   \(.not_after)",
        "Storage:     \(.storage_location)"
    '
    
    echo ""
    echo "========================================="
    echo "Certificate PEM:"
    echo "========================================="
    echo "$CERT_RESULT" | jq -r '.certificate_pem'
    
    echo ""
    echo "Certificate saved to Key Vault as secret: $CERT_NAME"
    echo ""
    echo "To retrieve certificate from Key Vault:"
    echo "  az keyvault secret show --vault-name kv-dev-aue-dcert-poc-001 --name $CERT_NAME --query value -o tsv"
    echo ""
    echo "Private key saved to: $KEY_FILE"
    echo "To keep the key and CSR, copy them before they are deleted on exit."
    
else
    echo "❌ Failed to issue certificate"
    echo ""
    echo "Response:"
    echo "$CERT_RESULT" | jq '.' 2>/dev/null || echo "$CERT_RESULT"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cleanup temp files
echo ""
echo "----------------------------------------"
echo "Cleaning up temporary CSR files..."
rm -rf "$TEMP_DIR"
echo "✅ Cleanup complete"
echo ""
