#!/bin/bash
set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
check_vm_config

# Get master key
echo "Getting master key..."
MASTER_KEY=$(az functionapp keys list --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query "masterKey" -o tsv)
echo "Master key retrieved"
echo ""

# Call API via SSH 
echo "Calling list-certificates API..."
ssh -i "$SSH_KEY" -o LogLevel=ERROR azureuser@"$VM_IP" \
  "curl -s 'https://${FUNCTION_APP}.azurewebsites.net/api/list-certificates?type=all' \
    -H 'x-functions-key: $MASTER_KEY'" > /tmp/api-output.txt 2>&1

echo "Response saved to /tmp/api-output.txt"
echo ""
echo "========================================="
echo "API Response:"
echo "========================================="
cat /tmp/api-output.txt
