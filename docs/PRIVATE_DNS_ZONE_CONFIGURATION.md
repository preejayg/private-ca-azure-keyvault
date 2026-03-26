# Private DNS Zone Configuration Guide

## Overview

Due to organizational policies that block Bicep/Terraform from creating private DNS zones, DNS zone groups must be manually configured for each private endpoint after infrastructure deployment.

This guide provides step-by-step instructions for configuring DNS zone groups to enable private name resolution for all Azure services.

---

## Prerequisites

1. ✅ Infrastructure deployed via Bicep (`main.bicep`)
2. ✅ Private endpoints created for:
   - Key Vault
   - Storage Account (Blob)
   - Storage Account (File)
   - Function App (Sites)
3. ✅ Access to Azure Portal or Azure CLI with appropriate permissions
4. ✅ Private DNS zones created in central network resource group (contact platform team if not available)

---

## Required Private DNS Zones

| Service      | Private DNS Zone                    | Purpose                                  |
| ------------ | ----------------------------------- | ---------------------------------------- |
| Key Vault    | `privatelink.vaultcore.azure.net`   | Key Vault private endpoint resolution    |
| Storage Blob | `privatelink.blob.core.windows.net` | Storage blob endpoint resolution         |
| Storage File | `privatelink.file.core.windows.net` | Storage file share endpoint resolution   |
| Function App | `privatelink.azurewebsites.net`     | Function App and SCM endpoint resolution |

---

## Configuration Steps

### Option 1: Azure Portal (Recommended)

#### Step 1: Navigate to Private Endpoint

1. Open **Azure Portal**
2. Navigate to **Resource Group**: `rg-dev-aue-dcert-poc`
3. Select the private endpoint

#### Step 2: Add DNS Zone Group

For each private endpoint, perform the following:

##### 1. Key Vault Private Endpoint (`pe-dev-aue-kv-dcert-poc`)

1. **Navigate to**: `pe-dev-aue-kv-dcert-poc`
2. **Left menu**: Click **DNS configuration**
3. **Click**: `+ Add`
4. **Configure**:
   - **Name**: `default` (or `kv-dns-zone-group`)
   - **Private DNS zone**: Select `privatelink.vaultcore.azure.net`
     - If not available, contact platform team to create and link zone
   - **Resource group**: `rg-network-dev-aue-001` (or your central DNS resource group)
5. **Click**: `Add`
6. **Wait**: 2-3 minutes for DNS propagation

**Verification**:

```bash
# From VM or VPN-connected machine:
nslookup kv-dev-aue-dcert-poc-001.vault.azure.net
# Expected: Should resolve to private IP (10.x.x.x)
```

---

##### 2. Storage Blob Private Endpoint (`pe-dev-aue-storage-blob-dcert-poc`)

1. **Navigate to**: `pe-dev-aue-storage-blob-dcert-poc`
2. **Left menu**: Click **DNS configuration**
3. **Click**: `+ Add`
4. **Configure**:
   - **Name**: `default` (or `blob-dns-zone-group`)
   - **Private DNS zone**: Select `privatelink.blob.core.windows.net`
   - **Resource group**: `rg-network-dev-aue-001`
5. **Click**: `Add`

**Verification**:

```bash
nslookup stfuncdevdevicepki001.blob.core.windows.net
# Expected: Should resolve to private IP (10.x.x.x)
```

---

##### 3. Storage File Private Endpoint (`pe-dev-aue-storage-file-dcert-poc`)

1. **Navigate to**: `pe-dev-aue-storage-file-dcert-poc`
2. **Left menu**: Click **DNS configuration**
3. **Click**: `+ Add`
4. **Configure**:
   - **Name**: `default` (or `file-dns-zone-group`)
   - **Private DNS zone**: Select `privatelink.file.core.windows.net`
   - **Resource group**: `rg-network-dev-aue-001`
5. **Click**: `Add`

**Verification**:

```bash
nslookup stfuncdevdevicepki001.file.core.windows.net
# Expected: Should resolve to private IP (10.x.x.x)
```

---

##### 4. Function App Private Endpoint (`pe-dev-aue-functionapp-dcert-poc`)

1. **Navigate to**: `pe-dev-aue-functionapp-dcert-poc`
2. **Left menu**: Click **DNS configuration**
3. **Click**: `+ Add`
4. **Configure**:
   - **Name**: `default` (or `sites-dns-zone-group`)
   - **Private DNS zone**: Select `privatelink.azurewebsites.net`
   - **Resource group**: `rg-network-dev-aue-001`
5. **Click**: `Add`

**Verification**:

```bash
nslookup func-devicepki-dev-001.azurewebsites.net
# Expected: Should resolve to private IP (10.x.x.x)

nslookup func-devicepki-dev-001.scm.azurewebsites.net
# Expected: Should resolve to private IP (10.x.x.x)
```

---

### Option 2: Azure CLI

If you have permissions to manage DNS zone groups via CLI, use these commands:

