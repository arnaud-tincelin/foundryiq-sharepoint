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

# ---------- 0. Container App is deployed by azd (services.enrich-snippet) ----------
ACR_NAME="${ACR_NAME:?'ACR_NAME is required - should be set by Bicep output'}"
CONTAINER_APP_NAME="${CONTAINER_APP_NAME:?'CONTAINER_APP_NAME is required - should be set by Bicep output'}"
CONTAINER_APP_URL="${CONTAINER_APP_URL:?'CONTAINER_APP_URL is required - should be set by Bicep output'}"
RG="${AZURE_RESOURCE_GROUP:?'AZURE_RESOURCE_GROUP is required'}"

echo "  ✅ Container App deployed by azd: ${CONTAINER_APP_URL}"

echo "  Search endpoint : $SEARCH_ENDPOINT"
echo "  SharePoint site : $SP_SITE_URL"
echo "  Container       : $SP_CONTAINER"
echo "  Knowledge source: $KS_NAME"
echo "  Knowledge base  : $KB_NAME"

# ---------- 1. Create / update the indexed SharePoint knowledge source ----------
# Check if the KS already exists first - re-PUTting would fail if the index has
# extra fields (like page_number) that aren't in the KS schema.
echo "==> Checking for existing knowledge source '${KS_NAME}'…"

KS_CHECK_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "${SEARCH_ENDPOINT}/knowledgesources/${KS_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}")

if [[ "$KS_CHECK_CODE" -eq 200 ]]; then
  echo "  ✅ Knowledge source '${KS_NAME}' already exists - skipping creation"
else
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
      "contentExtractionMode": "standard",
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
fi

# ---------- 1b. Patch the index, skillset & indexer ----------
# - Add a Custom Web API Skill (Container App) to prepend [Page X] to snippets
#   inline during indexing — works automatically for new documents
# - Use metadata_spo_item_weburi for doc_url (real SharePoint web URL)
INDEX_NAME="${KS_NAME}-index"
INDEXER_NAME="${KS_NAME}-indexer"
SKILLSET_NAME="${KS_NAME}-skillset"

# Resolve the Container App URL for the Custom Web API Skill
CONTAINER_URL="${CONTAINER_APP_URL:?'CONTAINER_APP_URL is required - should be set by Bicep output'}"
SKILL_URI="${CONTAINER_URL}/api/enrich_snippet"
echo "  Container App URL: ${CONTAINER_URL}"

echo "==> Patching index '${INDEX_NAME}' to add page_number field…"

# Wait for the index to be created by the knowledge source (may take a moment)
for i in {1..12}; do
  IDX_CHECK_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${SEARCH_ENDPOINT}/indexes/${INDEX_NAME}?api-version=${API_VERSION}" \
    -H "Authorization: Bearer ${TOKEN}")
  if [[ "$IDX_CHECK_CODE" -eq 200 ]]; then
    break
  fi
  echo "  Waiting for index to be created (attempt $i/12)…"
  sleep 10
done

if [[ "$IDX_CHECK_CODE" -ne 200 ]]; then
  echo "  ⚠️  Index '${INDEX_NAME}' not found (HTTP ${IDX_CHECK_CODE}) — skipping index/skillset/indexer patches."
  echo "     The knowledge source may not have been created. Re-run: azd hooks run postprovision"
  exit 0
fi

CURRENT_INDEX=$(curl -s "${SEARCH_ENDPOINT}/indexes/${INDEX_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}")

