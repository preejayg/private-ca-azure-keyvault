#!/bin/bash

# Create Intermediate CA (LOCAL VERSION)
# Usage: ./create-intermediate-ca-local.sh [ca-name] [common-name] [root-ca-name] [validity-years]
#
# PREREQUISITES:
# - VPN connection to Azure virtual network
# - Hosts file entry: <FUNCTION_APP_PRIVATE_IP>  func-devicepki-dev-001.azurewebsites.net
# - Azure CLI logged in
# - Root CA must already exist

set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
check_local_config

FUNCTION_HOST="${FUNCTION_APP}.azurewebsites.net"

# CA configuration
CA_NAME="${1:-device-intermediate-ca}"
COMMON_NAME="${2:-Device PKI Intermediate CA}"
ROOT_CA_NAME="${3:-device-root-ca}"
VALIDITY_YEARS="${4:-5}"

echo "========================================="
echo "Create Intermediate CA (Local)"
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
PAYLOAD=$(jq -n \
    --arg ca_name "$CA_NAME" \
    --arg common_name "$COMMON_NAME" \
    --arg root_ca_name "$ROOT_CA_NAME" \
    --arg validity_years "$VALIDITY_YEARS" \
    '{
        ca_name: $ca_name,
        common_name: $common_name,
        root_ca_name: $root_ca_name,
        validity_years: ($validity_years | tonumber)
    }')

# Call function app directly
RESPONSE=$(curl -s -X POST "https://${FUNCTION_HOST}/api/create-intermediate-ca" \
    -H "x-functions-key: $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

# Check if response contains error
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Error:"
    echo "$RESPONSE" | jq -r '.error'
    
    # Check for common errors
    if echo "$RESPONSE" | grep -q "already exists"; then
        echo ""
        echo "Intermediate CA already exists. To recreate:"
        echo "  1. Delete: az keyvault certificate delete --vault-name <vault-name> --name $CA_NAME"
        echo "  2. Purge:  az keyvault certificate purge --vault-name <vault-name> --name $CA_NAME"
        echo "  3. Wait:   Wait 5-10 seconds for purge to complete"
        echo "  4. Retry:  ./create-intermediate-ca-local.sh"
    elif echo "$RESPONSE" | grep -q "not found"; then
        echo ""
        echo "Root CA not found. Create it first:"
        echo "  ./create-root-ca-local.sh"
    fi
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
echo "Signing Method:   $(echo "$RESPONSE" | jq -r '.signing_method')"
echo "Note:             $(echo "$RESPONSE" | jq -r '.note')"
echo ""
echo "Security: Private key is HSM-protected and non-exportable"
echo ""

# Verify certificate was created
echo "========================================="
echo "Verification"
echo "========================================="
echo ""
echo "Verifying intermediate CA certificate with OpenSSL..."
echo ""

# Get the certificate and verify
CERT_RESPONSE=$(curl -s "https://${FUNCTION_HOST}/api/get-intermediate-ca?ca_name=$CA_NAME&format=certificate" \
    -H "x-functions-key: $MASTER_KEY")

if echo "$CERT_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "⚠️  Could not retrieve certificate for verification"
else
    echo "$CERT_RESPONSE" | jq -r '.certificate_pem' > /tmp/${CA_NAME}-verify.pem
    
    echo "Subject:"
    openssl x509 -in /tmp/${CA_NAME}-verify.pem -noout -subject
    echo ""
    
    echo "Issuer (should be root CA):"
    openssl x509 -in /tmp/${CA_NAME}-verify.pem -noout -issuer
    echo ""
    
    echo "Validity:"
    openssl x509 -in /tmp/${CA_NAME}-verify.pem -noout -dates
    echo ""
    
    echo "CA Extensions:"
    openssl x509 -in /tmp/${CA_NAME}-verify.pem -noout -text | grep -A 10 "X509v3 extensions:"
    echo ""
    
    rm -f /tmp/${CA_NAME}-verify.pem
    echo "✅ Intermediate CA verification complete"
fi
echo ""
echo "Next steps:"
echo "  1. Issue device certificate: ./issue-certificate-local.sh device-001"
echo "  2. Generate CRL: Get the intermediate CA to generate CRL on first request"
