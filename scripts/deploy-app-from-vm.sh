#!/bin/bash

# Deploy function code from VM (required for private networking)
# This script automates the complete deployment workflow:
# 1. Build platform-specific Python packages locally
# 2. Package function app code with pre-built dependencies
# 3. Copy to VM via SCP
# 4. SSH to VM and deploy with Azure CLI
# 5. Verify deployment
#
# IMPORTANT: This script uses pre-built Python packages because config-zip
# deployment does NOT trigger remote builds. Packages must be built for
# Linux x86_64 platform (not macOS ARM64).

set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
VM_IP="10.140.34.6"
VM_USER="azureuser"
SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"
ZIP_FILE="function-app-with-deps.zip"
SOURCE_DIR="../function-private-ca"

echo "========================================="
echo "PKI Function App Deployment via VM"
echo "========================================="
echo ""

# Step 1: Verify SSH key exists and has correct permissions
echo "Step 1/7: Verifying SSH key..."
if [ ! -f "$SSH_KEY" ]; then
    echo "❌ Error: SSH key not found at $SSH_KEY"
    echo "Please ensure the SSH key exists and path is correct."
    exit 1
fi

# Ensure correct permissions on SSH key
chmod 600 "$SSH_KEY"
echo "✅ SSH key found and permissions set to 600"
echo ""

# Step 2: Build platform-specific Python packages
echo "Step 2/7: Building platform-specific Python packages..."
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

# Step 3: Package function app code with dependencies
echo "Step 3/7: Packaging function app with dependencies..."

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

# Step 4: Copy zip file to VM
echo "Step 4/7: Copying deployment package to VM ($VM_IP)..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$ZIP_FILE" "$VM_USER@$VM_IP:~/"
echo "✅ File copied to VM"
echo ""

# Step 5: Deploy via SSH
echo "Step 5/7: Deploying to Function App via VM..."
echo "This should take 20-30 seconds (file extraction only, no build)..."
echo ""

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" << 'ENDSSH'
set -e

RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
ZIP_FILE="function-app-with-deps.zip"

echo "  → Verifying Azure authentication..."
az account show --query "{Subscription:name}" -o tsv

echo "  → Starting deployment (config-zip with pre-built packages)..."
az functionapp deployment source config-zip \
    --resource-group $RESOURCE_GROUP \
    --name $FUNCTION_APP \
    --src $ZIP_FILE

echo "  → Waiting 45 seconds for function app to restart and load packages..."
sleep 45

echo "  → Deployment complete"
ENDSSH

echo ""
echo "✅ Deployment completed successfully"
echo ""

# Step 6: Verify function app status
echo "Step 6/7: Verifying function app status..."
FUNC_STATE=$(az functionapp show \
    --name $FUNCTION_APP \
    --resource-group $RESOURCE_GROUP \
    --query "{State:state}" -o tsv)

echo "Function App State: $FUNC_STATE"
echo ""

# Step 7: Test health endpoint
echo "Step 7/7: Testing health endpoint..."
echo "Testing via VM (required for private networking)..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" << ENDSSH2
echo "  → Calling /api/health endpoint..."
HEALTH_RESPONSE=\$(curl -s "https://$FUNCTION_APP.azurewebsites.net/api/health" 2>&1)

if echo "\$HEALTH_RESPONSE" | grep -q "healthy"; then
    echo "  ✅ Function app is healthy"
    echo "\$HEALTH_RESPONSE" | jq . 2>/dev/null || echo "\$HEALTH_RESPONSE"
else
    echo "  ⚠️  Health check returned unexpected response:"
    echo "\$HEALTH_RESPONSE"
fi
ENDSSH2

echo ""
echo "========================================="
echo "✅ Deployment Complete!"
echo "========================================="
echo ""
echo "Function App: $FUNCTION_APP"
echo "State: $FUNC_STATE"
echo "Package Size: $ZIP_SIZE (includes pre-built Python dependencies)"
echo ""
echo "Deployment Method:"
echo "  → Platform-specific packages (manylinux2014_x86_64)"
echo "  → Included in deployment zip (.python_packages/)"
echo "  → No remote build required"
echo ""
echo "Next Steps:"
echo "1. Test certificate operations:"
echo "   cd function-private-ca/test"
echo "   ./list-certificates.sh"
echo "   ./issue-certificate.sh device-101-cert"
echo ""
echo "2. View logs:"
echo "   az functionapp log stream --name $FUNCTION_APP --resource-group $RESOURCE_GROUP"
echo ""

cd - > /dev/null
