targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('Subnet resource IDs for all AKS clusters nodepools in all attached spokes to allow necessary outbound traffic through the firewall.')
@minLength(1)
param nodepoolSubnetResourceIds array

@description('Subnet resource IDs for API Server to allow necessary outbound traffic through the firewall.')
@minLength(1)
param apiServerSubnetResourceIds array

@description('Subnet resource IDs for jump vms in all attached spokes to allow necessary outbound traffic through the firewall.')
@minLength(1)
param vmSubnetResourceIds array

@description('Subnet resource IDs for private endpoints in all attached spokes to allow necessary outbound traffic through the firewall.')
@minLength(1)
param privateEndpointSubnetResourceIds array

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
@description('The hub\'s regional affinity. All resources tied to this hub will also be homed in this region. The network team maintains this approved regional list which is a subset of zones with Availability Zone support.')
param location string = 'eastus2'

@description('Optional. A /24 to contain the regional firewall, management, and gateway subnet. Defaults to 10.200.0.0/24')
@maxLength(18)
@minLength(10)
param hubVirtualNetworkAddressSpace string = '10.200.0.0/24'

@description('Optional. A /26 under the virtual network address space for the regional Azure Firewall. Defaults to 10.200.0.0/26')
@maxLength(18)
@minLength(10)
param hubVirtualNetworkAzureFirewallSubnetAddressSpace string = '10.200.0.0/26'

@description('Optional. A /27 under the virtual network address space for our regional On-Prem Gateway. Defaults to 10.200.0.64/27')
@maxLength(18)
@minLength(10)
param hubVirtualNetworkGatewaySubnetAddressSpace string = '10.200.0.64/27'

@description('Optional. A /26 under the virtual network address space for regional Azure Bastion. Defaults to 10.200.0.128/26')
@maxLength(18)
@minLength(10)
param hubVirtualNetworkBastionSubnetAddressSpace string = '10.200.0.128/26'

@description('Specifies the name of the Azure Bastion resource.')
param bastionHostName string = 'bas-${location}-hub'

/*** RESOURCES ***/

// This Log Analytics workspace stores logs from the regional hub network, its spokes, and bastion.
// Log analytics is a regional resource, as such there will be one workspace per hub (region)
resource laHub 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: 'la-hub-${location}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    forceCmkForQuery: false
    features: {
      disableLocalAuth: true
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
  }
}

resource laHub_diagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: laHub
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

