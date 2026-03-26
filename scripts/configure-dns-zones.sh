#!/bin/bash

# Add DNS zone groups to private endpoints (post-deployment)
# This must be done via CLI due to cross-subscription permissions

set -e

RESOURCE_GROUP="rg-dev-aue-dcert-poc"
SHARED_SERVICES_SUB="<YOUR_SHARED_SERVICES_SUBSCRIPTION_ID>"  # Replace with your shared services subscription ID
DNS_ZONE_RG="rg-privatedns-sharedsvcs-aue-001"

echo "========================================="
echo "Configure Private Endpoint DNS Zones"
echo "========================================="
echo ""
echo "This adds DNS zone groups to private endpoints"
echo "using Shared Services DNS zones."
echo ""

# Get DNS zone resource IDs from Shared Services subscription
echo "Step 1: Getting DNS zone resource IDs..."
BLOB_ZONE_ID="/subscriptions/$SHARED_SERVICES_SUB/resourceGroups/$DNS_ZONE_RG/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
FILE_ZONE_ID="/subscriptions/$SHARED_SERVICES_SUB/resourceGroups/$DNS_ZONE_RG/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
VAULT_ZONE_ID="/subscriptions/$SHARED_SERVICES_SUB/resourceGroups/$DNS_ZONE_RG/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"

echo "  Blob Zone: $BLOB_ZONE_ID"
echo "  File Zone: $FILE_ZONE_ID"
echo "  Vault Zone: $VAULT_ZONE_ID"
echo ""

# Check if DNS zone groups already exist
echo "Step 2: Checking existing DNS zone groups..."

BLOB_EXISTS=$(az network private-endpoint dns-zone-group list \
    --endpoint-name pe-dev-aue-storage-blob-dcert-poc \
    --resource-group $RESOURCE_GROUP \
    --query "[0].name" -o tsv 2>/dev/null || echo "")

FILE_EXISTS=$(az network private-endpoint dns-zone-group list \
    --endpoint-name pe-dev-aue-storage-file-dcert-poc \
    --resource-group $RESOURCE_GROUP \
    --query "[0].name" -o tsv 2>/dev/null || echo "")

VAULT_EXISTS=$(az network private-endpoint dns-zone-group list \
    --endpoint-name pe-dev-aue-kv-dcert-poc \
    --resource-group $RESOURCE_GROUP \
    --query "[0].name" -o tsv 2>/dev/null || echo "")

# Add DNS zone group to blob private endpoint
echo ""
echo "Step 3: Configuring Storage Blob private endpoint..."
if [ -n "$BLOB_EXISTS" ]; then
    echo "  ✅ DNS zone group already exists: $BLOB_EXISTS"
else
    echo "  Creating DNS zone group..."
    az network private-endpoint dns-zone-group create \
        --endpoint-name pe-dev-aue-storage-blob-dcert-poc \
        --resource-group $RESOURCE_GROUP \
        --name default \
        --private-dns-zone "$BLOB_ZONE_ID" \
        --zone-name blob \
        --output none
    echo "  ✅ DNS zone group created"
fi

# Add DNS zone group to file private endpoint
echo ""
echo "Step 4: Configuring Storage File private endpoint..."
if [ -n "$FILE_EXISTS" ]; then
    echo "  ✅ DNS zone group already exists: $FILE_EXISTS"
else
    echo "  Creating DNS zone group..."
    az network private-endpoint dns-zone-group create \
        --endpoint-name pe-dev-aue-storage-file-dcert-poc \
        --resource-group $RESOURCE_GROUP \
        --name default \
        --private-dns-zone "$FILE_ZONE_ID" \
        --zone-name file \
        --output none
    echo "  ✅ DNS zone group created"
fi

# Add DNS zone group to Key Vault private endpoint
echo ""
echo "Step 5: Configuring Key Vault private endpoint..."
if [ -n "$VAULT_EXISTS" ]; then
    echo "  ✅ DNS zone group already exists: $VAULT_EXISTS"
else
    echo "  Creating DNS zone group..."
    az network private-endpoint dns-zone-group create \
        --endpoint-name pe-dev-aue-kv-dcert-poc \
        --resource-group $RESOURCE_GROUP \
        --name default \
        --private-dns-zone "$VAULT_ZONE_ID" \
        --zone-name vault \
        --output none
    echo "  ✅ DNS zone group created"
fi

echo ""
echo "========================================="
echo "✅ DNS Configuration Complete!"
echo "========================================="
echo ""
echo "⏰ Wait 2-3 minutes for DNS propagation"
echo ""
echo "Test DNS resolution:"
echo "  nslookup stfuncdevdevicepki001.blob.core.windows.net"
echo "  nslookup stfuncdevdevicepki001.file.core.windows.net"
echo "  nslookup kv-dev-aue-dcert-poc-001.vault.azure.net"
echo ""
echo "Expected: All should resolve to 10.x.x.x private IPs"
echo ""
