#!/bin/bash

# Get Certificate Revocation List (LOCAL VERSION)
# Usage: ./get-crl-local.sh [ca-name]
#
# PREREQUISITES:
# - VPN connection to Azure virtual network
# - Hosts file entry: <FUNCTION_APP_PRIVATE_IP>  func-devicepki-dev-001.azurewebsites.net

set -e

# Configuration
FUNCTION_APP="func-devicepki-dev-001"
FUNCTION_HOST="${FUNCTION_APP}.azurewebsites.net"

# CA name (default: intermediate)
CA_NAME="${1:-intermediate}"

echo "========================================="
echo "Get Certificate Revocation List (CRL)"
echo "========================================="
echo "CA: $CA_NAME"
echo ""

echo "[1/2] Downloading CRL from function app..."

# Download CRL with headers saved separately
curl -s -D /tmp/crl-headers.txt -o /tmp/${CA_NAME}-ca.crl "https://${FUNCTION_HOST}/api/crl/$CA_NAME" 2>&1

# Check HTTP status
HTTP_STATUS=$(head -1 /tmp/crl-headers.txt | awk '{print $2}')

if [ "$HTTP_STATUS" != "200" ]; then
    echo "❌ Failed to download CRL (HTTP $HTTP_STATUS)"
    echo ""
    echo "Response Headers:"
    cat /tmp/crl-headers.txt
    echo ""
    echo "Response Body:"
    cat /tmp/${CA_NAME}-ca.crl
    rm -f /tmp/crl-headers.txt /tmp/${CA_NAME}-ca.crl
    exit 1
fi

# Show relevant headers
echo "Response Headers:"
grep -E "^(HTTP|Content-Type|Cache-Control|X-CRL-|X-Revoked)" /tmp/crl-headers.txt || echo "No custom headers found"
echo ""

if [ ! -s /tmp/${CA_NAME}-ca.crl ]; then
    echo "❌ CRL file is empty"
    rm -f /tmp/crl-headers.txt /tmp/${CA_NAME}-ca.crl
    exit 1
fi

CRL_SIZE=$(du -h /tmp/${CA_NAME}-ca.crl | cut -f1)
echo "✅ CRL downloaded: /tmp/${CA_NAME}-ca.crl ($CRL_SIZE)"
echo ""

# Cleanup headers file
rm -f /tmp/crl-headers.txt

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

if [ "$REVOKED_COUNT" -gt 0 ]; then
    echo ""
    echo "Revoked Certificate Details:"
    openssl crl -inform DER -in /tmp/${CA_NAME}-ca.crl -text -noout 2>/dev/null | \
        awk '/Serial Number:/ {serial=$3; getline; getline; date=$0; print "    Serial Number: " serial; print "        " date}'
fi

echo ""
echo "CRL saved to: /tmp/${CA_NAME}-ca.crl"
echo ""
echo "To verify a certificate against this CRL:"
echo "  openssl verify -crl_check -CAfile ca.pem -CRLfile /tmp/${CA_NAME}-ca.crl device.pem"
echo ""
