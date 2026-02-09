# Foundry IQ – SharePoint Knowledge Base (Managed Identity)

This project deploys an **Azure AI Foundry** project with an **Azure AI Search**
service connected to **SharePoint Online** via a **managed identity** (secretless
authentication). It uses the [Foundry IQ](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/what-is-foundry-iq)
agentic retrieval pipeline to create a knowledge base backed by SharePoint content.

## Architecture

```
┌──────────────────────────────┐
│  Azure AI Foundry (AI Svcs)  │
│  ├─ Project: demo-project    │
│  │  └─ Connection → AI Search│
│  └─ GPT-4.1 deployment       │
└───────────┬──────────────────┘
            │ Cognitive Services User
┌───────────▼──────────────────┐
│  Azure AI Search  (Basic)    │
│  ├─ System-assigned MI       │
│  ├─ User-assigned MI ────────┼──► Federated credential on Entra app
│  ├─ Knowledge Source (SPO)   │
│  └─ Knowledge Base           │
└──────────────────────────────┘
            │ Copilot Retrieval API (on behalf of user)
┌───────────▼──────────────────┐
│  SharePoint Online (M365)    │
└──────────────────────────────┘
```

## Prerequisites

| Requirement | Details |
|---|---|
| Azure subscription | With permissions to create resources |
| Azure Developer CLI (`azd`) | [Install](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) |
| SharePoint in Microsoft 365 | Same Entra tenant as the Azure subscription |
| Tenant admin consent | Required for the Entra app registration |
| Microsoft Copilot license | Required for the Copilot Retrieval API used by remote SharePoint knowledge sources |

## Quick Start

```bash
# 1. Log in
azd auth login

# 2. Provision infrastructure + create knowledge base objects
azd up
```

After `azd up` completes, you **must** complete the manual Entra ID app
registration steps below before SharePoint content is accessible.

## Manual Steps – Entra ID App Registration

The managed identity alone cannot access SharePoint. You need a **Microsoft Entra
application registration** configured with a **federated credential** pointing to
the user-assigned managed identity deployed by this project.

### Step 1 – Create the app registration

1. Go to the [Azure portal → Microsoft Entra ID → App registrations](https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/RegisteredApps).
2. Click **+ New registration**.
   - **Name**: e.g. `foundryiq-sharepoint-indexer`
   - **Supported account types**: Single tenant
   - **Redirect URI**: leave blank
3. Click **Register**.

### Step 2 – Add API permissions

1. In the app registration, go to **API permissions → Add a permission → Microsoft Graph**.
2. Choose **Application permissions**.
3. Add:
   - `Files.Read.All`
   - `Sites.Read.All`
4. Click **Grant admin consent for [your tenant]**.

### Step 3 – Configure authentication

1. Go to the **Authentication** tab.
2. Set **Allow public client flows** to **Yes**.
3. Click **Save**.

### Step 4 – Add a federated credential (managed identity)

