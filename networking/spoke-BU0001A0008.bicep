targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The regional hub network to which this regional spoke will peer to.')
@minLength(79)
param hubVnetResourceId string

@allowed([
  'australiaeast'
  'canadacentral'
  'centralus'
  'eastus'
  'eastus2'
  'westus2'
  'francecentral'
  'germanywestcentral'
  'northeurope'
  'southafricanorth'
  'southcentralus'
  'uksouth'
  'westeurope'
  'japaneast'
  'southeastasia'
])
@description('The spokes\'s regional affinity, must be the same as the hub\'s location. All resources tied to this spoke will also be homed in this region. The network team maintains this approved regional list which is a subset of zones with Availability Zone support.')
param location string

@description('Optional. A /22 under the virtual network address space for AKS nodes. Defaults to 10.240.0.0/22')
@maxLength(18)
@minLength(10)
param spokeVirtualNetworkClusterNodesSubnetAddressSpace string = '10.240.0.0/22'

@description('Optional. A /28 under the virtual network address space for AKS cluster ingress services. Defaults to 10.240.4.0/28')
@maxLength(18)
@minLength(10)
param spokeVirtualNetworkClusterIngressServicesSubnetAddressSpace string = '10.240.4.0/28'

@description('Optional. A /24 under the virtual network address space for private link endpoints. Defaults to 10.240.5.0/24')
@maxLength(18)
@minLength(10)
param spokeVirtualNetworkPrivateLinkEndpointsSubnetAddressSpace string = '10.240.5.0/24'

@description('Optional. A /24 under the virtual network address space for application gateway. Defaults to 10.240.6.0/24')
@maxLength(18)
@minLength(10)
param spokeVirtualNetworkAppGatewaySubnetAddressSpace string = '10.240.6.0/24'

@description('Optional. A /27 under the virtual network address space for AKS API server. Defaults to 10.240.7.0/27')
@maxLength(18)
@minLength(10)
param spokeVirtualNetworkApiServerSubnetAddressSpace string = '10.240.7.0/27'

@description('Optional. A /26 under the virtual network address space for Jump server. Defaults to 10.240.8.0/26')
@maxLength(18)
@minLength(10)
param spokeVirtualNetworkVmSubnetAddressSpace string = '10.240.8.0/26'

// A designator that represents a business unit id and application id
var orgAppId = 'BU0001A0008'
var clusterVNetName = 'vnet-spoke-${orgAppId}-00'

/*** EXISTING HUB RESOURCES ***/

// This is 'rg-enterprise-networking-hubs' if using the default values in the walkthrough
resource hubResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: '${split(hubVnetResourceId,'/')[4]}'
}

resource hubVirtualNetwork 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  scope: hubResourceGroup
  name: '${last(split(hubVnetResourceId,'/'))}'
}

// This is the firewall that was deployed in 'hub-default.bicep'
resource hubFirewall 'Microsoft.Network/azureFirewalls@2021-05-01' existing = {
  scope: hubResourceGroup
  name: 'fw-${location}'
}

// This is the networking log analytics workspace (in the hub)
resource laHub 'Microsoft.OperationalInsights/workspaces@2021-06-01' existing = {
  scope: hubResourceGroup
  name: 'la-hub-${location}'
}

/*** RESOURCES ***/

