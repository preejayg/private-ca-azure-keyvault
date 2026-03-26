#!/bin/bash

# Source local configuration if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Validate required variables for VM-based scripts
check_vm_config() {
    if [[ -z "$VM_IP" ]] || [[ "$VM_IP" == "<YOUR_VM_IP>" ]]; then
        echo "❌ ERROR: VM_IP not configured"
        echo ""
        echo "Please set up your configuration:"
        echo "  1. Copy config template: cp config.sh.example config.sh"
        echo "  2. Edit config.sh and set your VM IP"
        echo "  3. Or export VM_IP environment variable:"
        echo "     export VM_IP=\"10.x.x.x\""
        echo ""
        exit 1
    fi
}

# Validate required variables for local VPN scripts
check_local_config() {
    if [[ -z "$FUNCTION_APP_PRIVATE_IP" ]] || [[ "$FUNCTION_APP_PRIVATE_IP" == "<FUNCTION_APP_PRIVATE_IP>" ]]; then
        echo "❌ ERROR: FUNCTION_APP_PRIVATE_IP not configured"
        echo ""
        echo "Please set up your configuration:"
        echo "  1. Copy config template: cp config.sh.example config.sh"
        echo "  2. Edit config.sh and set your Function App private IP"
        echo "  3. Or export FUNCTION_APP_PRIVATE_IP environment variable:"
        echo "     export FUNCTION_APP_PRIVATE_IP=\"10.x.x.x\""
        echo ""
        echo "To find your Function App private IP:"
        echo "  az network private-endpoint show \\"
        echo "    --name pe-dev-aue-functionapp-dcert-poc \\"
        echo "    --resource-group rg-dev-aue-dcert-poc \\"
        echo "    --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv"
        echo ""
        exit 1
    fi
}

# Set defaults if not provided
export FUNCTION_APP="${FUNCTION_APP:-func-devicepki-dev-001}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-dev-aue-dcert-poc}"
export SSH_KEY="${SSH_KEY:-$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem}"
