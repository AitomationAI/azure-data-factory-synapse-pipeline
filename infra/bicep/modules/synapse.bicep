// Synapse workspace + dedicated SQL pool (the warehouse).
param name string
param location string
param tags object
param storageAccountName string
param defaultFileSystem string
param sqlAdminLogin string
@secure()
param sqlAdminPassword string
param sqlPoolSku string
param dataEngineersGroupId string

resource workspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: name
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: 'https://${storageAccountName}.dfs.${az.environment().suffixes.storage}'
      filesystem: defaultFileSystem
    }
    sqlAdministratorLogin: sqlAdminLogin
    sqlAdministratorLoginPassword: sqlAdminPassword
    managedVirtualNetwork: 'default'
    publicNetworkAccess: 'Enabled'
  }
}

resource allowAzureServices 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: workspace
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource aadAdmin 'Microsoft.Synapse/workspaces/administrators@2021-06-01' = if (!empty(dataEngineersGroupId)) {
  parent: workspace
  name: 'activeDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    sid: dataEngineersGroupId
    tenantId: subscription().tenantId
  }
}

resource sqlPool 'Microsoft.Synapse/workspaces/sqlPools@2021-06-01' = {
  parent: workspace
  name: 'claimsdw'
  location: location
  tags: tags
  sku: { name: sqlPoolSku }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    createMode: 'Default'
    storageAccountType: 'GRS'
  }
}

output name string = workspace.name
output principalId string = workspace.identity.principalId
output sqlEndpoint string = workspace.properties.connectivityEndpoints.sql
