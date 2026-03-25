"""
Mock Key Vault clients for local development/testing
Supports certificate, key, and secret operations for CSR-based certificate issuance
This module provides drop-in replacements for Azure SDK classes for local testing.
"""
from datetime import datetime, timedelta
from typing import Optional
import json
import base64
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend


# Mock Azure Identity
class MockDefaultAzureCredential:
    """Mock Azure credential for local testing"""
    def __init__(self):
        print("[MOCK] Using mock Azure credentials")


# Mock Certificate Policy and Content Type
class MockCertificateContentType:
    """Mock for azure.keyvault.certificates.CertificateContentType"""
    pem = "application/x-pem-file"
    pkcs12 = "application/x-pkcs12"


class MockCertificatePolicy:
    """Mock for azure.keyvault.certificates.CertificatePolicy"""
    def __init__(self, issuer_name=None, subject=None, san_dns_names=None, 
                 exportable=False, key_type="RSA", key_size=2048, reuse_key=False,
                 content_type=None, validity_in_months=12, key_usage=None,
                 certificate_transparency=False, **kwargs):
        self.issuer_name = issuer_name
        self.subject = subject
        self.san_dns_names = san_dns_names or []
        self.exportable = exportable
        self.key_type = key_type
        self.key_size = key_size
        self.reuse_key = reuse_key
        self.content_type = content_type
        self.validity_in_months = validity_in_months
        self.key_usage = key_usage or []
        self.certificate_transparency = certificate_transparency
        print(f"[MOCK] Created certificate policy: subject={subject}, validity={validity_in_months}mo")


# Mock Signature Algorithm
class MockSignatureAlgorithm:
    """Mock for azure.keyvault.keys.SignatureAlgorithm"""
    rs256 = "RS256"
    rs384 = "RS384"
    rs512 = "RS512"
    es256 = "ES256"
    es384 = "ES384"
    es512 = "ES512"
    ps256 = "PS256"
    ps384 = "PS384"
    ps512 = "PS512"


class MockCertificateProperties:
    def __init__(self, name, thumbprint):
        self.name = name
        self.x509_thumbprint = bytes.fromhex(thumbprint)
        self.expires_on = datetime.utcnow() + timedelta(days=3650)
        self.created_on = datetime.utcnow()


class MockCertificate:
    def __init__(self, name, thumbprint="ABCD1234567890", cert_bytes=None):
        self.id = f"https://mock-vault.vault.azure.net/certificates/{name}"
        self.name = name
        self.key_id = f"https://mock-vault.vault.azure.net/keys/{name}"
        self.properties = MockCertificateProperties(name, thumbprint)
        # Generate a realistic mock certificate if not provided
        if cert_bytes:
            self.cer = cert_bytes
        else:
            self.cer = self._generate_mock_certificate(name)
    
    def _generate_mock_certificate(self, name):
        """Generate a realistic self-signed certificate for testing"""
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )
        subject = issuer = x509.Name([
            x509.NameAttribute(x509.oid.NameOID.COMMON_NAME, name),
        ])
        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            issuer
        ).public_key(
            private_key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.utcnow()
        ).not_valid_after(
            datetime.utcnow() + timedelta(days=3650)
        ).add_extension(
            x509.BasicConstraints(ca=True, path_length=None),
            critical=True,
        ).sign(private_key, hashes.SHA256(), default_backend())
        
        return cert.public_bytes(serialization.Encoding.DER)


class MockCertificatePoller:
    def __init__(self, certificate):
        self._certificate = certificate
    
    def result(self):
        return self._certificate


class MockCertificateClient:
    def __init__(self, vault_url, credential):
        self.vault_url = vault_url
        self.certificates = {}
        print(f"[MOCK] Using mock Certificate Client for {vault_url}")
    
    def get_certificate(self, certificate_name):
        print(f"[MOCK] Getting certificate: {certificate_name}")
        if certificate_name not in self.certificates:
            raise Exception(f"Certificate {certificate_name} not found")
        return self.certificates[certificate_name]
    
    def begin_create_certificate(self, certificate_name, policy):
        print(f"[MOCK] Creating certificate: {certificate_name}")
        cert = MockCertificate(certificate_name)
        self.certificates[certificate_name] = cert
        return MockCertificatePoller(cert)


class MockKey:
    def __init__(self, name):
        self.id = f"https://mock-vault.vault.azure.net/keys/{name}"
        self.name = name
        # Generate a mock RSA key for signing
        self._private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )


class MockSignResult:
    def __init__(self, signature):
        self.signature = signature


class MockKeyClient:
    def __init__(self, vault_url, credential):
        self.vault_url = vault_url
        self.keys = {}
        print(f"[MOCK] Using mock Key Client for {vault_url}")
    
    def get_key(self, key_name):
        """Get a key (creates one if it doesn't exist)"""
        print(f"[MOCK] Getting key: {key_name}")
        if key_name not in self.keys:
            self.keys[key_name] = MockKey(key_name)
        return self.keys[key_name]
    
    def sign(self, algorithm, digest, name=None, **kwargs):
        """Mock sign operation using RSA - matches Azure SDK signature"""
        # Handle both positional and keyword arguments
        key_name = name if name else kwargs.get('name')
        print(f"[MOCK] Signing with key: {key_name}, algorithm: {algorithm}")
        key = self.get_key(key_name)
        # Sign the digest using the mock private key
        signature = key._private_key.sign(
            digest,
            padding.PKCS1v15(),
            hashes.SHA256()
        )
        return MockSignResult(signature)


class MockSecret:
    def __init__(self, name, value):
        self.id = f"https://mock-vault.vault.azure.net/secrets/{name}"
        self.name = name
        self.value = value
        self.properties = type('obj', (object,), {
            'created_on': datetime.utcnow(),
            'updated_on': datetime.utcnow()
        })


class MockSecretClient:
    def __init__(self, vault_url, credential):
        self.vault_url = vault_url
        self.secrets = {}
        print(f"[MOCK] Using mock Secret Client for {vault_url}")
    
    def set_secret(self, name, value):
        """Store a secret (like a signed certificate)"""
        print(f"[MOCK] Storing secret: {name}")
        secret = MockSecret(name, value)
        self.secrets[name] = secret
        return secret
    
    def get_secret(self, name):
        """Retrieve a secret"""
        print(f"[MOCK] Getting secret: {name}")
        if name not in self.secrets:
            raise Exception(f"Secret {name} not found")
        return self.secrets[name]
