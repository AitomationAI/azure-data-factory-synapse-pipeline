// Azure Data Factory with a system-assigned identity and diagnostics to Log Analytics.
// Pipelines, datasets and linked services are deployed from /adf via Git integration
// (or the ADF publish / ARM export flow) - not hard-coded here.
param name string
param location string
param tags object
param logAnalyticsId string

resource factory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: name
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// Self-hosted IR - install the agent on a VM that can reach the on-prem SQL Server.
resource selfHostedIr 'Microsoft.DataFactory/factories/integrationRuntimes@2018-06-01' = {
  parent: factory
  name: 'ir-onprem'
  properties: {
    type: 'SelfHosted'
    description: 'Reaches the on-premises claims SQL Server.'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: factory
  properties: {
    workspaceId: logAnalyticsId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      { category: 'PipelineRuns', enabled: true }
      { category: 'ActivityRuns', enabled: true }
      { category: 'TriggerRuns', enabled: true }
    ]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output name string = factory.name
output principalId string = factory.identity.principalId
