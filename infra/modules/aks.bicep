@description('Name of the AKS cluster')
param clusterName string

@description('Location for the AKS cluster')
param location string

@description('Log Analytics workspace resource ID for Container Insights')
param logAnalyticsWorkspaceId string

@description('ACR resource ID to attach')
param acrId string

// System pool VM: Standard_D2s_v3 (2 vCPU, 8 GB, ~$70/mo) — full sustained CPU.
// Cost optimization: switch to 'Standard_B2ms' (~$40/mo, burstable 60% baseline)
// for dev/POC workloads with low sustained load.
@description('System node pool VM size')
param systemNodeVmSize string = 'Standard_D2s_v3'

@description('Sandbox node pool VM size (must support nested virtualization)')
param sandboxNodeVmSize string = 'Standard_D4s_v3'

@description('System node pool count')
param systemNodeCount int = 1

@description('Sandbox node pool min count (0 = scale to zero)')
param sandboxNodeMinCount int = 0

@description('Sandbox node pool max count')
param sandboxNodeMaxCount int = 3

@description('Kubernetes version')
param kubernetesVersion string = '1.33'

@description('Tags')
param tags object = {}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: clusterName
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: false
      }
      {
        name: 'sandboxpool'
        count: sandboxNodeMinCount
        minCount: sandboxNodeMinCount
        maxCount: sandboxNodeMaxCount
        vmSize: sandboxNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'User'
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: true
        workloadRuntime: 'KataMshvVmIsolation'
        nodeLabels: {
          'workload-type': 'sandbox'
        }
        nodeTaints: [
          'sandbox=true:NoSchedule'
        ]
      }
    ]
  }
}

// Grant AKS kubelet identity AcrPull on the ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, acrId, 'acrpull')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

output clusterName string = aksCluster.name
output clusterFqdn string = aksCluster.properties.fqdn
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output clusterIdentityPrincipalId string = aksCluster.identity.principalId
