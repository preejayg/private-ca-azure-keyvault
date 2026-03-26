# PKI Certificate Management - Deployment Guide

## Overview

This guide covers the complete deployment process for the Azure Functions-based PKI Certificate Authority with private networking.

## Quick Deployment Summary

**3-Phase Deployment:**

1. **Infrastructure** → Deploy via Bicep (`./scripts/deploy-infrastructure.sh`)
2. **DNS Configuration** → Link private DNS zones (`./scripts/configure-dns-zones.sh`)
3. **Function Code** → Deploy from VPN or VM (`./scripts/deploy-app-from-*.sh`)

**Estimated Time:** 20-30 minutes for full deployment

---

## Architecture

- **Function App**: Python 3.11, private networking, VNet integrated
- **Storage Account**: Private endpoints, managed identity authentication
- **Key Vault**: HSM-backed certificate storage, private endpoint
- **Networking**: Private endpoints, VNet integration, Azure DNS

## Prerequisites

1. Azure subscription with appropriate permissions
2. Azure CLI installed and authenticated
3. Python 3.11 for local development
4. OpenSSL for generating CSRs
5. Access to a VM in the VNet (for deployment due to private networking) or VPN connection
6. Network team coordination for:
   - Private DNS zone linking
   - Service endpoint configuration (if subnet managed by account vending)

### Configuration

1. **Get your Azure Object ID:**

   ```bash
   az ad signed-in-user show --query id -o tsv
   ```

2. **Update parameter file:**
   Edit `infra/parameters/dev.bicepparam` and set:
   - `objectId` (from step 1)
   - `existingPrivateEndpointVNetName` (e.g., 'vnet-network-dev-aue-001')
   - `existingPrivateEndpointVNetResourceGroup` (e.g., 'rg-network-dev-aue-001')
   - `existingPrivateEndpointSubnetName` (e.g., 'snet-privateendpoint')
   - `functionAppSubnetName` (e.g., 'snet-functionapp-integration')

### Available Deployment Scripts

| Script                     | Purpose                                 | Network Requirement |
| -------------------------- | --------------------------------------- | ------------------- |
| `deploy-infrastructure.sh` | Deploy all Azure infrastructure (Bicep) | Local machine       |
| `configure-dns-zones.sh`   | Configure private DNS zones             | Local machine       |
| `deploy-app-from-local.sh` | Deploy function code from local machine | VPN + hosts file    |
| `deploy-app-from-vm.sh`    | Deploy function code via VM             | VM SSH access       |
| `setup-local-dev.sh`       | Setup local development environment     | Local machine       |

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

**Option 1 - Automated (Recommended):**

```bash
cd scripts
chmod +x configure-dns-zones.sh
./configure-dns-zones.sh
```

**Option 2 - Manual:** Contact your platform team to link these zones to your VNet.

See [PRIVATE_DNS_ZONE_CONFIGURATION.md](PRIVATE_DNS_ZONE_CONFIGURATION.md) for detailed DNS setup instructions.

### 3. Storage Network Access

**Option 1 - Service Endpoint (Better Performance):**

If your network team can add `Microsoft.Storage` service endpoint to `snet-functionapp-integration`, storage access will be faster.

**Option 2 - Private Endpoints Only (Default):**

Storage access works through private endpoints once DNS is configured (Step 2). This is the default configuration and works without additional subnet configuration.

**Note:** The infrastructure deployment (Step 1) configures both approaches. Choose based on your network team's policies.

### 4. Function Code Deployment

Since the function app has `publicNetworkAccess='Disabled'`, code must be deployed from within the VNet.

#### Option A: Deploy from Local Machine (with VPN)

If you have VPN access to the Azure VNet:

**Prerequisites:**

- VPN connection active
- Hosts file configured: `10.140.34.4  func-devicepki-dev-001.azurewebsites.net`

See [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) for VPN and hosts file setup.

**Deploy:**

```bash
cd scripts
chmod +x deploy-app-from-local.sh
./deploy-app-from-local.sh
```

The script will:

1. Build platform-specific Python packages (Linux x86_64)
2. Package function code with dependencies
3. Deploy via Azure CLI using config-zip
4. Verify deployment

#### Option B: Deploy from VM (Recommended for Production)

Deploy from a VM inside the VNet (no VPN required):

```bash
cd scripts
chmod +x deploy-app-from-vm.sh
./deploy-app-from-vm.sh
```

The script will:

1. Build platform-specific Python packages locally
2. Package function code with dependencies
3. SCP package to VM (10.140.34.6)
4. SSH to VM and deploy using Azure CLI
5. Verify deployment

**Prerequisites:**

- SSH key at `~/.ssh/vm-dev-aue-dcert-poc-keypair.pem`
- VM accessible at 10.140.34.6

#### Option C: Azure DevOps Pipeline (Automated CI/CD)

For automated deployments, use the provided Azure DevOps pipeline:

```bash
# The pipeline is defined in azure-pipelines.yml
```

See [azure-devops-setup.md](azure-devops-setup.md) for pipeline configuration.

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

**From Local (with VPN):**

```bash
cd scripts
./deploy-app-from-local.sh
```

**From VM:**

```bash
cd scripts
./deploy-app-from-vm.sh
```

**Via Azure DevOps:**
Commit changes to `main` or `develop` branch - pipeline will auto-deploy.

### Viewing Logs

```bash
az webapp log tail --name func-devicepki-dev-001 --resource-group rg-dev-aue-dcert-poc
```

## API Endpoints

| Endpoint                      | Method | Description                                   |
| ----------------------------- | ------ | --------------------------------------------- |
| `/api/health`                 | GET    | Health status                                 |
| `/api/create-root-ca`         | POST   | Create root CA certificate                    |
| `/api/get-root-ca`            | GET    | Retrieve root CA certificate                  |
| `/api/create-intermediate-ca` | POST   | Create intermediate CA                        |
| `/api/get-intermediate-ca`    | GET    | Retrieve intermediate CA                      |
| `/api/get-certificate`        | GET    | Get specific certificate                      |
| `/api/issue-certificate`      | POST   | Issue end-entity certificate from CSR         |
| `/api/renew-certificate`      | POST   | Renew existing certificate                    |
| `/api/revoke-certificate`     | POST   | Revoke certificate with X.509 reason          |
| `/api/check-revocation`       | GET    | Check if certificate is revoked               |
| `/api/list-certificates`      | GET    | List certificates with pagination             |
| `/api/crl/{ca_name}`          | GET    | Get Certificate Revocation List (DER-encoded) |

**Note:** All endpoints use hyphens (`-`) in route configuration.

For detailed API documentation with request/response examples, see [API_REFERENCE.md](API_REFERENCE.md).

## Testing

Comprehensive test scripts are available in `function-private-ca/test/` directory.

**Quick Test (from VM):**

```bash
cd function-private-ca/test
./create-root-ca.sh
./create-intermediate-ca.sh
./issue-certificate.sh device-001-cert
./list-certificates.sh
```

**Local Development Testing:**

```bash
cd function-private-ca
func start
./test/test-local.sh
```

For comprehensive testing procedures, see [TESTING_GUIDE.md](TESTING_GUIDE.md).

## Support

For issues related to:

- **Networking**: Contact platform/network team
- **DNS**: Contact platform team for private DNS zone linking
- **Deployment**: Check troubleshooting section above
- **Function Code**: Review application logs via log tail
