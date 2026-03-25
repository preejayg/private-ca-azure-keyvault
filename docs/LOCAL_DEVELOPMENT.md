# Local Development Setup

Guide for deploying and testing the PKI Function App from your local machine using VPN connection.

## Prerequisites

### 1. VPN Connection

Connect to the Azure virtual network where the Function App private endpoint resides.

**Check VPN Connection:**

```bash
# Verify you can reach the private subnet
ping 10.140.34.4

# Should show private IP (10.x.x.x range)
dig +short func-devicepki-dev-001.azurewebsites.net
```

### 2. Hosts File Configuration

Add the Function App hostname to your hosts file to resolve to the private endpoint IP.

**macOS/Linux:**

```bash
# Edit hosts file (requires sudo)
sudo nano /etc/hosts

# Add this line:
10.140.34.4  func-devicepki-dev-001.azurewebsites.net

# Save and verify
ping func-devicepki-dev-001.azurewebsites.net
# Should respond from 10.140.34.4
```

**Windows:**

```powershell
# Run as Administrator
notepad C:\Windows\System32\drivers\etc\hosts

# Add this line:
10.140.34.4  func-devicepki-dev-001.azurewebsites.net

# Save and verify
ping func-devicepki-dev-001.azurewebsites.net
```

### 3. Azure CLI

Ensure you're logged in to Azure CLI with proper permissions:

```bash
az login
az account show

# Verify you have access to the resource group
az group show --name rg-dev-aue-dcert-poc
```

### 4. Required Tools

- **OpenSSL**: For CSR generation and certificate verification
- **jq**: For JSON parsing
- **curl**: For HTTP requests
- **Azure CLI**: For authentication and deployment

```bash
# macOS install
brew install openssl jq curl azure-cli

# Verify installations
openssl version
jq --version
curl --version
az --version
```

## Deployment from Local Machine

### Deploy Function App

```bash
cd scripts
./deploy-local.sh
```

This script:

1. ✅ Verifies Azure CLI authentication
2. ✅ Checks VPN connection and hostname resolution
3. ✅ Builds platform-specific Python packages (Linux x86_64)
4. ✅ Creates deployment zip with dependencies
5. ✅ Deploys directly to Function App via Azure CLI
6. ✅ Verifies deployment with health check

**Deployment time:** ~60-90 seconds (no VM SSH overhead)

## Testing from Local Machine

All test scripts have `-local` versions that work via VPN:

### 1. List Certificates (Paginated)

```bash
cd function-private-ca/test

# List all certificates (page 1, 100 per page, summary mode)
./list-certificates-local.sh

# List only CA certificates
./list-certificates-local.sh ca

# List only device certificates
./list-certificates-local.sh device

# Paginated listing - page 2, 50 per page
./list-certificates-local.sh device 2 50

# Full details mode (slower, includes all certificate fields)
./list-certificates-local.sh all 1 100 full

# Large page for exports (500 max)
./list-certificates-local.sh device 1 500 summary
```

**Pagination Parameters:**

- **type**: `all`, `ca`, `device` (default: all)
- **page**: Page number, 1-based (default: 1)
- **page_size**: Items per page, max 500 (default: 100)
- **details**: `summary` or `full` (default: summary)

**Detail Modes:**

- `summary` (fast): Name, dates, enabled status only
- `full` (slower): Complete certificate details with parsing

### 2. Issue Device Certificate

```bash
# Issue certificate with auto-generated CSR
./issue-certificate-local.sh device-local-001

# Issue with custom validity
./issue-certificate-local.sh device-local-002 device-intermediate-ca 730
```

### 3. Get CRL (Certificate Revocation List)

```bash
# Download and parse intermediate CA CRL
./get-crl-local.sh intermediate

# Download root CA CRL
./get-crl-local.sh root
```

### 4. Verify Certificate with CRL

```bash
# Verify device certificate against CRL
./verify-cert-crl-local.sh device-local-001
```

## Quick Test Workflow

Complete test workflow from local machine:

```bash
cd function-private-ca/test

# 1. List existing certificates
./list-certificates-local.sh

# 2. Issue a new certificate
./issue-certificate-local.sh test-device-$(date +%s)

# 3. Verify the certificate
./verify-cert-crl-local.sh test-device-XXXXXXXXXX

# 4. Check CRL
./get-crl-local.sh intermediate
```

## Troubleshooting

### Issue: "Connection refused" or timeout

**Solution:** Check VPN connection and hostname resolution

```bash
# Test VPN connectivity
ping 10.140.34.4

# Test hostname resolution
dig +short func-devicepki-dev-001.azurewebsites.net
# Should return: 10.140.34.4

# Test HTTPS connectivity
curl -s -o /dev/null -w "%{http_code}" https://func-devicepki-dev-001.azurewebsites.net/api/health
# Should return: 200
```

### Issue: "Hostname resolves to public IP"

**Solution:** Update hosts file

```bash
# Check what IP hostname resolves to
dig +short func-devicepki-dev-001.azurewebsites.net

# If it's not 10.140.34.4, add hosts file entry:
echo "10.140.34.4  func-devicepki-dev-001.azurewebsites.net" | sudo tee -a /etc/hosts
```

### Issue: "Failed to retrieve master key"

**Solution:** Verify Azure CLI authentication and permissions

```bash
# Re-login to Azure
az login

# Verify subscription
az account show

# Test Function App access
az functionapp show --name func-devicepki-dev-001 --resource-group rg-dev-aue-dcert-poc
```

### Issue: Deployment fails with "build-remote"

**Solution:** The local deployment script uses `--build-remote false` and includes pre-built packages

```bash
# Check .python_packages directory was created
ls -la function-private-ca/.python_packages/lib/site-packages

# If missing, run deployment script again
cd scripts
./deploy-local.sh
```

## Comparison: Local vs VM Deployment

| Feature            | Local Deployment    | VM Deployment         |
| ------------------ | ------------------- | --------------------- |
| **Prerequisites**  | VPN + hosts file    | SSH key               |
| **Speed**          | ~60-90 seconds      | ~90-120 seconds       |
| **Network**        | Direct via VPN      | SSH tunnel            |
| **Use Case**       | Development/testing | Production/automation |
| **Authentication** | Azure CLI           | VM SSH key            |

## Best Practices

1. **Always verify VPN connection** before running scripts
2. **Keep hosts file updated** if private endpoint IP changes
3. **Use local scripts for rapid development** iteration
4. **Use VM scripts for production** deployments
5. **Test deployment with health check** after each update

## Script Comparison

| VM Script              | Local Script                 | Changes                                 |
| ---------------------- | ---------------------------- | --------------------------------------- |
| `deploy-from-vm.sh`    | `deploy-local.sh`            | No SSH/SCP, direct Azure CLI deployment |
| `issue-certificate.sh` | `issue-certificate-local.sh` | Direct curl to function app             |
| `get-crl.sh`           | `get-crl-local.sh`           | Direct curl, no SCP                     |
| `list-certificates.sh` | `list-certificates-local.sh` | Direct API call                         |
| `verify-cert-crl.sh`   | `verify-cert-crl-local.sh`   | Direct API calls                        |

All local scripts:

- ✅ Work over VPN connection
- ✅ Use direct HTTP/HTTPS calls (no SSH)
- ✅ Retrieve Azure credentials via Azure CLI
- ✅ Parse responses with jq
- ✅ Provide same functionality as VM scripts

## Additional Resources

- [API Reference](../docs/API_REFERENCE.md)
- [Testing Guide](../docs/TESTING_GUIDE.md)
- [Deployment Documentation](../docs/DEPLOYMENT.md)
