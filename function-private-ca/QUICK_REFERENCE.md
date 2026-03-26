# Certificate Lifecycle Quick Reference

## Complete Certificate Lifecycle

The PKI Function App provides **complete certificate lifecycle management**:

```
ISSUE → RENEW → REVOKE
  ↓       ↓       ↓
CHECK ← LIST ← CHECK
```

## API Endpoints Summary

| Endpoint                  | Method | Purpose                                         |
| ------------------------- | ------ | ----------------------------------------------- |
| `/api/issue-certificate`  | POST   | Issue new device certificate from CSR           |
| `/api/renew-certificate`  | POST   | Renew certificate with extended validity        |
| `/api/revoke-certificate` | POST   | Revoke certificate with X.509 reason            |
| `/api/check-revocation`   | GET    | Check if certificate is revoked                 |
| `/api/list-certificates`  | GET    | List all CA and device certificates (paginated) |
| `/api/get-crl`            | GET    | Get Certificate Revocation List (24-hour cache) |

## Common Workflows

### 1. Initial Device Enrollment

```bash
# Generate CSR and issue certificate
./test/issue-certificate.sh device-025-cert

# Verify certificate was issued
./test/list-certificates.sh
```

### 2. Certificate Expiring Soon

```bash
# Simple renewal (reuse existing subject/key)
./test/renew-certificate.sh device-025-cert 730

# Renewal with key rotation (new CSR)
./test/renew-certificate.sh device-025-cert 365 false false true
```

### 3. Key Compromise Scenario

```bash
# Immediately revoke compromised certificate
./test/revoke-certificate.sh device-025-cert keyCompromise

# Issue new certificate
./test/issue-certificate.sh device-025-cert
```

### 4. Certificate Replacement

```bash
# Renew and auto-revoke old certificate
./test/renew-certificate.sh device-025-cert 365 true superseded

# Verify old certificate was revoked
./test/check-revocation.sh device-025-cert
```

### 5. Device Decommissioning

```bash
# Revoke certificate permanently
./test/revoke-certificate.sh device-025-cert cessationOfOperation

# Verify revocation
./test/check-revocation.sh device-025-cert
```

## Renewal Scenarios

### Scenario 1: Simple Renewal (Same Key)

**Use Case:** Extend certificate validity without changing key pair

```bash
./test/renew-certificate.sh device-020-cert 730
```

- ✅ Reuses existing subject
- ✅ Reuses existing public key
- ✅ New serial number
- ✅ Extended validity (2 years)
- ⚪ Old certificate remains valid

### Scenario 2: Renewal with Auto-Revoke

**Use Case:** Replace certificate and ensure old one is revoked

```bash
./test/renew-certificate.sh device-002-cert 365 true superseded
```

- ✅ Issues new certificate
- ✅ Automatically revokes old certificate
- ✅ Revocation reason: "superseded"
- ✅ Atomic operation (both in same request)

### Scenario 3: Renewal with Key Rotation

**Use Case:** Security best practice - rotate cryptographic keys

```bash
./test/renew-certificate.sh device-020-cert 365 false false true
```

- ✅ Generates new 2048-bit RSA key pair
- ✅ Creates new CSR automatically
- ✅ Issues certificate with new public key
- ⚠️ New private key saved in temp directory
- 📝 Must distribute new private key to device

## Revocation Reasons (X.509 Standard)

| Reason                 | When to Use                                                 |
| ---------------------- | ----------------------------------------------------------- |
| `unspecified`          | General revocation                                          |
| `keyCompromise`        | Private key was exposed                                     |
| `caCompromise`         | CA was compromised                                          |
| `affiliationChanged`   | Certificate holder changed organization                     |
| `superseded`           | Certificate replaced by newer one (most common for renewal) |
| `cessationOfOperation` | Device decommissioned                                       |
| `certificateHold`      | Temporary suspension (can be reversed)                      |
| `privilegeWithdrawn`   | Permissions removed                                         |
| `aaCompromise`         | Attribute authority compromised                             |

## Test Scripts Usage

### Issue Certificate

```bash
# Basic usage
./test/issue-certificate.sh <cert-name>

# Example
./test/issue-certificate.sh device-030-cert
```

### Renew Certificate

```bash
# Syntax
./test/renew-certificate.sh <cert-name> [validity_days] [auto_revoke] [reason] [generate_csr]

# Examples
./test/renew-certificate.sh device-030-cert                      # Simple renewal
./test/renew-certificate.sh device-030-cert 730                  # 2-year renewal
./test/renew-certificate.sh device-030-cert 365 true             # Renew + revoke old
./test/renew-certificate.sh device-030-cert 365 true superseded  # Renew + revoke with reason
./test/renew-certificate.sh device-030-cert 365 false false true # Key rotation
```

### Revoke Certificate

```bash
# Syntax
./test/revoke-certificate.sh <cert-name> [reason]

# Examples
./test/revoke-certificate.sh device-030-cert keyCompromise
./test/revoke-certificate.sh device-030-cert cessationOfOperation
```

### Check Revocation

```bash
./test/check-revocation.sh <cert-name>

# Example
./test/check-revocation.sh device-030-cert
```

### List Certificates

