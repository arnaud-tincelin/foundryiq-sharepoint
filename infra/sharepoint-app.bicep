extension graphV1

targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@description('Object (principal) ID of the search service system-assigned managed identity')
param searchSystemIdentityPrincipalId string

// ---------------------------------------------------------------------------
// Entra App Registration for SharePoint indexer
// Uses federated identity credential so the search service's system MI can
// authenticate to SharePoint without a client secret.
// ---------------------------------------------------------------------------
resource sharepointApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: 'SharePoint Indexer for Foundry IQ - ${environmentName}'
  uniqueName: 'foundryiq-sharepoint-indexer-${environmentName}'
  // Request Sites.Selected permission (application type) on Microsoft Graph
  // This must be admin-consented after deployment.
  requiredResourceAccess: [
    {
      resourceAppId: '00000003-0000-0000-c000-000000000000' // Microsoft Graph
      resourceAccess: [
        // {
        //   id: '883ea226-0bf2-4a8f-9f9d-92c9162a727d' // Sites.Selected (Application)
        //   type: 'Role'
        // }
        {
          id: '01d4889c-1287-42c6-ac1f-5d1e02578ef6' // Files.Read.All (Application)
          type: 'Role'
        }
        {
          id: '332a536c-c7ef-4017-ab91-336970924f0d' // Sites.Read.All (Application)
          type: 'Role'
        }
      ]
    }
  ]

  resource federatedCredential 'federatedIdentityCredentials' = {
    name: '${sharepointApp.uniqueName}/search-system-mi'
    description: 'Allows the AI Search system-assigned managed identity to act as this app'
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
    subject: searchSystemIdentityPrincipalId
  }
}

// Service principal for the app registration (required for it to be usable)
resource sharepointAppServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: sharepointApp.appId
}

output appId string = sharepointApp.appId
output appObjectId string = sharepointApp.id
output servicePrincipalId string = sharepointAppServicePrincipal.id
