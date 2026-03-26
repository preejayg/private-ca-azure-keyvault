#!/bin/bash
set -e

# Configuration
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="<YOUR_VM_IP>"  # Replace with your VM IP
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

# Certificate name and renewal options
CERT_NAME="$1"
VALIDITY_DAYS="${2:-365}"
AUTO_REVOKE="${3:-false}"
REVOCATION_REASON="${4:-superseded}"
GENERATE_CSR="${5:-false}"

if [ -z "$CERT_NAME" ]; then
    echo "Usage: $0 <certificate-name> [validity_days] [auto_revoke] [revocation_reason] [generate_csr]"
    echo ""
    echo "Arguments:"
    echo "  certificate-name    : Name of the certificate to renew (required)"
    echo "  validity_days       : Validity period in days (default: 365)"
    echo "  auto_revoke         : Revoke old certificate (true|false, default: false)"
    echo "  revocation_reason   : Reason for revocation if auto_revoke=true (default: superseded)"
    echo "  generate_csr        : Generate new CSR for renewal (true|false, default: false)"
    echo ""
    echo "Examples:"
    echo "  $0 device-001                          # Simple renewal, keep same subject/key"
    echo "  $0 device-001 730                      # Renew for 2 years"
    echo "  $0 device-001 365 true                 # Renew and revoke old certificate"
    echo "  $0 device-001 365 true superseded      # Renew and revoke with reason"
    echo "  $0 device-001 365 false false true     # Renew with new CSR (new key pair)"
    exit 1
fi

echo "========================================="
echo "Renew Device Certificate"
echo "========================================="
echo "Certificate:     $CERT_NAME"
echo "Validity Days:   $VALIDITY_DAYS"
echo "Auto Revoke Old: $AUTO_REVOKE"
if [ "$AUTO_REVOKE" = "true" ]; then
    echo "Revoke Reason:   $REVOCATION_REASON"
fi
echo "Generate CSR:    $GENERATE_CSR"
echo ""

# Get master key
echo "[Step 1] Retrieving function master key..."
MASTER_KEY=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "az functionapp keys list -g rg-dev-aue-dcert-poc -n $FUNCTION_APP --query 'masterKey' -o tsv" 2>/dev/null)

if [ -z "$MASTER_KEY" ]; then
    echo "❌ Failed to retrieve master key"
    exit 1
fi
echo "✅ Master key retrieved"
echo ""

# Generate CSR if requested
CSR_DATA=""
TEMP_DIR=""
if [ "$GENERATE_CSR" = "true" ]; then
    echo "[Step 2] Generating new CSR with OpenSSL..."
    
    # Create temporary directory for CSR files
    TEMP_DIR=$(mktemp -d)
    
    # Generate private key
    openssl genrsa -out "$TEMP_DIR/device.key" 2048 2>/dev/null
    
    # Create CSR with subject
    openssl req -new -key "$TEMP_DIR/device.key" \
        -out "$TEMP_DIR/device.csr" \
        -subj "/C=US/ST=WA/L=Redmond/O=Example/CN=${CERT_NAME}.example.com" \
        -addext "subjectAltName=DNS:${CERT_NAME}.local,DNS:${CERT_NAME}.example.com" \
        2>/dev/null
    
    # Read CSR content
    CSR_DATA=$(cat "$TEMP_DIR/device.csr")
    
    echo "✅ CSR generated with new key pair"
    echo "   Private Key: $TEMP_DIR/device.key"
    echo "   CSR File:    $TEMP_DIR/device.csr"
    echo ""
fi

# Build JSON payload
echo "[Step 3] Building renewal request..."
if [ -n "$CSR_DATA" ]; then
    # With CSR
    PAYLOAD=$(jq -n \
        --arg cert_name "$CERT_NAME" \
        --arg validity_days "$VALIDITY_DAYS" \
        --arg csr "$CSR_DATA" \
        --argjson auto_revoke "$AUTO_REVOKE" \
        --arg revocation_reason "$REVOCATION_REASON" \
        '{
            certificate_name: $cert_name,
            validity_days: ($validity_days | tonumber),
            csr: $csr,
            auto_revoke: $auto_revoke,
            revocation_reason: $revocation_reason
        }')
else
    # Without CSR (reuse existing subject/key)
    PAYLOAD=$(jq -n \
        --arg cert_name "$CERT_NAME" \
        --arg validity_days "$VALIDITY_DAYS" \
        --argjson auto_revoke "$AUTO_REVOKE" \
        --arg revocation_reason "$REVOCATION_REASON" \
        '{
            certificate_name: $cert_name,
            validity_days: ($validity_days | tonumber),
            auto_revoke: $auto_revoke,
            revocation_reason: $revocation_reason
        }')
fi
echo "✅ Request payload built"
echo ""

# Renew certificate
echo "[Step 4] Renewing certificate via VM..."

RESPONSE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@$VM_IP \
    "curl -s -X POST 'https://$FUNCTION_APP.azurewebsites.net/api/renew-certificate?code=$MASTER_KEY' \
    -H 'Content-Type: application/json' \
    -d '$PAYLOAD'" 2>/dev/null)

# Check response
if echo "$RESPONSE" | grep -q 'renewed successfully'; then
    echo "✅ Certificate renewed successfully"
    echo ""
    echo "========================================="
    echo "Renewal Details:"
    echo "========================================="
    echo "$RESPONSE" | jq '.'
    echo ""
    
    # Show certificate PEM if available
    if echo "$RESPONSE" | jq -e '.certificate_pem' > /dev/null 2>&1; then
        echo "========================================="
        echo "New Certificate PEM:"
        echo "========================================="
        echo "$RESPONSE" | jq -r '.certificate_pem'
        echo ""
    fi
    
    # Show storage location
    if echo "$RESPONSE" | jq -e '.storage_location' > /dev/null 2>&1; then
        STORAGE_LOCATION=$(echo "$RESPONSE" | jq -r '.storage_location')
        echo "Certificate saved: $STORAGE_LOCATION"
        echo ""
    fi
    
    # Show revocation info if auto-revoked
    if echo "$RESPONSE" | jq -e '.old_certificate_revoked' > /dev/null 2>&1; then
        OLD_CERT_REVOKED=$(echo "$RESPONSE" | jq -r '.old_certificate_revoked')
        if [ "$OLD_CERT_REVOKED" = "true" ]; then
            echo "⚠️  Old certificate was automatically revoked"
            echo "$RESPONSE" | jq -r '.revocation_info | "   Reason: \(.reason)\n   Revoked At: \(.revoked_at)"'
            echo ""
        fi
    fi
    
    # If CSR was generated, show cleanup info
    if [ -n "$TEMP_DIR" ]; then
        echo "----------------------------------------"
        echo "New private key saved to: $TEMP_DIR/device.key"
        echo "To keep the key, copy it before cleanup."
        echo "To cleanup temporary files: rm -rf $TEMP_DIR"
    fi
    
else
    echo "❌ Failed to renew certificate"
    echo ""
    echo "Response:"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    
    # Cleanup temp directory on failure
    if [ -n "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    exit 1
fi
