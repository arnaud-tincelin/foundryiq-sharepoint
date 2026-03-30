#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Post-provision hook — thin orchestrator that calls:
#   1. setup-search.sh  (knowledge source, index templates, indexer, KB)
#   2. setup-agent.sh   (MCP connection, duplicate cleanup, prompt agent)
#
# Required azd env vars (set by Bicep):  SEARCH_SERVICE_ENDPOINT,
#   SEARCH_SERVICE_NAME, MODEL_DEPLOYMENT, EMBEDDING_DEPLOYMENT,
#   PROJECT_ENDPOINT, SHAREPOINT_APP_ID, AZURE_TENANT_ID,
#   SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID
#
# Required user-supplied:  SHAREPOINT_SITE_URL
#
# Optional:  SHAREPOINT_CONTAINER, SHAREPOINT_QUERY,
#   KNOWLEDGE_SOURCE_NAME, KNOWLEDGE_BASE_NAME,
#   AGENT_NAME, AGENT_DESCRIPTION
# ---------------------------------------------------------------------------
set -euo pipefail

export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Setting up Foundry IQ indexed SharePoint knowledge base…"

# ── Resolve & export shared variables ─────────────────────────────────────
export SEARCH_ENDPOINT="${SEARCH_SERVICE_ENDPOINT:?required}"
export SEARCH_NAME="${SEARCH_SERVICE_NAME:?required}"
export MODEL_DEPLOY="${MODEL_DEPLOYMENT:?required}"
export EMBEDDING_DEPLOY="${EMBEDDING_DEPLOYMENT:?required}"
export PROJECT_EP="${PROJECT_ENDPOINT:?required}"
export SP_APP_ID="${SHAREPOINT_APP_ID:?required}"
export SP_TENANT_ID="${AZURE_TENANT_ID:?required}"
export SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID="${SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID:?required}"

SP_SITE_URL="${SHAREPOINT_SITE_URL:-}"
if [[ -z "$SP_SITE_URL" ]]; then
  echo ""
  echo "  ⏭️  Skipping — SHAREPOINT_SITE_URL not set yet."
  echo "     azd env set SHAREPOINT_SITE_URL https://contoso.sharepoint.com/sites/mysite"
  echo "     azd up"
  echo ""
  exit 0
fi

export AOAI_ENDPOINT="${PROJECT_EP%%/api/*}"
export AOAI_OPENAI_ENDPOINT="${AOAI_ENDPOINT/.services.ai.azure.com/.openai.azure.com}"
export KS_NAME="${KNOWLEDGE_SOURCE_NAME:-sharepoint-ks}"
export KB_NAME="${KNOWLEDGE_BASE_NAME:-sharepoint-kb}"
export SP_CONTAINER="${SHAREPOINT_CONTAINER:-allSiteLibraries}"
export SP_QUERY="${SHAREPOINT_QUERY:-}"
export API_VERSION="2025-11-01-preview"
export SP_CONNECTION_STRING="SharePointOnlineEndpoint=${SP_SITE_URL};ApplicationId=${SP_APP_ID};FederatedCredentialObjectId=${SEARCH_SYSTEM_IDENTITY_PRINCIPAL_ID};TenantId=${SP_TENANT_ID}"

if [[ -z "$SP_QUERY" ]]; then export SP_QUERY_JSON="null"; else export SP_QUERY_JSON="\"${SP_QUERY}\""; fi

export TOKEN=$(az account get-access-token --resource "https://search.azure.com" --query accessToken -o tsv)

echo "  Search endpoint : $SEARCH_ENDPOINT"
echo "  SharePoint site : $SP_SITE_URL"
echo "  Knowledge source: $KS_NAME"
echo "  Knowledge base  : $KB_NAME"
echo ""

# ── Run sub-scripts ───────────────────────────────────────────────────────
source "${SCRIPT_DIR}/setup-search.sh"
source "${SCRIPT_DIR}/setup-agent.sh"

echo ""
echo "==> All done."
echo "    Indexer will crawl SharePoint content on a daily schedule."
echo "    Agent '${AGENT_NAME}' is ready in the Foundry portal."