PATCHED_INDEX=$(echo "$CURRENT_INDEX" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for key in list(data.keys()):
    if key.startswith('@odata'):
        del data[key]
existing = {f['name'] for f in data.get('fields', [])}
new_fields = []
if 'page_number' not in existing:
    new_fields.append({
        'name': 'page_number', 'type': 'Edm.Int32',
        'searchable': False, 'filterable': True, 'retrievable': True,
        'stored': True, 'sortable': True, 'facetable': False, 'key': False
    })
# Remove doc_web_url if it exists (no longer needed - doc_url now gets web URLs directly)
data['fields'] = [f for f in data['fields'] if f['name'] != 'doc_web_url']
if new_fields:
    data['fields'].extend(new_fields)
    print(json.dumps(data))
else:
    print('SKIP')
")

if [[ "$PATCHED_INDEX" != "SKIP" ]]; then
  IDX_RESP=$(curl -s -w "\n%{http_code}" -X PUT \
    "${SEARCH_ENDPOINT}/indexes/${INDEX_NAME}?api-version=${API_VERSION}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PATCHED_INDEX}")
  IDX_CODE=$(echo "$IDX_RESP" | tail -1)
  if [[ "$IDX_CODE" -ge 200 && "$IDX_CODE" -lt 300 ]]; then
    echo "  ✅ Index fields updated (HTTP ${IDX_CODE})"
  else
    echo "  ⚠️  Index patch returned HTTP ${IDX_CODE}: $(echo "$IDX_RESP" | sed '$d')"
  fi
else
  echo "  ✅ All fields already exist in index"
fi

# Patch the skillset:
# - Enable locationMetadata on ContentUnderstandingSkill (provides pageNumberFrom)
# - Add Custom Web API Skill (Container App) to prepend "[Page X] " to snippets
# - Update snippet projection to use enriched output from the custom skill
echo "==> Patching skillset '${SKILLSET_NAME}' (WebApiSkill + locationMetadata)…"

CURRENT_SKILLSET=$(curl -s "${SEARCH_ENDPOINT}/skillsets/${SKILLSET_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}")

PATCHED_SKILLSET=$(echo "$CURRENT_SKILLSET" | SKILL_URI="$SKILL_URI" python3 -c "
import sys, json, os
data = json.load(sys.stdin)
skill_uri = os.environ['SKILL_URI']

for key in list(data.keys()):
    if key.startswith('@odata') and key != '@odata.type':
        del data[key]

changed = False

# --- 0. Enable locationMetadata on ContentUnderstandingSkill ---
# Without this, text_sections do NOT include pageNumberFrom/pageNumberTo.
for s in data.get('skills', []):
    if s.get('@odata.type', '').endswith('ContentUnderstandingSkill'):
        opts = s.get('extractionOptions') or []
        if 'locationMetadata' not in opts:
            opts.append('locationMetadata')
            s['extractionOptions'] = opts
            changed = True

# --- 1. Remove old ConditionalSkill if present (replaced by WebApiSkill) ---
before = len(data.get('skills', []))
data['skills'] = [s for s in data.get('skills', []) if s.get('name') != 'enrichSnippetWithPage']
if len(data['skills']) < before:
    changed = True

# --- 2. Add or update Custom Web API Skill ---
existing_skill = next((s for s in data['skills'] if s.get('name') == 'enrichSnippetWebApi'), None)
web_api_skill = {
    '@odata.type': '#Microsoft.Skills.Custom.WebApiSkill',
    'name': 'enrichSnippetWebApi',
    'context': '/document/text_sections/*',
    'uri': skill_uri,
    'httpMethod': 'POST',
    'timeout': 'PT30S',
    'batchSize': 100,
    'inputs': [
        {'name': 'content', 'source': '/document/text_sections/*/content'},
        {'name': 'pageNumber', 'source': '/document/text_sections/*/locationMetadata/pageNumberFrom'}
    ],
    'outputs': [
        {'name': 'enriched_snippet', 'targetName': 'enriched_snippet'}
    ]
}
if existing_skill:
    # Update URI (function key may have changed)
    if existing_skill.get('uri') != skill_uri:
        idx = data['skills'].index(existing_skill)
        data['skills'][idx] = web_api_skill
        changed = True
else:
    data['skills'].append(web_api_skill)
    changed = True

# --- 3. Update index projections ---
for sel in data.get('indexProjections', {}).get('selectors', []):
    if sel.get('sourceContext', '').endswith('/text_sections/*'):
        # Remove page_number mapping if present - page numbers are already
        # embedded in the enriched_snippet by the WebApiSkill, and referencing
        # locationMetadata/pageNumberFrom directly in a projection causes
        # the entire ?map to fail for text_sections that lack that path.
        before_len = len(sel.get('mappings', []))
        sel['mappings'] = [m for m in sel.get('mappings', []) if m['name'] != 'page_number']
        if len(sel['mappings']) < before_len:
            changed = True

        # Update snippet mapping to use enriched_snippet from WebApiSkill
        for m in sel['mappings']:
            if m['name'] == 'snippet' and m['source'] != '/document/text_sections/*/enriched_snippet':
                m['source'] = '/document/text_sections/*/enriched_snippet'
                changed = True

if changed:
    print(json.dumps(data))
else:
    print('SKIP')
")

if [[ "$PATCHED_SKILLSET" != "SKIP" ]]; then
  SK_RESP=$(curl -s -w "\n%{http_code}" -X PUT \
    "${SEARCH_ENDPOINT}/skillsets/${SKILLSET_NAME}?api-version=${API_VERSION}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PATCHED_SKILLSET}")
  SK_CODE=$(echo "$SK_RESP" | tail -1)
  if [[ "$SK_CODE" -ge 200 && "$SK_CODE" -lt 300 ]]; then
    echo "  ✅ Skillset updated with WebApiSkill (HTTP ${SK_CODE})"
  else
    echo "  ⚠️  Skillset patch returned HTTP ${SK_CODE}: $(echo "$SK_RESP" | sed '$d')"
  fi
else
  echo "  ✅ Skillset already has WebApiSkill"
fi

# Patch the indexer:
# - Use metadata_spo_item_weburi for doc_url (real SharePoint web URL instead of
#   the Graph drive path from metadata_spo_item_path). This eliminates the need
#   for post-indexing Graph API backfill.
echo "==> Patching indexer '${INDEXER_NAME}' to use metadata_spo_item_weburi…"

CURRENT_INDEXER=$(curl -s "${SEARCH_ENDPOINT}/indexers/${INDEXER_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}")

PATCHED_INDEXER=$(echo "$CURRENT_INDEXER" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for key in list(data.keys()):
    if key.startswith('@odata'):
        del data[key]
# Replace metadata_spo_item_path with metadata_spo_item_weburi for doc_url
for m in data.get('fieldMappings', []):
    if m.get('targetFieldName') == 'doc_url' and m.get('sourceFieldName') == 'metadata_spo_item_path':
        m['sourceFieldName'] = 'metadata_spo_item_weburi'
# Remove any doc_web_url mapping (no longer needed)
data['fieldMappings'] = [m for m in data.get('fieldMappings', []) if m.get('targetFieldName') != 'doc_web_url']
print(json.dumps(data))
")

IXER_RESP=$(curl -s -w "\n%{http_code}" -X PUT \
  "${SEARCH_ENDPOINT}/indexers/${INDEXER_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PATCHED_INDEXER}")
IXER_CODE=$(echo "$IXER_RESP" | tail -1)
if [[ "$IXER_CODE" -ge 200 && "$IXER_CODE" -lt 300 ]]; then
  echo "  ✅ Indexer updated to use metadata_spo_item_weburi (HTTP ${IXER_CODE})"
else
  echo "  ⚠️  Indexer patch returned HTTP ${IXER_CODE}: $(echo "$IXER_RESP" | sed '$d')"
fi

# Reset and re-run the indexer so all documents are freshly indexed
echo "==> Resetting and re-running indexer '${INDEXER_NAME}'…"
curl -s -o /dev/null -X POST "${SEARCH_ENDPOINT}/indexers/${INDEXER_NAME}/reset?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Length: 0"
sleep 2
curl -s -o /dev/null -X POST "${SEARCH_ENDPOINT}/indexers/${INDEXER_NAME}/run?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Length: 0"
echo "  ✅ Indexer reset and re-run triggered"

# Wait for the indexer to finish
echo "==> Waiting for indexer to complete…"
for i in $(seq 1 30); do
  sleep 5
  INDEXER_STATUS=$(curl -s "${SEARCH_ENDPOINT}/indexers/${INDEXER_NAME}/status?api-version=${API_VERSION}" \
    -H "Authorization: Bearer ${TOKEN}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
r = data.get('lastResult', {})
print(r.get('status', 'unknown'))
" 2>/dev/null)
  if [[ "$INDEXER_STATUS" == "success" || "$INDEXER_STATUS" == "transientFailure" ]]; then
    echo "  ✅ Indexer finished (status: ${INDEXER_STATUS})"
    break
  fi
  echo "    … still running (attempt ${i}/30)"
done

# ---------- 2. Create / update the knowledge base ----------
echo "==> Creating knowledge base '${KB_NAME}'…"

KB_BODY=$(cat <<EOF
{
  "name": "${KB_NAME}",
  "description": "Foundry IQ knowledge base backed by indexed SharePoint content",
  "retrievalInstructions": "Use the SharePoint knowledge source to answer questions about documents stored in SharePoint. Always retrieve the doc_url, page_number, and snippet fields for each chunk.",
  "answerInstructions": "Provide concise, informative answers. Each snippet starts with [Page X] indicating the source page number. Use this to cite pages accurately.",
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
