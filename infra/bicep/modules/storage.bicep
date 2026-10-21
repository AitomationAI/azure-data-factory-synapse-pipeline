// ADLS Gen2 data lake with a medallion layout.
param name string
param location string
param tags object

var containers = [
  'inbound' // partner file drops (triggers ADF)
  'bronze' // raw copies, partitioned by load date
  'silver' // cleaned, conformed Parquet
  'quarantine' // rejected rows + bad files
  'synapse' // Synapse workspace default file system
]

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_ZRS' }
  properties: {
    isHnsEnabled: true // hierarchical namespace = ADLS Gen2
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // Entra ID / managed identity only
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: account
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true, days: 14 }
    containerDeleteRetentionPolicy: { enabled: true, days: 14 }
  }
}

resource lakeContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [
  for container in containers: {
    parent: blobService
    name: container
    properties: { publicAccess: 'None' }
  }
]

resource lifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: account
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'bronze-to-cool'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: { blobTypes: ['blockBlob'], prefixMatch: ['bronze/'] }
            actions: { baseBlob: { tierToCool: { daysAfterModificationGreaterThan: 30 } } }
          }
        }
        {
          name: 'expire-inbound'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: { blobTypes: ['blockBlob'], prefixMatch: ['inbound/'] }
            actions: { baseBlob: { delete: { daysAfterModificationGreaterThan: 14 } } }
          }
        }
      ]
    }
  }
}

output name string = account.name
output dfsEndpoint string = account.properties.primaryEndpoints.dfs
