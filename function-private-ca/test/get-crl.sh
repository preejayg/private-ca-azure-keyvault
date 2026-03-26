#!/bin/bash
set -e

# Configuration
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="<YOUR_VM_IP>"  # Replace with your VM IP
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

# CA name (default: intermediate)
CA_NAME="${1:-intermediate}"

echo "========================================="
echo "Get Certificate Revocation List (CRL)"
echo "========================================="
echo "CA: $CA_NAME"
echo ""

echo "[1/2] Downloading CRL from function app..."

# Download CRL via SSH (required for private endpoints)
# Use -i for headers, -s for silent, no output redirect to preserve binary
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s 'https://$FUNCTION_APP.azurewebsites.net/api/crl/$CA_NAME' -o /tmp/crl-download.crl && curl -s -I 'https://$FUNCTION_APP.azurewebsites.net/api/crl/$CA_NAME'" > /tmp/crl-headers.txt 2>&1

# Extract headers from separate HEAD request
echo "Response Headers:"
grep -E "^(HTTP|Content-Type|Cache-Control|X-CRL-)" /tmp/crl-headers.txt || echo "No headers found"
echo ""

# Copy downloaded CRL from VM
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP:/tmp/crl-download.crl /tmp/${CA_NAME}-ca.crl 2>/dev/null || true

if [ ! -s /tmp/${CA_NAME}-ca.crl ]; then
    echo "❌ Failed to download CRL or CRL is empty"
    echo ""
    echo "Headers:"
    cat /tmp/crl-headers.txt
    exit 1
fi

CRL_SIZE=$(du -h /tmp/${CA_NAME}-ca.crl | cut -f1)
echo "✅ CRL downloaded: /tmp/${CA_NAME}-ca.crl ($CRL_SIZE)"
echo ""

echo "[2/2] Parsing CRL with OpenSSL..."
echo ""

# Convert DER to text
openssl crl -inform DER -in /tmp/${CA_NAME}-ca.crl -text -noout 2>/dev/null || {
    echo "⚠️  Could not parse as DER, trying PEM format..."
    openssl crl -inform PEM -in /tmp/${CA_NAME}-ca.crl -text -noout 2>/dev/null || {
        echo "❌ Failed to parse CRL"
        echo ""
        echo "File content (first 100 bytes):"
        head -c 100 /tmp/${CA_NAME}-ca.crl | od -A x -t x1z -v
        exit 1
    }
}

echo ""
echo "========================================="
echo "CRL Summary"
echo "========================================="

# Extract key information
ISSUER=$(openssl crl -inform DER -in /tmp/${CA_NAME}-ca.crl -noout -issuer 2>/dev/null | sed 's/issuer=//')
LAST_UPDATE=$(openssl crl -inform DER -in /tmp/${CA_NAME}-ca.crl -noout -lastupdate 2>/dev/null | sed 's/lastUpdate=//')
NEXT_UPDATE=$(openssl crl -inform DER -in /tmp/${CA_NAME}-ca.crl -noout -nextupdate 2>/dev/null | sed 's/nextUpdate=//')

echo "Issuer:      $ISSUER"
echo "Last Update: $LAST_UPDATE"
echo "Next Update: $NEXT_UPDATE"
echo ""

# Count revoked certificates
REVOKED_COUNT=$(openssl crl -inform DER -in /tmp/${CA_NAME}-ca.crl -text -noout 2>/dev/null | grep -c "Serial Number:" || echo "0")
echo "Revoked Certificates: $REVOKED_COUNT"
echo ""

if [ "$REVOKED_COUNT" -gt 0 ]; then
    echo "Revoked Certificate Details:"
    openssl crl -inform DER -in /tmp/${CA_NAME}-ca.crl -text -noout 2>/dev/null | \
        grep -A 2 "Serial Number:" | head -20
    echo ""
fi

echo "CRL saved to: /tmp/${CA_NAME}-ca.crl"
echo ""
echo "To verify a certificate against this CRL:"
echo "  openssl verify -crl_check -CAfile ca.pem -CRLfile /tmp/${CA_NAME}-ca.crl device.pem"
echo ""
