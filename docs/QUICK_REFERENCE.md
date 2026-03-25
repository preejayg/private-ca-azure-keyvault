# Quick Reference - Bicep Deployment

## 🚀 Deploy Infrastructure

```bash
# Quick deployment (recommended)
./scripts/deploy-keyvault.sh

# Manual deployment
az group create --name rg-dev-aue-dcert-poc --location australiaeast
az deployment group create \
  --resource-group rg-dev-aue-dcert-poc \
  --template-file ./infra/bicep/main.bicep \
  --parameters ./infra/parameters/dev.bicepparam
```

## 🔍 Preview Changes (What-If)

```bash
az deployment group what-if \
  --resource-group rg-dev-aue-dcert-poc \
  --template-file ./infra/bicep/main.bicep \
  --parameters ./infra/parameters/dev.bicepparam
```

## ✅ Validate Templates

```bash
# Validate main template
az bicep build --file ./infra/bicep/main.bicep

# Validate Key Vault module
az bicep build --file ./infra/bicep/modules/keyvault/keyvault.bicep

# Validate Private Endpoint module
az bicep build --file ./infra/bicep/modules/privateendpoint/privateendpoint.bicep
```

## 📋 Get Deployment Outputs

```bash
# All outputs
az deployment group show \
  --resource-group rg-dev-aue-dcert-poc \
  --name main \
  --query properties.outputs

# Specific outputs
az deployment group show \
  --resource-group rg-dev-aue-dcert-poc \
  --name main \
  --query properties.outputs.keyVaultName.value -o tsv

az deployment group show \
  --resource-group rg-dev-aue-dcert-poc \
  --name main \
  --query properties.outputs.privateIP.value -o tsv
```

## 🔐 Get Your Object ID

```bash
az ad signed-in-user show --query id -o tsv
```

## 🌐 Configure DNS (After Deployment)

```bash
# Get values
KEYVAULT_NAME=$(az deployment group show \
  --resource-group rg-dev-aue-dcert-poc \
  --name main \
  --query properties.outputs.keyVaultName.value -o tsv)

PRIVATE_IP=$(az deployment group show \
  --resource-group rg-dev-aue-dcert-poc \
  --name main \
  --query properties.outputs.privateIP.value -o tsv)

# Add to hosts file (macOS/Linux)
sudo bash -c "echo \"$PRIVATE_IP ${KEYVAULT_NAME}.vault.azure.net\" >> /etc/hosts"

# Flush DNS cache
sudo dscacheutil -flushcache  # macOS
# OR
sudo systemd-resolve --flush-caches  # Linux
```

## 🧪 Test Access

```bash
# List secrets (should work after DNS configuration)
az keyvault secret list --vault-name $(az deployment group show \
  --resource-group rg-dev-aue-dcert-poc \
  --name main \
  --query properties.outputs.keyVaultName.value -o tsv)

# Test connectivity to private endpoint
KEYVAULT_NAME=$(az deployment group show \
  --resource-group rg-dev-aue-dcert-poc \
  --name main \
  --query properties.outputs.keyVaultName.value -o tsv)
nslookup ${KEYVAULT_NAME}.vault.azure.net
```

## 🗑️ Clean Up Resources

```bash
# Delete resource group and all resources
az group delete --name rg-dev-aue-dcert-poc --yes --no-wait
```

## 📁 File Structure

```
infra/
├── bicep/
│   ├── main.bicep                    # Main orchestration
│   └── modules/
│       ├── keyvault/
│       │   └── keyvault.bicep        # Key Vault module
│       └── privateendpoint/
│           └── privateendpoint.bicep # Private Endpoint module
└── parameters/
    └── dev.bicepparam                # Dev environment config

scripts/
└── deploy-keyvault.sh                # Automated deployment

docs/
├── BICEP_MIGRATION.md                # Detailed documentation
├── CONVERSION_SUMMARY.md             # Migration summary
├── QUICK_REFERENCE.md                # This file
└── CONVERSION_MAP.md                 # Detailed mapping
```

## 🔑 Key Resources Created

| Resource Type    | Name                                  | Purpose                     |
| ---------------- | ------------------------------------- | --------------------------- |
| Resource Group   | rg-dev-aue-dcert-poc                  | Container for all resources |
| Key Vault        | kv-dev-aue-dcert-poc-001              | Secure credential storage   |
| Private Endpoint | private-endpoint-dev-aue-kv-dcert-poc | Private network access      |

## ⚙️ Configuration Files

| File                                          | Purpose                  | Update Needed        |
| --------------------------------------------- | ------------------------ | -------------------- |
| `infra/parameters/dev.bicepparam`             | Dev environment settings | ✅ Update `objectId` |
| `infra/bicep/main.bicep`                      | Main template            | ❌ No changes needed |
| `infra/bicep/modules/keyvault/keyvault.bicep` | Key Vault module         | ❌ No changes needed |

## 📚 Documentation

- **Complete Guide**: [BICEP_MIGRATION.md](BICEP_MIGRATION.md)
- **Summary**: [CONVERSION_SUMMARY.md](CONVERSION_SUMMARY.md)
- **Architecture**: [../docs/architecture.md](../docs/architecture.md)

## 🆘 Troubleshooting

| Issue                   | Solution                                            |
| ----------------------- | --------------------------------------------------- |
| Cannot access Key Vault | Add private IP to hosts file                        |
| Subnet error            | Run `./infra/deploy-keyvault.sh` which handles this |
| Object ID error         | Update `objectId` in `dev.bicepparam`               |
| DNS not resolving       | Flush DNS cache and verify hosts file entry         |

## 🔄 Multi-Environment Deployment

```bash
# Create test environment parameters
cp infra/parameters/dev.bicepparam infra/parameters/test.bicepparam

# Edit test.bicepparam with test values
# Then deploy
az deployment group create \
  --resource-group rg-test-aue-dcert-poc \
  --template-file ./infra/bicep/main.bicep \
  --parameters ./infra/parameters/test.bicepparam
```

---

## 📈 PKI Function App Quick Reference

For complete certificate lifecycle management, see:

- **[Function App Testing Guide](TESTING_GUIDE.md)** - Complete API endpoints, workflows, and testing
- **[API Reference](API_REFERENCE.md)** - Detailed API documentation with pagination, CRL caching
- **[Local Development Guide](LOCAL_DEVELOPMENT.md)** - Local testing and development workflow

---

**Last Updated**: 2026-03-25  
**Bicep Version**: 0.40.x+  
**Azure CLI Version**: 2.20.0+
