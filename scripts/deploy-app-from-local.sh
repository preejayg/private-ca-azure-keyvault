#!/bin/bash

# Deploy function code from local machine (requires VPN connection)
# This script automates the deployment workflow for local development:
# 1. Build platform-specific Python packages locally
# 2. Package function app code with pre-built dependencies
# 3. Deploy directly to Azure Function App via Azure CLI
# 4. Verify deployment
#
# PREREQUISITES:
# - VPN connection to Azure virtual network
# - Hosts file entry pointing function app hostname to private endpoint IP
#   Example: 10.140.34.4  func-devicepki-dev-001.azurewebsites.net
# - Azure CLI logged in with proper permissions
#
# IMPORTANT: This script uses pre-built Python packages because config-zip
# deployment does NOT trigger remote builds. Packages must be built for
# Linux x86_64 platform (not macOS ARM64).

set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
ZIP_FILE="function-app-with-deps.zip"
SOURCE_DIR="../function-private-ca"

echo "========================================="
echo "PKI Function App Deployment (Local)"
echo "========================================="
echo ""

# Step 1: Verify Azure CLI is logged in
echo "Step 1/6: Verifying Azure CLI authentication..."
az account show > /dev/null 2>&1 || {
    echo "❌ Error: Not logged in to Azure CLI"
    echo "Please run: az login"
    exit 1
}

ACCOUNT_NAME=$(az account show --query "user.name" -o tsv)
SUBSCRIPTION=$(az account show --query "name" -o tsv)
echo "✅ Logged in as: $ACCOUNT_NAME"
echo "   Subscription: $SUBSCRIPTION"
echo ""

# Step 2: Verify VPN connection and hostname resolution
echo "Step 2/6: Verifying network connectivity..."
FUNCTION_HOST="${FUNCTION_APP}.azurewebsites.net"

# Check if hostname resolves to private IP (10.x.x.x range)
RESOLVED_IP=$(dig +short $FUNCTION_HOST | head -1)
if [[ ! $RESOLVED_IP =~ ^10\. ]]; then
    echo "⚠️  Warning: $FUNCTION_HOST resolves to: ${RESOLVED_IP:-not found}"
    echo ""
    echo "To deploy from local machine, you need:"
    echo "1. VPN connection to Azure virtual network"
    echo "2. Hosts file entry:"
    echo "   echo '10.140.34.4  $FUNCTION_HOST' | sudo tee -a /etc/hosts"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "✅ $FUNCTION_HOST resolves to private IP: $RESOLVED_IP"
fi
echo ""

# Step 3: Build platform-specific Python packages
echo "Step 3/6: Building platform-specific Python packages..."
cd "$SOURCE_DIR"

# Clean previous builds
if [ -d ".python_packages" ]; then
    echo "  → Removing old .python_packages directory..."
    rm -rf .python_packages
fi

echo "  → Installing packages for Linux x86_64 platform..."
echo "  → This ensures compatibility with Azure Functions runtime"
pip install --platform manylinux2014_x86_64 --only-binary=:all: \
    --target ./.python_packages/lib/site-packages \
    -r requirements.txt 2>&1 | grep -E "Successfully installed|Collecting|Using cached" || true

if [ ! -d ".python_packages/lib/site-packages" ]; then
    echo "❌ Error: Failed to install Python packages"
    exit 1
fi

PACKAGE_COUNT=$(ls -1 .python_packages/lib/site-packages | wc -l | tr -d ' ')
echo "✅ Installed packages to .python_packages/ ($PACKAGE_COUNT packages)"
echo ""

# Step 4: Package function app code with dependencies
echo "Step 4/6: Packaging function app with dependencies..."

# Remove old zip if exists
[ -f "$ZIP_FILE" ] && rm -f "$ZIP_FILE"

# Create zip with Python packages included
zip -r "$ZIP_FILE" \
    function_app.py \
    host.json \
    requirements.txt \
    .python_packages \
    > /dev/null

ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
echo "✅ Created $ZIP_FILE ($ZIP_SIZE)"
echo ""

# Step 5: Deploy to Function App
echo "Step 5/6: Deploying to Function App..."
echo "This should take 20-30 seconds (file extraction only, no build)..."
echo ""

az functionapp deployment source config-zip \
    --resource-group "$RESOURCE_GROUP" \
    --name "$FUNCTION_APP" \
    --src "$ZIP_FILE" \
    --build-remote false \
    --timeout 600 \
    2>&1 | grep -E "Deployment|succeeded|failed|Finished"

echo ""
echo "✅ Deployment package uploaded"

# Wait for function app to restart
echo ""
echo "Waiting for function app to restart (10 seconds)..."
sleep 10

# Step 6: Verify deployment
echo ""
echo "Step 6/6: Verifying deployment..."

# Check function app state
FUNCTION_STATE=$(az functionapp show \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --query "state" -o tsv)

echo "  → Function App State: $FUNCTION_STATE"

# Test health endpoint (no auth required)
echo "  → Calling /api/health endpoint..."
HEALTH_RESPONSE=$(curl -s -m 10 "https://${FUNCTION_HOST}/api/health" 2>/dev/null || echo '{"status":"unreachable"}')
HEALTH_STATUS=$(echo "$HEALTH_RESPONSE" | jq -r '.status' 2>/dev/null || echo "error")

if [ "$HEALTH_STATUS" = "healthy" ]; then
    echo "  ✅ Function app is healthy"
    echo "$HEALTH_RESPONSE" | jq .
else
    echo "  ⚠️  Health check response:"
    echo "$HEALTH_RESPONSE"
fi

echo ""
echo "========================================="
echo "✅ Deployment Complete!"
echo "========================================="
echo ""
echo "Function App: $FUNCTION_APP"
echo "State: $FUNCTION_STATE"
echo "Package Size: $ZIP_SIZE (includes pre-built Python dependencies)"
echo ""
echo "Deployment Method:"
echo "  → Platform-specific packages (manylinux2014_x86_64)"
echo "  → Included in deployment zip (.python_packages/)"
echo "  → No remote build required"
echo ""
echo "Next Steps:"
echo "1. Test certificate operations:"
echo "   cd ../function-private-ca/test"
echo "   ./list-certificates-local.sh"
echo "   ./issue-certificate-local.sh device-101"
echo ""
echo "2. View logs:"
echo "   az functionapp log stream --name $FUNCTION_APP --resource-group $RESOURCE_GROUP"
echo ""

# Cleanup
cd - > /dev/null
