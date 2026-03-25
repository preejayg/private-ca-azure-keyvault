"""
Site customization for local testing with mock Key Vault.
This file is automatically loaded by Python at startup (before any other imports).
It intercepts Azure SDK imports when USE_MOCK_KEYVAULT=true.

IMPORTANT: This file is ONLY used for local testing. It will NOT be included
in Azure deployment (excluded via .funcignore).
"""
import os
import sys

# Check if we should use mock Key Vault
USE_MOCK_KEYVAULT = os.getenv("USE_MOCK_KEYVAULT", "false").lower() == "true"

if USE_MOCK_KEYVAULT:
    print("[SITECUSTOMIZE] LOCAL TESTING MODE: Intercepting Azure SDK imports with mocks")
    
    # Import mock implementations
    try:
        import mock_keyvault
        
        # Create mock module objects that mimic Azure SDK structure
        class MockAzureIdentity:
            DefaultAzureCredential = mock_keyvault.MockDefaultAzureCredential
        
        class MockAzureKeyvaultCertificates:
            CertificateClient = mock_keyvault.MockCertificateClient
            CertificatePolicy = mock_keyvault.MockCertificatePolicy
            CertificateContentType = mock_keyvault.MockCertificateContentType
        
        class MockAzureKeyvaultKeys:
            KeyClient = mock_keyvault.MockKeyClient
            SignatureAlgorithm = mock_keyvault.MockSignatureAlgorithm
        
        class MockAzureKeyvaultSecrets:
            SecretClient = mock_keyvault.MockSecretClient
        
        # Inject mocks into sys.modules BEFORE any application code imports them
        sys.modules['azure.identity'] = MockAzureIdentity
        sys.modules['azure.keyvault.certificates'] = MockAzureKeyvaultCertificates
        sys.modules['azure.keyvault.keys'] = MockAzureKeyvaultKeys
        sys.modules['azure.keyvault.secrets'] = MockAzureKeyvaultSecrets
        
        print("[SITECUSTOMIZE] ✅ Mock Key Vault interception initialized")
        print("[SITECUSTOMIZE] All azure.keyvault imports will use mock implementations")
        
    except ImportError as e:
        print(f"[SITECUSTOMIZE] ⚠️  Warning: Could not import mock_keyvault: {e}")
        print("[SITECUSTOMIZE] Falling back to real Azure SDK")
else:
    print("[SITECUSTOMIZE] Production mode: Using real Azure Key Vault SDK")
