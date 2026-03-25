# Private Certificate Authority (PKI) Management Service

Azure Function App implementing a production-grade Private Certificate Authority with HSM-protected cryptographic operations.

## 🔒 Security Architecture

**All certificate operations use Azure Key Vault HSM signing:**

- Private keys are **non-exportable** from HSM
- Signing operations use `CryptographyClient` with RS256
- No private keys ever exposed to application code
- Certificates reconstructed from HSM signatures using ASN.1 DER encoding

## 📋 Certificate Hierarchy

```
Root CA (4096-bit RSA, self-signed, HSM-protected)
    ↓ signs via Azure Key Vault HSM
Intermediate CA (4096-bit RSA, HSM-protected)
    ↓ signs via Azure Key Vault HSM
Device Certificates (2048-bit RSA, private key stays with device)
```

## API Endpoints

### 1. Create Root CA

**Endpoint:** `POST /api/create-root-ca`

Creates a self-signed root CA certificate with CA:TRUE constraint.

**Request:**

```json
{
  "ca_name": "device-root-ca",
  "common_name": "Device PKI Root CA",
  "validity_years": 10
}
```

**Response:**

```json
{
  "message": "Root CA created successfully",
  "certificate_name": "device-root-ca",
  "serial_number": "ABC123...",
  "thumbprint": "DEF456...",
  "not_before": "2026-03-24T00:00:00",
  "not_after": "2036-03-24T00:00:00",
  "note": "Root CA created with CA:TRUE constraint",
  "security": "Private key is non-exportable (HSM-protected)"
}
```

### 2. Get Root CA

**Endpoint:** `GET /api/get-root-ca?format=certificate`

Retrieves the root CA public certificate.

### 3. Create Intermediate CA

**Endpoint:** `POST /api/create-intermediate-ca`

Creates an intermediate CA signed by the root CA using HSM.

**Request:**

```json
{
  "ca_name": "device-intermediate-ca",
  "common_name": "Device PKI Intermediate CA",
  "root_ca_name": "device-root-ca",
  "validity_years": 5
}
```

**Response:**

```json
{
  "message": "Intermediate CA created successfully",
  "signing_method": "Azure Key Vault CryptographyClient with RS256",
  "note": "Intermediate CA signed by Root CA using HSM-protected key"
}
```

### 4. Issue Certificate

**Endpoint:** `POST /api/issue-certificate`

Issues a device certificate from a Certificate Signing Request (CSR).

**Request:**

```json
{
  "csr": "-----BEGIN CERTIFICATE REQUEST-----\n...",
  "certificate_name": "device-001",
  "intermediate_ca_name": "device-intermediate-ca",
  "validity_days": 365
}
```

**Response:**

```json
{
  "signing_method": "✅ Azure Key Vault HSM (CryptographyClient with RS256)",
  "certificate_pem": "-----BEGIN CERTIFICATE-----\n...",
  "note": "Device certificate signed using HSM-protected Intermediate CA key"
}
```

### 5. Renew Certificate

**Endpoint:** `POST /api/renew-certificate`

Renews an existing certificate with optional key rotation.

**Request:**

```json
{
  "certificate_name": "device-001",
  "validity_days": 365,
  "csr": "-----BEGIN CERTIFICATE REQUEST-----\n..." // optional for key rotation
  "auto_revoke": true,  // optional
  "revocation_reason": "superseded"  // optional
}
```

**Response:**

```json
{
  "signing_method": "✅ Azure Key Vault HSM (CryptographyClient with RS256)",
  "old_certificate": { "serial_number": "...", "expires_on": "..." },
  "new_certificate": { "serial_number": "...", "expires_on": "..." }
}
```

### 6. Revoke Certificate

**Endpoint:** `POST /api/revoke-certificate`

Marks a certificate as revoked (added to CRL).

**Request:**

```json
{
  "certificate_name": "device-001",
  "reason": "keyCompromise"
}
```

**Valid revocation reasons:** `keyCompromise`, `caCompromise`, `affiliationChanged`, `superseded`, `cessationOfOperation`, `unspecified`

### 7. Get CRL (Certificate Revocation List)

**Endpoint:** `GET /api/crl/{ca_name}`

Returns HSM-signed CRL in DER format.

**Example:** `GET /api/crl/intermediate`

