#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Post-provision hook - creates a Foundry IQ indexed SharePoint knowledge source
# and knowledge base on the deployed Azure AI Search service.
#
# Required azd environment variables (set automatically by Bicep outputs):
#   SEARCH_SERVICE_ENDPOINT
#   MODEL_DEPLOYMENT
#   PROJECT_ENDPOINT
#
# Auto-populated from Bicep outputs:
#   SHAREPOINT_APP_ID          - Entra app registration Application (client) ID (created by sharepoint-app.bicep)
#   AZURE_TENANT_ID            - Entra tenant ID
#   SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID - search service system MI principal ID
#
# Required user-supplied environment variables:
#   SHAREPOINT_SITE_URL        - SharePoint Online site URL (e.g. https://contoso.sharepoint.com/sites/mysite)
#
# Authentication: Uses federated identity credential on the Entra app registration
#   linked to the search service's system-assigned managed identity (passwordless).
#
# Optional overrides:
#   SHAREPOINT_CONTAINER       - which libraries to index: defaultSiteLibrary | allSiteLibraries | useQuery (default: defaultSiteLibrary)
#   SHAREPOINT_QUERY           - file filter when containerName=useQuery (e.g. "*.docx OR *.pdf")
#   KNOWLEDGE_SOURCE_NAME      - name of the knowledge source  (default: sharepoint-ks)
#   KNOWLEDGE_BASE_NAME        - name of the knowledge base    (default: sharepoint-kb)
# ---------------------------------------------------------------------------
set -euo pipefail

echo "==> Setting up Foundry IQ indexed SharePoint knowledge base…"

# ---------- resolve values from azd env ----------
SEARCH_ENDPOINT="${SEARCH_SERVICE_ENDPOINT:?'SEARCH_SERVICE_ENDPOINT is required'}"
MODEL_DEPLOY="${MODEL_DEPLOYMENT:?'MODEL_DEPLOYMENT is required'}"
EMBEDDING_DEPLOY="${EMBEDDING_DEPLOYMENT:?'EMBEDDING_DEPLOYMENT is required'}"
PROJECT_EP="${PROJECT_ENDPOINT:?'PROJECT_ENDPOINT is required'}"

# SharePoint connection parameters
SP_SITE_URL="${SHAREPOINT_SITE_URL:-}"
SP_APP_ID="${SHAREPOINT_APP_ID:?'SHAREPOINT_APP_ID is required - should be set automatically by Bicep'}"
SP_TENANT_ID="${AZURE_TENANT_ID:?'AZURE_TENANT_ID is required - should be set automatically by Bicep'}"

if [[ -z "$SP_SITE_URL" ]]; then
  echo ""
  echo "  ⏭️  Skipping knowledge source/base creation - SHAREPOINT_SITE_URL not set yet."
  echo "     Set it with:"
  echo "       azd env set SHAREPOINT_SITE_URL https://contoso.sharepoint.com/sites/mysite"
  echo "     Then re-run: azd up  (or: azd hooks run postprovision)"
  echo ""
  exit 0
fi

# Derive the Azure OpenAI / Foundry endpoint from the project endpoint
# PROJECT_ENDPOINT looks like: https://foundry-<token>.services.ai.azure.com/api/projects/demo-project
AOAI_ENDPOINT="${PROJECT_EP%%/api/*}"
# The OpenAI endpoint uses a different subdomain than the AI Services endpoint
AOAI_OPENAI_ENDPOINT="${AOAI_ENDPOINT/.services.ai.azure.com/.openai.azure.com}"

KS_NAME="${KNOWLEDGE_SOURCE_NAME:-sharepoint-ks}"
KB_NAME="${KNOWLEDGE_BASE_NAME:-sharepoint-kb}"
SP_CONTAINER="${SHAREPOINT_CONTAINER:-allSiteLibraries}"
SP_QUERY="${SHAREPOINT_QUERY:-}"
API_VERSION="2025-11-01-preview"

# Build the SharePoint connection string (passwordless - system-assigned managed identity via federated credential)
# FederatedCredentialObjectId = the search service's system-assigned managed identity principal ID
SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID="${SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID:?'SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID is required'}"
SP_CONNECTION_STRING="SharePointOnlineEndpoint=${SP_SITE_URL};ApplicationId=${SP_APP_ID};FederatedCredentialObjectId=${SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID};TenantId=${SP_TENANT_ID}"

# ---------- acquire an access token for Azure AI Search ----------
TOKEN=$(az account get-access-token --resource "https://search.azure.com" --query accessToken -o tsv)

