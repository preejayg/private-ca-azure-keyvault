# Private Certificate Authority - API Reference

## Overview

Production-grade PKI management API with **HSM-protected signing operations**. All certificate operations use Azure Key Vault HSM via `CryptographyClient` with RS256 signing algorithm.

## 🔒 Security Model

**HSM Signing Architecture:**

- All CA private keys stored in Azure Key Vault HSM (non-exportable)
- Signing operations use `CryptographyClient.sign(SignatureAlgorithm.rs256, digest)`
- TBS (To-Be-Signed) certificate bytes extracted and hashed with SHA-256
- Signature generated in HSM, never exposing private key
- Certificates reconstructed using manual ASN.1 DER encoding
- CRL generation uses `asn1crypto` library for reliable DER parsing

## Certificate Hierarchy

```
Root CA (4096-bit RSA, self-signed)
  ↓ signs via HSM
Intermediate CA (4096-bit RSA, CA:TRUE pathlen=0)
  ↓ signs via HSM
Device Certificates (2048-bit RSA, CA:FALSE)
```

---

## API Endpoints

### 1. Create Root CA

**Endpoint:** `POST /api/create-root-ca`

Creates a self-signed root CA certificate with proper CA constraints.

**Request Body:**

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
  "serial_number": "71671A3529C0CFBCF7B45CC808A7C5B3CB29AB24",
  "thumbprint": "e73e139c8b27165b3f9995b4b0c784c4b605f4e4",
  "not_before": "2026-03-24T01:17:37",
  "not_after": "2036-03-24T01:17:37",
  "note": "Root CA created with CA:TRUE constraint",
  "security": "Private key is non-exportable (HSM-protected)"
}
```

**Key Extensions:**

- `BasicConstraints: CA=TRUE` (no path length limit)
- `KeyUsage: keyCertSign, cRLSign`

---

### 2. Get Root CA

**Endpoint:** `GET /api/get-root-ca?format=certificate`

Retrieves the root CA public certificate.

**Query Parameters:**

- `format`: `certificate` (default) or `chain` (includes chain info)

**Response:**

```json
{
  "certificate_name": "device-root-ca",
  "thumbprint": "e73e139c8b27165b3f9995b4b0c784c4b605f4e4",
  "subject": "CN=Device PKI Root CA",
  "issuer": "CN=Device PKI Root CA",
  "not_before": "2026-03-24T01:17:37",
  "not_after": "2036-03-24T01:17:37",
  "serial_number": "71671A3529C0CFBCF7B45CC808A7C5B3CB29AB24",
  "certificate_pem": "-----BEGIN CERTIFICATE-----\nMIIE...\n-----END CERTIFICATE-----"
}
```

---

### 3. Create Intermediate CA

**Endpoint:** `POST /api/create-intermediate-ca`

Creates an intermediate CA signed by the root CA using **Azure Key Vault HSM**.

**Request Body:**

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
  "certificate_name": "device-intermediate-ca",
  "root_ca": "device-root-ca",
  "serial_number": "68FCE6DA6E96E8FA93C0DB0406B7FAC6DB891260",
  "subject": "CN=Device PKI Intermediate CA",
  "issuer": "CN=Device PKI Root CA",
  "not_before": "2026-03-24T01:25:31",
  "not_after": "2031-03-24T01:25:31",
  "signing_method": "Azure Key Vault CryptographyClient with RS256",
  "note": "Intermediate CA signed by Root CA using HSM-protected key. Private key is non-exportable."
}
```

**Key Extensions:**

- `BasicConstraints: CA=TRUE, pathlen=0`
- `KeyUsage: keyCertSign, cRLSign`
- **Signing:** Root CA HSM key signs the intermediate certificate

---

### 4. Get Intermediate CA

**Endpoint:** `GET /api/get-intermediate-ca?format=certificate`

Retrieves the intermediate CA certificate.

---

### 5. Issue Certificate (CSR Processing)

**Endpoint:** `POST /api/issue-certificate`

