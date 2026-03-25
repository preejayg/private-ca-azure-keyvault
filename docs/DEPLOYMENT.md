# PKI Certificate Management - Deployment Guide

## Overview

This guide covers the complete deployment process for the Azure Functions-based PKI Certificate Authority with private networking.

## Architecture

- **Function App**: Python 3.11, private networking, VNet integrated
- **Storage Account**: Private endpoints, managed identity authentication
- **Key Vault**: HSM-backed certificate storage, private endpoint
- **Networking**: Private endpoints, VNet integration, Azure DNS

## Prerequisites

1. Azure subscription with appropriate permissions
2. Azure CLI installed and authenticated
3. Access to a VM in the VNet (for deployment due to private networking)
4. Network team coordination for:
   - Private DNS zone linking
   - Service endpoint configuration (if subnet managed by account vending)

## Deployment Steps

### 1. Infrastructure Deployment (From Local Machine)

```bash
cd scripts
chmod +x deploy-infrastructure.sh
./deploy-infrastructure.sh
```

This deploys:

- ✅ Key Vault with private endpoint
- ✅ Storage Account with private endpoints (blob, file)
- ✅ Function App with VNet integration
- ✅ RBAC role assignments (Storage Blob Data Owner, Key Vault access)
- ✅ App settings for managed identity storage authentication

### 2. Private DNS Configuration (Coordinate with Platform Team)

The following Private DNS zones must be linked to your VNet:

| DNS Zone                            | Purpose                       |
| ----------------------------------- | ----------------------------- |
| `privatelink.vaultcore.azure.net`   | Key Vault private endpoint    |
| `privatelink.blob.core.windows.net` | Storage blob private endpoint |
| `privatelink.file.core.windows.net` | Storage file private endpoint |
| `privatelink.azurewebsites.net`     | Function App private endpoint |

**Action Required**: Contact your platform team to link these zones.

### 3. Storage Network Access (If Service Endpoint Available)

If your network team can add `Microsoft.Storage` service endpoint to `snet-functionapp-integration`:

```bash
# After service endpoint is added by network team
cd scripts
chmod +x configure-storage-network.sh
./configure-storage-network.sh
```

**Alternative**: If service endpoints cannot be added due to account vending constraints, storage access will work through private endpoints once DNS is configured (Step 2).

### 4. Function Code Deployment (From VM)

Since the function app has `publicNetworkAccess='Disabled'`, code must be deployed from a VM in the VNet:

```bash
# SSH/Bastion to vm-dev-aue-dcert-poc

# Upload function_app_fixed.zip to VM, then:
cat > ultimate-simple-deploy.sh << 'ENDOFFILE'
#!/bin/bash
FUNCTION_APP_NAME="func-devicepki-dev-001"
RESOURCE_GROUP="rg-dev-aue-dcert-poc"

# Extract zip
unzip -o function_app_fixed.zip -d extracted/

# Get Kudu credentials
CREDS=$(az functionapp deployment list-publishing-credentials \
    --name $FUNCTION_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "{username:publishingUserName,password:publishingPassword}" \
    -o json)

USERNAME=$(echo $CREDS | jq -r '.username')
PASSWORD=$(echo $CREDS | jq -r '.password')
KUDU_URL="https://$FUNCTION_APP_NAME.scm.azurewebsites.net"

# Upload files via VFS API
curl -u "$USERNAME:$PASSWORD" -X PUT --data-binary @extracted/function_app.py \
    "$KUDU_URL/api/vfs/site/wwwroot/function_app.py"

curl -u "$USERNAME:$PASSWORD" -X PUT --data-binary @extracted/requirements.txt \
    "$KUDU_URL/api/vfs/site/wwwroot/requirements.txt"

curl -u "$USERNAME:$PASSWORD" -X PUT --data-binary @extracted/host.json \
    "$KUDU_URL/api/vfs/site/wwwroot/host.json"

# SSH in and install packages
az webapp ssh --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP << 'SSHEOF'
cd /home/site/wwwroot
python3 -m pip install --target .python_packages/lib/site-packages \
    azure-functions azure-identity \
    azure-keyvault-certificates azure-keyvault-keys azure-keyvault-secrets \
    cryptography werkzeug
exit
SSHEOF

# Restart
az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
ENDOFFILE

chmod +x ultimate-simple-deploy.sh
./ultimate-simple-deploy.sh
```

### 5. Verify Deployment

Wait 60-90 seconds after restart, then test:

