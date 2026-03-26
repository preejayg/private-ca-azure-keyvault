# Testing Guide - PKI Certificate Authority Function App

> **📖 For comprehensive testing documentation, see [function-private-ca/QUICK_REFERENCE.md](../function-private-ca/QUICK_REFERENCE.md)**
>
> The Quick Reference guide provides complete documentation of all API endpoints, common workflows, test scripts, and deployment procedures.

## Quick Links

- **[Complete Certificate Lifecycle Guide](../function-private-ca/QUICK_REFERENCE.md)** - All endpoints, workflows, and testing scenarios
- **[Revocation Feature Documentation](../function-private-ca/REVOCATION.md)** - Detailed revoke/renew/check-revocation API docs
- **[Architecture Documentation](architecture.md)** - Infrastructure and networking details

---

## Architecture Summary

- **Function App**: `func-devicepki-dev-001` (private endpoints only, no public access)
- **Key Vault**: `kv-dev-aue-dcert-poc-001` (private endpoints, RBAC-enabled)
- **Test VM**: `<YOUR_VM_IP>` (inside VNet, SSH key: `~/.ssh/vm-dev-aue-dcert-poc-keypair.pem`)

### All API Endpoints

| Endpoint                      | Method | Purpose                         | Test Script                     |
| ----------------------------- | ------ | ------------------------------- | ------------------------------- |
| `/api/health`                 | GET    | Health check                    | N/A                             |
| `/api/create-root-ca`         | POST   | Create Root CA                  | N/A (one-time setup)            |
| `/api/get-root-ca`            | GET    | Get Root CA cert                | `./test/get-root-ca.sh`         |
| `/api/create-intermediate-ca` | POST   | Create Intermediate CA          | N/A (one-time setup)            |
| `/api/get-intermediate-ca`    | GET    | Get Intermediate CA cert        | `./test/get-intermediate-ca.sh` |
| `/api/issue-certificate`      | POST   | Issue device cert from CSR      | `./test/issue-certificate.sh`   |
| `/api/renew-certificate`      | POST   | Renew existing certificate      | `./test/renew-certificate.sh`   |
| `/api/revoke-certificate`     | POST   | Revoke certificate              | `./test/revoke-certificate.sh`  |
| `/api/check-revocation`       | GET    | Check revocation status         | `./test/check-revocation.sh`    |
| `/api/list-certificates`      | GET    | List all certificates           | `./test/list-certificates.sh`   |
| `/api/get-crl`                | GET    | Get Certificate Revocation List | See CRL testing section         |

---

## Common Testing Workflows

### 1. Initial Device Enrollment

```bash
cd function-private-ca/test
./issue-certificate.sh device-025-cert
```

### 2. Certificate Renewal

```bash
# Simple renewal (extend validity)
./renew-certificate.sh device-025-cert 730

# Renewal with key rotation
./renew-certificate.sh device-025-cert 365 false false true
```

### 3. Certificate Revocation

```bash
# Revoke compromised certificate
./revoke-certificate.sh device-025-cert keyCompromise

# Check revocation status
./check-revocation.sh device-025-cert
```

### 4. List All Certificates

```bash
# List first 100 certificates (default)
./list-certificates.sh

# List with pagination
./list-certificates.sh all 1 100 summary   # Page 1, 100 items, summary mode
./list-certificates.sh device 2 50 full    # Page 2, 50 items, full details

# Filter by type
./list-certificates.sh ca                  # Only CA certificates
./list-certificates.sh device              # Only device certificates
```

**Detail Modes:**

- `summary` (default): Fast, lightweight metadata only
- `full`: Complete certificate details (slower, parses each cert)

**Performance at Scale (10K-20K certificates):**

- Summary mode: ~2-3 seconds for 100 certs
- Full mode: ~5-8 seconds for 100 certs
- Max page size: 500 (recommend 100-200 for balance)

For detailed examples of all scenarios, see [QUICK_REFERENCE.md](../function-private-ca/QUICK_REFERENCE.md).

---

## Manual Testing via VM

All function endpoints are behind private networking. Test via the VM:

### 1. SSH to VM

```bash
ssh -i ~/.ssh/vm-dev-aue-dcert-poc-keypair.pem azureuser@<YOUR_VM_IP>
```

### 2. Get Function Master Key (one-time)

From your local machine:

```bash
az functionapp keys list \
  --name func-devicepki-dev-001 \
  --resource-group rg-dev-aue-dcert-poc \
  --query "masterKey" -o tsv
```

### 3. Test Function Endpoints

**Health Check (anonymous):**

