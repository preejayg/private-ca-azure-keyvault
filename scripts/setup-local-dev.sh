#!/bin/bash

# Local Development Environment Setup

echo "=== Device Identity Project - Local Dev Setup ==="
echo ""

# Check for required tools
echo "Checking prerequisites..."

# Azure CLI
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
echo "✅ Azure CLI installed: $(az version --query '\"azure-cli\"' -o tsv)"

# Bicep
if ! command -v bicep &> /dev/null; then
    echo "Installing Bicep..."
    az bicep install
fi
echo "✅ Bicep installed: $(az bicep version)"

# Get Object ID
echo ""
echo "Getting your Azure AD Object ID..."
OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)

if [ -z "$OBJECT_ID" ]; then
    echo "⚠️  Not logged in to Azure. Please run: az login"
else
    echo "✅ Your Object ID: $OBJECT_ID"
    echo ""
    echo "📝 Update this Object ID in:"
    echo "   - infra/parameters/dev.bicepparam"
    echo "   - infra/parameters/prod.bicepparam"
fi

echo ""
echo "✅ Setup complete! You're ready to deploy."
echo ""
echo "Next steps:"
echo "1. Update Object ID in parameter files"
echo "2. Run: ./scripts/deploy-infrastructure.sh"