Issues a device certificate from a Certificate Signing Request (CSR). **Signs using HSM-protected Intermediate CA key.**

**Request Body:**

```json
{
  "csr": "-----BEGIN CERTIFICATE REQUEST-----\nMIIC...\n-----END CERTIFICATE REQUEST-----",
  "certificate_name": "device-001",
  "intermediate_ca_name": "device-intermediate-ca",
  "validity_days": 365
}
```

**Request Parameters:**

- `csr` (required): Certificate Signing Request in PEM or base64 format
- `certificate_name` (required): Unique identifier for the certificate
- `intermediate_ca_name` (optional): Default "device-intermediate-ca"
- `validity_days` (optional): Default 365

**CSR Validation:**

- CSR signature must be valid
- Subject and public key extracted from CSR
- Subject Alternative Names (SAN) copied if present

**Response:**

```json
{
  "message": "Certificate issued successfully",
  "certificate_name": "device-001",
  "subject": "C=US, ST=WA, L=Redmond, O=Example, CN=device-001.example.com",
  "issuer": "CN=Device PKI Intermediate CA",
  "serial_number": "189777137224028790363488726113771428053142672532",
  "not_before": "2026-03-24T01:38:00",
  "not_after": "2027-03-24T01:38:00",
  "certificate_pem": "-----BEGIN CERTIFICATE-----\nMIIE...\n-----END CERTIFICATE-----",
  "storage_location": "Key Vault secret: device-001-cert",
  "signing_method": "✅ Azure Key Vault HSM (CryptographyClient with RS256)",
  "note": "Device certificate signed using HSM-protected Intermediate CA key. Private key remains with device."
}
```

**Key Extensions:**

- `BasicConstraints: CA=FALSE`
- `KeyUsage: digitalSignature, keyEncipherment`
- `SubjectAlternativeName`: Copied from CSR
- `CRLDistributionPoints`: Points to `/api/crl/intermediate`

**Storage:** Certificate stored as Key Vault secret (private key stays with device)

---

### 6. Renew Certificate

**Endpoint:** `POST /api/renew-certificate`

Renews an existing certificate with optional key rotation. **Signs using HSM.**

**Request Body:**

```json
{
  "certificate_name": "device-001",
  "validity_days": 365,
  "csr": "-----BEGIN CERTIFICATE REQUEST-----\n...", // optional - for key rotation
  "auto_revoke": true, // optional - revoke old certificate
  "revocation_reason": "superseded", // optional
  "intermediate_ca_name": "device-intermediate-ca" // optional
}
```

**Two Renewal Modes:**

1. **Simple Renewal** (no CSR): Reuses existing subject and public key, extends validity
2. **Key Rotation** (with CSR): New key pair, new subject (if changed), new validity

**Response:**

```json
{
  "message": "Certificate renewed successfully",
  "certificate_name": "device-001",
  "old_certificate": {
    "serial_number": "123...",
    "subject": "CN=device-001",
    "expires_on": "2027-03-24T..."
  },
  "new_certificate": {
    "serial_number": "456...",
    "subject": "CN=device-001",
    "not_before": "2026-03-24T...",
    "not_after": "2027-03-24T...",
    "validity_days": 365
  },
  "certificate_pem": "-----BEGIN CERTIFICATE-----\n...",
  "storage_location": "Key Vault secret: device-001-cert",
  "signing_method": "✅ Azure Key Vault HSM (CryptographyClient with RS256)",
  "note": "Renewed certificate signed using HSM-protected Intermediate CA key",
  "old_certificate_revoked": true,  // if auto_revoke=true
  "revocation_info": { ... }  // if auto_revoke=true
}
```

---

### 7. Revoke Certificate

**Endpoint:** `POST /api/revoke-certificate`

Marks a certificate as revoked. Revocation records are included in CRL generation.

**Request Body:**

```json
{
  "certificate_name": "device-001",
  "reason": "keyCompromise",
  "revocation_date": "2026-03-24T10:00:00Z" // optional, defaults to current time
}
```

