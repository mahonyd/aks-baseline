targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The AKS Control Plane Principal Id to be given with Network Contributor Role in different spoke subnets, so it can join VMSS and load balancers resources to them.')
@minLength(36)
@maxLength(36)
param miClusterControlPlanePrincipalId string

@description('The AKS Control Plane Principal Name to be used to create unique role assignments names.')
@minLength(3)
@maxLength(128)
param clusterControlPlaneIdentityName string

@description('The regional network spoke VNet Resource name that the cluster is being joined to, so it can be used to discover subnets during role assignments.')
@minLength(1)
param targetVirtualNetworkName string

/*** EXISTING SUBSCRIPTION RESOURCES ***/

resource networkContributorRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: '4d97b98b-1d4f-4787-a291-c67834d212e7'
  scope: subscription()
}

/*** EXISTING HUB RESOURCES ***/

resource targetVirtualNetwork 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: targetVirtualNetworkName
}

resource snetClusterNodes 'Microsoft.Network/virtualNetworks/subnets@2021-05-01' existing = {
  parent: targetVirtualNetwork
  name: 'snet-clusternodes'
}

resource snetClusterIngress 'Microsoft.Network/virtualNetworks/subnets@2021-05-01' existing = {
  parent: targetVirtualNetwork
  name: 'snet-clusteringressservices'
}

resource snetApiServer 'Microsoft.Network/virtualNetworks/subnets@2021-05-01' existing = {
  parent: targetVirtualNetwork
  name: 'snet-apiserver'
}

/*** RESOURCES ***/

resource snetClusterNodesMiClusterControlPlaneNetworkContributorRole_roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: snetClusterNodes
  name: guid(snetClusterNodes.id, networkContributorRole.id, clusterControlPlaneIdentityName)
  properties: {
    roleDefinitionId: networkContributorRole.id
    description: 'Allows cluster identity to join the nodepool vmss resources to this subnet.'
    principalId: miClusterControlPlanePrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource snetClusterIngressServicesMiClusterControlPlaneSecretsUserRole_roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: snetClusterIngress
  name: guid(snetClusterIngress.id, networkContributorRole.id, clusterControlPlaneIdentityName)
  properties: {
    roleDefinitionId: networkContributorRole.id
    description: 'Allows cluster identity to join load balancers (ingress resources) to this subnet.'
    principalId: miClusterControlPlanePrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource snetApiServerMiClusterControlPlaneNetworkContributorRole_roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: snetApiServer
  name: guid(snetApiServer.id, networkContributorRole.id, clusterControlPlaneIdentityName)
  properties: {
    roleDefinitionId: networkContributorRole.id
    description: 'Allows cluster identity to access this subnet.'
    principalId: miClusterControlPlanePrincipalId
    principalType: 'ServicePrincipal'
  }
}
