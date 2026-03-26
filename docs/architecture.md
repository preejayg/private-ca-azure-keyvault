# Private Certificate Authority (PKI) Architecture

## Overview

Production-grade Private Certificate Authority (PKI) system for IoT device identity management. Provides complete certificate lifecycle management with HSM-protected cryptographic operations using Azure Key Vault.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                Azure Function App (Python)                       │
│              func-devicepki-dev-001                              │
│    ┌──────────────────────────────────────────────────┐         │
│    │ API Endpoints:                                    │         │
│    │  • POST /api/create-root-ca                      │         │
│    │  • POST /api/create-intermediate-ca              │         │
│    │  • POST /api/issue-certificate                   │         │
│    │  • POST /api/renew-certificate                   │         │
│    │  • POST /api/revoke-certificate                  │         │
│    │  • GET  /api/check-revocation                    │         │
│    │  • GET  /api/list-certificates (paginated)       │         │
│    │  • GET  /api/get-crl                             │         │
│    └──────────────────────────────────────────────────┘         │
│                                                                  │
│    Private Endpoint Only (No Public Access)                     │
│    VNet Integration: snet-functionapp-integration               │
└──────────────┬──────────────────────────┬────────────────────────┘
               │                          │
               ▼                          ▼
┌──────────────────────────┐   ┌──────────────────────────┐
│  Azure Key Vault HSM     │   │   Storage Account        │
│  kv-dev-aue-dcert-poc    │   │   st*dev*dcertpoc        │
│                          │   │                          │
│  • Root CA (HSM key)     │   │  • Function artifacts    │
│  • Intermediate CA       │   │  • Blob container        │
│  • Device certificates   │   │  • File share            │
│  • Revocation records    │   │                          │
│  • CryptographyClient    │   │  Private Endpoint Only   │
│    signing (RS256)       │   └──────────────────────────┘
│                          │
│  Private Endpoint Only   │
└──────────────────────────┘

        ▲
        │ Access for testing
        │
┌──────────────────────────┐
│   Test VM (VNet)         │
│   <YOUR_VM_IP>            │
│                          │
│   • SSH access           │
│   • Test scripts         │
│   • Inside VNet          │
└──────────────────────────┘
```

## Components

### 1. Azure Function App (func-devicepki-dev-001)

**Runtime:** Python 3.11  
**Plan:** Consumption (Dev) / Premium (Production recommended)  
**Networking:** Private endpoints only, VNet integration

**Core Responsibilities:**

- PKI certificate authority operations
- Certificate lifecycle management (issue, renew, revoke)
- CRL (Certificate Revocation List) generation
- HSM signing orchestration via CryptographyClient
- Certificate validation and verification

**Key Configuration:**

- `WEBSITE_VNET_ROUTE_ALL=1` - Routes all traffic through VNet
- `WEBSITE_DNS_SERVER=168.63.129.16` - Azure DNS for private endpoint resolution
- System-assigned managed identity with Key Vault RBAC roles

**Python Libraries:**

- `azure-identity` - Managed identity authentication
- `azure-keyvault-certificates` - CA certificate management
- `azure-keyvault-keys` - Key operations
- `azure-keyvault-secrets` - Device certificate and revocation storage
- `cryptography` - X.509 certificate construction
- `asn1crypto` (v1.5.1+) - CRL parsing

### 2. Azure Key Vault HSM (kv-dev-aue-dcert-poc-001)

**SKU:** Premium (HSM-backed)  
**Purpose:** HSM-protected certificate authority

**Stored Assets:**

- **CA Certificates** (Certificate Store):
  - Root CA: 4096-bit RSA, 10-year validity, self-signed
  - Intermediate CA: 4096-bit RSA, 5-year validity, signed by Root CA
  - Private keys are **non-exportable** (HSM-protected)
- **Device Certificates** (Secrets):
  - Stored as secrets with content type "application/x-pem-file"
  - 2048-bit RSA, 1-2 year validity
  - Public certificate only (private key stays with device)
  - Naming: `{device-name}-cert`
- **Revocation Records** (Secrets):
  - JSON metadata: `{"revoked": true, "reason": "keyCompromise", "timestamp": "..."}`
  - Naming: `{device-name}-revoked`

**Access Control (RBAC):**

- Function App managed identity:
  - `Key Vault Certificates Officer` - Create/manage CA certificates
  - `Key Vault Crypto Officer` - HSM signing operations
  - `Key Vault Secrets User` - Read device certificates and revocation records

**Signing Method:**

```python
from azure.keyvault.keys.crypto import CryptographyClient, SignatureAlgorithm
crypto_client = CryptographyClient(key, credential)
signature = crypto_client.sign(SignatureAlgorithm.rs256, digest)
```

### 3. Storage Account

**Purpose:** Function App artifacts and dependencies  
**Networking:** Private endpoints for blob, file, queue

**Services Used:**

- **Blob Storage** - Function app code packages
- **File Share** - Function app content share
- **Queue** (optional) - For async processing

**Access Control:**

- Function App managed identity: `Storage Blob Data Owner`
- Network: VNet service endpoints + firewall rules

### 4. Test VM (<YOUR_VM_IP>)

**Purpose:** Testing and accessing private endpoints  
**OS:** Linux (Ubuntu)  
**Network:** Inside VNet (snet-vm)

**Usage:**

- SSH access with key: `~/.ssh/vm-dev-aue-dcert-poc-keypair.pem`
- Execute test scripts against Function App private endpoint
- Certificate verification with OpenSSL
- CRL download and validation

## PKI Certificate Hierarchy

```
Root CA
├─ Common Name: Device PKI Root CA
├─ Key Type: RSA 4096-bit (HSM-protected)
├─ Validity: 10 years
├─ Self-signed
└─ CA:TRUE, pathLenConstraint:1

    ↓ Signs via HSM (CryptographyClient.sign)

