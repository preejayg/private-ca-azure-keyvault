"""
Certificate Authority Management Service
Manages three-level PKI hierarchy:
1. Root CA Certificate - Top-level certificate authority
2. Intermediate CA Certificate - Intermediate certificate authority signed by root CA
3. Certificate Issuance - Issue/sign end-entity certificates using intermediate CA
"""
import logging
import json
import azure.functions as func
import os
from datetime import datetime, timedelta
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtensionOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
import base64
from azure.identity import DefaultAzureCredential
from azure.keyvault.certificates import CertificateClient, CertificatePolicy, CertificateContentType
from azure.keyvault.keys import KeyClient
from azure.keyvault.keys.crypto import CryptographyClient, SignatureAlgorithm
from azure.keyvault.secrets import SecretClient

# Initialize Function App
app = func.FunctionApp()

# Configuration
KEY_VAULT_NAME = os.environ.get("KEY_VAULT_NAME")
if not KEY_VAULT_NAME:
    raise ValueError("KEY_VAULT_NAME environment variable is required")

KEY_VAULT_URL = f"https://{KEY_VAULT_NAME}.vault.azure.net"

# Global client variables (lazy-loaded)
_credential = None
_cert_client = None
_key_client = None
_secret_client = None

def get_keyvault_clients():
    """
    Lazy-load Key Vault clients (initialized on first use).
    This prevents startup failures if Key Vault is temporarily unavailable.
    """
    global _credential, _cert_client, _key_client, _secret_client

    if _cert_client is None:
        _credential = DefaultAzureCredential()
        _cert_client = CertificateClient(vault_url=KEY_VAULT_URL, credential=_credential)
        _key_client = KeyClient(vault_url=KEY_VAULT_URL, credential=_credential)
        _secret_client = SecretClient(vault_url=KEY_VAULT_URL, credential=_credential)

    return _cert_client, _key_client, _secret_client


def sign_certificate_with_keyvault(tbs_cert_bytes, ca_key_name, signature_algorithm_oid):
    """
    Sign certificate TBS (To-Be-Signed) bytes using Azure Key Vault's HSM-backed private key.

    This function:
    1. Takes the TBS certificate DER bytes
    2. Hashes them with SHA-256
    3. Signs the hash using Key Vault's sign() operation
    4. Returns the raw signature bytes

    Args:
        tbs_cert_bytes: DER-encoded TBS certificate bytes
        ca_key_name: Name of the CA key in Key Vault (e.g., 'device-root-ca')
        signature_algorithm_oid: OID for signature algorithm (for verification)

    Returns:
        Raw signature bytes (DER-encoded BIT STRING content)

    Note: The certificate must be reconstructed by combining:
          SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
    """
    try:
        # Get Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        # Get the CA key reference
        ca_key = key_client.get_key(ca_key_name)

        # Create a cryptography client for signing
        crypto_client = CryptographyClient(ca_key, credential=_credential)

        # Hash the TBS certificate bytes with SHA-256
        hasher = hashes.Hash(hashes.SHA256(), backend=default_backend())
        hasher.update(tbs_cert_bytes)
        digest = hasher.finalize()

        # Sign the digest using Key Vault (RS256 = RSASSA-PKCS1-v1_5 with SHA-256)
        logging.info(f"Signing certificate with Key Vault key: {ca_key_name}")
        sign_result = crypto_client.sign(SignatureAlgorithm.rs256, digest)

        logging.info(f"✅ Certificate signed successfully with Key Vault HSM key")
        return sign_result.signature

    except Exception as e:
        logging.error(f"Error signing certificate with Key Vault: {str(e)}")
        import traceback
        logging.error(f"Traceback: {traceback.format_exc()}")
        raise


def build_signed_certificate_der(tbs_cert_der, signature_algorithm_oid, signature_bytes):
    """
    Manually construct a complete X.509 certificate in DER format.

    X.509 Certificate structure (ASN.1):
    Certificate ::= SEQUENCE {
        tbsCertificate       TBSCertificate,
        signatureAlgorithm   AlgorithmIdentifier,
        signature            BIT STRING
    }

    Args:
        tbs_cert_der: DER-encoded TBS certificate bytes
        signature_algorithm_oid: OID for signature algorithm (e.g., sha256WithRSAEncryption)
        signature_bytes: Raw signature bytes from Key Vault

    Returns:
        Complete DER-encoded certificate bytes
    """
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat._oid import ObjectIdentifier

    # Build signatureAlgorithm (AlgorithmIdentifier)
    # sha256WithRSAEncryption: SEQUENCE { OBJECT IDENTIFIER, NULL }
    sig_alg_oid_bytes = b'\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x0b'  # OID for sha256WithRSAEncryption
    sig_alg_null = b'\x05\x00'  # NULL
    sig_alg_sequence = sig_alg_oid_bytes + sig_alg_null
    sig_alg_der = b'\x30' + _encode_length(len(sig_alg_sequence)) + sig_alg_sequence

    # Build signature (BIT STRING)
    # BIT STRING: tag 0x03, length, unused_bits (0x00), signature_bytes
    signature_content = b'\x00' + signature_bytes  # 0x00 = no unused bits
    signature_der = b'\x03' + _encode_length(len(signature_content)) + signature_content

    # Build complete certificate (SEQUENCE)
    cert_content = tbs_cert_der + sig_alg_der + signature_der
    cert_der = b'\x30' + _encode_length(len(cert_content)) + cert_content

    return cert_der