```bash
SUB_ID=$(az account show --query id -o tsv)
MASTER_KEY=$(az rest --method post \
    --url "/subscriptions/$SUB_ID/resourceGroups/rg-dev-aue-dcert-poc/providers/Microsoft.Web/sites/func-devicepki-dev-001/host/default/listKeys?api-version=2022-03-01" \
    --query masterKey -o tsv)

curl "https://func-devicepki-dev-001.azurewebsites.net/api/health?code=$MASTER_KEY"
```

Expected response:

```json
{
  "status": "healthy",
  "timestamp": "2026-03-19T...",
  "keyvault_connection": "ready"
}
```

## Troubleshooting

### Storage Access Errors

**Symptom**: `AuthorizationFailure` in logs

**Solutions**:

1. Verify RBAC roles are assigned: `az role assignment list --scope <storage-id>`
2. Check VNet routing settings: `WEBSITE_VNET_ROUTE_ALL=1`
3. Verify private DNS zones are linked to VNet
4. If using service endpoints: confirm `Microsoft.Storage` is on the subnet

### Function Runtime Not Starting

**Symptom**: `InternalServerError from host runtime`

**Solutions**:

1. Check storage access (see above)
2. Verify function code is deployed (SSH in and check `/home/site/wwwroot/`)
3. Verify packages are installed (check `.python_packages/lib/site-packages/`)
4. Check DNS resolution from function app

### DNS Resolution Issues

**Symptom**: Can't reach storage or Key Vault

**Solutions**:

1. Verify private DNS zones are linked to the VNet containing the function app subnet
2. Check `WEBSITE_DNS_SERVER=168.63.129.16` is set
3. Test DNS resolution from VM in same VNet:
   ```bash
   nslookup stfuncdevdevicepki001.blob.core.windows.net
   # Should resolve to 10.x.x.x (private IP)
   ```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  VNet (vnet-network-dev-aue-001)                           │
│                                                              │
│  ┌──────────────────────┐      ┌─────────────────────────┐ │
│  │ Function App         │──────│ Private Endpoint Subnet │ │
│  │ (VNet Integrated)    │      │                         │ │
│  │ - Managed Identity   │      │ - Key Vault PE          │ │
│  │ - Route All Traffic  │      │ - Storage Blob PE       │ │
│  └──────────────────────┘      │ - Storage File PE       │ │
│           │                     │ - Function App PE       │ │
│           │                     └─────────────────────────┘ │
│           │                                  │               │
│           │  via Private Endpoints          │               │
│           └──────────────────────────────────┘               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
           │                      │
           ▼                      ▼
    ┌─────────────┐       ┌────────────┐
    │ Storage     │       │ Key Vault  │
    │ Account     │       │            │
    └─────────────┘       └────────────┘
```

## Security Features

- ✅ Private networking (no public access)
- ✅ Managed identity authentication (no connection strings)
- ✅ RBAC-based access control
- ✅ HSM-backed certificate storage
- ✅ VNet-isolated traffic flow
- ✅ TLS 1.2 minimum
- ✅ HTTPS only

## Maintenance

### Updating Infrastructure

```bash
cd scripts
./deploy-infrastructure.sh
```

Bicep deployment is idempotent - safe to re-run.

### Redeploying Function Code

From the VM:

```bash
./ultimate-simple-deploy.sh
```

### Viewing Logs

```bash
az webapp log tail --name func-devicepki-dev-001 --resource-group rg-dev-aue-dcert-poc
```

## API Endpoints

| Endpoint                      | Method | Description                                   |
| ----------------------------- | ------ | --------------------------------------------- |
| `/api/health`                 | GET    | Health status                                 |
| `/api/create_root_ca`         | POST   | Create root CA certificate                    |
| `/api/get_root_ca`            | GET    | Retrieve root CA certificate                  |
| `/api/create_intermediate_ca` | POST   | Create intermediate CA                        |
| `/api/get_intermediate_ca`    | GET    | Retrieve intermediate CA                      |
| `/api/issue_certificate`      | POST   | Issue end-entity certificate from CSR         |
| `/api/renew_certificate`      | POST   | Renew existing certificate                    |
| `/api/revoke_certificate`     | POST   | Revoke certificate with X.509 reason          |
| `/api/check_revocation`       | GET    | Check if certificate is revoked               |
| `/api/list_certificates`      | GET    | List certificates with pagination             |
| `/api/get_crl`                | GET    | Get Certificate Revocation List (DER-encoded) |

**Note:** Endpoint names use underscores (`_`) in the actual function code, but may use hyphens (`-`) in route configuration.

For detailed API documentation, see [API_REFERENCE.md](API_REFERENCE.md).

## Support

For issues related to:

- **Networking**: Contact platform/network team
- **DNS**: Contact platform team for private DNS zone linking
- **Deployment**: Check troubleshooting section above
- **Function Code**: Review application logs via log tail