**Valid Revocation Reasons (RFC 5280):**

- `unspecified`
- `keyCompromise`
- `caCompromise`
- `affiliationChanged`
- `superseded`
- `cessationOfOperation`
- `certificateHold`
- `removeFromCRL`
- `privilegeWithdrawn`
- `aaCompromise`

**Response:**

```json
{
  "message": "Certificate revoked successfully",
  "revocation_info": {
    "certificate_name": "device-001",
    "serial_number": "189777137224028790363488726113771428053142672532",
    "subject": "C=US, ST=WA, L=Redmond, O=Example, CN=device-001.example.com",
    "reason": "keyCompromise",
    "revoked_at": "2026-03-24T03:50:51.475927",
    "expires_on": "2027-03-24T01:38:00",
    "revoked_by": "Function App"
  },
  "revocation_record": "Key Vault secret: device-001-revoked"
}
```

**Idempotency:** Returns 409 Conflict if certificate is already revoked

**Note:** Revocation stores metadata only. The CRL is signed with HSM when generated.

---

### 8. Get CRL (Certificate Revocation List)

**Endpoint:** `GET /api/crl/{ca_name}`

Returns a DER-encoded CRL signed with the CA's HSM-protected key.

**Path Parameters:**

- `ca_name`: `root`, `intermediate`, `device-root-ca`, or `device-intermediate-ca`

**Example:** `GET /api/crl/intermediate`

**Response:** Binary DER-encoded CRL

**Headers:**

```
Content-Type: application/pkix-crl
Content-Disposition: inline; filename=device-intermediate-ca.crl
Cache-Control: public, max-age=86400
Expires: Wed, 26 Mar 2026 10:30:00 GMT
Last-Modified: Tue, 25 Mar 2026 10:30:00 GMT
X-CRL-Number: 1774323007
X-CRL-Issuer: CN=Device PKI Intermediate CA
X-CRL-Last-Update: 2026-03-24T03:30:07
X-CRL-Next-Update: 2026-03-25T03:30:07
X-Revoked-Count: 1
```

**Cache Strategy:**

- **Cache duration**: 24 hours (86400 seconds)
- **Client caching**: Response includes `Cache-Control` and `Expires` headers
- **API Gateway caching**: Can be implemented with Azure APIM (future enhancement)
- **Next update**: CRL valid for 24 hours
- **Performance**: CRL generation (~30-60 sec) per request; clients should cache locally

**CRL Structure:**

- Issuer: Intermediate CA subject
- Last Update: Current timestamp
- Next Update: 24 hours from now
- Revoked Certificates: List with serial numbers, revocation dates, and reasons
- Signature: **512 bytes** (4096-bit HSM key signature)

**HSM Signing Process:**

1. Query all revocation records from Key Vault secrets (`*-revoked`)
2. Build CRL structure with revoked certificate entries
3. Extract TBS CertList using `asn1crypto`
4. Sign with Intermediate CA HSM key via `CryptographyClient`
5. Reconstruct CRL with HSM signature

**OpenSSL Verification:**

```bash
openssl crl -in intermediate-ca.crl -inform DER -noout -text
```

---

### 9. Get Certificate

**Endpoint:** `GET /api/get-certificate?name={certificate_name}`

Retrieves an issued device certificate.

\*\*Query Parameters:

## Implementation Details

### CSR Processing

The `issue-certificate` endpoint now:

1. **Parses the CSR** - Accepts both PEM and base64 encoded formats
2. **Validates CSR signature** - Ensures the CSR is cryptographically valid
3. **Extracts information** - Pulls subject, public key, and extensions (like SAN) from CSR
4. **Signs the certificate** - Creates a signed X.509 certificate using the intermediate CA
5. **Stores the certificate** - Saves the signed certificate in Key Vault as a secret
6. **Returns the certificate** - Provides the full PEM-encoded certificate in the response

### Key Features

