# Setting Up Azure DevOps CI/CD Pipeline

This guide walks through setting up Azure DevOps pipeline for automated deployment to the private network Function App.

## Prerequisites

- Azure DevOps organization and project
- Service Principal with access to Azure resources
- Azure subscription with the Function App deployed

## Step 1: Create Azure DevOps Service Connection

### 1.1 Create Service Principal

```bash
# Set variables
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SERVICE_PRINCIPAL_NAME="sp-azdo-devicepki-dev"

# Create service principal
az ad sp create-for-rbac \
  --name $SERVICE_PRINCIPAL_NAME \
  --role Contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-dev-aue-dcert-poc \
  --sdk-auth

# Save the output JSON - you'll need it for the service connection
```

### 1.2 Create Service Connection in Azure DevOps

1. Go to your Azure DevOps project
2. Click **Project Settings** (bottom left)
3. Under **Pipelines**, click **Service connections**
4. Click **New service connection**
5. Select **Azure Resource Manager** → **Next**
6. Select **Service principal (manual)** → **Next**
7. Fill in the details from the service principal output:
   - **Subscription ID**: Your Azure subscription ID
   - **Subscription Name**: Your subscription name
   - **Service Principal ID**: `clientId` from JSON
   - **Service Principal Key**: `clientSecret` from JSON
   - **Tenant ID**: `tenantId` from JSON
8. **Service connection name**: `Azure-ServiceConnection`
9. Check **Grant access permission to all pipelines** (for now)
10. Click **Verify and save**

## Step 2: Configure Environments

### 2.1 Create Development Environment

1. In Azure DevOps, go to **Pipelines** → **Environments**
2. Click **New environment**
3. Name: `Development`
4. Description: "Development environment for function app"
5. Click **Create**

### 2.2 Create Production Environment with Approval

1. Click **New environment**
2. Name: `Production`
3. Description: "Production environment with manual approval"
4. Click **Create**
5. Click the **⋯** menu → **Approvals and checks**
6. Click **+** → **Approvals**
7. Add approvers (your team members)
8. Set minimum number of approvers
9. Click **Create**

## Step 3: Configure Pipeline Variables

### 3.1 Update azure-pipelines.yml

Edit `azure-pipelines.yml` and update these variables:

```yaml
variables:
  azureSubscription: "Azure-ServiceConnection" # Match your service connection name
  functionAppName: "func-devicepki-dev-001" # Your Function App name
  resourceGroupName: "rg-dev-aue-dcert-poc" # Your resource group
```

### 3.2 Add Pipeline to Azure DevOps

1. Go to **Pipelines** → **Pipelines**
2. Click **New pipeline**
3. Select your repository (Azure Repos, GitHub, etc.)
4. Select **Existing Azure Pipelines YAML file**
5. Select `/azure-pipelines.yml`
6. Click **Continue**
7. Review the pipeline and click **Run**

## Step 4: Grant Service Principal Additional Permissions

The service principal needs permissions to deploy to the Function App:

```bash
# Get service principal object ID
SP_OBJECT_ID=$(az ad sp list --display-name $SERVICE_PRINCIPAL_NAME --query '[0].id' -o tsv)

# Grant permissions to Function App
az functionapp identity assign \
  --name func-devicepki-dev-001 \
  --resource-group rg-dev-aue-dcert-poc

# Grant service principal role on Function App
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role "Website Contributor" \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-dev-aue-dcert-poc/providers/Microsoft.Web/sites/func-devicepki-dev-001
```

## Step 5: Configure Branch Policies (Optional)

### 5.1 Protect Main Branch

1. Go to **Repos** → **Branches**
2. Find `main` branch → **⋯** → **Branch policies**
3. Enable:
   - **Require a minimum number of reviewers**: 1-2 reviewers
   - **Check for linked work items**: Optional
   - **Build Validation**: Add pipeline
   - **Limit merge types**: Squash merge only

### 5.2 Create Develop Branch

```bash
git checkout -b develop
git push origin develop
```

## Step 6: Test the Pipeline

### 6.1 Trigger Build

```bash
# Make a change to function code
cd function-rootca
echo "# Updated" >> function_app.py

# Commit and push
git add .
git commit -m "test: trigger pipeline"
git push origin develop
```

### 6.2 Monitor Pipeline

1. Go to **Pipelines** → **Pipelines**
2. Click on the running pipeline
3. Monitor build and deployment stages
4. Check deployment logs

## Pipeline Workflow

```
┌─────────────────────────────────────────────────────┐
│ Code Push                                           │
│  ├── develop branch → Deploy to Development        │
│  └── main branch → Deploy to Production (approval) │
└─────────────────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│ Build Stage                                         │
│  ├── Install Python dependencies                   │
│  ├── Create deployment package                     │
│  └── Publish build artifacts                       │
└─────────────────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│ Deploy Stage                                        │
│  ├── Download artifacts                            │
│  ├── Deploy to Function App (ZIP Deploy)           │
│  └── Verify health endpoint                        │
└─────────────────────────────────────────────────────┘
```

## Troubleshooting

### Pipeline fails with "Service connection not found"

**Cause**: Service connection name doesn't match
**Solution**: Update `azureSubscription` variable in `azure-pipelines.yml`

### Deployment fails with permission error

**Cause**: Service principal lacks permissions
**Solution**: Grant "Website Contributor" role (see Step 4)

### Health check fails after deployment

**Cause**: Function App may be in private network
**Solution**:

- Check if Azure DevOps agent can reach the Function App
- May need self-hosted agent in Azure VNet
- Or configure Azure DevOps service connection with VNet integration

### Build succeeds but deployment skipped

**Cause**: Branch condition doesn't match
**Solution**: Check branch name matches pipeline conditions (`main` or `develop`)

## Next Steps

1. ✅ Set up service connection
2. ✅ Configure environments with approvals
3. ✅ Test deployment pipeline
4. Add monitoring and alerts
5. Configure self-hosted agents if needed for VNet access
6. Add integration tests to pipeline
7. Implement blue-green deployment strategy

## Additional Resources

- [Azure DevOps Service Connections](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints)
- [Azure Function App Deployment](https://docs.microsoft.com/en-us/azure/devops/pipelines/targets/azure-functions)
- [Pipeline Approvals and Gates](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/approvals)
