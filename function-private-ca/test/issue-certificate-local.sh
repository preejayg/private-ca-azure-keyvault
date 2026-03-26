#!/bin/bash

# Issue device certificate from CSR via PKI Function App (LOCAL VERSION)
# Usage: ./issue-certificate-local.sh [certificate-name] [intermediate-ca-name] [validity-days]
#
# PREREQUISITES:
# - VPN connection to Azure virtual network
# - Hosts file entry: <FUNCTION_APP_PRIVATE_IP>  func-devicepki-dev-001.azurewebsites.net
# - Azure CLI logged in

set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
FUNCTION_HOST="${FUNCTION_APP}.azurewebsites.net"

# Parse arguments
CERT_NAME="${1:-device-test-$(date +%s)}"
INTERMEDIATE_CA="${2:-device-intermediate-ca}"
VALIDITY_DAYS="${3:-365}"

# Validate arguments
if [ -z "$CERT_NAME" ]; then
    echo "Usage: $0 [certificate-name] [intermediate-ca-name] [validity-days]"
    echo ""
    echo "Example:"
    echo "  $0 device-002 device-intermediate-ca 365"
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

if [ -z "$CSR_JSON" ]; then
    echo "❌ Failed to read CSR"
    exit 1
fi

CSR_LINES=$(echo "$CSR_CONTENT" | wc -l | tr -d ' ')
echo "✅ CSR loaded ($CSR_LINES lines)"
echo ""

# Issue certificate via direct API call (no SSH)
echo "[3/3] Issuing certificate via function app..."

RESPONSE=$(curl -s -X POST "https://${FUNCTION_HOST}/api/issue-certificate" \
    -H "Content-Type: application/json" \
    -H "x-functions-key: $MASTER_KEY" \
    -d "{
        \"csr\": $CSR_JSON,
        \"certificate_name\": \"$CERT_NAME\",
        \"intermediate_ca_name\": \"$INTERMEDIATE_CA\",
        \"validity_days\": $VALIDITY_DAYS
    }" 2>&1)

# Check if response contains error
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Failed to issue certificate"
    echo "Response:"
    echo "$RESPONSE" | jq .
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "✅ Certificate issued successfully"
echo ""

# Parse and display certificate details
echo "========================================="
echo "Certificate Details:"
echo "========================================="

# Extract fields safely
CERT_NAME_RESP=$(echo "$RESPONSE" | jq -r '.certificate_name // "N/A"')
SUBJECT=$(echo "$RESPONSE" | jq -r '.subject // "N/A"')
ISSUER=$(echo "$RESPONSE" | jq -r '.issuer // "N/A"')
SERIAL=$(echo "$RESPONSE" | jq -r '.serial_number // "N/A"')
NOT_BEFORE=$(echo "$RESPONSE" | jq -r '.not_before // "N/A"')
NOT_AFTER=$(echo "$RESPONSE" | jq -r '.not_after // "N/A"')
STORAGE=$(echo "$RESPONSE" | jq -r '.storage_location // "N/A"')

echo "Name:        $CERT_NAME_RESP"
echo "Subject:     $SUBJECT"
echo "Issuer:      $ISSUER"
echo "Serial:      $SERIAL"
echo "Not Before:  $NOT_BEFORE"
echo "Not After:   $NOT_AFTER"
echo "Storage:     $STORAGE"
echo ""

# Display certificate PEM
echo "========================================="
echo "Certificate PEM:"
echo "========================================="
echo "$RESPONSE" | jq -r '.certificate_pem'
echo ""
echo ""

# Save certificate and private key
CERT_FILE="$TEMP_DIR/${CERT_NAME}.pem"
echo "$RESPONSE" | jq -r '.certificate_pem' > "$CERT_FILE"

echo "Certificate saved to Key Vault as secret: $CERT_NAME"
echo ""
echo "To retrieve certificate from Key Vault:"
echo "  az keyvault secret show --vault-name kv-dev-aue-dcert-poc-001 --name $CERT_NAME --query value -o tsv"
echo ""
echo "Private key saved to: $KEY_FILE"
echo "To keep the key and CSR, copy them before they are deleted on exit."
echo ""

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        echo "----------------------------------------"
        echo "Cleaning up temporary CSR files..."
        rm -rf "$TEMP_DIR"
        echo "✅ Cleanup complete"
    fi
}

# Register cleanup on exit
trap cleanup EXIT
