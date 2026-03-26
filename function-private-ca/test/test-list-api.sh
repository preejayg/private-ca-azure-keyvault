#!/bin/bash

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
check_vm_config

MASTER_KEY=$(az functionapp keys list --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query "masterKey" -o tsv)
ssh -i "$SSH_KEY" -o LogLevel=ERROR azureuser@"$VM_IP" "curl -s 'https://${FUNCTION_APP}.azurewebsites.net/api/list-certificates?type=all' -H 'x-functions-key: $MASTER_KEY'"
