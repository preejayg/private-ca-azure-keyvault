# Test Scripts Configuration

## Quick Setup

1. **Copy the configuration template:**

   ```bash
   cp config.sh.example config.sh
   ```

2. **Edit config.sh and update with your values:**

   ```bash
   # Find your Function App private IP
   az network private-endpoint show \
     --name pe-dev-aue-functionapp-dcert-poc \
     --resource-group rg-dev-aue-dcert-poc \
     --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv

   # Edit the config file
   nano config.sh
   ```

3. **Run any test script:**
   ```bash
   ./list-certificates-local.sh
   ./check-revocation.sh device-001-cert
   ```

## Configuration Variables

The `config.sh` file (created from `config.sh.example`) sets these environment variables:

| Variable                  | Description                      | How to Find                                                                                                                                                          |
| ------------------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `FUNCTION_APP_PRIVATE_IP` | Function App private endpoint IP | `az network private-endpoint show --name pe-dev-aue-functionapp-dcert-poc --resource-group rg-dev-aue-dcert-poc --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv` |
| `VM_IP`                   | Test VM IP address               | Check Azure Portal or `az vm list-ip-addresses`                                                                                                                      |
| `SSH_KEY`                 | Path to SSH key for VM           | Default: `~/.ssh/vm-dev-aue-dcert-poc-keypair.pem`                                                                                                                   |
| `FUNCTION_APP`            | Function App name                | Default: `func-devicepki-dev-001`                                                                                                                                    |
| `RESOURCE_GROUP`          | Azure resource group             | Default: `rg-dev-aue-dcert-poc`                                                                                                                                      |

## Alternative: Environment Variables

Instead of using `config.sh`, you can export variables directly:

```bash
export FUNCTION_APP_PRIVATE_IP="10.140.34.4"
export VM_IP="10.140.34.6"
export SSH_KEY="$HOME/.ssh/vm-dev-aue-dcert-poc-keypair.pem"

./list-certificates-local.sh
```

## Script Types

### Local Scripts (\*-local.sh)

- Run from your local machine with VPN connection
- Require: `FUNCTION_APP_PRIVATE_IP` and hosts file entry
- Example: `create-root-ca-local.sh`, `list-certificates-local.sh`

### VM Scripts (\*.sh without -local suffix)

- Run via SSH to VM inside VNet
- Require: `VM_IP` and `SSH_KEY`
- Example: `create-root-ca.sh`, `list-certificates.sh`

## Troubleshooting

### "VM_IP not configured" error

```bash
# Copy and edit config
cp config.sh.example config.sh
nano config.sh  # Set VM_IP="10.x.x.x"

# OR export directly
export VM_IP="10.140.34.6"
```

### "FUNCTION_APP_PRIVATE_IP not configured" error

```bash
# Find the IP
az network private-endpoint show \
  --name pe-dev-aue-functionapp-dcert-poc \
  --resource-group rg-dev-aue-dcert-poc \
  --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv

# Set in config.sh or export
export FUNCTION_APP_PRIVATE_IP="10.140.34.4"
```

### Script still shows placeholder values

Some older scripts may not yet use `common.sh`. You can:

1. Update the script manually to source common.sh
2. Or set the variable directly in the script file
3. Or export the environment variable before running

## Example: Full Setup

```bash
# Navigate to test directory
cd function-private-ca/test

# Copy configuration template
cp config.sh.example config.sh

# Get your IPs
FUNCTION_PE_IP=$(az network private-endpoint show \
  --name pe-dev-aue-functionapp-dcert-poc \
  --resource-group rg-dev-aue-dcert-poc \
  --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv)

VM_IP=$(az vm show -d --name vm-dev-aue-dcert-poc \
  --resource-group rg-dev-aue-dcert-poc \
  --query privateIps -o tsv)

# Update config.sh
sed -i.bak "s|FUNCTION_APP_PRIVATE_IP=\"10.x.x.x\"|FUNCTION_APP_PRIVATE_IP=\"$FUNCTION_PE_IP\"|" config.sh
sed -i.bak "s|VM_IP=\"10.x.x.x\"|VM_IP=\"$VM_IP\"|" config.sh
rm config.sh.bak

# Test it
./list-certificates-local.sh
```

---

For more information, see [TESTING_GUIDE.md](../../docs/TESTING_GUIDE.md)