```bash
curl -s https://func-devicepki-dev-001.azurewebsites.net/api/health | jq
```

**Get Root CA:**

```bash
MASTER_KEY="<your-master-key>"

curl -s "https://func-devicepki-dev-001.azurewebsites.net/api/get-root-ca?ca_name=device-root-ca" \
  -H "x-functions-key: $MASTER_KEY" | jq
```

**Create Root CA:**

```bash
curl -s -X POST "https://func-devicepki-dev-001.azurewebsites.net/api/create-root-ca" \
  -H "Content-Type: application/json" \
  -H "x-functions-key: $MASTER_KEY" \
  -d '{
    "common_name": "My Root CA",
    "ca_name": "my-root-ca",
    "key_size": 4096,
    "validity_days": 3650
  }' | jq
```

**Create Intermediate CA:**

```bash
curl -s -X POST "https://func-devicepki-dev-001.azurewebsites.net/api/create-intermediate-ca" \
  -H "Content-Type: application/json" \
  -H "x-functions-key: $MASTER_KEY" \
  -d '{
    "common_name": "My Intermediate CA",
    "ca_name": "my-intermediate-ca",
    "root_ca_name": "my-root-ca",
    "key_size": 4096,
    "validity_days": 1825
  }' | jq
```

**Issue Certificate from CSR:**

```bash
# Generate CSR on VM
openssl req -new -newkey rsa:2048 -nodes \
  -keyout /tmp/device.key \
  -out /tmp/device.csr \
  -subj "/CN=device.example.com" \
  -addext "subjectAltName=DNS:device.local"

# Read CSR and format for JSON
CSR_JSON=$(cat /tmp/device.csr | jq -Rs .)

# Issue certificate
curl -s -X POST "https://func-devicepki-dev-001.azurewebsites.net/api/issue-certificate" \
  -H "Content-Type: application/json" \
  -H "x-functions-key: $MASTER_KEY" \
  -d "{
    \"csr\": $CSR_JSON,
    \"intermediate_ca_name\": \"my-intermediate-ca\",
    \"certificate_name\": \"my-device-cert\",
    \"validity_days\": 365
  }" | jq
```

---

## Key Vault Operations

### List All Certificates

```bash
az keyvault certificate list \
  --vault-name kv-dev-aue-dcert-poc-001 \
  --query "[].{Name:name, Expires:attributes.expires}" -o table
```

### Get Certificate Details

```bash
az keyvault certificate show \
  --vault-name kv-dev-aue-dcert-poc-001 \
  --name device-root-ca
```

### List All Secrets (Device Certificates)

```bash
az keyvault secret list \
  --vault-name kv-dev-aue-dcert-poc-001 \
  --query "[].{Name:name, ContentType:contentType}" -o table
```

### Retrieve Device Certificate

```bash
az keyvault secret show \
  --vault-name kv-dev-aue-dcert-poc-001 \
  --name device-001-cert \
  --query value -o tsv
```

### Delete Certificate

```bash
# Delete CA certificate
az keyvault certificate delete \
  --vault-name kv-dev-aue-dcert-poc-001 \
  --name device-root-ca-test

# Delete device certificate (secret)
az keyvault secret delete \
  --vault-name kv-dev-aue-dcert-poc-001 \
  --name test-device-001-cert
```

---

## Certificate Validation with OpenSSL

### View Certificate Details

```bash
# Save certificate to file first
./get-root-ca.sh device-root-ca | grep -A 100 'BEGIN CERTIFICATE' | grep -B 100 'END CERTIFICATE' > root-ca.pem

# View certificate details
openssl x509 -in root-ca.pem -text -noout
```

### Verify Certificate Chain

```bash
# Get certificates
./get-root-ca.sh device-root-ca > root-ca.pem
./get-intermediate-ca.sh device-intermediate-ca > intermediate-ca.pem
az keyvault secret show --vault-name kv-dev-aue-dcert-poc-001 --name device-001-cert --query value -o tsv > device-001.pem

# Verify chain: device cert → intermediate CA → root CA
openssl verify -CAfile root-ca.pem -untrusted intermediate-ca.pem device-001.pem
```

**Expected output:**

```
device-001.pem: OK
```

### Check Certificate Validity

```bash
# Check dates
openssl x509 -in device-001.pem -noout -dates

# Check if certificate is currently valid
openssl x509 -in device-001.pem -noout -checkend 0 && echo "Valid" || echo "Expired"

# Check if certificate will expire in 30 days
openssl x509 -in device-001.pem -noout -checkend 2592000 && echo "Valid for >30 days" || echo "Expires in <30 days"
```

---