- ✅ Full CSR parsing using cryptography library
- ✅ CSR signature validation
- ✅ Subject Alternative Names (SAN) support
- ✅ Configurable validity period
- ✅ Unique serial number generation
- ✅ PEM-encoded certificate output
- ✅ Automatic Key Vault storage
- ✅ Error handling and validation

### Security Notes

- Intermediate CA private keys remain in Key Vault HSM (non-exportable)
- For production HSM-backed signing, the code attempts to use Key Vault's Sign API
- End-entity certificate private keys are **not** generated or stored by this service
- The client generates their own private key and submits only the CSR

---

## Testing

### Generate a Test CSR:

```bash
# Generate a private key and CSR using OpenSSL
openssl req -new -newkey rsa:2048 -nodes \
  -keyout device.key \
  -out device.csr \
  -subj "/C=US/ST=WA/L=Redmond/O=Example Corp/OU=IoT/CN=device.example.com" \
  -addext "subjectAltName=DNS:device.local,IP:192.168.1.100"
```

This will generate:

- `device.key` - Private key (keep secure, never share)
- `device.csr` - Certificate Signing Request (submit to API)

### Test the Endpoint:

```bash
# Read CSR and format for JSON
CSR_JSON=$(cat device.csr | jq -Rs .)

# Issue a certificate
curl -X POST "http://localhost:7071/api/issue-certificate" \
  -H "Content-Type: application/json" \
  -d "{
    \"csr\": $CSR_JSON,
    \"intermediate_ca_name\": \"device-intermediate-ca\",
    \"certificate_name\": \"device-001-cert\",
    \"validity_days\": 365
  }"
```

---

## Workflow Example

```bash
# Step 1: Create Root CA
curl -X POST "http://localhost:7071/api/create-root-ca" \
  -H "Content-Type: application/json" \
  -d '{"ca_name":"device-root-ca","common_name":"Root CA","validity_years":10}'

# Step 2: Create Intermediate CA
curl -X POST "http://localhost:7071/api/create-intermediate-ca" \
  -H "Content-Type: application/json" \
  -d '{"ca_name":"device-intermediate-ca","common_name":"Intermediate CA","root_ca_name":"device-root-ca","validity_years":5}'

# Step 3: Generate CSR (on client side)
openssl req -new -newkey rsa:2048 -nodes \
  -keyout device-001.key \
  -out device-001.csr \
  -subj "/C=US/ST=CA/L=SF/O=MyOrg/CN=device-001.example.com"

# Step 4: Issue Certificate
curl -X POST "http://localhost:7071/api/issue-certificate" \
  -H "Content-Type: application/json" \
  -d "{\"csr\":\"$(cat device-001.csr | tr -d '\n')\",\"certificate_name\":\"device-001\",\"validity_days\":365}"
```

---

## Error Handling

Common errors and solutions:

| Error                          | Cause                    | Solution                                |
| ------------------------------ | ------------------------ | --------------------------------------- |
| "CSR data is required"         | Missing CSR in request   | Include the `csr` field in request body |
| "certificate_name is required" | Missing certificate name | Include the `certificate_name` field    |
| "Intermediate CA not found"    | CA doesn't exist         | Create the intermediate CA first        |
| "Invalid CSR format"           | Malformed CSR            | Verify CSR is valid PEM format          |
| "CSR signature is invalid"     | Corrupted CSR            | Regenerate the CSR                      |

---

## Next Steps

For production deployment:

1. ✅ CSR parsing - **Implemented**
2. ✅ Certificate signing - **Implemented** (with fallback)
3. ⚠️ Full HSM-backed signing - Partially implemented (needs ASN.1 reconstruction)
4. 🔲 CA hierarchy chain validation
5. 🔲 Certificate revocation list (CRL) management
6. 🔲 OCSP responder support

---

## 10. List Certificates (Paginated)

**Endpoint:** `GET /api/list-certificates`

**⚡ Optimized for 10K-20K certificates** with pagination and two detail levels.

