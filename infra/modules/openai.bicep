@description('Name of the Azure OpenAI resource')
param openAiName string

@description('Location for the OpenAI resource')
param location string = 'southeastasia'

@description('Model deployment name')
param modelDeploymentName string = 'gpt-41'

@description('Model name')
param modelName string = 'gpt-4.1'

@description('Model version')
param modelVersion string = '2025-04-14'

@description('Deployment capacity (TPM in thousands)')
param deploymentCapacity int = 10

@description('Tags')
param tags object = {}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAiName
    publicNetworkAccess: 'Enabled'
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: modelDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: deploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

output openAiEndpoint string = openAiAccount.properties.endpoint
output openAiName string = openAiAccount.name
output openAiId string = openAiAccount.id
output deploymentName string = modelDeployment.name

#disable-next-line outputs-should-not-contain-secrets
output openAiKey string = openAiAccount.listKeys().key1
