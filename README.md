# Private Certificate Authority (PKI) with Azure KeyVault

Production-grade Private Certificate Authority (PKI) system for IoT device identity and credential management, built on Azure KeyVault with HSM-protected cryptographic operations.

## 🎯 Project Overview

This project provides a complete PKI infrastructure for managing IoT device identities, X.509 certificates, and secure device authentication using Azure Key Vault HSM.

### Current Implementation: Production PKI System ✅

- **Private Certificate Authority**: 3-tier PKI hierarchy (Root CA → Intermediate CA → Device Certificates)
- **HSM-Protected Keys**: All CA private keys stored in Azure Key Vault HSM (non-exportable)
- **Certificate Lifecycle**: Issue, renew, revoke, and validate X.509 certificates
- **CRL Distribution**: Certificate Revocation List generation and distribution
- **Secure Architecture**: Private networking with Azure Private Endpoints
- **Automated Deployment**: Infrastructure as Code (Bicep) with CI/CD pipeline

### Key Features

✅ **HSM Signing**: All certificate operations use Azure Key Vault HSM (CryptographyClient with RS256)  
✅ **Non-Exportable Keys**: CA private keys never leave the HSM boundary  
✅ **CSR Processing**: Full Certificate Signing Request support  
✅ **CRL Management**: Automated revocation checking with HSM-signed CRLs  
✅ **Certificate Renewal**: Support for key rotation or simple expiry extension  
✅ **Audit Trail**: Complete logging and revocation tracking

See [docs/API_REFERENCE.md](docs/API_REFERENCE.md) for API documentation and [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md) for testing procedures.