**Query Parameters:**

| Parameter   | Type    | Default   | Description                       |
| ----------- | ------- | --------- | --------------------------------- |
| `type`      | string  | `all`     | Filter: `all`, `ca`, or `device`  |
| `page`      | integer | `1`       | Page number (1-based)             |
| `page_size` | integer | `100`     | Items per page (max: 500)         |
| `details`   | string  | `summary` | Detail level: `summary` or `full` |

**Detail Levels:**

- **`summary`**: Fast! Returns only metadata (name, dates, enabled status)
  - **Use for**: Quick listing, navigation, UI displays
  - **Performance**: ~2-3 seconds for 100 items
- **`full`**: Complete certificate details (parses each certificate)
  - **Use for**: Auditing, detailed inspection
  - **Performance**: ~5-8 seconds for 100 items

**Response:**

```json
{
  "key_vault": "kv-dev-aue-dcert-poc-001",
  "pagination": {
    "page": 1,
    "page_size": 100,
    "total_items": 15234,
    "total_pages": 153,
    "has_next": true,
    "has_previous": false
  },
  "detail_level": "summary",
  "ca_certificates": {
    "total_count": 2,
    "page_count": 2,
    "items": [
      {
        "name": "device-root-ca",
        "thumbprint": "abc123...",
        "created_on": "2026-03-20T10:00:00Z",
        "expires_on": "2036-03-20T10:00:00Z",
        "enabled": true,
        "storage_type": "certificate"
      }
    ],
    "storage_type": "certificate (with private keys in Key Vault)"
  },
  "device_certificates": {
    "total_count": 15232,
    "page_count": 98,
    "items": [
      {
        "name": "device-001",
        "created_on": "2026-03-24T15:30:00Z",
        "enabled": true,
        "storage_type": "secret"
      }
    ],
    "storage_type": "secret (private keys stay with devices)"
  }
}
```

**Full Details Mode Response** (with `details=full`):

```json
{
  "device_certificates": {
    "items": [
      {
        "name": "device-001",
        "thumbprint": "def456...",
        "serial_number": "213DE6B1CE204270933F36736DFC5BFDC23B1494",
        "subject": "CN=device-001.example.com,O=Example,L=Redmond,ST=WA,C=US",
        "issuer": "CN=Device PKI Intermediate CA",
        "created_on": "2026-03-24T15:30:00Z",
        "expires_on": "2027-03-24T15:30:00Z",
        "not_before": "2026-03-24T15:30:00Z",
        "enabled": true,
        "storage_type": "secret"
      }
    ]
  }
}
```

**Example Requests:**

```bash
# Get first page with summary (fast)
GET /api/list-certificates?type=all&page=1&page_size=100&details=summary

# Get device certificates, page 2
GET /api/list-certificates?type=device&page=2&page_size=50

# Get full details for first 200 certificates
GET /api/list-certificates?type=all&page=1&page_size=200&details=full

# Get only CA certificates
GET /api/list-certificates?type=ca
```

**Performance at Scale:**

| Certificates | Page Size | Detail Level | Response Time |
| ------------ | --------- | ------------ | ------------- |
| 1,000        | 100       | summary      | ~2 sec        |
| 10,000       | 100       | summary      | ~2 sec        |
| 20,000       | 100       | summary      | ~2-3 sec      |
| 10,000       | 100       | full         | ~5-8 sec      |
| 20,000       | 500       | summary      | ~8-10 sec     |

**Best Practices:**

1. **Use `summary` mode by default** - 3x faster than full mode
2. **Page size 100-200** optimal for UI display
3. **Use `full` mode only when needed** - for exports or detailed analysis
4. **Cache results** on client side when possible
5. **Use type filters** to reduce result set (`type=device`)

---

## Health Check

**Endpoint:** `GET /api/health`

**Response:**

```json
{
  "status": "healthy",
  "service": "Certificate Authority Management",
  "timestamp": "2026-03-11T..."
}
```