def _encode_length(length):
    """
    Encode length in DER format.

    DER length encoding:
    - 0-127: single byte
    - 128+: first byte = 0x80 | num_bytes, followed by length bytes (big-endian)
    """
    if length < 128:
        return bytes([length])
    else:
        # Multi-byte length
        length_bytes = length.to_bytes((length.bit_length() + 7) // 8, byteorder='big')
        return bytes([0x80 | len(length_bytes)]) + length_bytes

    # Add extensions
    cert_builder = cert_builder.add_extension(
        x509.BasicConstraints(ca=False, path_length=None),
        critical=True,
    )
    cert_builder = cert_builder.add_extension(
        x509.KeyUsage(
            digital_signature=True,
            key_encipherment=True,
            content_commitment=False,
            data_encipherment=False,
            key_agreement=False,
            key_cert_sign=False,
            crl_sign=False,
            encipher_only=False,
            decipher_only=False,
        ),
        critical=True,
    )

    # Sign the certificate (using temp key for demo)
    certificate = cert_builder.sign(temp_ca_key, hashes.SHA256(), default_backend())

    return certificate


@app.route(route="create-root-ca", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def create_root_ca(req: func.HttpRequest) -> func.HttpResponse:
    """
    Create a self-signed root CA certificate in Key Vault

    POST Body:
    {
        "ca_name": "device-root-ca",
        "common_name": "Device PKI Root CA",
        "validity_years": 10
    }

    Note: This creates a proper root CA certificate with CA:TRUE in Basic Constraints.
    The root CA is self-signed and stored in Key Vault HSM.
    """
    logging.info('Creating root CA certificate')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        # Parse request
        req_body = req.get_json()
        ca_name = req_body.get('ca_name', 'device-root-ca')
        common_name = req_body.get('common_name', 'Device PKI Root CA')
        validity_years = req_body.get('validity_years', 10)

        # Check if CA already exists
        try:
            existing_cert = cert_client.get_certificate(ca_name)
            return func.HttpResponse(
                json.dumps({
                    "error": "Root CA already exists",
                    "certificate_id": existing_cert.id,
                    "thumbprint": existing_cert.properties.x509_thumbprint.hex()
                }),
                status_code=409,
                mimetype="application/json"
            )
        except Exception:
            pass  # Certificate doesn't exist, proceed

        # Generate private key for root CA
        logging.info(f"Generating root CA private key (4096-bit RSA)")
        root_private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=4096,
            backend=default_backend()
        )

        # Build root CA certificate (self-signed)
        subject_name = x509.Name([
            x509.NameAttribute(x509.NameOID.COMMON_NAME, common_name)
        ])

        # Root CA is self-signed, so issuer = subject
        builder = x509.CertificateBuilder()
        builder = builder.subject_name(subject_name)
        builder = builder.issuer_name(subject_name)  # Self-signed
        builder = builder.public_key(root_private_key.public_key())
        builder = builder.serial_number(x509.random_serial_number())
        builder = builder.not_valid_before(datetime.utcnow())
        builder = builder.not_valid_after(
            datetime.utcnow() + timedelta(days=validity_years * 365)
        )

        # Add CA extensions
        # Basic Constraints: CA=TRUE, no path length constraint (can sign anything)
        builder = builder.add_extension(
            x509.BasicConstraints(ca=True, path_length=None),
            critical=True
        )

        # Key Usage: Certificate Sign, CRL Sign
        builder = builder.add_extension(
            x509.KeyUsage(
                digital_signature=False,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=True,
                crl_sign=True,
                encipher_only=False,
                decipher_only=False
            ),
            critical=True
        )

        # Subject Key Identifier
        builder = builder.add_extension(
            x509.SubjectKeyIdentifier.from_public_key(root_private_key.public_key()),
            critical=False
        )

        # Sign the root CA certificate with its own private key (self-signed)
        logging.info("Signing root CA certificate (self-signed)...")
        root_cert = builder.sign(
            private_key=root_private_key,
            algorithm=hashes.SHA256(),
            backend=default_backend()
        )

        # Convert certificate to PEM
        cert_pem = root_cert.public_bytes(serialization.Encoding.PEM).decode('utf-8')

        # Convert private key to PEM
        private_key_pem = root_private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        ).decode('utf-8')

        # Import certificate and private key to Key Vault
        logging.info(f"Importing root CA to Key Vault: {ca_name}")

        # Combine certificate and private key for import
        import_content = cert_pem + private_key_pem

        imported_cert = cert_client.import_certificate(
            certificate_name=ca_name,
            certificate_bytes=import_content.encode('utf-8'),
            policy=CertificatePolicy(
                issuer_name="Self",
                subject=f"CN={common_name}",
                exportable=False,  # HSM-protected: NEVER export CA private keys
                key_type="RSA",
                key_size=4096,
                reuse_key=False,
                content_type=CertificateContentType.pem,
                validity_in_months=validity_years * 12
            )
        )

        return func.HttpResponse(
            json.dumps({
                "message": "Root CA created successfully",
                "certificate_id": imported_cert.id,
                "certificate_name": imported_cert.name,
                "thumbprint": imported_cert.properties.x509_thumbprint.hex(),
                "expires_on": imported_cert.properties.expires_on.isoformat(),
                "subject": root_cert.subject.rfc4514_string(),
                "serial_number": format(root_cert.serial_number, 'X'),
                "note": "✅ Root CA created with proper CA:TRUE constraint",
                "vault_url": KEY_VAULT_URL
            }),
            status_code=201,
            mimetype="application/json"
        )

    except ValueError as e:
        logging.error(f"Invalid request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Invalid request: {str(e)}"}),
            status_code=400,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Error creating root CA: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to create root CA: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="get-root-ca", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def get_root_ca(req: func.HttpRequest) -> func.HttpResponse:
    """
    Get root CA certificate public key/certificate

    Query Parameters:
    - ca_name: Name of the root CA (default: device-root-ca)
    - format: certificate or public_key (default: certificate)
    """
    logging.info('Retrieving root CA certificate')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        ca_name = req.params.get('ca_name', 'device-root-ca')
        format_type = req.params.get('format', 'certificate')

        # Get certificate from Key Vault
        certificate = cert_client.get_certificate(ca_name)

        response_data = {
            "certificate_name": certificate.name,
            "thumbprint": certificate.properties.x509_thumbprint.hex(),
            "expires_on": certificate.properties.expires_on.isoformat(),
            "created_on": certificate.properties.created_on.isoformat(),
            "key_id": certificate.key_id
        }

        if format_type == "certificate":
            # Convert DER certificate to PEM format
            cert_der = certificate.cer
            cert_pem = "-----BEGIN CERTIFICATE-----\n"
            cert_pem += base64.b64encode(cert_der).decode('utf-8')
            # Insert line breaks every 64 characters
            cert_pem = cert_pem[:len("-----BEGIN CERTIFICATE-----\n")] + '\n'.join(
                [cert_pem[i:i+64] for i in range(len("-----BEGIN CERTIFICATE-----\n"), len(cert_pem), 64)]
            )
            cert_pem += "\n-----END CERTIFICATE-----"
            response_data["certificate_pem"] = cert_pem

        return func.HttpResponse(
            json.dumps(response_data),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error retrieving root CA: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to retrieve root CA: {str(e)}"}),
            status_code=404 if "not found" in str(e).lower() else 500,
            mimetype="application/json"
        )


