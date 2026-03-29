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

## 📊 Standards Compliance

### RFC 5280 (X.509 PKI) ✅ **Compliant**

- ✅ Basic certificate structure
- ✅ Extensions handling
- ✅ CRL format
- ⚠️ Missing: OCSP, some optional extensions

### CA/Browser Forum Baseline Requirements ⚠️ **Partial**

_(Applicable if issuing publicly-trusted certificates)_

- ✅ Maximum validity: 397 days (currently 365)
- ✅ Key storage: HSM required
- ⚠️ CRL/OCSP: CRL only (OCSP missing)
- ❌ Audit logging: Needs enhancement for compliance

### NIST SP 800-57 ✅ **Compliant**

- ✅ Key sizes: 4096-bit RSA (exceeds 2048 minimum)
- ✅ Key separation: Root/Intermediate separate
- ✅ HSM protection: Azure Key Vault HSM (FIPS 140-2 Level 2)

**Overall Score: 7.5/10** - Solid foundation with room for hardening

## � Production Readiness TODO

### Critical (Security & Compliance)

- [ ] **OCSP Responder**: Add Online Certificate Status Protocol support for real-time revocation checking
- [ ] **Certificate Chain Validation**: Verify intermediate CA is properly signed by root CA before issuance
- [ ] **Audit Logging**: Implement immutable audit trail (Azure Monitor/Sentinel) for all certificate operations
- [ ] **Rate Limiting**: Add per-IP/per-identity limits to prevent certificate issuance attacks

### Important (Operational Excellence)

- [ ] **Certificate Policy OIDs**: Add certificate policies to classify certificate types and usage
- [ ] **Name Constraints**: Add to Root CA to restrict what domains/names Intermediate CA can issue
- [ ] **Stronger Authentication**: Migrate from function keys to certificate-based or managed identity auth
- [ ] **Certificate Expiry Monitoring**: Azure Monitor alerts for CA expiration (30/60/90 days before)
- [ ] **Subject Validation**: Add CSR subject name validation rules (e.g., CN must match patterns)
- [ ] **AIA Extension**: Add Authority Information Access extension for CA certificate discovery

### Enhancements (Performance & Reliability)

- [ ] **CRL Caching**: Cache generated CRLs for 24 hours instead of generating on every request
- [ ] **Certificate Templates**: Define preset configurations for different certificate types (IoT, server, etc.)
- [ ] **Backup & DR Strategy**: Document and implement Key Vault backup and disaster recovery procedures
- [ ] **Multi-Region Deployment**: Deploy secondary CA for high availability
- [ ] **Performance Testing**: Load test with 1000+ concurrent certificate requests
- [ ] **Security Review**: Professional penetration testing and security audit

### Compliance (If Required)

- [ ] **CPS Documentation**: Write Certification Practice Statement
- [ ] **SOC2/ISO27001**: Compliance audit preparation
- [ ] **CA/Browser Forum**: Ensure compliance with Baseline Requirements (if publicly-trusted)