echo "  Search endpoint : $SEARCH_ENDPOINT"
echo "  SharePoint site : $SP_SITE_URL"
echo "  Container       : $SP_CONTAINER"
echo "  Knowledge source: $KS_NAME"
echo "  Knowledge base  : $KB_NAME"

# ---------- 1. Create / update the indexed SharePoint knowledge source ----------
echo "==> Creating indexed SharePoint knowledge source '${KS_NAME}'…"

KS_BODY=$(cat <<EOF
{
  "name": "${KS_NAME}",
  "kind": "indexedSharePoint",
  "description": "Indexed SharePoint knowledge source - crawls and indexes SharePoint content",
  "indexedSharePointParameters": {
    "connectionString": "${SP_CONNECTION_STRING}",
    "containerName": "${SP_CONTAINER}",
    "query": "${SP_QUERY}",
    "ingestionParameters": {
      "aiServices": {
        "uri": "${AOAI_ENDPOINT}"
      },
      "embeddingModel": {
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "${AOAI_ENDPOINT}",
          "deploymentId": "${EMBEDDING_DEPLOY}",
          "modelName": "text-embedding-3-large"
        }
      },
      "chatCompletionModel": {
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "${AOAI_ENDPOINT}",
          "deploymentId": "${MODEL_DEPLOY}",
          "modelName": "gpt-4.1"
        }
      },
      "contentExtractionMode": "standard",
      "ingestionSchedule": {
        "interval": "P1D"
      }
    }
  }
}
EOF
)

