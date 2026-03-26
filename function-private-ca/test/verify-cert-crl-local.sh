#!/bin/bash

# Verify certificate with CRL check (LOCAL VERSION)
# Usage: ./verify-cert-crl-local.sh [certificate-name]
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

# Certificate name
CERT_NAME="${1}"

if [ -z "$CERT_NAME" ]; then
    echo "Usage: $0 <certificate-name>"
    echo ""
    echo "Example:"
    echo "  $0 device-001"
    exit 1
fi

echo "========================================="
echo "Verify Certificate with CRL"
echo "========================================="
echo "Certificate: $CERT_NAME"
echo ""
echo "Note: Only PUBLIC certificates are downloaded."
echo "      Private keys remain in Azure Key Vault HSM."
echo ""

# Get function master key
echo "[1/4] Retrieving function master key..."
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

# Download Root CA
echo "[2/4] Downloading root CA..."
ROOT_RESPONSE=$(curl -s "https://${FUNCTION_HOST}/api/get-root-ca?format=certificate" \
    -H "x-functions-key: $MASTER_KEY")

if echo "$ROOT_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Failed to download root CA"
    echo "$ROOT_RESPONSE" | jq '.'
    exit 1
fi

echo "$ROOT_RESPONSE" | jq -r '.certificate_pem' > /tmp/root-ca.pem

if [ ! -s /tmp/root-ca.pem ] || ! grep -q "BEGIN CERTIFICATE" /tmp/root-ca.pem; then
    echo "❌ Invalid root CA certificate"
    exit 1
fi
echo "✅ Root CA downloaded (public certificate only)"
echo ""

# Download Intermediate CA
echo "[3/4] Downloading intermediate CA..."
INTERMEDIATE_RESPONSE=$(curl -s "https://${FUNCTION_HOST}/api/get-intermediate-ca?format=certificate" \
    -H "x-functions-key: $MASTER_KEY")

if echo "$INTERMEDIATE_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Failed to download intermediate CA"
    echo "$INTERMEDIATE_RESPONSE" | jq '.'
    exit 1
fi

echo "$INTERMEDIATE_RESPONSE" | jq -r '.certificate_pem' > /tmp/intermediate-ca.pem

if [ ! -s /tmp/intermediate-ca.pem ] || ! grep -q "BEGIN CERTIFICATE" /tmp/intermediate-ca.pem; then
    echo "❌ Invalid intermediate CA certificate"
    exit 1
fi
echo "✅ Intermediate CA downloaded (public certificate only)"
echo ""

# Download CRL
echo "Downloading CRL..."
curl -s -o /tmp/intermediate-ca.crl "https://${FUNCTION_HOST}/api/crl/intermediate"

if [ ! -s /tmp/intermediate-ca.crl ]; then
    echo "⚠️  Warning: Failed to download CRL"
else
    echo "✅ CRL downloaded"
fi
echo ""

# Download device certificate
echo "[4/4] Downloading device certificate..."
DEVICE_RESPONSE=$(curl -s "https://${FUNCTION_HOST}/api/get-certificate?cert_name=$CERT_NAME" \
    -H "x-functions-key: $MASTER_KEY")

if echo "$DEVICE_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Failed to download device certificate"
    echo "$DEVICE_RESPONSE" | jq '.'
    exit 1
fi

# Note: Device certificates use 'certificate' field, not 'certificate_pem'
echo "$DEVICE_RESPONSE" | jq -r '.certificate' > /tmp/${CERT_NAME}.pem

if [ ! -s /tmp/${CERT_NAME}.pem ] || ! grep -q "BEGIN CERTIFICATE" /tmp/${CERT_NAME}.pem; then
    echo "❌ Invalid device certificate"
    exit 1
fi
echo "✅ Device certificate downloaded (public certificate only)"
echo ""

echo "========================================="
echo "Certificate Chain Verification"
echo "========================================="
echo ""

# Verify without CRL
echo "Verifying certificate chain (without CRL)..."
openssl verify -CAfile /tmp/root-ca.pem -untrusted /tmp/intermediate-ca.pem /tmp/${CERT_NAME}.pem

echo ""

# Verify with CRL
if [ -s /tmp/intermediate-ca.crl ]; then
    echo "Verifying certificate chain (with CRL check)..."
    
    # Run verification - capture stdout and stderr
    set +e  # Don't exit on error
    CRL_OUTPUT=$(mktemp)
    openssl verify -CAfile /tmp/root-ca.pem -untrusted /tmp/intermediate-ca.pem \
        -crl_check -CRLfile /tmp/intermediate-ca.crl /tmp/${CERT_NAME}.pem > "$CRL_OUTPUT" 2>&1
    
    CRL_EXIT_CODE=$?
    set -e  # Re-enable exit on error
    
    # Check if revoked before filtering output
    IS_REVOKED=$(grep -c "certificate revoked" "$CRL_OUTPUT" || echo "0")
    
    # Display output (filter only the SSL path warnings that aren't relevant)
    cat "$CRL_OUTPUT" | grep -v "error:16000069:STORE routines" | grep -v "error:80000002:system library" | grep -v "calling stat(" || true
    
    echo ""
    if [ $CRL_EXIT_CODE -eq 0 ]; then
        echo "✅ Certificate is VALID and NOT revoked"
    else
        # Check if it's a revocation error
        if [ "$IS_REVOKED" -gt 0 ]; then
            echo "❌ Certificate has been REVOKED"
            
            # Show revocation details from CRL
            CERT_SERIAL=$(openssl x509 -in /tmp/${CERT_NAME}.pem -noout -serial | cut -d= -f2)
            echo ""
            echo "Revocation Details:"
            openssl crl -inform DER -in /tmp/intermediate-ca.crl -text -noout | \
                awk "/Serial Number: $CERT_SERIAL/,/CRL entry extensions:/{print}" | head -4
            
            echo ""
            echo "To test with a valid certificate:"
            echo "  ./issue-certificate-local.sh device-test-005"
            echo "  ./verify-cert-crl-local.sh device-test-005"
        else
            echo "❌ Certificate verification failed (exit code: $CRL_EXIT_CODE)"
        fi
    fi
    
    # Cleanup
    rm -f "$CRL_OUTPUT"
else
    echo "⚠️  Skipping CRL check (CRL not available)"
fi

echo ""
echo "========================================="
echo "Certificate Details"
echo "========================================="
echo "Subject:"
openssl x509 -in /tmp/${CERT_NAME}.pem -noout -subject
echo ""
echo "Issuer:"
openssl x509 -in /tmp/${CERT_NAME}.pem -noout -issuer
echo ""
echo "Validity:"
openssl x509 -in /tmp/${CERT_NAME}.pem -noout -dates
echo ""
echo "Serial Number:"
openssl x509 -in /tmp/${CERT_NAME}.pem -noout -serial
echo ""

echo "========================================="
echo "Files Created"
echo "========================================="
echo "  /tmp/root-ca.pem             (Root CA public certificate)"
echo "  /tmp/intermediate-ca.pem     (Intermediate CA public certificate)"
echo "  /tmp/intermediate-ca.crl     (Certificate Revocation List)"
echo "  /tmp/${CERT_NAME}.pem        (Device public certificate)"
echo ""
