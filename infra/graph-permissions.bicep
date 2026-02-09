extension graphV1

targetScope = 'resourceGroup'

@description('Service principal ID of the SharePoint app registration')
param sharepointAppServicePrincipalId string

// ---------------------------------------------------------------------------
// Microsoft Graph app role assignments for the SharePoint app registration
// Files.Read.All and Sites.Read.All on Microsoft Graph
// ---------------------------------------------------------------------------

// Microsoft Graph service principal (well-known appId: 00000003-0000-0000-c000-000000000000)
resource microsoftGraph 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000003-0000-0000-c000-000000000000'
}

@description('Graph Files.Read.All role (https://learn.microsoft.com/en-us/graph/permissions-reference#filesreadall)')
resource filesReadAllAssignment 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  appRoleId: '01d4889c-1287-42c6-ac1f-5d1e02578ef6'
  principalId: sharepointAppServicePrincipalId
  resourceId: microsoftGraph.id
}

@description('Graph Sites.Read.All role (https://learn.microsoft.com/en-us/graph/permissions-reference#sitesreadall)')
resource sitesReadAllAssignment 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  appRoleId: '332a536c-c7ef-4017-ab91-336970924f0d'
  principalId: sharepointAppServicePrincipalId
  resourceId: microsoftGraph.id
}
