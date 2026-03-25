#!/bin/bash

# Local testing script for Certificate Authority Management Functions

echo "Testing Certificate Authority Management Functions Locally"
echo "==========================================================="
echo ""

BASE_URL="http://localhost:7071/api"

# Helper function to check if response is valid JSON
check_json_response() {
    local response="$1"
    local test_name="$2"
    
    if [ -z "$response" ]; then
        echo "❌ ERROR: Empty response from server"
        echo "   Is the function app running? Try: func start"
        return 1
    fi
    
    if echo "$response" | python3 -m json.tool > /dev/null 2>&1; then
        echo "$response" | python3 -m json.tool
        return 0
    else
        echo "❌ ERROR: Invalid JSON response"
        echo "Raw response:"
        echo "$response"
        return 1
    fi
}

echo "0. Checking if function app is running..."
echo "-----------------------------------------"
HEALTH_CHECK=$(curl -s -w "\n%{http_code}" $BASE_URL/health 2>/dev/null)
HTTP_CODE=$(echo "$HEALTH_CHECK" | tail -n 1)
RESPONSE_BODY=$(echo "$HEALTH_CHECK" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Function app is not responding!"
    echo "   HTTP Code: $HTTP_CODE"
    echo "   Please start the function app with: func start"
    echo ""
    exit 1
fi

echo "✅ Function app is running"
echo ""
echo ""

echo "1. Health Check"
echo "---------------"
RESPONSE=$(curl -s $BASE_URL/health)
check_json_response "$RESPONSE" "Health Check"
echo ""
echo ""

echo "2. Create Root CA"
echo "----------------"
RESPONSE=$(curl -s -X POST $BASE_URL/create-root-ca \
  -H "Content-Type: application/json" \
  -d '{
    "ca_name": "device-root-ca",
    "common_name": "Device PKI Root CA",
    "validity_years": 10
  }')
check_json_response "$RESPONSE" "Create Root CA"
echo ""
echo ""

echo "3. Get Root CA"
echo "-------------"
RESPONSE=$(curl -s "$BASE_URL/get-root-ca?ca_name=device-root-ca&format=certificate")
check_json_response "$RESPONSE" "Get Root CA"
echo ""
echo ""

echo "4. Create Intermediate CA"
echo "------------------------"
RESPONSE=$(curl -s -X POST $BASE_URL/create-intermediate-ca \
  -H "Content-Type: application/json" \
  -d '{
    "ca_name": "device-intermediate-ca",
    "common_name": "Device PKI Intermediate CA",
    "root_ca_name": "device-root-ca",
    "validity_years": 5
  }')
check_json_response "$RESPONSE" "Create Intermediate CA"
echo ""
echo ""

echo "5. Get Intermediate CA"
echo "---------------------"
RESPONSE=$(curl -s "$BASE_URL/get-intermediate-ca?ca_name=device-intermediate-ca&format=certificate")
check_json_response "$RESPONSE" "Get Intermediate CA"
echo ""
echo ""

echo "6. Generate CSR for testing"
echo "---------------------------"
# Create a temporary directory for test certificates
TEMP_DIR=$(mktemp -d)
echo "Using temp directory: $TEMP_DIR"

# Generate CSR using OpenSSL
echo "Generating CSR with OpenSSL..."
openssl req -new -newkey rsa:2048 -nodes -keyout "$TEMP_DIR/device-001.key" -out "$TEMP_DIR/device-001.csr" \
  -subj "/C=US/ST=Washington/L=Redmond/O=Example Corp/OU=IoT Devices/CN=device-001.example.com" \
  -addext "subjectAltName=DNS:device-001.local,IP:192.168.1.100" 2>/dev/null

if [ -f "$TEMP_DIR/device-001.csr" ]; then
  echo "✅ CSR generated successfully"
  echo ""
else
  echo "❌ Failed to generate CSR"
  rm -rf "$TEMP_DIR"
  exit 1
fi
echo ""

echo "7. Issue Certificate using CSR"
echo "-----------------------------"
CSR_CONTENT=$(cat "$TEMP_DIR/device-001.csr")
CSR_JSON=$(echo "$CSR_CONTENT" | jq -Rs .)

RESPONSE=$(curl -s -X POST $BASE_URL/issue-certificate \
  -H "Content-Type: application/json" \
  -d "{
    \"csr\": $CSR_JSON,
    \"intermediate_ca_name\": \"device-intermediate-ca\",
    \"certificate_name\": \"device-001-cert\",
    \"validity_days\": 365
  }")
check_json_response "$RESPONSE" "Issue Certificate"
echo ""
echo ""

echo "8. Verify issued certificate"
echo "----------------------------"
if echo "$RESPONSE" | grep -q "certificate_pem"; then
  echo "Extracting certificate and saving to file..."
  echo "$RESPONSE" | jq -r '.certificate_pem' > "$TEMP_DIR/device-001.crt"
  
  if [ -f "$TEMP_DIR/device-001.crt" ]; then
    echo "✅ Certificate saved to $TEMP_DIR/device-001.crt"
    echo ""
    echo "Certificate details:"
    openssl x509 -in "$TEMP_DIR/device-001.crt" -text -noout | grep -A 2 "Subject:\|Issuer:\|Validity"
    echo ""
  fi
else
  echo "⚠️  No certificate PEM found in response"
fi
echo ""

echo "==========================================================="
echo "Testing Complete!"
echo "==========================================================="
echo ""
echo "Test certificates saved in: $TEMP_DIR"
echo "  - Private Key: device-001.key"
echo "  - CSR: device-001.csr"
echo "  - Certificate: device-001.crt"
echo ""
echo "To clean up:"
echo "  rm -rf $TEMP_DIR"
echo ""