This is the key step from [the documentation](https://learn.microsoft.com/en-us/azure/search/search-how-to-index-sharepoint-online#configuring-the-registered-application-with-a-managed-identity).

1. In the app registration, go to **Certificates & Secrets → Federated credentials**.
2. Click **+ Add credential**.
3. Under **Federated credential scenario**, select **Managed Identity**.
4. **Select managed identity**: Choose the user-assigned managed identity deployed
   by this project. It is named `id-search-<token>` (you can find the exact name
   in the `azd` output as `SEARCH_IDENTITY_NAME`).
5. Add a **Name** for the credential (e.g. `search-managed-identity`).
6. Click **Save**.

### Step 5 – Note the values you'll need

From the app registration **Overview** page, copy:
- **Application (client) ID** → this is the `ApplicationId`
- **Directory (tenant) ID** → this is the `TenantId`

From the `azd` outputs (or Azure portal):
- **`SEARCH_IDENTITY_PRINCIPAL_ID`** → this is the `FederatedCredentialObjectId`

### Step 6 – (If using a SharePoint indexer) Create the data source

If you want to index SharePoint content into a search index (rather than using
the remote SharePoint knowledge source), create a data source with the secretless
connection string:

```
SharePointOnlineEndpoint=https://yourcompany.sharepoint.com/sites/YourSite;ApplicationId=<app-id>;FederatedCredentialObjectId=<managed-identity-principal-id>;TenantId=<tenant-id>
```

## Environment Variables

After `azd up`, these variables are set in your azd environment:

| Variable | Description |
|---|---|
| `SEARCH_SERVICE_NAME` | Name of the Azure AI Search service |
| `SEARCH_SERVICE_ENDPOINT` | HTTPS endpoint of the search service |
| `SEARCH_IDENTITY_NAME` | Name of the user-assigned managed identity |
| `SEARCH_IDENTITY_PRINCIPAL_ID` | Object (principal) ID of the managed identity – use as `FederatedCredentialObjectId` |
| `SEARCH_IDENTITY_CLIENT_ID` | Client ID of the managed identity |
| `SEARCH_IDENTITY_RESOURCE_ID` | Full ARM resource ID of the managed identity |
| `PROJECT_ENDPOINT` | Foundry project endpoint |
| `MODEL_DEPLOYMENT` | Name of the GPT-4.1 deployment |

## Querying the Knowledge Base

Once the Entra app is configured and admin consent is granted, you can query the
knowledge base. The remote SharePoint knowledge source calls the Copilot Retrieval
API **on behalf of the calling user**, so users only see content they have access to
in SharePoint.

```python
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.core.credentials import AzureKeyCredential
from azure.search.documents.knowledgebases import KnowledgeBaseRetrievalClient
from azure.search.documents.knowledgebases.models import (
    KnowledgeBaseMessage,
    KnowledgeBaseMessageTextContent,
    KnowledgeBaseRetrievalRequest,
    RemoteSharePointKnowledgeSourceParams,
)

# Get user access token for SharePoint
identity_token_provider = get_bearer_token_provider(
    DefaultAzureCredential(), "https://search.azure.com/.default"
)
token = identity_token_provider()

kb_client = KnowledgeBaseRetrievalClient(
    endpoint="<SEARCH_SERVICE_ENDPOINT>",
    knowledge_base_name="sharepoint-kb",
    credential=DefaultAzureCredential(),
)

request = KnowledgeBaseRetrievalRequest(
    include_activity=True,
    messages=[
        KnowledgeBaseMessage(
            role="user",
            content=[KnowledgeBaseMessageTextContent(text="What are the latest project updates?")]
        )
    ],
    knowledge_source_params=[
        RemoteSharePointKnowledgeSourceParams(
            knowledge_source_name="sharepoint-ks",
            include_references=True,
            include_reference_source_data=True,
        )
    ],
)

result = kb_client.retrieve(retrieval_request=request, x_ms_query_source_authorization=token)
print(result.response[0].content[0].text)
```

## Optional: Customize SharePoint Filtering

Set the `SHAREPOINT_FILTER` environment variable before running `azd up` to scope
which SharePoint content is queried:

```bash
# Filter to a specific site
azd env set SHAREPOINT_FILTER 'Path:"https://mycompany.sharepoint.com/sites/Engineering"'

# Filter to specific file types
azd env set SHAREPOINT_FILTER 'FileExtension:"docx" OR FileExtension:"pdf"'

azd up
```

## References

- [Index data from SharePoint document libraries](https://learn.microsoft.com/en-us/azure/search/search-how-to-index-sharepoint-online)
- [Configuring the registered application with a managed identity](https://learn.microsoft.com/en-us/azure/search/search-how-to-index-sharepoint-online#configuring-the-registered-application-with-a-managed-identity)
- [Create a remote SharePoint knowledge source](https://learn.microsoft.com/en-us/azure/search/agentic-knowledge-source-how-to-sharepoint-remote)
- [Create a knowledge base in Azure AI Search](https://learn.microsoft.com/en-us/azure/search/agentic-retrieval-how-to-create-knowledge-base)
- [Foundry IQ](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/what-is-foundry-iq)