@app.route(route="create-intermediate-ca", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def create_intermediate_ca(req: func.HttpRequest) -> func.HttpResponse:
    """
    Create an intermediate CA certificate signed by the root CA

    POST Body:
    {
        "ca_name": "device-intermediate-ca",
        "common_name": "Device PKI Intermediate CA",
        "root_ca_name": "device-root-ca",
        "validity_years": 5
    }

    Note: This creates a proper CA hierarchy with the intermediate CA signed by the root CA.
    The intermediate CA private key is stored in Key Vault for signing device certificates.
    """
    logging.info('Creating intermediate CA certificate')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        # Parse request
        req_body = req.get_json()
        ca_name = req_body.get('ca_name', 'device-intermediate-ca')
        common_name = req_body.get('common_name', 'Device PKI Intermediate CA')
        root_ca_name = req_body.get('root_ca_name', 'device-root-ca')
        validity_years = req_body.get('validity_years', 5)

        # Check if intermediate CA already exists
        try:
            existing_cert = cert_client.get_certificate(ca_name)
            return func.HttpResponse(
                json.dumps({
                    "error": "Intermediate CA already exists",
                    "certificate_id": existing_cert.id,
                    "thumbprint": existing_cert.properties.x509_thumbprint.hex()
                }),
                status_code=409,
                mimetype="application/json"
            )
        except Exception:
            pass  # Certificate doesn't exist, proceed

        # Get root CA certificate
        try:
            root_kv_cert = cert_client.get_certificate(root_ca_name)
            # Convert DER to PEM and load with cryptography
            root_cert_der = root_kv_cert.cer
            root_cert = x509.load_der_x509_certificate(root_cert_der, default_backend())
        except Exception as e:
            return func.HttpResponse(
                json.dumps({"error": f"Root CA '{root_ca_name}' not found: {str(e)}"}),
                status_code=404,
                mimetype="application/json"
            )

        # Generate private key for intermediate CA
        logging.info(f"Generating intermediate CA private key (4096-bit RSA)")
        intermediate_private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=4096,
            backend=default_backend()
        )

        # Build intermediate CA certificate
        subject_name = x509.Name([
            x509.NameAttribute(x509.NameOID.COMMON_NAME, common_name)
        ])

        # Use root CA's subject as issuer
        issuer_name = root_cert.subject

        # Build certificate
        builder = x509.CertificateBuilder()
        builder = builder.subject_name(subject_name)
        builder = builder.issuer_name(issuer_name)
        builder = builder.public_key(intermediate_private_key.public_key())
        builder = builder.serial_number(x509.random_serial_number())
        builder = builder.not_valid_before(datetime.utcnow())
        builder = builder.not_valid_after(
            datetime.utcnow() + timedelta(days=validity_years * 365)
        )

        # Add extensions for intermediate CA
        # Basic Constraints: CA=TRUE, pathlen=0 (can sign end-entity certs but not other CAs)
        builder = builder.add_extension(
            x509.BasicConstraints(ca=True, path_length=0),
            critical=True
        )

        # Key Usage: Certificate Sign, CRL Sign
        builder = builder.add_extension(
            x509.KeyUsage(
                digital_signature=False,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=True,
                crl_sign=True,
                encipher_only=False,
                decipher_only=False
            ),
            critical=True
        )

        # Subject Key Identifier
        builder = builder.add_extension(
            x509.SubjectKeyIdentifier.from_public_key(intermediate_private_key.public_key()),
            critical=False
        )

        # Authority Key Identifier (from root CA)
        builder = builder.add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(root_cert.public_key()),
            critical=False
        )

        # Step 1: Build certificate with temporary key to get TBS (To-Be-Signed) structure
        logging.info("Building TBS certificate structure...")
        temp_signing_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )

        temp_cert = builder.sign(
            private_key=temp_signing_key,
            algorithm=hashes.SHA256(),
            backend=default_backend()
        )

        # Step 2: Extract TBS certificate DER bytes
        tbs_cert_der = temp_cert.tbs_certificate_bytes
        logging.info(f"TBS certificate size: {len(tbs_cert_der)} bytes")

        # Step 3: Sign TBS using Key Vault's HSM-protected root CA private key
        logging.info(f"Signing TBS with Key Vault HSM key: {root_ca_name}")
        signature_bytes = sign_certificate_with_keyvault(
            tbs_cert_bytes=tbs_cert_der,
            ca_key_name=root_ca_name,
            signature_algorithm_oid=None  # sha256WithRSAEncryption
        )

        # Step 4: Reconstruct complete certificate with real signature
        logging.info("Reconstructing certificate with Key Vault signature...")
        final_cert_der = build_signed_certificate_der(
            tbs_cert_der=tbs_cert_der,
            signature_algorithm_oid=None,  # sha256WithRSAEncryption
            signature_bytes=signature_bytes
        )

        # Step 5: Load and verify the reconstructed certificate
        intermediate_cert = x509.load_der_x509_certificate(final_cert_der, default_backend())
        logging.info(f"✅ Certificate reconstructed successfully")
        logging.info(f"   Issuer: {intermediate_cert.issuer.rfc4514_string()}")
        logging.info(f"   Subject: {intermediate_cert.subject.rfc4514_string()}")
        logging.info(f"   Serial: {format(intermediate_cert.serial_number, 'X')}")

        # Convert certificate to PEM
        cert_pem = intermediate_cert.public_bytes(serialization.Encoding.PEM).decode('utf-8')

        # Convert private key to PEM
        private_key_pem = intermediate_private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        ).decode('utf-8')

        # Import certificate and private key to Key Vault
        # Use import_certificate to store both cert and key together
        logging.info(f"Importing intermediate CA to Key Vault: {ca_name}")

        # Combine certificate and private key for import
        import_content = cert_pem + private_key_pem

        imported_cert = cert_client.import_certificate(
            certificate_name=ca_name,
            certificate_bytes=import_content.encode('utf-8'),
            policy=CertificatePolicy(
                issuer_name="Unknown",  # External issuer (root CA)
                subject=f"CN={common_name}",
                exportable=False,  # HSM-protected: NEVER export CA private keys
                key_type="RSA",
                key_size=4096,
                reuse_key=False,
                content_type=CertificateContentType.pem,
                validity_in_months=validity_years * 12
            )
        )

        return func.HttpResponse(
            json.dumps({
                "message": "Intermediate CA created successfully",
                "certificate_id": imported_cert.id,
                "certificate_name": imported_cert.name,
                "thumbprint": imported_cert.properties.x509_thumbprint.hex(),
                "expires_on": imported_cert.properties.expires_on.isoformat(),
                "root_ca": root_ca_name,
                "issuer": root_cert.subject.rfc4514_string(),
                "subject": intermediate_cert.subject.rfc4514_string(),
                "serial_number": format(intermediate_cert.serial_number, 'X'),
                "note": "✅ Intermediate CA signed by Root CA using Azure Key Vault HSM",
                "signing_method": "Azure Key Vault CryptographyClient with RS256 (RSASSA-PKCS1-v1_5 + SHA256)",
                "vault_url": KEY_VAULT_URL
            }),
            status_code=201,
            mimetype="application/json"
        )

    except ValueError as e:
        logging.error(f"Invalid request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Invalid request: {str(e)}"}),
            status_code=400,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Error creating intermediate CA: {str(e)}")
        import traceback
        logging.error(f"Traceback: {traceback.format_exc()}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to create intermediate CA: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="get-intermediate-ca", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def get_intermediate_ca(req: func.HttpRequest) -> func.HttpResponse:
    """
    Get intermediate CA certificate

    Query Parameters:
    - ca_name: Name of the intermediate CA (default: device-intermediate-ca)
    - format: certificate or public_key (default: certificate)
    """
    logging.info('Retrieving intermediate CA certificate')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        ca_name = req.params.get('ca_name', 'device-intermediate-ca')
        format_type = req.params.get('format', 'certificate')

        # Get certificate from Key Vault
        certificate = cert_client.get_certificate(ca_name)

        response_data = {
            "certificate_name": certificate.name,
            "thumbprint": certificate.properties.x509_thumbprint.hex(),
            "expires_on": certificate.properties.expires_on.isoformat(),
            "created_on": certificate.properties.created_on.isoformat(),
            "key_id": certificate.key_id
        }

        if format_type == "certificate":
            # Convert DER certificate to PEM format
            cert_der = certificate.cer
            cert_pem = "-----BEGIN CERTIFICATE-----\n"
            cert_pem += base64.b64encode(cert_der).decode('utf-8')
            # Insert line breaks every 64 characters
            cert_pem = cert_pem[:len("-----BEGIN CERTIFICATE-----\n")] + '\n'.join(
                [cert_pem[i:i+64] for i in range(len("-----BEGIN CERTIFICATE-----\n"), len(cert_pem), 64)]
            )
            cert_pem += "\n-----END CERTIFICATE-----"
            response_data["certificate_pem"] = cert_pem

        return func.HttpResponse(
            json.dumps(response_data),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error retrieving intermediate CA: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to retrieve intermediate CA: {str(e)}"}),
            status_code=404 if "not found" in str(e).lower() else 500,
            mimetype="application/json"
        )


@app.route(route="get-certificate", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def get_certificate(req: func.HttpRequest) -> func.HttpResponse:
    """
    Get an issued device certificate

    Query Parameters:
    - cert_name: Name of the certificate (required)
    - format: certificate or metadata (default: certificate)

    Returns the certificate PEM and metadata for issued device certificates.
    Device certificates are stored as Key Vault secrets (not in the certificate store).
    """
    logging.info('Retrieving device certificate')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        cert_name = req.params.get('cert_name')
        if not cert_name:
            return func.HttpResponse(
                json.dumps({"error": "cert_name parameter is required"}),
                status_code=400,
                mimetype="application/json"
            )

        format_type = req.params.get('format', 'certificate')

        # Get certificate from Key Vault secrets (stored as {cert_name}-cert)
        secret_name = f"{cert_name}-cert"
        try:
            secret = secret_client.get_secret(secret_name)
            cert_pem = secret.value
        except Exception as e:
            if "not found" in str(e).lower():
                return func.HttpResponse(
                    json.dumps({"error": f"Certificate not found: {cert_name}"}),
                    status_code=404,
                    mimetype="application/json"
                )
            raise

        # Parse certificate to extract metadata
        from cryptography import x509
        from cryptography.hazmat.backends import default_backend

        cert_obj = x509.load_pem_x509_certificate(cert_pem.encode(), default_backend())

        # Extract subject information
        subject_dict = {}
        for attribute in cert_obj.subject:
            subject_dict[attribute.oid._name] = attribute.value

        # Extract issuer information
        issuer_dict = {}
        for attribute in cert_obj.issuer:
            issuer_dict[attribute.oid._name] = attribute.value

        response_data = {
            "certificate_name": cert_name,
            "serial_number": format(cert_obj.serial_number, 'X'),
            "subject": subject_dict,
            "issuer": issuer_dict,
            "not_before": cert_obj.not_valid_before_utc.isoformat(),
            "not_after": cert_obj.not_valid_after_utc.isoformat(),
            "signature_algorithm": cert_obj.signature_algorithm_oid._name,
            "version": cert_obj.version.name,
            "created_on": secret.properties.created_on.isoformat() if secret.properties.created_on else None,
            "updated_on": secret.properties.updated_on.isoformat() if secret.properties.updated_on else None
        }

        if format_type == "certificate":
            response_data["certificate"] = cert_pem

        return func.HttpResponse(
            json.dumps(response_data),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error retrieving certificate: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to retrieve certificate: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="issue-certificate", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def issue_certificate(req: func.HttpRequest) -> func.HttpResponse:
    """
    Issue/sign an end-entity certificate using the intermediate CA

    POST Body:
    {
        "csr": "-----BEGIN CERTIFICATE REQUEST-----...",
        "intermediate_ca_name": "device-intermediate-ca",
        "validity_days": 365,
        "certificate_name": "device-001"
    }

    Note: This is a placeholder. Full CSR signing requires additional crypto libraries
    or using Key Vault's certificate signing capabilities.
    """
    logging.info('Issuing certificate using intermediate CA')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        req_body = req.get_json()
        csr_data = req_body.get('csr')
        intermediate_ca_name = req_body.get('intermediate_ca_name', 'device-intermediate-ca')
        validity_days = req_body.get('validity_days', 365)
        cert_name = req_body.get('certificate_name')

        if not csr_data:
            return func.HttpResponse(
                json.dumps({"error": "CSR data is required"}),
                status_code=400,
                mimetype="application/json"
            )

        if not cert_name:
            return func.HttpResponse(
                json.dumps({"error": "certificate_name is required"}),
                status_code=400,
                mimetype="application/json"
            )

        # Verify intermediate CA exists
        try:
            intermediate_cert = cert_client.get_certificate(intermediate_ca_name)
            # Key Vault returns DER format, not PEM
            intermediate_cert_obj = x509.load_der_x509_certificate(
                intermediate_cert.cer,
                default_backend()
            )
        except Exception as e:
            return func.HttpResponse(
                json.dumps({"error": f"Intermediate CA '{intermediate_ca_name}' not found: {str(e)}"}),
                status_code=404,
                mimetype="application/json"
            )

        # Parse the CSR
        try:
            # Handle both PEM and base64 encoded CSR
            if "BEGIN CERTIFICATE REQUEST" in csr_data:
                csr_pem = csr_data.encode('utf-8')
            else:
                # Assume base64 encoded
                csr_pem = base64.b64decode(csr_data)

            csr = x509.load_pem_x509_csr(csr_pem, default_backend())
            logging.info(f"CSR parsed successfully. Subject: {csr.subject}")
        except Exception as e:
            logging.error(f"Failed to parse CSR: {str(e)}")
            return func.HttpResponse(
                json.dumps({"error": f"Invalid CSR format: {str(e)}"}),
                status_code=400,
                mimetype="application/json"
            )

        # Validate CSR signature
        if not csr.is_signature_valid:
            return func.HttpResponse(
                json.dumps({"error": "CSR signature is invalid"}),
                status_code=400,
                mimetype="application/json"
            )

        # Extract information from CSR
        subject = csr.subject
        public_key = csr.public_key()

        # Get the intermediate CA key from Key Vault
        try:
            ca_key = key_client.get_key(intermediate_ca_name)
        except Exception as e:
            logging.error(f"Failed to get intermediate CA key: {str(e)}")
            return func.HttpResponse(
                json.dumps({"error": f"Failed to access intermediate CA key: {str(e)}"}),
                status_code=500,
                mimetype="application/json"
            )

        # Build the certificate
        # Note: Since Key Vault keys are not exportable, we need to use Key Vault's signing capability
        # For this implementation, we'll create a certificate using Azure Key Vault's certificate merge operation

        # Create certificate builder
        cert_builder = x509.CertificateBuilder()
        cert_builder = cert_builder.subject_name(subject)
        cert_builder = cert_builder.issuer_name(intermediate_cert_obj.subject)
        cert_builder = cert_builder.public_key(public_key)
        cert_builder = cert_builder.serial_number(x509.random_serial_number())
        cert_builder = cert_builder.not_valid_before(datetime.utcnow())
        cert_builder = cert_builder.not_valid_after(
            datetime.utcnow() + timedelta(days=validity_days)
        )

        # Add extensions
        cert_builder = cert_builder.add_extension(
            x509.BasicConstraints(ca=False, path_length=None),
            critical=True,
        )
        cert_builder = cert_builder.add_extension(
            x509.KeyUsage(
                digital_signature=True,
                key_encipherment=True,
                content_commitment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )

        # Add Subject Alternative Names if present in CSR
        try:
            san_ext = csr.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
            cert_builder = cert_builder.add_extension(san_ext.value, critical=False)
        except x509.ExtensionNotFound:
            pass

        # Add CRL Distribution Point extension
        # Points to the CRL endpoint for certificate revocation checking
        try:
            function_app_url = os.environ.get("WEBSITE_HOSTNAME", "func-devicepki-dev-001.azurewebsites.net")
            crl_url = f"https://{function_app_url}/api/crl/intermediate"

            crl_dp = x509.CRLDistributionPoints([
                x509.DistributionPoint(
                    full_name=[x509.UniformResourceIdentifier(crl_url)],
                    relative_name=None,
                    crl_issuer=None,
                    reasons=None
                )
            ])
            cert_builder = cert_builder.add_extension(crl_dp, critical=False)
            logging.info(f"Added CRL Distribution Point: {crl_url}")
        except Exception as e:
            logging.warning(f"Failed to add CRL Distribution Point: {str(e)}")
            # Continue without CRL DP - not critical

        # Create and sign the certificate using Key Vault HSM signing
        try:
            # Step 1: Build certificate with temporary key to get TBS structure
            logging.info("Building TBS certificate structure...")
            temp_signing_key = rsa.generate_private_key(
                public_exponent=65537,
                key_size=2048,
                backend=default_backend()
            )

            temp_cert = cert_builder.sign(
                private_key=temp_signing_key,
                algorithm=hashes.SHA256(),
                backend=default_backend()
            )

            # Step 2: Extract TBS certificate DER bytes
            tbs_cert_der = temp_cert.tbs_certificate_bytes
            logging.info(f"TBS certificate size: {len(tbs_cert_der)} bytes")

            # Step 3: Sign TBS using Key Vault's HSM-protected intermediate CA private key
            logging.info(f"Signing TBS with Key Vault HSM key: {intermediate_ca_name}")
            signature_bytes = sign_certificate_with_keyvault(
                tbs_cert_bytes=tbs_cert_der,
                ca_key_name=intermediate_ca_name,
                signature_algorithm_oid=None  # sha256WithRSAEncryption
            )

            # Step 4: Reconstruct complete certificate with real signature
            logging.info("Reconstructing certificate with Key Vault signature...")
            final_cert_der = build_signed_certificate_der(
                tbs_cert_der=tbs_cert_der,
                signature_algorithm_oid=None,
                signature_bytes=signature_bytes
            )

            # Step 5: Load and verify the reconstructed certificate
            signed_cert = x509.load_der_x509_certificate(final_cert_der, default_backend())
            logging.info(f"✅ Certificate signed successfully with Key Vault HSM")
            logging.info(f"   Issuer: {signed_cert.issuer.rfc4514_string()}")
            logging.info(f"   Subject: {signed_cert.subject.rfc4514_string()}")
            logging.info(f"   Serial: {format(signed_cert.serial_number, 'X')}")

            # Convert to PEM format
            cert_pem = signed_cert.public_bytes(encoding=serialization.Encoding.PEM).decode('utf-8')

            # Store device certificate as a secret (private key stays with device)
            # Note: Key Vault certificate store is for certificates WITH private keys.
            # Device certificates (where private key stays with the device) are stored as secrets.
            secret_name = f"{cert_name}-cert"
            secret_client.set_secret(secret_name, cert_pem, content_type="application/x-pem-file")
            storage_location = f"Key Vault secret: {secret_name}"
            logging.info(f"Device certificate {cert_name} stored as secret (private key stays with device)")

            return func.HttpResponse(
                json.dumps({
                    "message": "Certificate issued successfully",
                    "intermediate_ca": intermediate_ca_name,
                    "certificate_name": cert_name,
                    "subject": str(subject),
                    "issuer": str(signed_cert.issuer),
                    "validity_days": validity_days,
                    "not_before": signed_cert.not_valid_before.isoformat(),
                    "not_after": signed_cert.not_valid_after.isoformat(),
                    "serial_number": str(signed_cert.serial_number),
                    "certificate_pem": cert_pem,
                    "storage_location": storage_location,
                    "signing_method": "✅ Azure Key Vault HSM (CryptographyClient with RS256)",
                    "note": "Device certificate signed using HSM-protected Intermediate CA key. Private key remains with device."
                }),
                status_code=201,
                mimetype="application/json"
            )

        except Exception as e:
            logging.error(f"Error during certificate issuance: {str(e)}")
            return func.HttpResponse(
                json.dumps({"error": f"Certificate issuance failed: {str(e)}"}),
                status_code=500,
                mimetype="application/json"
            )

    except ValueError as e:
        logging.error(f"Invalid request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Invalid request: {str(e)}"}),
            status_code=400,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Error issuing certificate: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to issue certificate: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="revoke-certificate", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def revoke_certificate(req: func.HttpRequest) -> func.HttpResponse:
    """
    Revoke a previously issued certificate

    POST Body:
    {
        "certificate_name": "device-001",
        "reason": "keyCompromise|cessationOfOperation|affiliationChanged|superseded|unspecified",
        "revocation_date": "2026-03-23T10:00:00Z" (optional, defaults to current time)
    }

    Stores revocation information in Key Vault as a secret.
    """
    logging.info('Revoking certificate')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        req_body = req.get_json()
        cert_name = req_body.get('certificate_name')
        reason = req_body.get('reason', 'unspecified')
        revocation_date = req_body.get('revocation_date')

        if not cert_name:
            return func.HttpResponse(
                json.dumps({"error": "certificate_name is required"}),
                status_code=400,
                mimetype="application/json"
            )

        # Validate revocation reason
        valid_reasons = [
            'unspecified',
            'keyCompromise',
            'caCompromise',
            'affiliationChanged',
            'superseded',
            'cessationOfOperation',
            'certificateHold',
            'removeFromCRL',
            'privilegeWithdrawn',
            'aaCompromise'
        ]

        if reason not in valid_reasons:
            return func.HttpResponse(
                json.dumps({
                    "error": f"Invalid revocation reason. Valid reasons: {', '.join(valid_reasons)}"
                }),
                status_code=400,
                mimetype="application/json"
            )

        # Check if certificate exists (try certificate store first, then secrets for backward compatibility)
        cert_pem = None
        cert_obj = None

        # Try to get certificate from certificate store
        try:
            certificate = cert_client.get_certificate(cert_name)
            # Convert DER to PEM for parsing
            cert_der = certificate.cer
            cert_obj = x509.load_der_x509_certificate(cert_der, default_backend())
            serial_number = str(cert_obj.serial_number)
            subject = str(cert_obj.subject)
            expires_on = cert_obj.not_valid_after.isoformat()
            logging.info(f"Certificate {cert_name} found in certificate store")

        except Exception as cert_error:
            # Certificate not in cert store, try secrets (backward compatibility)
            logging.info(f"Certificate not in cert store, checking secrets: {str(cert_error)}")
            cert_secret_name = f"{cert_name}-cert"
            try:
                cert_secret = secret_client.get_secret(cert_secret_name)
                cert_pem = cert_secret.value

                # Parse certificate to get serial number and expiry
                cert_obj = x509.load_pem_x509_certificate(cert_pem.encode('utf-8'), default_backend())
                serial_number = str(cert_obj.serial_number)
                subject = str(cert_obj.subject)
                expires_on = cert_obj.not_valid_after.isoformat()
                logging.info(f"Certificate {cert_name} found in secrets")

            except Exception as secret_error:
                return func.HttpResponse(
                    json.dumps({
                        "error": f"Certificate '{cert_name}' not found in certificate store or secrets",
                        "details": {
                            "cert_store_error": str(cert_error),
                            "secrets_error": str(secret_error)
                        }
                    }),
                    status_code=404,
                    mimetype="application/json"
                )

        # Check if already revoked
        revocation_secret_name = f"{cert_name}-revoked"
        try:
            existing_revocation = secret_client.get_secret(revocation_secret_name)
            revocation_data = json.loads(existing_revocation.value)
            return func.HttpResponse(
                json.dumps({
                    "error": "Certificate already revoked",
                    "revocation_info": revocation_data
                }),
                status_code=409,
                mimetype="application/json"
            )
        except Exception:
            pass  # Not revoked yet, proceed

        # Set revocation date
        if revocation_date:
            try:
                revoked_at = datetime.fromisoformat(revocation_date.replace('Z', '+00:00'))
            except Exception as e:
                return func.HttpResponse(
                    json.dumps({"error": f"Invalid revocation_date format: {str(e)}"}),
                    status_code=400,
                    mimetype="application/json"
                )
        else:
            revoked_at = datetime.utcnow()

        # Create revocation record
        revocation_info = {
            "certificate_name": cert_name,
            "serial_number": serial_number,
            "subject": subject,
            "reason": reason,
            "revoked_at": revoked_at.isoformat(),
            "expires_on": expires_on,
            "revoked_by": "Function App"
        }

        # Store revocation information as a secret
        secret_client.set_secret(
            revocation_secret_name,
            json.dumps(revocation_info),
            content_type="application/json"
        )

        logging.info(f"Certificate {cert_name} revoked successfully. Reason: {reason}")

        return func.HttpResponse(
            json.dumps({
                "message": "Certificate revoked successfully",
                "revocation_info": revocation_info,
                "revocation_record": f"Key Vault secret: {revocation_secret_name}"
            }),
            status_code=200,
            mimetype="application/json"
        )

    except ValueError as e:
        logging.error(f"Invalid request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Invalid request: {str(e)}"}),
            status_code=400,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Error revoking certificate: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to revoke certificate: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="renew-certificate", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def renew_certificate(req: func.HttpRequest) -> func.HttpResponse:
    """
    Renew an existing certificate with a new validity period

    POST Body:
    {
        "certificate_name": "device-001",
        "validity_days": 365,
        "csr": "-----BEGIN CERTIFICATE REQUEST-----..." (optional),
        "intermediate_ca_name": "device-intermediate-ca" (optional),
        "auto_revoke": true|false (optional, default: false),
        "revocation_reason": "superseded" (optional, required if auto_revoke=true)
    }

    If CSR is provided, it will be used to issue the new certificate.
    If CSR is not provided, the existing certificate's subject will be extracted and reused.
    """
    logging.info('Renewing certificate')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        req_body = req.get_json()
        cert_name = req_body.get('certificate_name')
        validity_days = req_body.get('validity_days', 365)
        csr_data = req_body.get('csr')
        intermediate_ca_name = req_body.get('intermediate_ca_name', 'device-intermediate-ca')
        auto_revoke = req_body.get('auto_revoke', False)
        revocation_reason = req_body.get('revocation_reason', 'superseded')

        if not cert_name:
            return func.HttpResponse(
                json.dumps({"error": "certificate_name is required"}),
                status_code=400,
                mimetype="application/json"
            )

        # Find existing certificate (try certificate store first, then secrets)
        existing_cert_obj = None
        old_subject = None
        old_serial = None
        old_expiry = None

        try:
            certificate = cert_client.get_certificate(cert_name)
            cert_der = certificate.cer
            existing_cert_obj = x509.load_der_x509_certificate(cert_der, default_backend())
            old_subject = existing_cert_obj.subject
            old_serial = str(existing_cert_obj.serial_number)
            old_expiry = existing_cert_obj.not_valid_after.isoformat()
            logging.info(f"Found existing certificate {cert_name} in certificate store")

        except Exception as cert_error:
            # Try secrets
            cert_secret_name = f"{cert_name}-cert"
            try:
                cert_secret = secret_client.get_secret(cert_secret_name)
                cert_pem = cert_secret.value
                existing_cert_obj = x509.load_pem_x509_certificate(cert_pem.encode('utf-8'), default_backend())
                old_subject = existing_cert_obj.subject
                old_serial = str(existing_cert_obj.serial_number)
                old_expiry = existing_cert_obj.not_valid_after.isoformat()
                logging.info(f"Found existing certificate {cert_name} in secrets")

            except Exception as secret_error:
                return func.HttpResponse(
                    json.dumps({
                        "error": f"Certificate '{cert_name}' not found",
                        "details": {
                            "cert_store_error": str(cert_error),
                            "secrets_error": str(secret_error)
                        }
                    }),
                    status_code=404,
                    mimetype="application/json"
                )

        # If CSR provided, parse it; otherwise reuse existing certificate's subject and public key
        if csr_data:
            try:
                # Handle both PEM and base64 encoded CSR
                if "BEGIN CERTIFICATE REQUEST" in csr_data:
                    csr_pem = csr_data.encode('utf-8')
                else:
                    csr_pem = base64.b64decode(csr_data)

                csr = x509.load_pem_x509_csr(csr_pem, default_backend())

                if not csr.is_signature_valid:
                    return func.HttpResponse(
                        json.dumps({"error": "CSR signature is invalid"}),
                        status_code=400,
                        mimetype="application/json"
                    )

                subject = csr.subject
                public_key = csr.public_key()
                logging.info(f"Using CSR for renewal. Subject: {subject}")

            except Exception as e:
                return func.HttpResponse(
                    json.dumps({"error": f"Invalid CSR format: {str(e)}"}),
                    status_code=400,
                    mimetype="application/json"
                )
        else:
            # Reuse existing certificate's subject and public key
            subject = old_subject
            public_key = existing_cert_obj.public_key()
            logging.info(f"Reusing existing certificate's subject and public key for renewal")

        # Get intermediate CA certificate
        try:
            intermediate_cert = cert_client.get_certificate(intermediate_ca_name)
            intermediate_cert_obj = x509.load_der_x509_certificate(
                intermediate_cert.cer,
                default_backend()
            )
        except Exception as e:
            return func.HttpResponse(
                json.dumps({"error": f"Intermediate CA '{intermediate_ca_name}' not found: {str(e)}"}),
                status_code=404,
                mimetype="application/json"
            )

        # Create new certificate
        try:
            cert_builder = x509.CertificateBuilder()
            cert_builder = cert_builder.subject_name(subject)
            cert_builder = cert_builder.issuer_name(intermediate_cert_obj.subject)
            cert_builder = cert_builder.public_key(public_key)
            cert_builder = cert_builder.serial_number(x509.random_serial_number())
            cert_builder = cert_builder.not_valid_before(datetime.utcnow())
            cert_builder = cert_builder.not_valid_after(
                datetime.utcnow() + timedelta(days=validity_days)
            )

            # Add extensions
            cert_builder = cert_builder.add_extension(
                x509.BasicConstraints(ca=False, path_length=None),
                critical=True,
            )
            cert_builder = cert_builder.add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    key_encipherment=True,
                    content_commitment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    key_cert_sign=False,
                    crl_sign=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )

            # Copy Subject Alternative Names from CSR if available, otherwise from existing cert
            try:
                if csr_data:
                    san_ext = csr.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
                else:
                    san_ext = existing_cert_obj.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
                cert_builder = cert_builder.add_extension(san_ext.value, critical=False)
            except x509.ExtensionNotFound:
                pass

            # Add CRL Distribution Point extension
            try:
                function_app_url = os.environ.get("WEBSITE_HOSTNAME", "func-devicepki-dev-001.azurewebsites.net")
                crl_url = f"https://{function_app_url}/api/crl/intermediate"

                crl_dp = x509.CRLDistributionPoints([
                    x509.DistributionPoint(
                        full_name=[x509.UniformResourceIdentifier(crl_url)],
                        relative_name=None,
                        crl_issuer=None,
                        reasons=None
                    )
                ])
                cert_builder = cert_builder.add_extension(crl_dp, critical=False)
                logging.info(f"Added CRL Distribution Point: {crl_url}")
            except Exception as e:
                logging.warning(f"Failed to add CRL Distribution Point: {str(e)}")

            # Sign the renewed certificate using Key Vault HSM
            logging.info("Signing renewed certificate with Key Vault HSM...")

            # Step 1: Build certificate with temporary key to get TBS structure
            temp_signing_key = rsa.generate_private_key(
                public_exponent=65537,
                key_size=2048,
                backend=default_backend()
            )

            temp_cert = cert_builder.sign(
                private_key=temp_signing_key,
                algorithm=hashes.SHA256(),
                backend=default_backend()
            )

            # Step 2: Extract TBS certificate DER bytes
            tbs_cert_der = temp_cert.tbs_certificate_bytes
            logging.info(f"TBS certificate size: {len(tbs_cert_der)} bytes")

            # Step 3: Sign TBS using Key Vault's HSM-protected intermediate CA private key
            logging.info(f"Signing TBS with Key Vault HSM key: {intermediate_ca_name}")
            signature_bytes = sign_certificate_with_keyvault(
                tbs_cert_bytes=tbs_cert_der,
                ca_key_name=intermediate_ca_name,
                signature_algorithm_oid=None  # sha256WithRSAEncryption
            )

            # Step 4: Reconstruct complete certificate with real signature
            logging.info("Reconstructing certificate with Key Vault signature...")
            final_cert_der = build_signed_certificate_der(
                tbs_cert_der=tbs_cert_der,
                signature_algorithm_oid=None,
                signature_bytes=signature_bytes
            )

            # Step 5: Load and verify the reconstructed certificate
            signed_cert = x509.load_der_x509_certificate(final_cert_der, default_backend())
            logging.info(f"✅ Renewed certificate signed successfully with Key Vault HSM")
            logging.info(f"   Issuer: {signed_cert.issuer.rfc4514_string()}")
            logging.info(f"   Subject: {signed_cert.subject.rfc4514_string()}")
            logging.info(f"   Serial: {format(signed_cert.serial_number, 'X')}")

            # Convert to PEM format
            cert_pem = signed_cert.public_bytes(encoding=serialization.Encoding.PEM).decode('utf-8')

            # Store new certificate as secret
            secret_name = f"{cert_name}-cert"
            secret_client.set_secret(secret_name, cert_pem, content_type="application/x-pem-file")
            logging.info(f"Renewed certificate {cert_name} stored as secret")

            # Optionally revoke the old certificate
            revocation_info = None
            if auto_revoke:
                try:
                    # Check if already revoked
                    revocation_secret_name = f"{cert_name}-revoked"
                    try:
                        existing_revocation = secret_client.get_secret(revocation_secret_name)
                        logging.info(f"Certificate {cert_name} was already revoked, skipping auto-revoke")
                    except Exception:
                        # Not revoked yet, proceed with revocation
                        revoked_at = datetime.utcnow()
                        revocation_info = {
                            "certificate_name": cert_name,
                            "serial_number": old_serial,
                            "subject": str(old_subject),
                            "reason": revocation_reason,
                            "revoked_at": revoked_at.isoformat(),
                            "expires_on": old_expiry,
                            "revoked_by": "Function App (auto-revoke on renewal)"
                        }

                        secret_client.set_secret(
                            revocation_secret_name,
                            json.dumps(revocation_info),
                            content_type="application/json"
                        )
                        logging.info(f"Old certificate {cert_name} auto-revoked with reason: {revocation_reason}")
                except Exception as revoke_error:
                    logging.warning(f"Failed to auto-revoke old certificate: {str(revoke_error)}")

            response_data = {
                "message": "Certificate renewed successfully",
                "certificate_name": cert_name,
                "old_certificate": {
                    "serial_number": old_serial,
                    "subject": str(old_subject),
                    "expires_on": old_expiry
                },
                "new_certificate": {
                    "serial_number": str(signed_cert.serial_number),
                    "subject": str(signed_cert.subject),
                    "issuer": str(signed_cert.issuer),
                    "not_before": signed_cert.not_valid_before.isoformat(),
                    "not_after": signed_cert.not_valid_after.isoformat(),
                    "validity_days": validity_days
                },
                "certificate_pem": cert_pem,
                "storage_location": f"Key Vault secret: {secret_name}",
                "signing_method": "✅ Azure Key Vault HSM (CryptographyClient with RS256)",
                "note": "Renewed certificate signed using HSM-protected Intermediate CA key"
            }

            if auto_revoke and revocation_info:
                response_data["old_certificate_revoked"] = True
                response_data["revocation_info"] = revocation_info

            return func.HttpResponse(
                json.dumps(response_data),
                status_code=200,
                mimetype="application/json"
            )

        except Exception as e:
            logging.error(f"Error creating renewed certificate: {str(e)}")
            return func.HttpResponse(
                json.dumps({"error": f"Certificate renewal failed: {str(e)}"}),
                status_code=500,
                mimetype="application/json"
            )

    except ValueError as e:
        logging.error(f"Invalid request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Invalid request: {str(e)}"}),
            status_code=400,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Error renewing certificate: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to renew certificate: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="list-certificates", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def list_certificates(req: func.HttpRequest) -> func.HttpResponse:
    """
    List certificates in Key Vault with pagination support

    Query Parameters:
    - type: all|ca|device (default: all)
      - all: List both CA certificates and device certificates
      - ca: List only CA certificates (root-ca, intermediate-ca)
      - device: List only device certificates
    - page: Page number (1-based, default: 1)
    - page_size: Items per page (default: 100, max: 500)
    - details: full|summary (default: summary)
      - summary: Returns lightweight data (name, expiry, enabled)
      - full: Returns complete certificate details (slower, parses each cert)

    Note: CA certificates are stored in the certificate store (with private keys).
    Device certificates are stored as secrets (private keys stay with devices).

    Pagination is essential for handling 10K+ certificates efficiently.
    """
    logging.info('Listing certificates with pagination')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        # Parse query parameters
        list_type = req.params.get('type', 'all')
        page = max(1, int(req.params.get('page', '1')))
        page_size = min(max(1, int(req.params.get('page_size', '100'))), 500)  # Max 500 per page
        detail_level = req.params.get('details', 'summary')

        logging.info(f"List type: {list_type}, page: {page}, page_size: {page_size}, detail: {detail_level}")

        ca_certificates = []
        device_certificates = []

        # Get CA certificates from certificate store
        if list_type in ['all', 'ca']:
            try:
                cert_properties = cert_client.list_properties_of_certificates()

                for cert_prop in cert_properties:
                    cert_info = {
                        "name": cert_prop.name,
                        "thumbprint": cert_prop.x509_thumbprint.hex() if cert_prop.x509_thumbprint else None,
                        "created_on": cert_prop.created_on.isoformat() if cert_prop.created_on else None,
                        "expires_on": cert_prop.expires_on.isoformat() if cert_prop.expires_on else None,
                        "enabled": cert_prop.enabled,
                        "storage_type": "certificate"
                    }
                    ca_certificates.append(cert_info)

            except Exception as e:
                logging.error(f"Error listing certificates: {str(e)}")

        # Get device certificates from secrets (secrets ending with -cert)
        if list_type in ['all', 'device']:
            try:
                secret_properties = secret_client.list_properties_of_secrets()

                for secret_prop in secret_properties:
                    # Filter for device certificate secrets (end with -cert, exclude revocation records)
                    if secret_prop.name.endswith('-cert') and not secret_prop.name.endswith('-revoked'):
                        if detail_level == 'summary':
                            # Lightweight: Only secret properties (no certificate parsing)
                            cert_info = {
                                "name": secret_prop.name.replace('-cert', ''),
                                "created_on": secret_prop.created_on.isoformat() if secret_prop.created_on else None,
                                "updated_on": secret_prop.updated_on.isoformat() if secret_prop.updated_on else None,
                                "enabled": secret_prop.enabled,
                                "storage_type": "secret"
                            }
                            device_certificates.append(cert_info)
                        else:
                            # Full details: Parse certificate (slower)
                            try:
                                secret = secret_client.get_secret(secret_prop.name)
                                cert_pem = secret.value

                                # Parse certificate to get details
                                cert_obj = x509.load_pem_x509_certificate(cert_pem.encode('utf-8'), default_backend())

                                cert_info = {
                                    "name": secret_prop.name.replace('-cert', ''),
                                    "thumbprint": cert_obj.fingerprint(hashes.SHA256()).hex(),
                                    "serial_number": str(cert_obj.serial_number),
                                    "subject": str(cert_obj.subject),
                                    "issuer": str(cert_obj.issuer),
                                    "created_on": secret_prop.created_on.isoformat() if secret_prop.created_on else None,
                                    "expires_on": cert_obj.not_valid_after.isoformat(),
                                    "not_before": cert_obj.not_valid_before.isoformat(),
                                    "enabled": secret_prop.enabled,
                                    "storage_type": "secret"
                                }
                                device_certificates.append(cert_info)
                            except Exception as parse_error:
                                logging.warning(f"Failed to parse certificate secret {secret_prop.name}: {str(parse_error)}")

            except Exception as e:
                logging.error(f"Error listing device certificate secrets: {str(e)}")

        # Calculate pagination
        total_ca = len(ca_certificates)
        total_device = len(device_certificates)
        total_items = total_ca + total_device
        total_pages = (total_items + page_size - 1) // page_size  # Ceiling division

        # Apply pagination
        start_idx = (page - 1) * page_size
        end_idx = start_idx + page_size

        # Paginate combined list (CA certs first, then device certs)
        all_certs = ca_certificates + device_certificates
        paginated_certs = all_certs[start_idx:end_idx]

        # Separate paginated results back into CA and device
        paginated_ca = [c for c in paginated_certs if c.get('storage_type') == 'certificate']
        paginated_device = [c for c in paginated_certs if c.get('storage_type') == 'secret']

        # Build response
        response_data = {
            "key_vault": KEY_VAULT_NAME,
            "pagination": {
                "page": page,
                "page_size": page_size,
                "total_items": total_items,
                "total_pages": total_pages,
                "has_next": page < total_pages,
                "has_previous": page > 1
            },
            "detail_level": detail_level
        }

        if list_type in ['all', 'ca']:
            response_data["ca_certificates"] = {
                "total_count": total_ca,
                "page_count": len(paginated_ca),
                "items": paginated_ca,
                "storage_type": "certificate (with private keys in Key Vault)"
            }

        if list_type in ['all', 'device']:
            response_data["device_certificates"] = {
                "total_count": total_device,
                "page_count": len(paginated_device),
                "items": paginated_device,
                "storage_type": "secret (private keys stay with devices)"
            }

        return func.HttpResponse(
            json.dumps(response_data, indent=2),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error listing certificates: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to list certificates: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="check-revocation", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def check_revocation(req: func.HttpRequest) -> func.HttpResponse:
    """
    Check if a certificate has been revoked

    Query Parameters:
    - certificate_name: Name of the certificate (e.g., device-001)
    - serial_number: Serial number of the certificate (optional)
    """
    logging.info('Checking certificate revocation status')

    try:
        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        cert_name = req.params.get('certificate_name')
        serial_number = req.params.get('serial_number')

        if not cert_name:
            return func.HttpResponse(
                json.dumps({"error": "certificate_name query parameter is required"}),
                status_code=400,
                mimetype="application/json"
            )

        # Check for revocation record
        revocation_secret_name = f"{cert_name}-revoked"
        try:
            revocation_secret = secret_client.get_secret(revocation_secret_name)
            revocation_data = json.loads(revocation_secret.value)

            return func.HttpResponse(
                json.dumps({
                    "revoked": True,
                    "certificate_name": cert_name,
                    "revocation_info": revocation_data
                }),
                status_code=200,
                mimetype="application/json"
            )
        except Exception:
            # No revocation record found - certificate is valid
            return func.HttpResponse(
                json.dumps({
                    "revoked": False,
                    "certificate_name": cert_name,
                    "message": "Certificate is not revoked"
                }),
                status_code=200,
                mimetype="application/json"
            )

    except Exception as e:
        logging.error(f"Error checking revocation status: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to check revocation status: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="crl/{ca_name}", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def get_crl(req: func.HttpRequest) -> func.HttpResponse:
    """
    Generate and serve Certificate Revocation List (CRL) for a CA

    Path Parameters:
    - ca_name: Name of the CA (e.g., 'intermediate', 'root')

    Returns:
    - DER-encoded CRL with appropriate cache headers

    CRL Distribution Point URL:
    - https://func-devicepki-dev-001.azurewebsites.net/api/crl/intermediate
    """
    logging.info('Generating Certificate Revocation List (CRL)')

    try:
        # Get CA name from path
        ca_name = req.route_params.get('ca_name')

        # Map short names to full certificate names
        ca_name_map = {
            'root': 'device-root-ca',
            'intermediate': 'device-intermediate-ca',
            'device-root-ca': 'device-root-ca',
            'device-intermediate-ca': 'device-intermediate-ca'
        }

        full_ca_name = ca_name_map.get(ca_name, ca_name)
        logging.info(f"Generating CRL for CA: {full_ca_name}")

        # Initialize Key Vault clients
        cert_client, key_client, secret_client = get_keyvault_clients()

        # Get CA certificate
        try:
            ca_cert_kv = cert_client.get_certificate(full_ca_name)
            ca_cert = x509.load_der_x509_certificate(ca_cert_kv.cer, default_backend())
        except Exception as e:
            return func.HttpResponse(
                json.dumps({"error": f"CA certificate '{full_ca_name}' not found: {str(e)}"}),
                status_code=404,
                mimetype="application/json"
            )

        # Query all revocation records from Key Vault
        revoked_certificates = []
        try:
            all_secrets = secret_client.list_properties_of_secrets()

            for secret_props in all_secrets:
                # Filter for revocation records (secrets ending with -revoked)
                if secret_props.name.endswith('-revoked'):
                    try:
                        secret = secret_client.get_secret(secret_props.name)
                        revocation_data = json.loads(secret.value)

                        # Parse serial number and revocation time
                        serial_number = int(revocation_data.get('serial_number'))
                        revoked_at_str = revocation_data.get('revoked_at')
                        revoked_at = datetime.fromisoformat(revoked_at_str.replace('Z', '+00:00'))

                        # Map reason string to CRL reason code
                        reason_map = {
                            'unspecified': x509.ReasonFlags.unspecified,
                            'keyCompromise': x509.ReasonFlags.key_compromise,
                            'caCompromise': x509.ReasonFlags.ca_compromise,
                            'affiliationChanged': x509.ReasonFlags.affiliation_changed,
                            'superseded': x509.ReasonFlags.superseded,
                            'cessationOfOperation': x509.ReasonFlags.cessation_of_operation,
                            'certificateHold': x509.ReasonFlags.certificate_hold,
                            'removeFromCRL': x509.ReasonFlags.remove_from_crl,
                            'privilegeWithdrawn': x509.ReasonFlags.privilege_withdrawn,
                            'aaCompromise': x509.ReasonFlags.aa_compromise
                        }
                        reason_str = revocation_data.get('reason', 'unspecified')
                        reason = reason_map.get(reason_str, x509.ReasonFlags.unspecified)

                        # Create revoked certificate entry
                        revoked_cert_builder = x509.RevokedCertificateBuilder()
                        revoked_cert_builder = revoked_cert_builder.serial_number(serial_number)
                        revoked_cert_builder = revoked_cert_builder.revocation_date(revoked_at)
                        revoked_cert_builder = revoked_cert_builder.add_extension(
                            x509.CRLReason(reason),
                            critical=False
                        )

                        revoked_certificates.append(revoked_cert_builder.build())
                        logging.info(f"Added revoked certificate: serial={serial_number}, reason={reason_str}")

                    except Exception as e:
                        logging.warning(f"Failed to parse revocation record {secret_props.name}: {str(e)}")
                        continue

        except Exception as e:
            logging.error(f"Failed to query revocation records: {str(e)}")
            # Continue with empty list - CRL can be empty

        logging.info(f"Found {len(revoked_certificates)} revoked certificates for CRL")

        # Build CRL
        crl_builder = x509.CertificateRevocationListBuilder()
        crl_builder = crl_builder.issuer_name(ca_cert.subject)
        crl_builder = crl_builder.last_update(datetime.utcnow())
        crl_builder = crl_builder.next_update(datetime.utcnow() + timedelta(hours=24))  # CRL valid for 24 hours

        # Add all revoked certificates
        for revoked_cert in revoked_certificates:
            crl_builder = crl_builder.add_revoked_certificate(revoked_cert)

        # Add CRL Number extension (monotonically increasing)
        # For simplicity, use current timestamp as CRL number
        crl_number = int(datetime.utcnow().timestamp())
        crl_builder = crl_builder.add_extension(
            x509.CRLNumber(crl_number),
            critical=False
        )

        # Sign CRL using Key Vault HSM
        try:
            # Build CRL with temporary key to extract TBS (To-Be-Signed) bytes
            temp_signing_key = rsa.generate_private_key(
                public_exponent=65537,
                key_size=2048,
                backend=default_backend()
            )

            # Sign with temporary key to build structure
            temp_crl = crl_builder.sign(
                private_key=temp_signing_key,
                algorithm=hashes.SHA256(),
                backend=default_backend()
            )

            # Extract TBS CertList bytes using asn1crypto
            temp_crl_der = temp_crl.public_bytes(encoding=serialization.Encoding.DER)

            from asn1crypto import crl as asn1_crl

            # Parse CRL structure to extract TBS CertList
            crl_info = asn1_crl.CertificateList.load(temp_crl_der)
            tbs_cert_list_der = crl_info['tbs_cert_list'].dump()

            logging.info(f"Extracted TBS CertList: {len(tbs_cert_list_der)} bytes")

            # Sign TBS CertList with Key Vault HSM
            signature_bytes = sign_certificate_with_keyvault(
                tbs_cert_bytes=tbs_cert_list_der,
                ca_key_name=full_ca_name,
                signature_algorithm_oid=None  # Will use sha256WithRSAEncryption
            )

            # Log signature details
            logging.info(f"CRL signed with Key Vault key: {full_ca_name}, Signature length: {len(signature_bytes)} bytes")

            # Reconstruct CRL with HSM signature
            # Build final CRL DER: SEQUENCE { tbsCertList, signatureAlgorithm, signature }
            # SignatureAlgorithm: SEQUENCE { algorithm OID, parameters NULL }
            sha256_with_rsa_oid = b'\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x0b'  # 1.2.840.113549.1.1.11
            null_params = b'\x05\x00'
            sig_alg_seq = b'\x30' + _encode_length(len(sha256_with_rsa_oid) + len(null_params)) + sha256_with_rsa_oid + null_params

            # Signature: BIT STRING with 0 unused bits
            signature_bitstring = b'\x03' + _encode_length(len(signature_bytes) + 1) + b'\x00' + signature_bytes

            # Combine into final SEQUENCE
            crl_content = tbs_cert_list_der + sig_alg_seq + signature_bitstring
            final_crl_der = b'\x30' + _encode_length(len(crl_content)) + crl_content

            # Load the reconstructed CRL to validate
            crl = x509.load_der_x509_crl(final_crl_der, default_backend())

            logging.info(f"✅ CRL signed using Azure Key Vault HSM (CryptographyClient with RS256)")

        except Exception as e:
            logging.error(f"Failed to sign CRL with Key Vault: {str(e)}")
            import traceback
            logging.error(traceback.format_exc())
            return func.HttpResponse(
                json.dumps({"error": f"Failed to sign CRL: {str(e)}"}),
                status_code=500,
                mimetype="application/json"
            )

        # Convert CRL to DER format
        crl_der = crl.public_bytes(encoding=serialization.Encoding.DER)

        # Also provide PEM format for debugging
        crl_pem = crl.public_bytes(encoding=serialization.Encoding.PEM).decode('utf-8')

        # Calculate next update time (24 hours for APIM caching)
        current_time = datetime.utcnow()
        next_update = current_time + timedelta(hours=24)

        # Return DER-encoded CRL with cache headers optimized for APIM
        return func.HttpResponse(
            body=crl_der,
            status_code=200,
            mimetype="application/pkix-crl",
            headers={
                "Content-Type": "application/pkix-crl",
                "Content-Disposition": f"inline; filename={full_ca_name}.crl",
                "Cache-Control": "public, max-age=86400",  # Cache for 24 hours (APIM)
                "Expires": next_update.strftime('%a, %d %b %Y %H:%M:%S GMT'),
                "Last-Modified": current_time.strftime('%a, %d %b %Y %H:%M:%S GMT'),
                "X-CRL-Number": str(crl_number),
                "X-CRL-Issuer": str(ca_cert.subject),
                "X-CRL-Last-Update": current_time.isoformat(),
                "X-CRL-Next-Update": next_update.isoformat(),
                "X-Revoked-Count": str(len(revoked_certificates))
            }
        )

    except Exception as e:
        logging.error(f"Error generating CRL: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Failed to generate CRL: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint"""
    return func.HttpResponse(
        json.dumps({
            "status": "healthy",
            "service": "Certificate Authority Management",
            "timestamp": datetime.utcnow().isoformat()
        }),
        status_code=200,
        mimetype="application/json"
    )