```bash
# Set variables
SUBSCRIPTION_ID="<YOUR_SUBSCRIPTION_ID>"  # Replace with your subscription ID
PE_RG="rg-dev-aue-dcert-poc"
DNS_RG="rg-network-dev-aue-001"  # Adjust to your DNS zone resource group

# 1. Key Vault Private Endpoint DNS Zone Group
az network private-endpoint dns-zone-group create \
  --resource-group $PE_RG \
  --endpoint-name pe-dev-aue-kv-dcert-poc \
  --name default \
  --private-dns-zone /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DNS_RG/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net \
  --zone-name vault

# 2. Storage Blob Private Endpoint DNS Zone Group
az network private-endpoint dns-zone-group create \
  --resource-group $PE_RG \
  --endpoint-name pe-dev-aue-storage-blob-dcert-poc \
  --name default \
  --private-dns-zone /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DNS_RG/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net \
  --zone-name blob

# 3. Storage File Private Endpoint DNS Zone Group
az network private-endpoint dns-zone-group create \
  --resource-group $PE_RG \
  --endpoint-name pe-dev-aue-storage-file-dcert-poc \
  --name default \
  --private-dns-zone /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DNS_RG/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net \
  --zone-name file

# 4. Function App Private Endpoint DNS Zone Group
az network private-endpoint dns-zone-group create \
  --resource-group $PE_RG \
  --endpoint-name pe-dev-aue-functionapp-dcert-poc \
  --name default \
  --private-dns-zone /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DNS_RG/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net \
  --zone-name sites
```

---

## Verification Checklist

After configuring all DNS zone groups, verify that private name resolution is working:

### From VM (or VPN-connected machine):

```bash
# Test Key Vault
nslookup kv-dev-aue-dcert-poc-001.vault.azure.net
# ✅ Expected: 10.x.x.x private IP

# Test Storage Blob
nslookup stfuncdevdevicepki001.blob.core.windows.net
# ✅ Expected: 10.x.x.x private IP

# Test Storage File
nslookup stfuncdevdevicepki001.file.core.windows.net
# ✅ Expected: 10.x.x.x private IP

# Test Function App
nslookup func-devicepki-dev-001.azurewebsites.net
# ✅ Expected: 10.x.x.x private IP

# Test Function App SCM
nslookup func-devicepki-dev-001.scm.azurewebsites.net
# ✅ Expected: 10.x.x.x private IP
```

---

## Troubleshooting

### Issue: DNS still resolves to public IP

**Causes**:

1. DNS zone group not created
2. DNS propagation delay (wait 2-5 minutes)
3. DNS cache on client machine

**Solutions**:

```bash
# Clear DNS cache on Linux/macOS
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder  # macOS

# Clear DNS cache on Windows
ipconfig /flushdns

# Force DNS query from Azure DNS
nslookup kv-dev-aue-dcert-poc-001.vault.azure.net 168.63.129.16
```

### Issue: Private DNS zone not found

**Solution**: Contact your platform/network team to create and link the private DNS zone to your VNet.

Required information to provide:

- Private DNS zone name (e.g., `privatelink.vaultcore.azure.net`)
- VNet name: `vnet-network-dev-aue-001`
- VNet resource group: `rg-network-dev-aue-001`
- Subscription ID: `<YOUR_SUBSCRIPTION_ID>`

### Issue: Function App health check fails after deployment

**Cause**: Storage or Key Vault DNS not resolving privately

**Solution**:

1. Verify storage DNS (blob + file) is configured first
2. Restart function app: `az functionapp restart --name func-devicepki-dev-001 --resource-group rg-dev-aue-dcert-poc`
3. Wait 30 seconds, then test health endpoint

---

## Impact of Missing DNS Configuration

| Missing DNS Zone       | Impact                                                            | Severity    |
| ---------------------- | ----------------------------------------------------------------- | ----------- |
| **Key Vault**          | Function app cannot access certificates/keys, PKI operations fail | 🔴 Critical |
| **Storage Blob**       | Function app runtime fails to start, no function execution        | 🔴 Critical |
| **Storage File**       | Function app content share inaccessible, deployment may fail      | 🔴 Critical |
| **Function App Sites** | Cannot deploy from local machine, must use VM inside VNet         | 🟡 Medium   |

---

## Deployment Sequence

⚠️ **IMPORTANT**: Configure DNS zone groups immediately after Bicep deployment and before deploying function code.

**Recommended Order**:

1. ✅ Deploy Bicep infrastructure (`az deployment group create ...`)
2. ✅ Configure Storage Blob DNS zone group
3. ✅ Configure Storage File DNS zone group
4. ✅ Configure Key Vault DNS zone group
5. ✅ Wait 2-3 minutes for DNS propagation
6. ✅ Deploy function app code
7. ✅ Verify health endpoint
8. ⚪ (Optional) Configure Function App Sites DNS zone group for local deployment

---

## Additional Resources

- [Azure Private Endpoint DNS Integration](https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Private DNS Zone Records](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)
- [Troubleshooting Azure Private Endpoint Connectivity](https://learn.microsoft.com/en-us/azure/private-link/troubleshoot-private-endpoint-connectivity)

---

## Document Version

- **Version**: 1.0
- **Last Updated**: 2026-03-22
- **Author**: Infrastructure Team
- **Status**: Production Ready