Intermediate CA
├─ Common Name: Device PKI Intermediate CA
├─ Key Type: RSA 4096-bit (HSM-protected)
├─ Validity: 5 years
├─ Signed by: Root CA
└─ CA:TRUE, pathLenConstraint:0

    ↓ Signs via HSM (CryptographyClient.sign)

Device Certificates
├─ Common Name: device-{id}
├─ Key Type: RSA 2048-bit (device-generated, not in KV)
├─ Validity: 1-2 years
├─ Signed by: Intermediate CA
└─ Extended Key Usage: TLS Client Auth
```

## Private Networking Architecture

### VNet Configuration

**Subnets:**

- `snet-functionapp-integration` - Function App VNet integration
- `snet-privateendpoint` - Private endpoints for PaaS services
- `snet-vm` - Test VM

### Private Endpoints

All Azure PaaS services accessible only via private endpoints:

1. **Key Vault** - `privatelink.vaultcore.azure.net`
2. **Storage (Blob)** - `privatelink.blob.core.windows.net`
3. **Storage (File)** - `privatelink.file.core.windows.net`
4. **Function App** - `privatelink.azurewebsites.net`

### DNS Resolution

**Private DNS Zones:**

- Managed by platform team (organizational policy)
- Linked to VNet for automatic resolution
- Azure DNS server: `168.63.129.16`

**For Local Testing:**

```bash
# Add to /etc/hosts
<private-ip> kv-dev-aue-dcert-poc-001.vault.azure.net
<private-ip> func-devicepki-dev-001.azurewebsites.net
```

### Security Boundaries

```
┌─────────────────────────────────────────────┐
│         No Public Internet Access           │
│                                             │
│  ✅ Function App = Private Endpoint Only    │
│  ✅ Key Vault = Private Endpoint Only       │
│  ✅ Storage = Private Endpoint Only         │
│  ✅ All traffic routed through VNet         │
└─────────────────────────────────────────────┘
```

## Certificate Lifecycle Operations

### 1. Issue Certificate

**Flow:**

1. Device generates RSA key pair (2048-bit)
2. Device creates CSR with subject and extensions
3. POST `/api/issue-certificate` with CSR
4. Function App validates CSR format
5. Function App creates certificate via HSM signing
6. Certificate stored in Key Vault secrets
7. Return signed certificate to device

**Performance:** 2-3 seconds

### 2. Renew Certificate

**Flow:**

1. POST `/api/renew-certificate` with cert name and validity
2. Options:
   - **Simple renewal**: Reuse existing subject/key, extend validity
   - **Key rotation**: Generate new CSR, new key pair
   - **Auto-revoke**: Revoke old cert with reason "superseded"
3. Issue new certificate via HSM signing
4. Store in Key Vault, return to device

**Performance:** 2-3 seconds

### 3. Revoke Certificate

**Flow:**

1. POST `/api/revoke-certificate` with cert name and reason
2. Create revocation record in Key Vault secrets
3. Record includes: timestamp, X.509 reason code, serial number
4. Certificate marked as revoked
5. CRL regenerated on next request (cached 24 hours)

**X.509 Revocation Reasons:**

- `keyCompromise` - Private key exposed
- `superseded` - Replaced by newer certificate
- `cessationOfOperation` - Device decommissioned
- `certificateHold` - Temporary suspension
- Others: `unspecified`, `caCompromise`, `affiliationChanged`, etc.

### 4. Check Revocation

**Methods:**

**API Check:**

```bash
GET /api/check-revocation?certificate_name=device-001-cert
```

Returns: `{"revoked": true/false, "reason": "...", "timestamp": "..."}`

**CRL Download:**

```bash
GET /api/get-crl?ca_name=device-intermediate-ca
```

- Returns DER-encoded CRL
- Signed by Intermediate CA HSM key
- Includes Cache-Control headers for client-side caching (24 hours)
- Performance: ~30-60 seconds per generation

**Certificate Chain Verification:**

```bash
openssl verify -CAfile root-ca.pem -untrusted intermediate-ca.pem device-cert.pem
```

### 5. List Certificates (Paginated)

**Query Parameters:**

- `type` - Filter: `all`, `ca`, `device`
- `page` - Page number (1-based)
- `page_size` - Items per page (max 500, recommended 100-200)
- `details` - Mode: `summary` (fast) or `full` (complete)

**Detail Modes:**

- **Summary**: Metadata only (name, created date, enabled status)
  - Performance: 2-3 sec for 100 certs at 10K scale
- **Full**: Complete certificate parsing (subject, serial, dates, extensions)
  - Performance: 5-8 sec for 100 certs at 10K scale

**Response:**

```json
{
  "pagination": {
    "page": 1,
    "page_size": 100,
    "total_items": 5234,
    "total_pages": 53,
    "has_next": true,
    "has_previous": false
  },
  "ca_certificates": {"count": 2, "items": [...]},
  "device_certificates": {"count": 100, "items": [...]}
}
```

## Scalability & Performance

**Current Target:** 10K-20K certificates per region

### Performance Metrics

| Certificate Count | List (Summary) | List (Full) | Issue Cert | Renew Cert | Get CRL   |
| ----------------- | -------------- | ----------- | ---------- | ---------- | --------- |
| 1K                | <1 sec         | 2-3 sec     | 2-3 sec    | 2-3 sec    | 30-45 sec |
| 5K                | 1-2 sec        | 4-5 sec     | 2-3 sec    | 2-3 sec    | 40-50 sec |
| 10K               | 2-3 sec        | 8-10 sec    | 2-3 sec    | 2-3 sec    | 50-60 sec |
| 20K               | 3-5 sec        | 15-20 sec   | 2-3 sec    | 2-3 sec    | 60-90 sec |

### Limits & Constraints

**Azure Key Vault:**

- Maximum secrets: 25,000 per vault
- Device certificates: ~20,000 (leaves room for CA certs, revocation records)
- Certificate operations: 2,000 read requests/10 sec per vault
- Signature operations: 500/10 sec per key

**Function App:**

- Consumption Plan: 5-minute execution timeout
- Premium Plan (recommended): 10-minute timeout, no cold starts
- Memory: 1.5 GB (Consumption) / 3.5 GB+ (Premium)

**Pagination Best Practices:**

- Use `summary` mode by default (3x faster than full)
- Page size 100-200 optimal for performance/UX balance
- Cache list results client-side for navigation

### Optimization Strategies

1. **Pagination** - Limit data retrieval per request
2. **Detail Modes** - Summary vs. full parsing
3. **CRL Caching** - HTTP cache headers enable client-side caching (24 hours recommended)
4. **Premium Plan** - Eliminates cold starts, increases memory
5. **Key Vault Batching** - Fetch multiple secrets in parallel (future)

### Scaling Beyond 20K

**For 50K-100K+ certificates:**

- Hybrid architecture: Cosmos DB for certificate metadata + Key Vault HSM for signing
- Multi-region deployment with regional Key Vaults
- Azure API Management for API gateway, rate limiting, and CRL caching
- Azure Front Door for global load balancing
- Table Storage or Cosmos DB for revocation records

## Security Model

### Authentication & Authorization

**Function App APIs:**

- Require function key (`x-functions-key` header)
- Function keys managed in Azure Portal
- Rotate keys regularly (every 90 days recommended)

**Azure Resources:**

- Azure RBAC for all resource access
- Managed identity for service-to-service auth
- No connection strings or passwords

### RBAC Roles

**Key Vault:**
| Role | Purpose |
|-----------------------------------|-----------------------------------|
| Key Vault Certificates Officer | Create/manage CA certificates |
| Key Vault Crypto Officer | Sign certificates via HSM |
| Key Vault Secrets User | Read device certs, revocation |

**Storage Account:**
| Role | Purpose |
|-----------------------------------|-----------------------------------|
| Storage Blob Data Owner | Function app artifact access |

### Network Security

- ✅ Private endpoints for all PaaS services
- ✅ No public internet access
- ✅ VNet integration for Function App
- ✅ Service endpoints for Storage
- ✅ NSG rules on subnets (managed by platform team)
- ✅ Private DNS zones for name resolution

### Key Protection

- ✅ CA private keys stored in HSM (non-exportable)
- ✅ All signing operations via CryptographyClient
- ✅ Device private keys never leave device
- ✅ No private keys in application code or logs
- ✅ Soft delete + purge protection on Key Vault

### Audit & Monitoring

**Azure Monitor:**

- Function App execution logs
- Key Vault access logs
- Certificate issuance/revocation events
- Performance metrics

**Application Insights:**

- Distributed tracing
- Request/response logging
- Error tracking
- Custom telemetry

**Log Analytics:**

- Centralized log aggregation
- KQL queries for analysis
- Alerts on anomalies

## Deployment

### Infrastructure as Code (Bicep)

**Modules:**

- `main.bicep` - Orchestration
- `modules/keyvault/keyvault.bicep` - Key Vault + RBAC
- `modules/storage/storage.bicep` - Storage account
- `modules/functionapp/functionapp.bicep` - Function App + VNet integration
- `modules/privateendpoint/privateendpoint.bicep` - Private endpoints

**Parameters:**

- `infra/parameters/dev.bicepparam` - Dev environment
- `infra/parameters/test.bicepparam` - Test environment
- `infra/parameters/prod.bicepparam` - Production environment

**Deployment:**

```bash
./scripts/deploy-keyvault.sh
```

### Function App Deployment

**From Local:**

```bash
cd scripts
./deploy-appl-from-local.sh
```

**CI/CD Pipeline:**

- Azure DevOps pipeline: `azure-pipelines.yml`
- Automated build and deployment
- Run tests before deployment
- Infrastructure validation

## Testing

### Local Development

**Prerequisites:**

- Python 3.11 virtual environment
- Azure Functions Core Tools
- Environment variables configured

**Test Scripts:**

```bash
cd function-private-ca/test