// Next hop to the regional hub's Azure Firewall
resource routeNextHopToFirewall 'Microsoft.Network/routeTables@2021-05-01' = {
  name: 'route-to-${location}-hub-fw'
  location: location
  properties: {
    routes: [
      {
        name: 'r-nexthop-to-fw'
        properties: {
          nextHopType: 'VirtualAppliance'
          addressPrefix: '0.0.0.0/0'
          nextHopIpAddress: hubFirewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

// Default NSG on the AKS nodepools. Feel free to constrict further.
resource nsgNodepoolSubnet 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${clusterVNetName}-nodepools'
  location: location
  properties: {
    securityRules: []
  }
}

resource nsgNodepoolSubnet_diagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: nsgNodepoolSubnet
  name: 'default'
  properties: {
    workspaceId: laHub.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// Default NSG on the AKS internal load balancer subnet. Feel free to constrict further.
resource nsgInternalLoadBalancerSubnet 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${clusterVNetName}-aksilbs'
  location: location
  properties: {
    securityRules: []
  }
}

resource nsgInternalLoadBalancerSubnet_diagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: nsgInternalLoadBalancerSubnet
  name: 'default'
  properties: {
    workspaceId: laHub.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// NSG on the Application Gateway subnet.
resource nsgAppGwSubnet 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${clusterVNetName}-appgw'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow443Inbound'
        properties: {
          description: 'Allow ALL web traffic into 443. (If you wanted to allow-list specific IPs, this is where you\'d list them.)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationPortRange: '443'
          destinationAddressPrefix: 'VirtualNetwork'
          direction: 'Inbound'
          access: 'Allow'
          priority: 100
        }
      }
      {
        name: 'AllowControlPlaneInbound'
        properties: {
          description: 'Allow Azure Control Plane in. (https://learn.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'GatewayManager'
          destinationPortRange: '65200-65535'
          destinationAddressPrefix: '*'
          direction: 'Inbound'
          access: 'Allow'
          priority: 110
        }
      }
      {
        name: 'AllowHealthProbesInbound'
        properties: {
          description: 'Allow Azure Health Probes in. (https://learn.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          direction: 'Inbound'
          access: 'Allow'
          priority: 120
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'No further inbound traffic allowed.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAllOutbound'
        properties: {
          description: 'App Gateway v2 requires full outbound access.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource nsgAppGwSubnet_diagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: nsgAppGwSubnet
  name: 'default'
  properties: {
    workspaceId: laHub.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// NSG on the Private Link subnet.
resource nsgPrivateLinkEndpointsSubnet 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${clusterVNetName}-privatelinkendpoints'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAll443InFromVnet'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource nsgPrivateLinkEndpointsSubnet_diagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: nsgPrivateLinkEndpointsSubnet
  name: 'default'
  properties: {
    workspaceId: laHub.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// NSG on the AKS API Server subnet.
resource nsgApiServerSubnet 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${clusterVNetName}-apiserver'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAllHttpsInFromVnet'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAllHttpsOutToVnet'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource nsgApiServerSubnet_diagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: nsgApiServerSubnet
  name: 'default'
  properties: {
    workspaceId: laHub.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// NSG around the VM Subnet.
resource nsgVmSubnet 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${clusterVNetName}-vm'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSshToVnetInbound'
        properties: {
          description: 'Allow SSH in to the virtual network'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '22'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHealthProbesInbound'
        properties: {
          description: 'Service Requirement. Allow Health Probes.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'No further inbound traffic allowed.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSshToVnetOutbound'
        properties: {
          description: 'Allow SSH out to the virtual network'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '22'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowHttpsToInternetOutbound'
        properties: {
          description: 'Allow HTTPS out to the internet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowHttpToInternetOutbound'
        properties: {
          description: 'Allow HTTP out to the internet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '80'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutbound'
        properties: {
          description: 'No further outbound traffic allowed.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource nsgVmSubnet_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: nsgVmSubnet
  name: 'default'
  properties: {
    workspaceId: laHub.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// The spoke virtual network.
// 65,536 (-reserved) IPs available to the workload, split across two subnets for AKS,
// one for App Gateway and one for Private Link endpoints.
resource vnetSpoke 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: clusterVNetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.240.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-clusternodes'
        properties: {
          addressPrefix: spokeVirtualNetworkClusterNodesSubnetAddressSpace
          routeTable: {
            id: routeNextHopToFirewall.id
          }
          networkSecurityGroup: {
            id: nsgNodepoolSubnet.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-clusteringressservices'
        properties: {
          addressPrefix: spokeVirtualNetworkClusterIngressServicesSubnetAddressSpace
          routeTable: {
            id: routeNextHopToFirewall.id
          }
          networkSecurityGroup: {
            id: nsgInternalLoadBalancerSubnet.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-applicationgateway'
        properties: {
          addressPrefix: spokeVirtualNetworkAppGatewaySubnetAddressSpace
          networkSecurityGroup: {
            id: nsgAppGwSubnet.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-privatelinkendpoints'
        properties: {
          addressPrefix: spokeVirtualNetworkPrivateLinkEndpointsSubnetAddressSpace
          networkSecurityGroup: {
            id: nsgPrivateLinkEndpointsSubnet.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-apiserver'
        properties: {
          addressPrefix: spokeVirtualNetworkApiServerSubnetAddressSpace
          networkSecurityGroup: {
            id: nsgApiServerSubnet.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-vm'
        properties: {
          routeTable: {
            id: routeNextHopToFirewall.id
          }
          addressPrefix: spokeVirtualNetworkVmSubnetAddressSpace
          networkSecurityGroup: {
            id: nsgVmSubnet.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }

  resource snetClusterNodes 'subnets' existing = {
    name: 'snet-clusternodes'
  }

  resource snetVm 'subnets' existing = {
    name: 'snet-vm'
  }
}

// Peer to regional hub
module peeringSpokeToHub 'virtualNetworkPeering.bicep' = {
  name: take('Peer-${vnetSpoke.name}To${hubVirtualNetwork.name}', 64)
  params: {
    remoteVirtualNetworkId: hubVirtualNetwork.id
    localVnetName: vnetSpoke.name
  }
}

// Connect regional hub back to this spoke, this could also be handled via the
// hub template or via Azure Policy or Portal. How virtual networks are peered
// may vary from organization to organization. This example simply does it in
// the most direct way.
module peeringHubToSpoke 'virtualNetworkPeering.bicep' = {
  name: take('Peer-${hubVirtualNetwork.name}To${vnetSpoke.name}', 64)
  dependsOn: [
    peeringSpokeToHub
  ]
  scope: hubResourceGroup
  params: {
    remoteVirtualNetworkId: vnetSpoke.id
    localVnetName: hubVirtualNetwork.name
  }
}

resource vnetSpoke_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: vnetSpoke
  name: 'default'
  properties: {
    workspaceId: laHub.id
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Used as primary public entry point for cluster. Expected to be assigned to an Azure Application Gateway.
// This is a public facing IP, and would be best behind a DDoS Policy (not deployed simply for cost considerations)
resource pipPrimaryClusterIp 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'pip-${orgAppId}-00'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
}

resource pipPrimaryClusterIp_diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' =  {
  name: 'default'
  scope: pipPrimaryClusterIp
  properties: {
    workspaceId: laHub.id
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

/*** OUTPUTS ***/

output clusterVnetResourceId string = vnetSpoke.id
output nodepoolSubnetResourceIds array = [
  vnetSpoke::snetClusterNodes.id
]
output vmSubnetResourceIds array = [
  vnetSpoke::snetVm.id
]
output appGwPublicIpAddress string = pipPrimaryClusterIp.properties.ipAddress
output vmSubnetId string = resourceId('Microsoft.Network/VirtualNetworks/subnets', 'vnet-spoke-${orgAppId}-00', 'VmSubnet')
