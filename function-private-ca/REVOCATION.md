# Certificate Revocation Feature

This document describes the certificate revocation functionality added to the PKI Function App.

## New Endpoints

### 1. Revoke Certificate

**Endpoint:** `POST /api/revoke-certificate`

Revokes a device certificate and stores the revocation record in Key Vault.

**Request Body:**

```json
{
  "certificate_name": "device-004-cert",
  "reason": "keyCompromise"
}
```

**Valid Revocation Reasons:**

- `unspecified` - Default reason
- `keyCompromise` - Private key was compromised
- `caCompromise` - CA was compromised
- `affiliationChanged` - Certificate holder changed affiliation
- `superseded` - Certificate replaced by a newer one
- `cessationOfOperation` - Certificate no longer needed
- `certificateHold` - Temporary revocation (can be reversed)
- `removeFromCRL` - Remove from CRL (used with certificateHold)
- `privilegeWithdrawn` - Privileges associated with certificate withdrawn
- `aaCompromise` - Attribute authority was compromised

**Success Response (200):**

```json
{
  "message": "Certificate revoked successfully",
  "revocation_info": {
    "certificate_name": "device-004-cert",
    "serial_number": "274588966340161108532640181039801201354668015422",
    "subject": "<Name(C=US,ST=WA,L=Redmond,O=Example,CN=device-004-cert.example.com)>",
    "reason": "superseded",
    "revoked_at": "2026-03-23T05:00:41.617553",
    "expires_on": "2027-03-23T01:28:55",
    "revoked_by": "Function App"
  },
  "revocation_record": "Key Vault secret: device-004-cert-revoked"
}
```

**Error Responses:**

- `400` - Missing certificate_name or invalid reason
- `404` - Certificate not found
- `409` - Certificate already revoked

### 2. Check Revocation Status

**Endpoint:** `GET /api/check-revocation?certificate_name={name}`

Checks if a certificate has been revoked.

**Query Parameters:**

- `certificate_name` (required) - Name of the certificate to check

**Response (Revoked Certificate):**

```json
{
  "revoked": true,
  "certificate_name": "device-020-cert",
  "revocation_info": {
    "certificate_name": "device-020-cert",
    "serial_number": "361709149554587065338668670412792989332582036696",
    "subject": "<Name(C=US,ST=WA,L=Redmond,O=Example,CN=device-020-cert.example.com)>",
    "reason": "keyCompromise",
    "revoked_at": "2026-03-23T04:59:14.018312",
    "expires_on": "2027-03-23T04:58:34",
    "revoked_by": "Function App"
  }
}
```

**Response (Non-Revoked Certificate):**

```json
{
  "revoked": false,
  "certificate_name": "device-005-cert",
  "message": "Certificate is not revoked"
}
```

**Error Response:**

- `400` - Missing certificate_name parameter

### 3. Renew Certificate

**Endpoint:** `POST /api/renew-certificate`

Renews an existing certificate with a new validity period. The renewed certificate will have a new serial number and expiration date, but can maintain the same subject and public key (or use a new CSR).

**Request Body:**

```json
{
  "certificate_name": "device-001",
  "validity_days": 730,
  "csr": "-----BEGIN CERTIFICATE REQUEST-----..." (optional),
  "intermediate_ca_name": "device-intermediate-ca" (optional),
  "auto_revoke": true,
  "revocation_reason": "superseded" (optional, required if auto_revoke=true)
}
```

**Parameters:**

- `certificate_name` (required) - Name of the certificate to renew
- `validity_days` (optional) - Validity period in days (default: 365)
- `csr` (optional) - New CSR with potentially new key pair. If not provided, reuses existing certificate's subject and public key
- `intermediate_ca_name` (optional) - CA to sign with (default: device-intermediate-ca)
- `auto_revoke` (optional) - Automatically revoke old certificate (default: false)
- `revocation_reason` (optional) - Reason for revoking old certificate (default: superseded)

