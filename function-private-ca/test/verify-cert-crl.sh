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
    echo ""
    echo "Example: $0 device-020-cert"
    exit 1
fi

echo "========================================="
echo "Verify Certificate Against CRL"
echo "========================================="
echo "Certificate: $CERT_NAME"
echo ""

# Get function master key
echo "[0/4] Retrieving function master key..."
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

# Step 1: Get CRL
echo "[1/4] Downloading CRL..."
./get-crl.sh intermediate > /dev/null 2>&1

if [ ! -f /tmp/intermediate-ca.crl ]; then
    echo "❌ Failed to download CRL"
    exit 1
fi
echo "✅ CRL downloaded"
echo ""

# Step 2: Get Root CA certificate via function app API
echo "[2/4] Downloading Root CA certificate..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-root-ca?ca_name=device-root-ca&code=$MASTER_KEY'" | \
    jq -r '.certificate_pem' > /tmp/root-ca.pem 2>/dev/null

if [ ! -s /tmp/root-ca.pem ]; then
    echo "❌ Failed to download Root CA"
    exit 1
fi
echo "✅ Root CA downloaded"
echo ""

# Step 3: Get Intermediate CA certificate via function app API
echo "[3/4] Downloading Intermediate CA certificate..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-intermediate-ca?ca_name=device-intermediate-ca&code=$MASTER_KEY'" | \
    jq -r '.certificate_pem' > /tmp/intermediate-ca.pem 2>/dev/null

if [ ! -s /tmp/intermediate-ca.pem ]; then
    echo "❌ Failed to download Intermediate CA"
    exit 1
fi
echo "✅ Intermediate CA downloaded"
echo ""

# Step 4: Get device certificate via function app API
echo "[4/4] Downloading device certificate..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/get-certificate?cert_name=${CERT_NAME}&code=$MASTER_KEY'" | \
    jq -r '.certificate' > /tmp/${CERT_NAME}.pem 2>/dev/null

if [ ! -s /tmp/${CERT_NAME}.pem ]; then
    echo "❌ Failed to download device certificate"
    echo "    Note: Certificate must exist in Key Vault as ${CERT_NAME}-cert"
    exit 1
fi
echo "✅ Device certificate downloaded"
echo ""

echo "=========================================
"
echo "Certificate Chain Verification"
echo "========================================="
echo ""

# First verify without CRL check
echo "Verifying certificate chain (without CRL)..."
openssl verify -no-CApath -CAfile /tmp/root-ca.pem -untrusted /tmp/intermediate-ca.pem /tmp/${CERT_NAME}.pem

echo ""
echo "Verifying certificate chain (with CRL check)..."

# For CRL verification, we need:
# - Root CA as trusted anchor
# - Intermediate CA in untrusted chain
# - CRL for intermediate CA revocations
# Note: Use -crl_check (not -crl_check_all) to only check the end-entity cert

if openssl verify -no-CApath -crl_check -CAfile /tmp/root-ca.pem -untrusted /tmp/intermediate-ca.pem -CRLfile /tmp/intermediate-ca.crl /tmp/${CERT_NAME}.pem 2>&1; then
    echo ""
    echo "✅ Certificate is valid and NOT revoked"
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 2 ]; then
        echo ""
        echo "❌ Certificate verification failed - certificate may be REVOKED"
    else
        echo ""
        echo "⚠️  Certificate verification failed (exit code: $EXIT_CODE)"
    fi
fi

echo ""
echo "========================================="
echo "Certificate Details"
echo "========================================="
echo ""

# Show certificate details
openssl x509 -in /tmp/${CERT_NAME}.pem -text -noout | grep -A 5 "X509v3 CRL Distribution Points"

echo ""
echo "Files created:"
echo "  /tmp/root-ca.pem"
echo "  /tmp/intermediate-ca.pem"
echo "  /tmp/intermediate-ca.crl"
echo "  /tmp/${CERT_NAME}.pem"
echo ""