// NSG around the Azure Bastion Subnet.
resource nsgBastionSubnet 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${location}-bastion'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowWebExperienceInbound'
        properties: {
          description: 'Allow our users in. Update this to be as restrictive as possible.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowControlPlaneInbound'
        properties: {
          description: 'Service Requirement. Allow control plane access. Regional Tag not yet supported.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
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
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowBastionHostToHostInbound'
        properties: {
          description: 'Service Requirement. Allow Required Host to Host Communication.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
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
          sourceAddressPrefix: '*'
          destinationPortRange: '22'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowRdpToVnetOutbound'
        properties: {
          description: 'Allow RDP out to the virtual network'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '3389'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowControlPlaneOutbound'
        properties: {
          description: 'Required for control plane outbound. Regional prefix not yet supported'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '443'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBastionHostToHostOutbound'
        properties: {
          description: 'Service Requirement. Allow Required Host to Host Communication.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBastionCertificateValidationOutbound'
        properties: {
          description: 'Service Requirement. Allow Required Session and Certificate Validation.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '80'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 140
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

resource nsgBastionSubnet_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: nsgBastionSubnet
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

// The regional hub network
resource vnetHub 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: 'vnet-${location}-hub'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVirtualNetworkAddressSpace
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: hubVirtualNetworkAzureFirewallSubnetAddressSpace
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: hubVirtualNetworkGatewaySubnetAddressSpace
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: hubVirtualNetworkBastionSubnetAddressSpace
          networkSecurityGroup: {
            id: nsgBastionSubnet.id
          }
        }
      }
    ]
  }

  resource azureFirewallSubnet 'subnets' existing = {
    name: 'AzureFirewallSubnet'
  }
}

resource vnetHub_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: vnetHub
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

// Allocate three IP addresses to the firewall
var numFirewallIpAddressesToAssign = 3
resource pipsAzureFirewall 'Microsoft.Network/publicIPAddresses@2021-05-01' = [for i in range(0, numFirewallIpAddressesToAssign): {
  name: 'pip-fw-${location}-${padLeft(i, 2, '0')}'
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
}]

resource pipAzureFirewall_diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = [for i in range(0, numFirewallIpAddressesToAssign): {
  name: 'default'
  scope: pipsAzureFirewall[i]
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
}]

// This holds IP addresses of known nodepool subnets in spokes.
resource ipgNodepoolSubnet 'Microsoft.Network/ipGroups@2021-05-01' = {
  name: 'ipg-${location}-AksNodepools'
  location: location
  properties: {
    ipAddresses: [for nodepoolSubnetResourceId in nodepoolSubnetResourceIds: '${reference(nodepoolSubnetResourceId, '2020-05-01').addressPrefix}']
  }
}

resource ipgApiServerSubnet 'Microsoft.Network/ipGroups@2021-05-01' = {
  name: 'ipg-${location}-ApiServer'
  location: location
  properties: {
    ipAddresses: [for apiServerSubnetResourceId in apiServerSubnetResourceIds: '${reference(apiServerSubnetResourceId, '2020-05-01').addressPrefix}']
  }
}

// This holds IP addresses of known vm subnets in spokes.
resource ipgVmSubnet 'Microsoft.Network/ipGroups@2021-05-01' = {
  name: 'ipg-${location}-jumpvm'
  location: location
  properties: {
    ipAddresses: [for vmSubnetResourceId in vmSubnetResourceIds: '${reference(vmSubnetResourceId, '2020-05-01').addressPrefix}']
  }
}

// This holds IP addresses of known private endpoint subnets in spokes.
resource ipgPrivateEndpointSubnet 'Microsoft.Network/ipGroups@2021-05-01' = {
  name: 'ipg-${location}-pe'
  location: location
  properties: {
    ipAddresses: [for privateEndpointSubnetResourceId in privateEndpointSubnetResourceIds: '${reference(privateEndpointSubnetResourceId, '2020-05-01').addressPrefix}']
  }
}

// Azure Firewall starter policy
resource fwPolicy 'Microsoft.Network/firewallPolicies@2021-05-01' = {
  name: 'fw-policies-${location}'
  location: location
  dependsOn: [
    ipgNodepoolSubnet
  ]
  properties: {
    sku: {
      tier: 'Premium'
    }
    threatIntelMode: 'Deny'
    insights: {
      isEnabled: true
      retentionDays: 30
      logAnalyticsResources: {
        defaultWorkspaceId: {
          id: laHub.id
        }
      }
    }
    threatIntelWhitelist: {
      fqdns: []
      ipAddresses: []
    }
    intrusionDetection: {
      mode: 'Deny'
      configuration: {
        bypassTrafficSettings: []
        signatureOverrides: []
      }
    }
    dnsSettings: {
      servers: []
      enableProxy: true
    }
  }

  // Network hub starts out with only supporting DNS. This is only being done for
  // simplicity in this deployment and is not guidance, please ensure all firewall
  // rules are aligned with your security standards.
  resource defaultNetworkRuleCollectionGroup 'ruleCollectionGroups@2021-05-01' = {
    name: 'DefaultNetworkRuleCollectionGroup'
    properties: {
      priority: 200
      ruleCollections: [
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'org-wide-allowed'
          priority: 100
          action: {
            type: 'Allow'
          }
          rules: [
            {
              ruleType: 'NetworkRule'
              name: 'DNS'
              description: 'Allow DNS outbound (for simplicity, adjust as needed)'
              ipProtocols: [
                'UDP'
              ]
              sourceAddresses: [
                '*'
              ]
              sourceIpGroups: []
              destinationAddresses: [
                '*'
              ]
              destinationIpGroups: []
              destinationFqdns: []
              destinationPorts: [
                '53'
              ]
            }
          ]
        }
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'AKS-Global-Requirements'
          priority: 200
          action: {
            type: 'Allow'
          }
          rules: [
            {
              ruleType: 'NetworkRule'
              name: 'pods-to-api-server-konnectivity'
              description: 'This allows pods to communicate with the API server. Ensure your API server\'s allowed IP ranges support all of this firewall\'s public IPs.'
              ipProtocols: [
                'TCP'
              ]
              sourceAddresses: []
              sourceIpGroups: [
                ipgNodepoolSubnet.id
              ]
              destinationAddresses: [
                'AzureCloud.${location}' // Ideally you'd list your AKS server endpoints in appliction rules, instead of this wide-ranged rule
              ]
              destinationIpGroups: []
              destinationFqdns: []
              destinationPorts: [
                '443'
              ]
            }
            // NOTE: This rule is only required for for clusters not yet running in konnectivity mode and can be removed once it has been fully rolled out.
            {
              ruleType: 'NetworkRule'
              name: 'pod-to-api-server_udp-1194'
              description: 'This allows pods to communicate with the API server. Only needed if your cluster is not yet using konnectivity.'
              ipProtocols: [
                'UDP'
              ]
              sourceAddresses: []
              sourceIpGroups: [
                ipgNodepoolSubnet.id
              ]
              destinationAddresses: [
                'AzureCloud.${location}' // Ideally you'd list your AKS server endpoints in appliction rules, instead of this wide-ranged rule
              ]
              destinationIpGroups: []
              destinationFqdns: []
              destinationPorts: [
                '1194'
              ]
            }
          ]
        }
      ]
    }
  }

  // Network hub starts out with no allowances for appliction rules
  resource defaultApplicationRuleCollectionGroup 'ruleCollectionGroups@2021-05-01' = {
    name: 'DefaultApplicationRuleCollectionGroup'
    dependsOn: [
      defaultNetworkRuleCollectionGroup
    ]
    properties: {
      priority: 300
      ruleCollections: [
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'AKS-Global-Requirements'
          priority: 200
          action: {
            type: 'Allow'
          }
          rules: [
            {
              ruleType: 'ApplicationRule'
              name: 'azure-monitor-addon'
              description: 'Supports required communication for the Azure Monitor addon in AKS'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: [
                '*.ods.opinsights.azure.com'
                '*.oms.opinsights.azure.com'
                '${location}.monitoring.azure.com'
              ]
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgNodepoolSubnet.id
                ipgApiServerSubnet.id
              ]
            }
            {
              ruleType: 'ApplicationRule'
              name: 'azure-policy-addon'
              description: 'Supports required communication for the Azure Policy addon in AKS'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: [
                'data.policy.${environment().suffixes.storage}'
                'store.policy.${environment().suffixes.storage}'
              ]
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgNodepoolSubnet.id
                ipgApiServerSubnet.id
              ]
            }
            {
              ruleType: 'ApplicationRule'
              name: 'service-requirements'
              description: 'Supports required core AKS functionality. Could be replaced with individual rules if added granularity is desired.'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              fqdnTags: [
                'AzureKubernetesService'
              ]
              webCategories: []
              targetFqdns: []
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgNodepoolSubnet.id
                ipgApiServerSubnet.id
              ]
            }
          ]
        }
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'GitOps-Traffic'
          priority: 300
          action: {
            type: 'Allow'
          }
          rules: [
            {
              ruleType: 'ApplicationRule'
              name: 'github-origin'
              description: 'Supports pulling gitops configuration from GitHub.'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: [
                'github.com'
                'api.github.com'
                'raw.githubusercontent.com'
              ]
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgNodepoolSubnet.id
                ipgApiServerSubnet.id
              ]
            }
            {
              ruleType: 'ApplicationRule'
              name: 'flux-extension-runtime-requirements'
              description: 'Supports required communication for the Flux v2 extension operate and contains allowances for our applications deployed to the cluster.'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: [
                '${location}.dp.kubernetesconfiguration.azure.com'
                '*.hcp.${location}.azmk8s.io'
                'mcr.microsoft.com'
                'packages.microsoft.com'
                'get.helm.sh' // required to get helm 
                'fluxcd.io' // required to get flux
                '${split(environment().resourceManager, '/')[2]}' // Prevent the linter from getting upset at management.azure.com - https://github.com/Azure/bicep/issues/3080
                '${split(environment().authentication.loginEndpoint, '/')[2]}' // Prevent the linter from getting upset at login.microsoftonline.com
                '*.blob.${environment().suffixes.storage}' // required for the extension installer to download the helm chart install flux. This storage account is not predictable, but does look like eusreplstore196 for example.
                'azurearcfork8s.azurecr.io' // required for a few of the images installed by the extension.
                '*.docker.io' // Only required if you use the default bootstrapping manifests included in this repo.
                '*.docker.com' // Only required if you use the default bootstrapping manifests included in this repo.
                'ghcr.io' // Only required if you use the default bootstrapping manifests included in this repo. Kured is sourced from here by default.
                'pkg-containers.githubusercontent.com' // Only required if you use the default bootstrapping manifests included in this repo. Kured is sourced from here by default.
              ]
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgNodepoolSubnet.id
                ipgApiServerSubnet.id
              ]
            }
          ]
        }
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'SQL-Requirements'
          priority: 400
          action: {
            type: 'Allow'
          }
          rules: [
            {
              ruleType: 'ApplicationRule'
              name: 'sql-private-requirements'
              description: 'Supports required communication for SQL Server with private endpoint.'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
                {
                  protocolType: 'Http'
                  port: 80
                }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: [
                '${split(environment().resourceManager, '/')[2]}' // Prevent the linter from getting upset at management.azure.com - https://github.com/Azure/bicep/issues/3080
                '${split(environment().authentication.loginEndpoint, '/')[2]}' // Prevent the linter from getting upset at login.microsoftonline.com
                'autologon.microsoftazuread-sso.com' // required for Azure AD login
                '*.microsoft.com' // required for Azure AD login
                '*.windows.net' // required for Azure AD login
                'mscrl.microsoft.com' // Used to download CRL lists
                '*.verisign.com' // Used to download CRL lists
                '*.entrust.com' //Used to download CRL lists for MFA.
                'secure.aadcdn.microsoftonline-p.com' // Used for MFA.
                'aadcdn.msftauth.net' // Used for MFA.
                '*.microsoftonline.com' // Used to configure Azure AD directory and import/export data.
                '*.msappproxy.net' // Used for authentication
                'portal.azure.com' // required for authenticing SQL user using Azure Active Directory with MFA
                'aad.portal.azure.com' // required for authenticing SQL user using Azure Active Directory with MFA
              ]
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgPrivateEndpointSubnet.id
              ]
            }
          ]
        }
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'Jump-Server-Requirements'
          priority: 500
          action: {
            type: 'Allow'
          }
          rules: [
            {
              ruleType: 'ApplicationRule'
              name: 'jump-server-requirements'
              description: 'Supports required communication for the Jump Server.'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
                {
                  protocolType: 'Http'
                  port: 80
                }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: [
                '*.blob.${environment().suffixes.storage}' // required to connect to storage accounts AND LAW
                'azure.archive.ubuntu.com' // required to run apt-get commands
                'archive.ubuntu.com' // required to run apt-get commands
                'security.ubuntu.com' // required to run apt-get commands
                'packages.microsoft.com' // required to run apt-get commands
                'azurecliprod.blob.${environment().suffixes.storage}' // required to get az cli install script
                'aka.ms' // required to get az cli install script
                'storage.googleapis.com' // required to get kubectl
                'api.github.com' // required to get kubelogin and flux
                'github-releases.githubusercontent.com' // required to get kubelogin, flux, osm, helm
                'github.com' // required to get kubelogin and osm
                'dev.azure.com' // required to install and run Azure DevOps agent
                'raw.githubusercontent.com' // required to get helm and homebrew install scripts
                'get.helm.sh' // required to get helm 
                'fluxcd.io' // required to get flux
                '${split(environment().resourceManager, '/')[2]}' // Prevent the linter from getting upset at management.azure.com - https://github.com/Azure/bicep/issues/3080
                '${split(environment().authentication.loginEndpoint, '/')[2]}' // Prevent the linter from getting upset at login.microsoftonline.com
                '*.ods.opinsights.azure.com' // required for LAW
                '*.oms.opinsights.azure.com' // required for LAW
                '*.azure-automation.net' // required for LAW
                'dl.k8s.io' // required to get kubectl
                'microsoft.com' // required for device login
                '*.microsoft.com'  // required for downloading SSMS etc.
                'aadcdn.msftauth.net' // required for MS login page to work
                'onegetcdn.azureedge.net'
                'objects.githubusercontent.com' // required to get kubelogin
                'git-scm.com' // required to get git
                '*.vssps.visualstudio.com' // required for Azure DevOps login
                'logincdn.msauth.net' // required for Azure DevOps login
                'logincdn.msftauth.net' // required for Azure DevOps login
                'vstsagentpackage.azureedge.net' // required for Azure DevOps agent download
                '*.visualstudio.com' // required for Azure DevOps agent install
                '*.dev.azure.com' // required for Azure DevOps agent install
                '*.docker.com' // required for Docker download
                'github.githubassets.com' // required for github page
                'codeload.github.com' // required for github download
                'portal.azure.com' // required for Azure Portal
                'login.live.com' // required for Azure Portal login
                'ux.console.azure.com' // required for Azure Portal console
                'apt.kubernetes.io' // required for Docker install on Linux
                'packages.cloud.google.com' // required for Docker install on Linux
                'www.powershellgallery.com' // required for Powershell on Windows
                '*.azureedge.net' // required for Powershell module download on Windows
                '*.portal.azure.net' // required for portal
                'deb.debian.org' // required for image build
                'api.nuget.org' // required for image build
                'aad.portal.azure.com' // required for authenticing SQL user using Azure Active Directory with MFA
                '*.microsoftonline.com' // required for authenticing SQL user using Azure Active Directory with MFA
                '*.msappproxy.net' // Used for authentication
                '*.msecnd.net' // required for authenticing SQL user using Azure Active Directory with MFA
                '*.windowsupdate.com' // required for authenticing SQL user using Azure Active Directory with MFA
                'login.windows.net' // required for authenticing SQL user using Azure Active Directory with MFA
                '*.digicert.com' // required for authenticing SQL user using Azure Active Directory with MFA
              ]
              targetUrls: []
              destinationAddresses: []
              terminateTLS: false
              sourceAddresses: []
              sourceIpGroups: [
                ipgVmSubnet.id
              ]
            }
          ]
        }
      ]
    }
  }
}