**Success Response (200) - Without Auto-Revoke:**

```json
{
  "message": "Certificate renewed successfully",
  "certificate_name": "device-005-cert",
  "old_certificate": {
    "serial_number": "360270755081013868268530821642502379691846250268",
    "subject": "<Name(C=US,ST=WA,L=Redmond,O=Example,CN=device-005-cert.example.com)>",
    "expires_on": "2027-03-23T02:47:17"
  },
  "new_certificate": {
    "serial_number": "228555763690375614973967948413685531786169968180",
    "subject": "<Name(C=US,ST=WA,L=Redmond,O=Example,CN=device-005-cert.example.com)>",
    "issuer": "<Name(CN=Device PKI Intermediate CA)>",
    "not_before": "2026-03-23T06:02:35",
    "not_after": "2028-03-22T06:02:35",
    "validity_days": 730
  },
  "certificate_pem": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n",
  "storage_location": "Key Vault secret: device-005-cert-cert"
}
```

**Success Response (200) - With Auto-Revoke:**

```json
{
  "message": "Certificate renewed successfully",
  "certificate_name": "device-002-cert",
  "old_certificate": {...},
  "new_certificate": {...},
  "certificate_pem": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n",
  "storage_location": "Key Vault secret: device-002-cert-cert",
  "old_certificate_revoked": true,
  "revocation_info": {
    "certificate_name": "device-002-cert",
    "serial_number": "380148672987054564118898139631390014663332017042",
    "subject": "<Name(...)>",
    "reason": "superseded",
    "revoked_at": "2026-03-23T06:02:54.855700",
    "expires_on": "2027-03-23T01:27:24",
    "revoked_by": "Function App (auto-revoke on renewal)"
  }
}
```

**Error Responses:**

- `400` - Missing certificate_name or invalid parameters
- `404` - Certificate not found or intermediate CA not found
- `500` - Certificate renewal failed

**Renewal Scenarios:**

1. **Simple Renewal** - Reuse existing subject and public key, extend validity
2. **Renewal with New Key** - Provide CSR with new key pair for key rotation
3. **Renewal with Auto-Revoke** - Automatically revoke old certificate when renewing

### 4. List Certificates (Enhanced)

**Endpoint:** `GET /api/list-certificates?type={type}`

Lists all certificates from Key Vault, now including both CA certificates and device certificates.

**Query Parameters:**

- `type` (optional) - Filter by certificate type: `all`, `ca`, `device` (default: `all`)

**Response:**

```json
{
  "ca_certificates": [
    {
      "name": "device-root-ca",
      "thumbprint": "0f9cf5728d9482f390e1eb93720e606bc4ad6aec",
      "created": "2026-03-22T09:45:32+00:00",
      "expires": "2036-03-22T09:45:32+00:00",
      "enabled": true
    }
  ],
  "device_certificates": [
    {
      "name": "device-001",
      "thumbprint": "8b16d0e28b8f6f44d9462cc6c81d0e6920ea215d9b1f39ae3f21e68a8fd066a1",
      "created": "2026-03-22T10:24:12+00:00",
      "expires": "2027-03-22T10:24:11",
      "enabled": true
    }
  ],
  "summary": {
    "ca_certificates": 2,
    "device_certificates": 5,
    "total": 7
  }
}
```

## Certificate Storage Architecture

### CA Certificates

- Stored in Key Vault **certificate store** (both public cert and private key)
- Used for signing device certificates
- Accessible via `CertificateClient`

### Device Certificates

- Stored in Key Vault **secrets** (public certificate only, private key stays with device)
- Secret name pattern: `{certificate_name}-cert`
- Content type: `application/x-pem-file`
- This is the correct PKI architecture - device private keys should never leave the device

### Revocation Records

- Stored as Key Vault **secrets**
- Secret name pattern: `{certificate_name}-revoked`
- Contains JSON with revocation details
- Content type: `application/json`

## Test Scripts

### Issue a Certificate

