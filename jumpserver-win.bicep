// Parameters
@description('The regional hub network.')
@minLength(79)
param hubVnetResourceId string

@description('Specifies the name of the virtual machine.')
param vmName string = 'JumpVm'

@description('Specifies the size of the virtual machine.')
param vmSize string = 'Standard_D2s_v3'

@description('Specifies the resource id of the subnet hosting the virtual machine.')
param vmSubnetId string

//@description('Specifies the name of the storage account where the bootstrap diagnostic logs of the virtual machine are stored.')
//param storageAccountName string

@description('Specifies the image publisher of the disk image used to create the virtual machine.')
param imagePublisher string = 'MicrosoftWindowsServer'

@description('Specifies the offer of the platform image or marketplace image used to create the virtual machine.')
param imageOffer string = 'WindowsServer'

@description('Specifies the Windows version for the VM. This will pick a fully patched image of this given Windows version.')
param imageSku string = '2022-datacenter-azure-edition-smalldisk'

@description('Specifies the name of the administrator account of the virtual machine.')
param vmAdminUsername string

@description('Specifies the SSH Key or password for the virtual machine. SSH key is recommended.')
@secure()
param vmAdminPasswordOrKey string

@description('Specifies the storage account type for OS and data disk.')
@allowed([
  'Premium_LRS'
  'StandardSSD_LRS'
  'Standard_LRS'
  'UltraSSD_LRS'
])
param diskStorageAccounType string = 'StandardSSD_LRS'

@description('Specifies the number of data disks of the virtual machine.')
@minValue(0)
@maxValue(64)
param numDataDisks int = 1

@description('Specifies the size in GB of the OS disk of the VM.')
param osDiskSize int = 50

@description('Specifies the size in GB of the OS disk of the virtual machine.')
param dataDiskSize int = 50

@description('Specifies the caching requirements for the data disks.')
param dataDiskCaching string = 'ReadWrite'

@description('Specifies the location.')
param location string = resourceGroup().location

//@description('Specifies the resource tags.')
//param tags object

// Variables
var vmNicName = '${vmName}Nic'

// Resources
resource virtualMachineNic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: vmNicName
  location: location
  //tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vmSubnetId
          }
        }
      }
    ]
  }
}

// This is 'rg-enterprise-networking-hubs' if using the default values in the walkthrough
resource hubResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: '${split(hubVnetResourceId,'/')[4]}'
}

resource laHub 'Microsoft.OperationalInsights/workspaces@2021-06-01' existing = {
  scope: hubResourceGroup
  name: 'la-hub-${location}'
}

//resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
 // name: storageAccountName
//}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmName
  location: location
  //tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPasswordOrKey
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}_OSDisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        diskSizeGB: osDiskSize
        managedDisk: {
          storageAccountType: diskStorageAccounType
        }
      }
      dataDisks: [for j in range(0, numDataDisks): {
        caching: dataDiskCaching
        diskSizeGB: dataDiskSize
        lun: j
        name: '${vmName}-DataDisk${j}'
        createOption: 'Empty'
        managedDisk: {
          storageAccountType: diskStorageAccounType
        }
      }]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: virtualMachineNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
        //storageUri: reference(storageAccount.id, storageAccount.apiVersion).primaryEndpoints.blob
      }
    }
  }
}