// This is the regional Azure Firewall that all regional spoke networks can egress through.
resource hubFirewall 'Microsoft.Network/azureFirewalls@2021-05-01' = {
  name: 'fw-${location}'
  location: location
  zones: [
    '1'
    '2'
    '3'
  ]
  dependsOn: [
    // This helps prevent multiple PUT updates happening to the firewall causing a CONFLICT race condition
    // Ref: https://learn.microsoft.com/azure/firewall-manager/quick-firewall-policy
    fwPolicy::defaultApplicationRuleCollectionGroup
    fwPolicy::defaultNetworkRuleCollectionGroup
    ipgNodepoolSubnet
  ]
  properties: {
    sku: {
      tier: 'Premium'
      name: 'AZFW_VNet'
    }
    firewallPolicy: {
      id: fwPolicy.id
    }
    ipConfigurations: [for i in range(0, numFirewallIpAddressesToAssign): {
      name: pipsAzureFirewall[i].name
      properties: {
        subnet: (0 == i) ? {
          id: vnetHub::azureFirewallSubnet.id
        } : null
        publicIPAddress: {
          id: pipsAzureFirewall[i].id
        }
      }
    }]
  }
}

resource hubFirewall_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: hubFirewall
  properties: {
    workspaceId: laHub.id
    logs: [
      {
        categoryGroup: 'allLogs'
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

resource bastionPublicIpAddress 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: 'pip-bas-${location}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

var bastionSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-${location}-hub', 'AzureBastionSubnet')

resource bastionHost 'Microsoft.Network/bastionHosts@2022-05-01' = {
  name: bastionHostName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPublicIpAddress.id
          }
        }
      }
    ]
  }
  dependsOn: [
    vnetHub
  ]
}

/*** OUTPUTS ***/

output hubVnetId string = vnetHub.id
output bastionSubnetId string = resourceId('Microsoft.Network/VirtualNetworks/subnets', 'vnet-${location}-hub', 'AzureBastionSubnet')