```bash
# Basic usage (page 1, 100 items, summary mode)
./test/list-certificates.sh

# With pagination parameters
./test/list-certificates.sh <type> <page> <page_size> <details>

# Examples
./test/list-certificates.sh all 1 100 summary    # First 100, lightweight
./test/list-certificates.sh device 2 50 full      # Page 2, 50 device certs, full details
./test/list-certificates.sh ca 1 20 summary       # All CA certs, summary only
```

**Parameters:**

- `type`: `all` (default), `ca`, or `device`
- `page`: Page number (1-based, default: 1)
- `page_size`: Items per page (default: 100, max: 500)
- `details`: `summary` (default, fast) or `full` (complete, slower)

**Scalability:** Optimized for 10K-20K certificates per region. See [API_REFERENCE.md](../docs/API_REFERENCE.md#10-list-certificates-paginated) for performance metrics.

## CRL (Certificate Revocation List)

```bash
# Get CRL (with cache headers for client caching)
curl -s "https://func-devicepki-dev-001.azurewebsites.net/api/get-crl?ca_name=device-intermediate-ca" \
  -H "x-functions-key: $MASTER_KEY" \
  --output crl.der

# Verify CRL signature
openssl crl -in crl.der -inform DER -text -noout
```

**Caching Strategy:**

- CRL includes Cache-Control headers (max-age=86400 for 24-hour client caching)
- CRL generation: ~30-60 seconds per request
- Includes all revoked certificates with serial numbers and revocation reasons
- Signed by Intermediate CA HSM key (4096-bit RSA)
- **Future**: APIM can be added for centralized caching

**Performance:**

- CRL generation (10K revoked certs): ~30-60 seconds
- See [API_REFERENCE.md Section 8](../docs/API_REFERENCE.md#8-get-crl-certificate-revocation-list) for details

## Certificate Storage

| Type                | Storage Location  | Contains                  | Access Method                                |
| ------------------- | ----------------- | ------------------------- | -------------------------------------------- |
| CA Certificates     | Certificate Store | Public cert + Private key | `cert_client.get_certificate()`              |
| Device Certificates | Secrets           | Public cert only          | `secret_client.get_secret("{name}-cert")`    |
| Revocation Records  | Secrets           | JSON metadata             | `secret_client.get_secret("{name}-revoked")` |

## Deployment Command

```bash
# Build platform-specific packages
cd function-private-ca
rm -rf .python_packages
pip install --platform manylinux2014_x86_64 --only-binary=:all: \
  --target ./.python_packages/lib/site-packages \
  -r requirements.txt

# Create deployment package
zip -r function-app-with-deps.zip \
  function_app.py host.json requirements.txt .python_packages

# Transfer and deploy
scp -i ~/.ssh/vm-dev-aue-dcert-poc-keypair.pem \
  function-app-with-deps.zip azureuser@<YOUR_VM_IP>:~/

ssh -i ~/.ssh/vm-dev-aue-dcert-poc-keypair.pem azureuser@<YOUR_VM_IP> \
  "az functionapp deployment source config-zip \
    -g rg-dev-aue-dcert-poc \
    -n func-devicepki-dev-001 \
    --src ~/function-app-with-deps.zip"
```

**Key Point:** Use `--platform manylinux2014_x86_64` to build Linux-compatible packages on macOS.

## Security Considerations

### ✅ Best Practices Implemented

- Device private keys never stored in Key Vault
- CA private keys protected in HSM-backed Key Vault
- Revocation reasons follow X.509 standards
- RBAC enforced (Certificates Officer, Secrets Officer, Crypto Officer)
- All API endpoints require function key authentication

### ⚠️ Production Recommendations

1. **Monitoring** - Enable Application Insights for audit trails and certificate expiry alerts
2. **Key Rotation** - Regularly rotate device certificates (recommended: annually)
3. **CA Hierarchy** - Keep Root CA offline, only use Intermediate CA online
4. **Premium Plan** - Use Azure Functions Premium Plan for production (no cold starts, 10-min timeout)
5. **OCSP Responder** (Optional) - Add real-time revocation checking to complement CRL

## Troubleshooting

### Certificate Not Found

```bash
# Check if exists
./test/list-certificates.sh | grep <cert-name>

# Issue if missing
./test/issue-certificate.sh <cert-name>
```

### Function App Returns 404

```bash
# Check health
ssh -i ~/.ssh/vm-dev-aue-dcert-poc-keypair.pem azureuser@<YOUR_VM_IP> \
  "curl -s https://func-devicepki-dev-001.azurewebsites.net/api/health"

# Redeploy if needed (see Deployment Command above)
```

### Python Packages Not Installed

- Ensure `--platform manylinux2014_x86_64` flag used
- Verify `.python_packages/` directory included in zip
- Check deployment logs for errors

## Next: Advanced Features

Consider implementing:

- **OCSP Responder** - Real-time revocation checks to complement CRL
- **Certificate Templates** - Pre-configured profiles for device types
- **Bulk Operations** - Renew/revoke multiple certificates in single request
- **Automated Expiry Alerts** - Proactive notification before expiration
- **Multi-Region HA** - Deploy to multiple regions for high availability
