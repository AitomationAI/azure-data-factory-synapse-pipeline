// =============================================================================
// Claims analytics platform - Azure Data Factory + ADLS Gen2 + Synapse
//   az deployment group create -g <rg> -f infra/bicep/main.bicep \
//     -p infra/bicep/main.parameters.json -p sqlAdminPassword=<secret>
// =============================================================================
targetScope = 'resourceGroup'

@description('Short prefix used in every resource name.')
@maxLength(10)
param prefix string = 'claims'

@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

param location string = resourceGroup().location

@description('Synapse SQL administrator login.')
param sqlAdminLogin string = 'sqladmin'

@secure()
@description('Synapse SQL administrator password (pass at deploy time, never commit).')
param sqlAdminPassword string

@description('Dedicated SQL pool size. DW100c is the smallest; pause when idle.')
param sqlPoolSku string = 'DW100c'

@description('Object id of the data engineering AAD group (gets Synapse + Key Vault access).')
param dataEngineersGroupId string = ''

var suffix = uniqueString(resourceGroup().id)
var storageName = toLower('${prefix}${environment}lake${take(suffix, 6)}')
var tags = {
  project: 'claims-analytics'
  environment: environment
  managedBy: 'bicep'
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: storageName
    location: location
    tags: tags
  }
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-${environment}-logs'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${prefix}-${environment}-kv-${take(suffix, 6)}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
  }
}

// On-prem SQL Server password consumed by ADF through Key Vault - set after deploy:
//   az keyvault secret set --vault-name <kv> -n onprem-sql-password --value <pwd>

module dataFactory 'modules/datafactory.bicep' = {
  name: 'dataFactory'
  params: {
    name: '${prefix}-${environment}-adf-${take(suffix, 6)}'
    location: location
    tags: tags
    logAnalyticsId: logs.id
  }
}

module synapse 'modules/synapse.bicep' = {
  name: 'synapse'
  params: {
    name: '${prefix}-${environment}-syn-${take(suffix, 6)}'
    location: location
    tags: tags
    storageAccountName: storage.outputs.name
    defaultFileSystem: 'synapse'
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    sqlPoolSku: sqlPoolSku
    dataEngineersGroupId: dataEngineersGroupId
  }
}

// ---------------------------------------------------------------------------
// RBAC - managed identities only, no keys or connection strings
// ---------------------------------------------------------------------------
var roles = {
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  keyVaultSecretsOfficer: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource adfToLake 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, 'adf', roles.storageBlobDataContributor)
  scope: storageAccount
  dependsOn: [storage]
  properties: {
    principalId: dataFactory.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
  }
}

resource synapseToLake 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, 'synapse', roles.storageBlobDataContributor)
  scope: storageAccount
  dependsOn: [storage]
  properties: {
    principalId: synapse.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
  }
}

resource adfToKeyVault 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, 'adf', roles.keyVaultSecretsUser)
  scope: keyVault
  properties: {
    principalId: dataFactory.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.keyVaultSecretsUser)
  }
}

resource engineersToKeyVault 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(dataEngineersGroupId)) {
  name: guid(keyVault.id, 'engineers', roles.keyVaultSecretsOfficer)
  scope: keyVault
  properties: {
    principalId: dataEngineersGroupId
    principalType: 'Group'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.keyVaultSecretsOfficer)
  }
}

output storageAccountName string = storage.outputs.name
output dataFactoryName string = dataFactory.outputs.name
output synapseWorkspaceName string = synapse.outputs.name
output synapseSqlEndpoint string = synapse.outputs.sqlEndpoint
output keyVaultName string = keyVault.name