```bash
./test/issue-certificate.sh device-021-cert
```

### List All Certificates

```bash
./test/list-certificates.sh
```

### Revoke a Certificate

```bash
./test/revoke-certificate.sh device-021-cert keyCompromise
```

### Check Revocation Status

```bash
./test/check-revocation.sh device-021-cert
```

### Renew a Certificate

```bash
# Simple renewal - reuse existing subject and public key, extend for 2 years
./test/renew-certificate.sh device-021-cert 730

# Renewal with auto-revoke - renew and automatically revoke old certificate
./test/renew-certificate.sh device-021-cert 365 true superseded

# Renewal with new CSR - generate new key pair for certificate rotation
./test/renew-certificate.sh device-021-cert 365 false false true
```

## Deployment Notes

### Platform-Specific Python Packages

The function app runs on **Linux x86_64**, but development may happen on other platforms (e.g., macOS ARM64). When deploying with pre-built Python packages, use:

```bash
pip install --platform manylinux2014_x86_64 --only-binary=:all: \
  --target ./.python_packages/lib/site-packages \
  -r requirements.txt
```

This ensures packages like `cryptography` (with compiled C extensions) are compatible with the Azure Functions runtime.

### Creating Deployment Package

```bash
cd function-private-ca

# Install platform-specific dependencies
rm -rf .python_packages
pip install --platform manylinux2014_x86_64 --only-binary=:all: \
  --target ./.python_packages/lib/site-packages \
  -r requirements.txt

# Create deployment package
zip -r function-app-with-deps.zip \
  function_app.py \
  host.json \
  requirements.txt \
  .python_packages
```

### Deploy to Azure

```bash
# Transfer to VM (required for private endpoints)
scp -i ~/.ssh/vm-dev-aue-dcert-poc-keypair.pem \
  function-app-with-deps.zip \
  azureuser@<YOUR_VM_IP>:~/

# Deploy via Azure CLI
ssh -i ~/.ssh/vm-dev-aue-dcert-poc-keypair.pem azureuser@<YOUR_VM_IP> \
  "az functionapp deployment source config-zip \
    -g rg-dev-aue-dcert-poc \
    -n func-devicepki-dev-001 \
    --src ~/function-app-with-deps.zip"

# Wait for function app to restart (60-90 seconds)
# First request may timeout due to cold start with large package
```

## RBAC Requirements

The function app managed identity requires:

1. **Key Vault Certificates Officer** - Create and manage CA certificates
2. **Key Vault Secrets Officer** - Store device certificates and revocation records
3. **Key Vault Crypto Officer** - Sign certificates with CA private keys
4. **Key Vault Reader** - Read certificate properties

These roles are configured in `infra/bicep/main.bicep` (lines 300-345).

## Certificate Lifecycle Management

The PKI Function App now provides complete certificate lifecycle management:

✅ **Issue (Enroll)** - Create new device certificates from CSR  
✅ **Renew** - Extend certificate validity with optional auto-revoke of old certificate  
✅ **Revoke** - Invalidate certificates with X.509 standard reasons  
✅ **Check Status** - Query certificate revocation status  
✅ **List** - Inventory all CA and device certificates

## Next Steps / Future Enhancements

1. **CRL Generation** - Generate Certificate Revocation Lists (CRL) from revocation records for offline validation
2. **OCSP Responder** - Implement Online Certificate Status Protocol for real-time revocation checking
3. **Automated Expiry Monitoring** - Alert when certificates are about to expire (e.g., 30 days before)
4. **Bulk Operations** - Revoke or renew multiple certificates in a single operation
5. **Audit Logging** - Enhanced logging to Azure Monitor for compliance tracking
6. **Scheduled Certificate Renewal** - Automatically renew certificates approaching expiration via Azure Functions timer trigger
7. **Certificate Templates** - Define certificate profiles (validity periods, key usage, extensions) for different device types
8. **Key Escrow** - Optional private key backup for specific certificate types (with appropriate security controls)
