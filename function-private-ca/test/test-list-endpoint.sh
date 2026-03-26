#!/bin/bash
set -e

# Get master key
echo "Getting master key..."
MASTER_KEY=$(az functionapp keys list --name func-devicepki-dev-001 --resource-group rg-dev-aue-dcert-poc --query "masterKey" -o tsv)
echo "Master key retrieved"
echo ""

# Call API via SSH 
echo "Calling list-certificates API..."
ssh -i ~/.ssh/vm-dev-aue-dcert-poc-keypair.pem -o LogLevel=ERROR azureuser@<YOUR_VM_IP> \
  "curl -s 'https://func-devicepki-dev-001.azurewebsites.net/api/list-certificates?type=all' \
    -H 'x-functions-key: $MASTER_KEY'" > /tmp/api-output.txt 2>&1

echo "Response saved to /tmp/api-output.txt"
echo ""
echo "========================================="
echo "API Response:"
echo "========================================="
cat /tmp/api-output.txt
