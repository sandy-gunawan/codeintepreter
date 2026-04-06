targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Base name for all resources (alphanumeric, lowercase)')
@minLength(3)
@maxLength(15)
param baseName string = 'codeinterp'

@description('Primary location for compute resources (AKS, ACR, Storage)')
param primaryLocation string = 'indonesiacentral'

@description('Environment tag')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

// --- Existing Azure OpenAI (set these to skip creating a new resource) ---
@description('Existing Azure OpenAI endpoint URL. If set, no new OpenAI resource is created.')
param existingOpenAiEndpoint string = ''

@description('Existing Azure OpenAI model deployment name.')
param existingOpenAiDeploymentName string = ''

@description('Location for new Azure OpenAI resource (only used if existingOpenAiEndpoint is empty)')
param openAiLocation string = 'southeastasia'

// ============================================================================
// Variables
// ============================================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
// Storage account name: max 24 chars, lowercase+numbers only
// 'ci' (2) + 'st' (2) + uniqueString (13) = 17 chars — safe
var clusterName = '${baseName}-aks-${uniqueSuffix}'
var acrName = replace('${baseName}acr${uniqueSuffix}', '-', '')
var storageName = 'cist${uniqueSuffix}'
var openAiName = '${baseName}-openai-${uniqueSuffix}'
var logAnalyticsName = '${baseName}-logs-${uniqueSuffix}'
var deployOpenAi = empty(existingOpenAiEndpoint)

var tags = {
  project: 'code-interpreter'
  environment: environment
  managedBy: 'bicep'
}

// ============================================================================
// Modules
// ============================================================================

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    workspaceName: logAnalyticsName
    location: primaryLocation
    tags: tags
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr'
  params: {
    acrName: acrName
    location: primaryLocation
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    storageAccountName: storageName
    location: primaryLocation
    tags: tags
  }
}

module openai 'modules/openai.bicep' = if (deployOpenAi) {
  name: 'openai'
  params: {
    openAiName: openAiName
    location: openAiLocation
    tags: tags
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aks'
  params: {
    clusterName: clusterName
    location: primaryLocation
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    acrId: acr.outputs.acrId
    tags: tags
  }
}

// ============================================================================
// Outputs
// ============================================================================

output aksClusterName string = aks.outputs.clusterName
output aksClusterFqdn string = aks.outputs.clusterFqdn

output acrLoginServer string = acr.outputs.acrLoginServer
output acrName string = acr.outputs.acrName

output storageAccountName string = storage.outputs.storageAccountName
output storageBlobEndpoint string = storage.outputs.blobEndpoint

// OpenAI: use existing or newly created
output openAiEndpoint string = deployOpenAi ? openai!.outputs.openAiEndpoint : existingOpenAiEndpoint
output openAiDeploymentName string = deployOpenAi ? openai!.outputs.deploymentName : existingOpenAiDeploymentName

output logAnalyticsWorkspaceName string = monitoring.outputs.workspaceName
output resourceGroupName string = resourceGroup().name
output openAiCreated bool = deployOpenAi
