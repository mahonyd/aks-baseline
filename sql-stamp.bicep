targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The regional network spoke VNet Resource ID that the SQL Server will be joined to.')
@minLength(79)
param targetVnetResourceId string

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
@description('AKS Service, Node Pool, and supporting services (KeyVault, App Gateway, etc) region. This needs to be the same region as the vnet provided in these parameters.')
param location string = 'eastus2'

@description('The name of the SQL logical server.')
param serverName string = 'sql-sb-klirdb-01'

@description('The name of the SQL elastic pool.')
param poolName string = 'sqlep-sb-klirdb-01'

@description('The name of the SQL Database.')
param sqlDBName string = 'sqldb-sb-klirdb-01'

@description('The administrator username of the SQL logical server.')
param administratorLogin string

@description('The administrator password of the SQL logical server.')
@secure()
param administratorLoginPassword string

@description('Object ID of the server administrator group.')
param adminGroupId string

@description('Azure AD username of the server administrator.')
param adminUsername string

@description('Tenant ID of the administrator.')
param tenantId string

@description('Flag to indicate if database is zone redundant.')
param zoneRedundant bool

/*** VARIABLES ***/
var privateDnsZoneName = 'privatelink${environment().suffixes.sqlServerHostname}'


/*** EXISTING RESOURCES ***/

resource spokeResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: '${split(targetVnetResourceId,'/')[4]}'
}

resource spokeVirtualNetwork 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  scope: spokeResourceGroup
  name: '${last(split(targetVnetResourceId,'/'))}'
  
  resource snetPrivateLinkEndpoints 'subnets@2021-05-01' existing = {
    name: 'snet-privatelinkendpoints'
  }
}

/*** RESOURCES ***/

// Expose Azure SQL Server via Private Link, into the cluster nodes subnet.
resource privateEndpointSqlToVnet 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: 'pe-${serverName}'
  location: location
  dependsOn: [
  ]
  properties: {
    subnet: {
      id: spokeVirtualNetwork::snetPrivateLinkEndpoints.id
    }
    privateLinkServiceConnections: [
      {
        name: 'to_${spokeVirtualNetwork.name}'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

// SQL Server will be exposed via Private Link, set up the related Private DNS zone and virtual network link to the spoke.
resource dnsPrivateZoneSql 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  properties: {}
}

resource dnsVnetLinkSqlToSpoke 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dnsPrivateZoneSql
  name: 'to_${spokeVirtualNetwork.name}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: targetVnetResourceId
    }
    registrationEnabled: false
  }
}

resource privateDnsZoneGroupSql 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  name: 'pe-${serverName}/sqldnsgroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: dnsPrivateZoneSql.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointSqlToVnet
  ]
}

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: false
      login: adminUsername
      principalType: 'Group'
      sid: adminGroupId
      tenantId: tenantId
    }
    version: '12.0'
    publicNetworkAccess: 'Disabled'
  }
}

resource sqlElasticPool 'Microsoft.Sql/servers/elasticPools@2022-05-01-preview' = {
  name: poolName
  location: location
  sku: {
    capacity: 2
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
  }
  parent: sqlServer
  properties: {
    licenseType: 'LicenseIncluded'
    zoneRedundant: zoneRedundant
    perDatabaseSettings: {
      minCapacity: 0
      maxCapacity: 2
    }
  }
}

resource sqlDB 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  parent: sqlServer
  name: sqlDBName
  location: location
  sku: {
    name: 'ElasticPool'
    tier: 'GeneralPurpose'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    elasticPoolId: sqlElasticPool.id
    zoneRedundant: zoneRedundant
  }
}

/*** OUTPUTS ***/

output sqlServerName string = sqlServer.name