## 🚀 Quick Start

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Bicep](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) (included with Azure CLI 2.20.0+)
- [VS Code](https://code.visualstudio.com/) with Bicep extension
- Azure subscription
- **Azure DevOps** (for automated CI/CD deployment)

### Infrastructure Deployment (Bicep IaC)

The project uses **Infrastructure as Code** with Bicep templates.

1. **Get your Azure Object ID:**

   ```bash
   az ad signed-in-user show --query id -o tsv
   ```

2. **Update the parameter file:**

   Edit `infra/parameters/dev.bicepparam` and set your `objectId`

3. **Deploy using the automated script:**

   ```bash
   ./scripts/deploy-keyvault.sh
   ```

   Or manually:

   ```bash
   # Create resource group
   az group create --name rg-dev-aue-dcert-poc --location australiaeast

   # Deploy infrastructure
   az deployment group create \
     --resource-group rg-dev-aue-dcert-poc \
     --template-file ./infra/bicep/main.bicep \
     --parameters ./infra/parameters/dev.bicepparam
   ```

4. **Configure DNS for private endpoint:**

   Follow the instructions displayed after deployment to add the private IP to your hosts file.

📖 **Detailed documentation**: See [docs/BICEP_MIGRATION.md](docs/BICEP_MIGRATION.md) for complete migration guide and [docs/CONVERSION_SUMMARY.md](docs/CONVERSION_SUMMARY.md) for quick reference.

### Legacy Script (Deprecated)

The original `setup-keyvault.sh` script is now **deprecated** in favor of the Bicep IaC approach. Use `./scripts/deploy-keyvault.sh` instead.

### Setup

1. **Clone and open in VS Code:**

```bash
   git clone <your-repo>
   cd pos-device-identity
   code .
```

2. **Run local setup script:**

```bash
   chmod +x scripts/*.sh
   ./scripts/setup-local-dev.sh
```

3. **Get your Object ID:**

```bash
   az login
   az ad signed-in-user show --query id -o tsv
```

4. **Update parameter files** with your Object ID:
   - `infra/parameters/dev.bicepparam`
   - `infra/parameters/prod.bicepparam`

## 📁 Project Structure

```
pos-device-identity/
├── docs/                   # Documentation
│   ├── architecture.md            # System architecture
│   ├── azure-devops-setup.md      # Azure DevOps CI/CD setup guide
│   └── BICEP_MIGRATION.md         # Bicep migration documentation
├── infra/                  # Infrastructure as Code
│   ├── bicep/              # Bicep templates
│   │   ├── main.bicep             # Main orchestration
│   │   └── modules/               # Reusable modules (keyvault, storage, functionapp, etc.)
│   └── parameters/         # Environment parameters
├── scripts/                # Manual deployment scripts (optional)
│   ├── deploy-keyvault.sh         # Deploy Key Vault infrastructure
│   ├── deploy-functionapp.sh      # Deploy Function App infrastructure
│   └── setup-local-dev.sh         # Local development setup
├── function-rootca/        # Root CA management function
│   ├── function_app.py            # Azure Function implementation
│   ├── mock_keyvault.py           # Mock Key Vault for local testing
│   ├── requirements.txt           # Python dependencies
│   └── test-local.sh              # Local testing script
└── azure-pipelines.yml     # Azure DevOps CI/CD pipeline
```

## � Deployment

### 1. Deploy Infrastructure

Deploy Key Vault and Function App infrastructure using Bicep:

```bash
# Deploy Key Vault only
./scripts/deploy-keyvault.sh

# Deploy Function App infrastructure (includes storage, networking, VNet integration)
./scripts/deploy-functionapp.sh
```

### 2. Deploy Function Code

**⚠️ Important: Function App has `publicNetworkAccess: Disabled` due to corporate policy.**

You **cannot** deploy from your local machine. Use one of these methods:

#### Option A: Azure Portal Upload (Recommended for Quick Deploy)

```bash
# 1. Create deployment package
./scripts/create-deployment-package.sh

# 2. Upload via Azure Portal:
#    - Go to https://portal.azure.com
#    - Navigate to func-devicepki-dev-001
#    - Click "Deployment Center" → "Upload" tab
#    - Upload function-rootca.zip
```

#### Option B: Azure DevOps Pipeline (Recommended for Production)

Set up automated deployment using the provided `azure-pipelines.yml`:

- Deploys automatically on code changes
- Runs from Azure-hosted agents with network access
- Supports approval gates for production
- See [docs/deploy-from-cloudshell.md](docs/deploy-from-cloudshell.md) for setup

📖 **See detailed instructions**: [docs/deploy-from-cloudshell.md](docs/deploy-from-cloudshell.md)

### 3. Test Function App

Test the deployed functions (also requires Cloud Shell or Azure network access):

```bash
# From Azure Cloud Shell
./scripts/test-functioncode.sh
```

### Local Development

Test functions locally with mock Key Vault (no Azure connectivity required):

```bash
cd function-rootca
./test-local.sh
```

## �🔐 Phase 1: Key Vault

The Key Vault stores:

- Device connection strings
- Device certificates
- API keys and secrets
- Service principal credentials

### Environment Configurations

| Feature          | Dev       | Test      | Prod             |
| ---------------- | --------- | --------- | ---------------- |
| SKU              | Standard  | Standard  | Premium          |
| Purge Protection | ❌        | ❌        | ✅               |
| Network Access   | Allow All | Allow All | Deny (VNet only) |
| Soft Delete      | 7 days    | 30 days   | 90 days          |

## 🧪 Testing Your Deployment

```bash
# List deployed resources
az resource list --resource-group rg-device-identity-dev --output table

# Test Key Vault access
KV_NAME=$(az keyvault list --resource-group rg-device-identity-dev --query '[0].name' -o tsv)
az keyvault secret set --vault-name $KV_NAME --name test-secret --value "Hello Device Identity"
az keyvault secret show --vault-name $KV_NAME --name test-secret
```

## 📚 Documentation

- [Architecture Overview](docs/architecture.md)
- [Implementation Phases](docs/phases.md)

## 🛠️ Common Commands

```bash
# Validate Bicep templates
az bicep build --file infra/bicep/main.bicep

# Preview deployment changes
az deployment group what-if \
  --resource-group rg-device-identity-dev \
  --template-file infra/bicep/main.bicep \
  --parameters infra/parameters/dev.bicepparam

# Delete resources
az group delete --name rg-device-identity-dev --yes
```

## 🤝 Contributing

1. Create feature branch
2. Update appropriate phase module
3. Test in dev environment
4. Submit pull request

## 📝 License

[Your License Here]