## Local Development Testing

For local development with mock Key Vault (optional):

### Prerequisites

- Python 3.11
- Azure Functions Core Tools
- Virtual environment set up

### Local Testing Workflow

1. **Start Function App Locally:**

```bash
cd function-private-ca
func start
```

2. **Run Local Test Suite:**

```bash
# In another terminal
cd function-private-ca/test
./test-local.sh
```

**Note:** Local testing uses mock Key Vault. For real Key Vault testing, use the VM-based scripts in `function-private-ca/test/`.

---

## Troubleshooting

### Cannot connect to Function App from local machine

**Symptom:** `curl` commands return 403 Forbidden or timeout

**Cause:** Function App has private endpoints only, no public access

**Solution:** Use VM-based test scripts or SSH to VM

### Function App not responding

**Check function app status:**

```bash
az functionapp show \
  --name func-devicepki-dev-001 \
  --resource-group rg-dev-aue-dcert-poc \
  --query "{State:state, VNet:virtualNetworkSubnetId}" -o table
```

**View logs:**

```bash
az functionapp log stream \
  --name func-devicepki-dev-001 \
  --resource-group rg-dev-aue-dcert-poc
```

### Certificate not found in Key Vault

**List all certificates:**

```bash
./list-certificates.sh
```

**Check if certificate was created:**

```bash
az keyvault certificate list \
  --vault-name kv-dev-aue-dcert-poc-001 \
  --query "[?name=='device-root-ca'].name" -o tsv
```

### RBAC Permission Errors

**Check function app managed identity roles:**

```bash
FUNC_PRINCIPAL_ID=$(az functionapp identity show \
  --name func-devicepki-dev-001 \
  --resource-group rg-dev-aue-dcert-poc \
  --query principalId -o tsv)

az role assignment list --assignee $FUNC_PRINCIPAL_ID --all -o table
```

**Expected roles:**

- Key Vault Certificates Officer
- Key Vault Crypto Officer
- Key Vault Secrets User
- Storage Blob Data Owner
- Storage Queue Data Contributor
- Storage File Data Privileged Contributor

---

## Test Scripts Reference

### Test Suite Scripts (scripts/)

| Script                       | Purpose                        | Usage                          |
| ---------------------------- | ------------------------------ | ------------------------------ |
| `test-pki-functions.sh`      | Full end-to-end test suite     | `./test-pki-functions.sh`      |
| `verify-pki-certificates.sh` | Quick certificate verification | `./verify-pki-certificates.sh` |

### Individual Test Scripts (function-private-ca/test/)

| Script                   | Purpose                       | Usage                                 |
| ------------------------ | ----------------------------- | ------------------------------------- |
| `get-root-ca.sh`         | Retrieve Root CA certificate  | `./get-root-ca.sh [ca-name]`          |
| `get-intermediate-ca.sh` | Retrieve Intermediate CA      | `./get-intermediate-ca.sh [ca-name]`  |
| `issue-certificate.sh`   | Issue device certificate      | `./issue-certificate.sh <csr> <name>` |
| `list-certificates.sh`   | List all certificates/secrets | `./list-certificates.sh`              |

All scripts execute operations via the VM for private networking compatibility.

---

## Scalability & Performance

**Current Architecture Targets: 10K-20K certificates per region**

| Certificate Count | List (Summary) | List (Full) | Issue Cert | Get CRL   |
| ----------------- | -------------- | ----------- | ---------- | --------- |
| 1K                | <1 sec         | 2-3 sec     | 2-3 sec    | 30-45 sec |
| 5K                | 1-2 sec        | 4-5 sec     | 2-3 sec    | 40-50 sec |
| 10K               | 2-3 sec        | 8-10 sec    | 2-3 sec    | 50-60 sec |
| 20K               | 3-5 sec        | 15-20 sec   | 2-3 sec    | 60-90 sec |

**Key Optimizations:**

- Pagination with summary/full modes for efficient listing
- CRL with HTTP cache headers (Cache-Control: max-age=86400 for 24-hour client caching)
- Azure Key Vault supports 25K secrets (20K device certs + CA infrastructure)
- Premium Function Plan recommended for production (no cold starts)

**Best Practices:**

- Use `summary` mode for most list operations (3x faster)
- Page size 100-200 optimal for performance/UX balance
- CRL includes cache headers; clients can cache for up to 24 hours

See [API_REFERENCE.md](API_REFERENCE.md) for detailed pagination documentation.

---

## Next Steps

After testing:

