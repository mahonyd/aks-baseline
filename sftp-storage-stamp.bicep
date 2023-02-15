targetScope = 'resourceGroup'

// Creates a storage account, private endpoints and DNS zones
/*** PARAMETERS ***/

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
@description('SFTP Storage region. This needs to be the same region as the vnet provided in these parameters.')
param location string = 'eastus2'

@description('Name of the storage account')
param storageName string

@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_GZRS'
  'Standard_RAGRS'
  'Standard_RAGZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
@description('Storage SKU')
param storageSkuName string = 'Standard_LRS'

@description('Username of primary user')
param userName string

@description('Home directory of primary user. Should be a container.')
param homeDirectory string

@description('SSH Public Key for primary user. If not specified, Azure will generate a password which can be accessed securely')
@secure()
param publicKey string

// VARIABLES

var storageNameCleaned = replace(storageName, '-', '')

/*** EXISTING RESOURCES ***/


/*** RESOURCES ***/
resource storage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageNameCleaned
  location: location
  sku: {
    name: storageSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    allowCrossTenantReplication: false
    allowSharedKeyAccess: true
    isHnsEnabled: true
    isLocalUserEnabled: true
    isSftpEnabled: true
    largeFileSharesState: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = {
  name: '${storage.name}/default/${homeDirectory}'
  properties: {
    publicAccess: 'None'
  }

}

resource user 'Microsoft.Storage/storageAccounts/localUsers@2022-09-01' = {
  parent: storage
  name: userName
  properties: {
    permissionScopes: [
      {
        permissions: 'rcwdl'
        service: 'blob'
        resourceName: homeDirectory
      }
    ]
    homeDirectory: homeDirectory
    sshAuthorizedKeys: empty(publicKey) ? null : [
      {
        description: '${userName} public key'
        key: publicKey
      }
    ]
    hasSharedKey: false
  }
}

output storageId string = storage.id
