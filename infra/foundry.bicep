targetScope = 'resourceGroup'

param resourceToken string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Main location for the resources')
param location string

@description('Application Insights resource name')
param appInsightsName string

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
  name: 'foundry-${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: 'foundry-${resourceToken}'
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }

  resource embeddingDeployment 'deployments' = {
    name: 'text-embedding-3-large'
    sku: {
      name: 'Standard'
      capacity: 50
    }
    properties: {
      model: {
        format: 'OpenAI'
        name: 'text-embedding-3-large'
        version: '1'
      }
      versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
      currentCapacity: 50
    }
  }

  resource gpt41Deployment 'deployments' = {
    name: 'gpt-4.1'
    sku: {
      name: 'GlobalStandard'
      capacity: 50
    }
    properties: {
      model: {
        format: 'OpenAI'
        name: 'gpt-4.1'
        version: '2025-04-14'
      }
      versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
      currentCapacity: 50
      raiPolicyName: 'Microsoft.DefaultV2'
    }
    dependsOn: [
      embeddingDeployment
    ]
  }

  resource project 'projects' = {
    name: 'foundryiq-${environmentName}'
    location: location
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      description: 'Demo Project'
      displayName: 'Demo Project'
    }

    resource appInsightConnection 'connections' = {
      name: 'appinsights'
      properties: {
        category: 'AppInsights'
        target: appInsights.id
        authType: 'ApiKey'
        isSharedToAll: true
        credentials: {
          key: appInsights.properties.ConnectionString
        }
        metadata: {
          ApiType: 'Azure'
          ResourceId: appInsights.id
        }
      }
    }
  }
}

resource currentUserCanPerformDataActionsOnFoundry 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, deployer().objectId, azureAiUserRoleDefinition.id)
  properties: {
    roleDefinitionId: azureAiUserRoleDefinition.id
    principalId: deployer().objectId
    principalType: 'User'
    description: 'Allow deployer to perfom Data actions on Foundry resource'
  }
}

@description('This is the built-in Azure AI User role. See https://learn.microsoft.com/en-us/azure/ai-foundry/concepts/rbac-azure-ai-foundry?view=foundry#azure-ai-user')
resource azureAiUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
}

output projectEndpoint string = foundry::project.properties.endpoints['AI Foundry API']
output gpt41DeploymentName string = foundry::gpt41Deployment.name
output embeddingDeploymentName string = foundry::embeddingDeployment.name
output foundryAccountName string = foundry.name
output foundryProjectName string = foundry::project.name