1. **Production Deployment**: Update Bicep parameters for production environment
2. **CI/CD Pipeline**: Set up Azure DevOps pipeline for automated testing
3. **Monitoring**: Configure Application Insights alerts for certificate expiration
4. **Certificate Rotation**: Implement automated certificate renewal workflows

---

## Additional Resources

- [Function App Documentation](../README.md)
- [Architecture Documentation](./architecture.md)
- [Azure DevOps Setup](./azure-devops-setup.md)
- [Private DNS Configuration](./PRIVATE_DNS_ZONE_CONFIGURATION.md)
  [5/5] Deploying to Azure Function App...
  ✅ Code deployed successfully!

Deployment Summary
Function App: func-devicepki-dev-001
Package: function-app.zip (15K)
Files Deployed: function_app.py, requirements.txt, host.json
Mock Files: Excluded (not deployed)

```

### Step 3: Configure Azure Settings

In Azure Portal → Function App → Configuration:

```

KEY_VAULT_NAME = kv-dev-aue-dcert-poc-001

````

**Important:** Do **NOT** set `USE_MOCK_KEYVAULT` in Azure. When absent, `sitecustomize.py` won't be there anyway (excluded by `.funcignore`), and the function app uses real Azure Key Vault.

### Step 4: Configure Managed Identity

1. Enable System-Assigned Managed Identity on the Function App
2. Grant Key Vault permissions:
   - **Certificates**: Get, List, Create
   - **Keys**: Get, Sign
   - **Secrets**: Get, Set

### Step 5: Test Azure Deployment

```bash
cd function-private-ca
./test-azure.sh
````

---

## Troubleshooting

### Error: "Expecting value: line 1 column 1 (char 0)"

**Cause**: Function app is not running

**Solution**:

```bash
# Check if the app is running
./check-status.sh

# If not running, start it
./start-local.sh
```

### Error: "KEY_VAULT_NAME environment variable is required"

**Cause**: Missing configuration

**Solution**:

- **Local**: Add `KEY_VAULT_NAME` to `local.settings.json`
- **Azure**: Add `KEY_VAULT_NAME` in Azure Portal → Configuration

### Mock Not Working Locally

**Check**: Is `USE_MOCK_KEYVAULT` set to `"true"` in `local.settings.json`?

**Verify**: Look for `[SITECUSTOMIZE]` and `[MOCK]` log messages when starting the function app

### sitecustomize.py Not Loading

**Check**: Is `sitecustomize.py` in the same directory as `function_app.py`?

**Verify**: Start the function app and look for `[SITECUSTOMIZE]` messages at the very beginning

---

## Configuration Reference

### local.settings.json (Local Testing)

```json
{
  "Values": {
    "KEY_VAULT_NAME": "your-keyvault-name",
    "USE_MOCK_KEYVAULT": "true" // Enable mock for local testing
  }
}
```

### Azure Function App Settings (Production)

```
KEY_VAULT_NAME = your-keyvault-name
// DO NOT SET USE_MOCK_KEYVAULT
// sitecustomize.py is not deployed anyway (.funcignore)
```

---

## Quick Reference

| Test Type            | Location                    | Command                        | Description                      |
| -------------------- | --------------------------- | ------------------------------ | -------------------------------- |
| Full Test Suite      | `scripts/`                  | `./test-pki-functions.sh`      | All endpoints + Key Vault verify |
| Quick Verification   | `scripts/`                  | `./verify-pki-certificates.sh` | List certificates & secrets      |
| Get Root CA          | `function-private-ca/test/` | `./get-root-ca.sh [name]`      | Retrieve Root CA cert            |
| Get Intermediate CA  | `function-private-ca/test/` | `./get-intermediate-ca.sh`     | Retrieve Intermediate CA cert    |
| Issue Certificate    | `function-private-ca/test/` | `./issue-certificate.sh`       | Issue device cert from CSR       |
| List All Certs       | `function-private-ca/test/` | `./list-certificates.sh`       | All certs & secrets in Key Vault |
| Local Testing (Mock) | `function-private-ca/test/` | `./test-local.sh`              | Test locally with mock Key Vault |

---

## Benefits of This Approach

✅ **Private Networking Only**: Function app is completely isolated from public internet  
✅ **VM-based Testing**: All tests run via VM inside VNet for secure access  
✅ **Organized Test Scripts**: Test scripts separated from deployment scripts  
✅ **Comprehensive Coverage**: Individual operation tests + full end-to-end suite  
✅ **Transparent Testing**: Mocks are completely invisible to application code  
✅ **Standard Python**: Uses Python's built-in `sitecustomize.py` mechanism  
✅ **Easy Debugging**: Toggle mock on/off with one env variable
