#!/bin/bash
MASTER_KEY=$(az functionapp keys list --name func-devicepki-dev-001 --resource-group rg-dev-aue-dcert-poc --query "masterKey" -o tsv)
ssh -i ~/.ssh/vm-dev-aue-dcert-poc-keypair.pem -o LogLevel=ERROR azureuser@10.140.34.6 "curl -s 'https://func-devicepki-dev-001.azurewebsites.net/api/list-certificates?type=all' -H 'x-functions-key: $MASTER_KEY'"
