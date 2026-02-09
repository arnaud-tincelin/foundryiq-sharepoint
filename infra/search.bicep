targetScope = 'resourceGroup'

param resourceToken string

@description('Main location for the resources')
param location string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Name of the AI Foundry account to connect the search service to')
param foundryAccountName string

@description('Name of the AI Foundry project to connect the search service to')
param foundryProjectName string

@description('Name of the Foundry IQ knowledge base on the search service')
var knowledgeBaseName string = 'sharepoint-kb'

// ---------------------------------------------------------------------------
// Azure AI Search - Basic tier (minimum for managed identity + agentic retrieval)
// ---------------------------------------------------------------------------
resource search 'Microsoft.Search/searchServices@2025-05-01' = {
  name: 'search-${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hostingMode: 'Default'
    publicNetworkAccess: 'Enabled'
    partitionCount: 1
    replicaCount: 1
    semanticSearch: 'standard'
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Role assignments
// ---------------------------------------------------------------------------

// Allow the AI Foundry account's system identity to access the search service
// as "Search Index Data Reader" so the knowledge base can retrieve results.
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' existing = {
  name: foundryAccountName

  resource project 'projects' existing = {
    name: foundryProjectName
  }
}

@description('Search Index Data Reader - allows reading index data')
resource searchIndexDataReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
}

@description('Search Service Contributor - allows managing search service objects')
resource searchServiceContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
}

@description('Cognitive Services User - allows the search service to call the deployed model')
resource cognitiveServicesUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'a97b65f3-24c7-4388-baec-2e87135dc908'
}

// Search service system identity → Cognitive Services User on the Foundry account
// (so the knowledge base can call the GPT model for query planning / answer synthesis)
resource searchCanCallFoundryModel 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccount
  name: guid(foundryAccount.id, search.id, cognitiveServicesUserRole.id)
  properties: {
    roleDefinitionId: cognitiveServicesUserRole.id
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Allow AI Search to call GPT models on Foundry for knowledge base reasoning'
  }
}

// Foundry account system identity → Search Index Data Reader on the search service
// (so the agent can authenticate to the KB MCP endpoint and read index data)
resource foundryCanReadSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, foundryAccount.id, searchIndexDataReaderRole.id)
  properties: {
    roleDefinitionId: searchIndexDataReaderRole.id
    principalId: foundryAccount.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Allow Foundry account to read search index data (agent → KB MCP)'
  }
}

// Foundry account system identity → Search Service Contributor on the search service
// (so the agent can access knowledge bases and knowledge sources)
resource foundryCanManageSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, foundryAccount.id, searchServiceContributorRole.id)
  properties: {
    roleDefinitionId: searchServiceContributorRole.id
    principalId: foundryAccount.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Allow Foundry account to access search service objects (agent → KB MCP)'
  }
}

// Foundry PROJECT system identity → Search Index Data Reader on the search service
// The portal agent uses the project's managed identity (ProjectManagedIdentity auth)
// to call the KB MCP endpoint. This is a different identity from the account.
resource projectCanReadSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, foundryAccount::project.id, searchIndexDataReaderRole.id)
  properties: {
    roleDefinitionId: searchIndexDataReaderRole.id
    principalId: foundryAccount::project.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Allow Foundry project MI to read search index data (agent → KB MCP)'
  }
}

// Foundry PROJECT system identity → Search Service Contributor on the search service
resource projectCanManageSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, foundryAccount::project.id, searchServiceContributorRole.id)
  properties: {
    roleDefinitionId: searchServiceContributorRole.id
    principalId: foundryAccount::project.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Allow Foundry project MI to manage search objects (agent → KB MCP)'
  }
}

// Current deployer → Search Service Contributor (so post-deploy script can create KB objects)
resource deployerIsSearchContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, deployer().objectId, searchServiceContributorRole.id)
  properties: {
    roleDefinitionId: searchServiceContributorRole.id
    principalId: deployer().objectId
    principalType: 'User'
    description: 'Allow deployer to manage search service objects (knowledge sources, knowledge bases, indexes)'
  }
}

// Current deployer → Search Index Data Reader (so post-deploy script can query)
resource deployerCanReadSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, deployer().objectId, searchIndexDataReaderRole.id)
  properties: {
    roleDefinitionId: searchIndexDataReaderRole.id
    principalId: deployer().objectId
    principalType: 'User'
    description: 'Allow deployer to read search index data'
  }
}

// ---------------------------------------------------------------------------
// Connection from Foundry project → AI Search
// ---------------------------------------------------------------------------
resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview' = {
  parent: foundryAccount::project
  name: 'search-connection'
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${search.name}.search.windows.net'
    authType: 'AAD'
    isSharedToAll: false
    metadata: {
      type: 'azure_ai_search'
      ApiType: 'Azure'
      ResourceId: search.id
      ApiVersion: '2025-11-01-preview'
    }
  }
}

// ---------------------------------------------------------------------------
// KB MCP connection (RemoteTool / knowledgeBase_MCP) — created in postdeploy.sh
// ---------------------------------------------------------------------------
// This connection is NOT managed by Bicep because:
// 1. It uses authType=ProjectManagedIdentity with group=GenericProtocol — Bicep
//    doesn't reliably set `group` on this resource type.
// 2. The Foundry platform may auto-create a duplicate connection when it detects
//    a KB on a connected search service; the postdeploy hook handles cleanup.
// See hooks/postdeploy.sh steps 3 & 4.

output searchServiceName string = search.name
output searchServiceEndpoint string = 'https://${search.name}.search.windows.net'
output searchSystemIdentityPrincipalId string = search.identity.principalId