**Response:** Binary DER-encoded CRL with headers:

- `Content-Type: application/pkix-crl`
- `X-Revoked-Count: 5`
- `X-CRL-Next-Update: 2026-03-25T...`

**Security:** CRL signed with 4096-bit HSM key (512-byte signature)

### 8. Get Certificate

**Endpoint:** `GET /api/get-certificate?name={certificate_name}`

Retrieves an issued device certificate.

### 9. List Certificates

**Endpoint:** `GET /api/list-certificates?type={all|ca|device}`

Lists certificates stored in Key Vault.

### 10. Health Check

**Endpoint:** `GET /api/health`

Service health check (no authentication required).

## Deployment

### Prerequisites

- Azure CLI
- SSH access to deployment VM (private networking)
- Function master key

### Deploy from VM

```bash
cd scripts
./deploy-from-vm.sh
```

This script:

1. Builds platform-specific Python packages (Linux x86_64)
2. Packages function code with dependencies (.python_packages/)
3. Copies to VM via SCP
4. Deploys via Azure CLI on VM
5. Verifies deployment health

**Why VM deployment?** Function app uses private endpoints (no public access). Deployment must occur from within the virtual network.

## Testing

```bash
cd function-private-ca/test

# Complete PKI rebuild
./rebuild-pki.sh

# Issue device certificate
./issue-certificate.sh device-001

# Verify certificate chain with CRL
./verify-cert-crl.sh device-001

# Revoke certificate
./revoke-certificate.sh device-001 keyCompromise

# Check CRL
./get-crl.sh intermediate
```

See [docs/TESTING_GUIDE.md](../docs/TESTING_GUIDE.md) for comprehensive testing procedures.

## Dependencies

```
azure-functions>=1.18.0
azure-identity>=1.15.0
azure-keyvault-certificates>=4.7.0
azure-keyvault-keys>=4.8.0
azure-keyvault-secrets>=4.7.0
cryptography>=41.0.0
asn1crypto>=1.5.1  # For reliable ASN.1 DER parsing in CRL generation
```

## Environment Variables

- `KEY_VAULT_NAME`: Azure Key Vault name (auto-configured)
- `WEBSITE_HOSTNAME`: Function app hostname for CRL distribution URLs

## Security Best Practices

✅ **Non-Exportable Keys**: All CA keys marked as `exportable=False`  
✅ **HSM Signing**: Uses `CryptographyClient.sign()` for all certificate operations  
✅ **TBS Extraction**: Certificates built with temporary keys, then reconstructed with HSM signatures  
✅ **ASN.1 Encoding**: Manual DER reconstruction ensures signature integrity  
✅ **Audit Trail**: All operations logged with timestamps and reasons  
✅ **Revocation Tracking**: Revocation metadata stored securely in Key Vault  
✅ **CRL Distribution**: Automated CRL generation with 24-hour validity

**Production Deployment:** All cryptographic operations execute within Azure Key Vault HSM boundary. Private keys never leave the HSM.

## 📈 Scalability & Performance

**Optimized for 10K-20K certificates per region:**

✅ **Pagination Support**: List certificates endpoint supports pagination (100-500 items per page)  
✅ **Two Detail Levels**: `summary` mode (fast) vs `full` mode (complete data)  
✅ **CRL Caching**: 24-hour cache headers for APIM/CDN optimization  
✅ **Key Vault Limits**: Supports up to 25K secrets per vault  
✅ **Efficient Queries**: Optimized secret filtering and parsing

**Performance Targets:**

| Operation                  | Target  | Notes                   |
| -------------------------- | ------- | ----------------------- |
| Issue Certificate          | 2-3 sec | HSM signing operation   |
| List Certificates (page 1) | 2-3 sec | Paginated, summary mode |
| Get CRL                    | <1 sec  | With APIM caching       |
| Revoke Certificate         | 2-3 sec | Metadata update         |

**Recommended Infrastructure:**

- **Function App**: Premium Plan (EP1) for no cold starts
- **Scale Strategy**: Multi-region deployment for 100K+ certificates
- **Cache Strategy**: APIM caching for CRL (24-hour TTL)

See [API_REFERENCE.md](../docs/API_REFERENCE.md#10-list-certificates-paginated) for detailed pagination usage.