KS_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${SEARCH_ENDPOINT}/knowledgesources/${KS_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${KS_BODY}")

KS_HTTP_CODE=$(echo "$KS_RESPONSE" | tail -1)
KS_RESPONSE_BODY=$(echo "$KS_RESPONSE" | sed '$d')

if [[ "$KS_HTTP_CODE" -ge 200 && "$KS_HTTP_CODE" -lt 300 ]]; then
  echo "  ✅ Knowledge source '${KS_NAME}' created/updated (HTTP ${KS_HTTP_CODE})"
else
  echo "  ⚠️  Knowledge source creation returned HTTP ${KS_HTTP_CODE}:"
  echo "  ${KS_RESPONSE_BODY}"
  echo "  (This is expected if the preview feature is not yet enabled - see README.md)"
fi

# ---------- 2. Create / update the knowledge base ----------
echo "==> Creating knowledge base '${KB_NAME}'…"

KB_BODY=$(cat <<EOF
{
  "name": "${KB_NAME}",
  "description": "Foundry IQ knowledge base backed by indexed SharePoint content",
  "retrievalInstructions": "Use the SharePoint knowledge source to answer questions about documents stored in SharePoint.",
  "answerInstructions": "Provide concise, informative answers based on the retrieved SharePoint documents. Cite sources.",
  "outputMode": "extractiveData",
  "knowledgeSources": [
    {
      "name": "${KS_NAME}"
    }
  ],
  "models": [
    {
      "kind": "azureOpenAI",
      "azureOpenAIParameters": {
        "resourceUri": "${AOAI_OPENAI_ENDPOINT}",
        "deploymentId": "${MODEL_DEPLOY}",
        "modelName": "gpt-4.1"
      }
    }
  ],
  "retrievalReasoningEffort": {
    "kind": "minimal"
  }
}
EOF
)

KB_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${SEARCH_ENDPOINT}/knowledgebases/${KB_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${KB_BODY}")

KB_HTTP_CODE=$(echo "$KB_RESPONSE" | tail -1)
KB_RESPONSE_BODY=$(echo "$KB_RESPONSE" | sed '$d')

if [[ "$KB_HTTP_CODE" -ge 200 && "$KB_HTTP_CODE" -lt 300 ]]; then
  echo "  ✅ Knowledge base '${KB_NAME}' created/updated (HTTP ${KB_HTTP_CODE})"
else
  echo "  ⚠️  Knowledge base creation returned HTTP ${KB_HTTP_CODE}:"
  echo "  ${KB_RESPONSE_BODY}"
  echo "  (This is expected if the preview feature is not yet enabled - see README.md)"
fi

# ---------- 3. Create / update the KB MCP connection on the Foundry project ----------
# This connection lets agents in the Foundry portal discover the knowledge base as a
# tool.  We use authType=ProjectManagedIdentity so the agent runtime authenticates
# to the search service's KB MCP endpoint using the project's system-assigned MI.
# The Bicep grants the project MI "Search Index Data Reader" and "Search Service
# Contributor" roles on the search service.
echo "==> Creating KB MCP connection on Foundry project…"

# Derive Foundry account & project names from PROJECT_ENDPOINT
# PROJECT_ENDPOINT = https://foundry-<token>.services.ai.azure.com/api/projects/<project>
FOUNDRY_HOST="${PROJECT_EP#https://}"
FOUNDRY_HOST="${FOUNDRY_HOST%%.*}"          # foundry-<token>
FOUNDRY_ACCOUNT_NAME="${FOUNDRY_HOST}"
FOUNDRY_PROJECT_NAME="${PROJECT_EP##*/}"    # demo-project

SUB_ID=$(az account show --query id -o tsv)
ARM_TOKEN=$(az account get-access-token --resource "https://management.azure.com" --query accessToken -o tsv)

SEARCH_NAME="${SEARCH_SERVICE_NAME:?'SEARCH_SERVICE_NAME is required'}"
CONNECTION_NAME="kb-${KB_NAME}"

MCP_BODY=$(cat <<EOF
{
  "properties": {
    "authType": "ProjectManagedIdentity",
    "audience": "https://search.azure.com",
    "category": "RemoteTool",
    "group": "GenericProtocol",
    "target": "https://${SEARCH_NAME}.search.windows.net/knowledgebases/${KB_NAME}/mcp?api-version=2025-11-01-Preview",
    "isSharedToAll": false,
    "useWorkspaceManagedIdentity": false,
    "isDefault": true,
    "metadata": {
      "type": "knowledgeBase_MCP",
      "knowledgeBaseName": "${KB_NAME}"
    }
  }
}
EOF
)

MCP_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT_NAME}/projects/${FOUNDRY_PROJECT_NAME}/connections/${CONNECTION_NAME}?api-version=2025-04-01-preview" \
  -H "Authorization: Bearer ${ARM_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${MCP_BODY}")

MCP_HTTP_CODE=$(echo "$MCP_RESPONSE" | tail -1)
MCP_RESPONSE_BODY=$(echo "$MCP_RESPONSE" | sed '$d')

if [[ "$MCP_HTTP_CODE" -ge 200 && "$MCP_HTTP_CODE" -lt 300 ]]; then
  echo "  ✅ KB MCP connection '${CONNECTION_NAME}' created/updated (HTTP ${MCP_HTTP_CODE})"
else
  echo "  ⚠️  KB MCP connection creation returned HTTP ${MCP_HTTP_CODE}:"
  echo "  ${MCP_RESPONSE_BODY}"
fi

# ---------- 4. Clean up auto-created duplicate KB MCP connections ----------
# The Foundry platform sometimes auto-creates a duplicate RemoteTool connection
# with authType=ProjectManagedIdentity and a random suffix (e.g. kb-sharepoint-kb-vb95b).
# This duplicate can confuse the portal agent. Delete any KB MCP connections that
# are NOT the one we just created.
echo "==> Checking for duplicate KB MCP connections…"

CONNECTIONS_BASE="https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT_NAME}/projects/${FOUNDRY_PROJECT_NAME}/connections"

DUPLICATES=$(curl -s "${CONNECTIONS_BASE}?api-version=2025-04-01-preview" \
  -H "Authorization: Bearer ${ARM_TOKEN}" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data.get('value', []):
    p = c.get('properties', {})
    name = c.get('name', '')
    meta_type = p.get('metadata', {}).get('type', '')
    kb_name = p.get('metadata', {}).get('knowledgeBaseName', '')
    if meta_type == 'knowledgeBase_MCP' and kb_name == '${KB_NAME}' and name != '${CONNECTION_NAME}':
        print(name)
" 2>/dev/null)

if [[ -n "$DUPLICATES" ]]; then
  while IFS= read -r dup_name; do
    echo "  🗑️  Deleting duplicate KB MCP connection '${dup_name}'…"
    curl -s -o /dev/null -w "  HTTP %{http_code}\n" -X DELETE \
      "${CONNECTIONS_BASE}/${dup_name}?api-version=2025-04-01-preview" \
      -H "Authorization: Bearer ${ARM_TOKEN}"
  done <<< "$DUPLICATES"
else
  echo "  ✅ No duplicates found"
fi

echo ""
echo "==> Done."
echo "    The indexed SharePoint knowledge source will begin crawling content on the configured schedule (daily)."
echo "    Query the knowledge base at:"
echo "    POST ${SEARCH_ENDPOINT}/knowledgebases/${KB_NAME}/retrieval?api-version=${API_VERSION}"
