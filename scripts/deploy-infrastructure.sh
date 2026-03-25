#!/bin/bash

# Comprehensive deployment script for PKI Certificate Management Function App
# Run this from your local machine

set -e

RESOURCE_GROUP="rg-dev-aue-dcert-poc"
LOCATION="australiaeast"
ENVIRONMENT="dev"
VNET_NAME="vnet-network-dev-aue-001"
VNET_RG="rg-network-dev-aue-001"
SUBNET_NAME="snet-private-endpoints"
FUNCTION_SUBNET="snet-functionapp-integration"

echo "========================================="
echo "PKI Certificate Management Deployment"
echo "========================================="
echo ""

# Get current user's object ID for Key Vault access
echo "Step 1: Getting your Object ID for Key Vault access..."
OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
echo "Object ID: $OBJECT_ID"
echo ""

# Deploy infrastructure via Bicep
echo "Step 2: Deploying infrastructure via Bicep..."

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file "$REPO_ROOT/infra/bicep/main.bicep" \
    --parameters "$REPO_ROOT/infra/parameters/dev.bicepparam" \
    --parameters deployFunctionApp=true \
    --parameters objectId=$OBJECT_ID \
    --verbose

echo ""
echo "✅ Infrastructure deployed successfully!"
echo ""

# Get the function app name
FUNCTION_APP_NAME=$(az functionapp list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)
echo "Function App Name: $FUNCTION_APP_NAME"
echo ""

# Check deployment status
echo "Step 3: Verifying deployment..."
az functionapp show \
    --name $FUNCTION_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "{name:name,state:state,principalId:identity.principalId,vnetIntegration:virtualNetworkSubnetId}" -o json

echo ""
echo "========================================="
echo "⚠️  CRITICAL POST-DEPLOYMENT STEP"
echo "========================================="
echo ""
echo "DNS CONFIGURATION (Required for Private Endpoints):"
echo ""
echo "  Private endpoints need DNS zone groups to resolve to private IPs."
echo "  Run this script to configure them:"
echo ""
echo "  ./scripts/configure-dns-zones.sh"
echo ""
echo "  This will link your private endpoints to the Shared Services DNS zones."
echo ""
echo "After DNS configuration completes:"
echo "  1. Wait 2-3 minutes for DNS propagation"
echo "  2. Deploy function code: ./scripts/deploy-from-vm.sh"
echo "  3. Test function app health endpoint"
echo ""
echo "========================================="
echo "Deployment script completed!"
echo "========================================="