## �🚀 Quick Start

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Bicep](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) (included with Azure CLI 2.20.0+)
- [VS Code](https://code.visualstudio.com/) with Bicep extension
- Azure subscription

📖 **Detailed documentation**: See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for complete deployment guide and [docs/PRIVATE_DNS_ZONE_CONFIGURATION.md](docs/PRIVATE_DNS_ZONE_CONFIGURATION.md) for DNS setup.

### Setup

1. **Clone and open in VS Code:**

```bash
   git clone <your-repo>
   cd private-ca-azure-keyvault
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
private-ca-azure-keyvault/
├── docs/                   # Documentation
│   ├── architecture.md            # System architecture
│   ├── azure-devops-setup.md      # Azure DevOps CI/CD setup guide
│   └── DEPLOYMENT.md              # Deployment guide
├── infra/                  # Infrastructure as Code
│   ├── bicep/              # Bicep templates
│   │   ├── main.bicep             # Main orchestration
│   │   └── modules/               # Reusable modules (keyvault, storage, functionapp, etc.)
│   └── parameters/         # Environment parameters
├── scripts/                # Deployment scripts
│   ├── deploy-infrastructure.sh   # Deploy complete infrastructure (Key Vault, Storage, Function App)
│   ├── configure-dns-zones.sh     # Configure private DNS zones
│   ├── deploy-app-from-local.sh   # Deploy function code from local (VPN required)
│   ├── deploy-app-from-vm.sh      # Deploy function code from VM
│   └── setup-local-dev.sh         # Local development setup
├── function-private-ca/    # Private CA management function
│   ├── function_app.py            # Azure Function implementation
│   ├── mock_keyvault.py           # Mock Key Vault for local testing
│   ├── requirements.txt           # Python dependencies
│   └── test/                      # Test scripts
└── azure-pipelines.yml     # Azure DevOps CI/CD pipeline
```

## � Deployment

### 1. Deploy Infrastructure

Deploy infrastructure using Bicep:

```bash
# Deploy complete infrastructure (Key Vault, Storage, Function App)
./scripts/deploy-infrastructure.sh
```

Configure DNS for private endpoints:

```bash
./scripts/configure-dns-zones.sh
```

Or coordinate with platform team to link private DNS zones to your VNet.

### 2. Deploy Function Code

**⚠️ Important: Function App has `publicNetworkAccess: Disabled` - deployment requires network access.**

Choose one of these deployment methods:

#### Option A: Deploy from Local Machine (with VPN)

Requires VPN connection to Azure VNet and hosts file configuration:

```bash
# Deploy from local machine (requires VPN + hosts file setup)
./scripts/deploy-app-from-local.sh
```

**Prerequisites:**

- VPN connection to Azure VNet
- Hosts file entry: `<FUNCTION_APP_PRIVATE_IP>  func-devicepki-dev-001.azurewebsites.net`

See [docs/LOCAL_DEVELOPMENT.md](docs/LOCAL_DEVELOPMENT.md) for VPN and hosts file setup.

#### Option B: Deploy from VM (Recommended)

Deploy via VM inside the VNet (no VPN required):

```bash
# Deploy from VM (recommended for production)
./scripts/deploy-app-from-vm.sh
```

#### Option C: Azure DevOps Pipeline (Automated CI/CD)

Set up automated deployment using the provided `azure-pipelines.yml`:

- Deploys automatically on code changes
- Runs from Azure-hosted agents with network access
- Supports approval gates for production
- See [docs/azure-devops-setup.md](docs/azure-devops-setup.md) for setup

📖 **See detailed instructions**: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)

### 3. Test Function App

Comprehensive test scripts are available in `function-private-ca/test/` directory.

**Production Testing** (requires VPN or VM access):

```bash
# Complete PKI workflow test
cd function-private-ca/test

# From local machine with VPN
./create-root-ca-local.sh
./create-intermediate-ca-local.sh
./issue-certificate-local.sh device-001-cert

# OR from VM
./create-root-ca.sh
./create-intermediate-ca.sh
./issue-certificate.sh device-001-cert
```

**Local Development Testing** (no Azure connectivity required):

```bash
cd function-private-ca
func start
./test/test-local.sh
```

📖 **See full testing guide**: [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md)

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

📖 **See comprehensive testing guide**: [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md)

## 📚 Documentation

- [Architecture Overview](docs/architecture.md)
- [API Reference](docs/API_REFERENCE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Testing Guide](docs/TESTING_GUIDE.md)
- [Azure DevOps Setup](docs/azure-devops-setup.md)
- [Private DNS Configuration](docs/PRIVATE_DNS_ZONE_CONFIGURATION.md)
- [Local Development](docs/LOCAL_DEVELOPMENT.md)

## 🛠️ Common Commands

```bash
# Validate Bicep templates
az bicep build --file infra/bicep/main.bicep

# Preview deployment changes
az deployment group what-if \
  --resource-group rg-dev-aue-dcert-poc \
  --template-file infra/bicep/main.bicep \
  --parameters infra/parameters/dev.bicepparam

```

## 🤝 Contributing

1. Create feature branch
2. Update appropriate phase module
3. Test in dev environment
4. Submit pull request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.
