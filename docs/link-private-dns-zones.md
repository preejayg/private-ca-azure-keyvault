# Linking Private DNS Zones to VNet

## Option A: Azure Portal (Console) ✅

### Step 1: Find the Private DNS Zones

1. Go to **Azure Portal** → Search for **"Private DNS zones"**
2. Look for these zones (they may already exist in your subscription):
   - `privatelink.blob.core.windows.net`
   - `privatelink.file.core.windows.net`
   - `privatelink.vaultcore.azure.net`
   - `privatelink.azurewebsites.net`

**If they don't exist:** You (or platform team) need to create them first.

### Step 2: Link Each DNS Zone to Your VNet

For **each Private DNS zone**, follow these steps:

1. **Click on the Private DNS zone name**
2. In the left menu, click **"Virtual network links"**
3. Click **"+ Add"** at the top
4. Fill in the form:
   - **Link name:** `link-vnet-network-dev-aue-001` (or any descriptive name)
   - **Subscription:** Select your subscription
   - **Virtual network:** Select `vnet-network-dev-aue-001`
   - **Enable auto registration:** ✅ Check this box (important!)
5. Click **"OK"** or **"Create"**

**Repeat for all 4 DNS zones.**

### Step 3: Verify Links

Go back to each Private DNS zone → **Virtual network links** → You should see the VNet listed.

---

## Option B: Azure CLI (Alternative)

If you prefer automation or Portal is slow:

```bash
#!/bin/bash

SUBSCRIPTION_ID="a5fb8265-f881-447f-95bb-d174e99b217a"
VNET_NAME="vnet-network-dev-aue-001"
VNET_RG="rg-network-dev-aue-001"

# Get VNet resource ID
VNET_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$VNET_RG/providers/Microsoft.Network/virtualNetworks/$VNET_NAME"

echo "Linking Private DNS Zones to VNet..."

# Function to link or update DNS zone
link_dns_zone() {
    local ZONE_NAME=$1
    local DNS_RG=$2

    echo "Checking zone: $ZONE_NAME in resource group: $DNS_RG"

    # Check if link already exists
    EXISTING_LINK=$(az network private-dns link vnet list \
        --resource-group $DNS_RG \
        --zone-name $ZONE_NAME \
        --query "[?virtualNetwork.id=='$VNET_ID'].name" -o tsv 2>/dev/null)

    if [ -n "$EXISTING_LINK" ]; then
        echo "  ✅ Link already exists: $EXISTING_LINK"
    else
        echo "  Creating new link..."
        az network private-dns link vnet create \
            --resource-group $DNS_RG \
            --zone-name $ZONE_NAME \
            --name "link-${VNET_NAME}" \
            --virtual-network $VNET_ID \
            --registration-enabled true
        echo "  ✅ Link created"
    fi
    echo ""
}

# Find DNS zones - they might be in different resource groups
echo "Searching for Private DNS zones..."
echo ""

# Search for blob zone
BLOB_ZONE_RG=$(az network private-dns zone list --query "[?name=='privatelink.blob.core.windows.net'].resourceGroup" -o tsv | head -1)
if [ -n "$BLOB_ZONE_RG" ]; then
    link_dns_zone "privatelink.blob.core.windows.net" "$BLOB_ZONE_RG"
else
    echo "⚠️  privatelink.blob.core.windows.net not found - may need to be created"
fi

# Search for file zone
FILE_ZONE_RG=$(az network private-dns zone list --query "[?name=='privatelink.file.core.windows.net'].resourceGroup" -o tsv | head -1)
if [ -n "$FILE_ZONE_RG" ]; then
    link_dns_zone "privatelink.file.core.windows.net" "$FILE_ZONE_RG"
else
    echo "⚠️  privatelink.file.core.windows.net not found - may need to be created"
fi

# Search for vault zone
VAULT_ZONE_RG=$(az network private-dns zone list --query "[?name=='privatelink.vaultcore.azure.net'].resourceGroup" -o tsv | head -1)
if [ -n "$VAULT_ZONE_RG" ]; then
    link_dns_zone "privatelink.vaultcore.azure.net" "$VAULT_ZONE_RG"
else
    echo "⚠️  privatelink.vaultcore.azure.net not found - may need to be created"
fi

# Search for websites zone
SITES_ZONE_RG=$(az network private-dns zone list --query "[?name=='privatelink.azurewebsites.net'].resourceGroup" -o tsv | head -1)
if [ -n "$SITES_ZONE_RG" ]; then
    link_dns_zone "privatelink.azurewebsites.net" "$SITES_ZONE_RG"
else
    echo "⚠️  privatelink.azurewebsites.net not found - may need to be created"
fi

echo "========================================="
echo "DNS Zone Linking Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Wait 2-3 minutes for DNS propagation"
echo "2. Deploy function code from VM: ./scripts/deploy-from-vm.sh"
echo "3. Test: curl health endpoint"
echo ""
```

---

## Step 4: Check Private Endpoints

After linking, verify your private endpoints have DNS records:

```bash
# Check storage blob private endpoint
az network private-endpoint dns-zone-group show \
    --endpoint-name pe-dev-aue-storage-blob-dcert-poc \
    --resource-group rg-dev-aue-dcert-poc \
    --name default

# If no DNS zone group exists, private endpoints won't auto-register
# You may need to recreate private endpoints after DNS zones are linked
```

---

## Step 5: Test DNS Resolution

From your VM (after linking):

```bash
# Should resolve to private IP (10.x.x.x)
nslookup stfuncdevdevicepki001.blob.core.windows.net
nslookup stfuncdevdevicepki001.file.core.windows.net
nslookup kv-dev-aue-dcert-poc-001.vault.azure.net
nslookup func-devicepki-dev-001.azurewebsites.net
```

**Expected:** All should resolve to private IPs (10.x.x.x range), not public IPs (20.x.x.x or other public ranges).

---

## Troubleshooting

### "Private DNS zones don't exist"

Contact your platform team to create them. They're typically created once per subscription and shared across projects.

### "I don't have permissions to link DNS zones"

If the DNS zones are in a different resource group or subscription (common in enterprise setups), you'll need platform team to link them for you.

### "Private endpoints not showing in DNS zones"

After linking DNS zones, you may need to update the private endpoints to create DNS zone groups:

```bash
# This is typically done automatically, but can be added manually
az network private-endpoint dns-zone-group create \
    --endpoint-name pe-dev-aue-storage-blob-dcert-poc \
    --resource-group rg-dev-aue-dcert-poc \
    --name default \
    --private-dns-zone "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net" \
    --zone-name privatelink-blob-core-windows-net
```

---

## What This Solves

Without Private DNS zones linked:

- ❌ Function app tries to reach `stfuncdevdevicepki001.blob.core.windows.net`
- ❌ DNS resolves to **public IP** (20.x.x.x)
- ❌ Storage has `publicNetworkAccess=Disabled`
- ❌ Connection fails: "AuthorizationFailure"

With Private DNS zones linked:

- ✅ Function app tries to reach `stfuncdevdevicepki001.blob.core.windows.net`
- ✅ DNS resolves to **private IP** (10.x.x.x) via private endpoint
- ✅ Traffic stays within VNet
- ✅ Storage accepts connection via private endpoint
- ✅ Function runtime starts successfully