# Certificate operations
./issue-certificate-local.sh device-001
./renew-certificate-local.sh device-001 730
./revoke-certificate-local.sh device-001 keyCompromise
./check-revocation-local.sh device-001

# List with pagination
./list-certificates-local.sh device 1 100 summary
./list-certificates-local.sh device 2 50 full

# CRL operations
./get-crl-local.sh device-intermediate-ca
./verify-cert-crl-local.sh device-001
```

### VM-Based Testing

For testing against deployed Function App with private endpoints:

```bash
# SSH to test VM
ssh -i ~/.ssh/vm-dev-aue-dcert-poc-keypair.pem azureuser@<YOUR_VM_IP>

# Run test scripts
cd function-private-ca/test
./issue-certificate.sh device-001
```

### OpenSSL Verification

```bash
# Verify certificate chain
openssl verify -CAfile root-ca.pem -untrusted intermediate-ca.pem device.pem

# Check CRL
openssl crl -in crl.der -inform DER -text -noout

# Verify certificate against CRL
openssl verify -CAfile root-ca.pem -untrusted intermediate-ca.pem \
  -crl_check -CRLfile crl.pem device.pem
```

## Documentation

- **[API Reference](API_REFERENCE.md)** - Complete API documentation
- **[Testing Guide](TESTING_GUIDE.md)** - Testing procedures and examples
- **[Quick Reference](QUICK_REFERENCE.md)** - Common commands and workflows
- **[Local Development](LOCAL_DEVELOPMENT.md)** - Local development setup
- **[Bicep Migration](BICEP_MIGRATION.md)** - Infrastructure as Code guide

## Future Enhancements

### Planned Features

1. **Azure API Management (APIM)** - API gateway with rate limiting, throttling, and CRL caching
2. **OCSP Responder** - Real-time certificate status checking (complement to CRL)
3. **Certificate Templates** - Pre-configured profiles for different device types
4. **Bulk Operations** - Renew/revoke multiple certificates in single request
5. **Automated Expiry Alerts** - Proactive notifications before certificate expiration
6. **Multi-Region HA** - Deploy to multiple Azure regions for high availability
7. **Cosmos DB Integration** - For metadata storage beyond 20K certificates
8. **Azure Monitor Workbooks** - Custom dashboards for PKI monitoring

### Architecture Evolution

**For larger scale (50K+ certificates):**

- Migrate certificate metadata to Cosmos DB
- Keep Key Vault HSM for signing operations only
- Implement Azure Front Door for global distribution
- Add Azure Cache for Redis for high-performance caching
- Implement event-driven architecture with Event Grid

---

**Last Updated:** 2026-03-25  
**Architecture Version:** 1.0  
**Target Scale:** 10K-20K certificates per region
