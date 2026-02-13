targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources but AI Foundry.')
param location string

@minLength(1)
@description('SharePoint Online site URL (e.g. https://contoso.sharepoint.com/sites/mysite)')
param sharepointSiteUrl string

#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(resourceGroup().id, environmentName, location))

var tags = {
  'azd-env-name': environmentName
}

module foundryModule 'foundry.bicep' = {
  name: 'foundry'
  params: {
    resourceToken: resourceToken
    location: location
    appInsightsName: monitoringModule.outputs.appInsightsName
    tags: tags
    environmentName: environmentName
  }
}

module searchModule 'search.bicep' = {
  name: 'search'
  params: {
    resourceToken: resourceToken
    location: location
    tags: tags
    foundryAccountName: foundryModule.outputs.foundryAccountName
    foundryProjectName: foundryModule.outputs.foundryProjectName
  }
}

module graphPermissionsModule 'graph-permissions.bicep' = {
  name: 'graph-permissions'
  params: {
    sharepointAppServicePrincipalId: sharepointAppModule.outputs.servicePrincipalId
  }
}

module sharepointAppModule 'sharepoint-app.bicep' = {
  name: 'sharepoint-app'
  params: {
    searchSystemIdentityPrincipalId: searchModule.outputs.searchSystemIdentityPrincipalId
    environmentName: environmentName
  }
}

module monitoringModule 'monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

module containerAppModule 'container-app.bicep' = {
  name: 'container-app'
  params: {
    resourceToken: resourceToken
    location: location
    tags: tags
    logAnalyticsWorkspaceName: monitoringModule.outputs.lawName
  }
}

output PROJECT_ENDPOINT string = foundryModule.outputs.projectEndpoint
output MODEL_DEPLOYMENT string = foundryModule.outputs.gpt41DeploymentName
output EMBEDDING_DEPLOYMENT string = foundryModule.outputs.embeddingDeploymentName
output AZURE_RESOURCE_GROUP string = resourceGroup().name
output SEARCH_SERVICE_NAME string = searchModule.outputs.searchServiceName
output SEARCH_SERVICE_ENDPOINT string = searchModule.outputs.searchServiceEndpoint
output SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID string = searchModule.outputs.searchSystemIdentityPrincipalId
output SHAREPOINT_APP_ID string = sharepointAppModule.outputs.appId
output AZURE_TENANT_ID string = tenant().tenantId
output SHAREPOINT_SITE_URL string = sharepointSiteUrl
output CONTAINER_APP_NAME string = containerAppModule.outputs.containerAppName
output CONTAINER_APP_URL string = containerAppModule.outputs.containerAppUrl
output ACR_NAME string = containerAppModule.outputs.acrName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerAppModule.outputs.acrLoginServer
