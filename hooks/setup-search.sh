#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# AI Search setup — creates the knowledge source, applies custom index/
# skillset/indexer templates, runs the indexer, and creates the knowledge base.
#
# Called by postdeploy.sh.  Expects all environment variables to be set.
# ---------------------------------------------------------------------------
set -euo pipefail

TEMPLATE_DIR="${SCRIPT_DIR}/../ai-search"

# ---------- helper: render template & PUT ----------
put_resource() {
  local resource_type="$1" template_file="$2" resource_name="$3"
  echo "  PUT ${resource_type}/${resource_name}…"

  local body
  body=$(export KS_NAME SP_CONNECTION_STRING SP_CONTAINER SP_QUERY_JSON \
                AOAI_ENDPOINT MODEL_DEPLOY EMBEDDING_DEPLOY; \
         envsubst < "${TEMPLATE_DIR}/${template_file}")

  local response http_code
  response=$(curl -s -w "\n%{http_code}" -X PUT \
    "${SEARCH_ENDPOINT}/${resource_type}/${resource_name}?api-version=${API_VERSION}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${body}")
  http_code=$(echo "$response" | tail -1)

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    echo "  ✅ ${resource_name} (HTTP ${http_code})"
  else
    echo "  ❌ ${resource_name} (HTTP ${http_code}):"
    echo "  $(echo "$response" | sed '$d')"
    return 1
  fi
}

# ── 1. Knowledge source ──────────────────────────────────────────────────
echo "==> Creating knowledge source '${KS_NAME}'…"

KS_BODY=$(cat <<EOF
{
  "name": "${KS_NAME}",
  "kind": "indexedSharePoint",
  "description": "Indexed SharePoint knowledge source",
  "indexedSharePointParameters": {
    "connectionString": "${SP_CONNECTION_STRING}",
    "containerName": "${SP_CONTAINER}",
    "query": "${SP_QUERY}",
    "ingestionParameters": {
      "contentExtractionMode": "standard",
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
      "ingestionSchedule": { "interval": "P1D" },
      "aiServices": { "uri": "${AOAI_ENDPOINT}" }
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
if [[ "$KS_HTTP_CODE" -ge 200 && "$KS_HTTP_CODE" -lt 300 ]]; then
  echo "  ✅ Knowledge source created/updated (HTTP ${KS_HTTP_CODE})"
else
  echo "  ⚠️  HTTP ${KS_HTTP_CODE}: $(echo "$KS_RESPONSE" | sed '$d')"
fi

# Wait for auto-created search resources
echo "  Waiting for search resources…"
for i in $(seq 1 20); do
  sleep 3
  INDEX_COUNT=$(curl -s "${SEARCH_ENDPOINT}/indexes?api-version=${API_VERSION}&\$select=name" \
    -H "Authorization: Bearer ${TOKEN}" \
    | python3 -c "import sys,json; print(len([i for i in json.load(sys.stdin).get('value',[]) if i['name']=='${KS_NAME}-index']))" 2>/dev/null)
  if [[ "$INDEX_COUNT" -ge 1 ]]; then echo "  ✅ Resources ready"; break; fi
  echo "    … attempt ${i}/20"
done

# ── 2. Apply custom templates ────────────────────────────────────────────
echo "==> Applying custom templates…"
put_resource "indexes"   "index.json"    "${KS_NAME}-index"
put_resource "skillsets"  "skillset.json" "${KS_NAME}-skillset"
put_resource "indexers"   "indexer.json"  "${KS_NAME}-indexer"

# ── 3. Reset & run indexer ───────────────────────────────────────────────
echo "==> Running indexer '${KS_NAME}-indexer'…"
curl -s -o /dev/null -X POST \
  "${SEARCH_ENDPOINT}/indexers/${KS_NAME}-indexer/reset?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Length: 0"
sleep 2
curl -s -o /dev/null -X POST \
  "${SEARCH_ENDPOINT}/indexers/${KS_NAME}-indexer/run?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Length: 0"
echo "  ✅ Indexer triggered"

echo "  Waiting for indexer…"
for i in $(seq 1 30); do
  sleep 5
  INDEXER_STATUS=$(curl -s \
    "${SEARCH_ENDPOINT}/indexers/${KS_NAME}-indexer/status?api-version=${API_VERSION}" \
    -H "Authorization: Bearer ${TOKEN}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('lastResult',{}).get('status','unknown'))" 2>/dev/null)
  if [[ "$INDEXER_STATUS" == "success" || "$INDEXER_STATUS" == "transientFailure" ]]; then
    echo "  ✅ Indexer finished (${INDEXER_STATUS})"; break
  fi
  echo "    … attempt ${i}/30"
done

# ── 4. Knowledge base ────────────────────────────────────────────────────
echo "==> Creating knowledge base '${KB_NAME}'…"

KB_BODY=$(cat <<EOF
{
  "name": "${KB_NAME}",
  "description": "Foundry IQ knowledge base backed by indexed SharePoint content",
  "retrievalInstructions": "Use the SharePoint knowledge source to answer questions. Always retrieve doc_url, title, page_number, and snippet.",
  "answerInstructions": "Provide concise answers grounded in retrieved documents. Cite using document title, URL and page number.",
  "outputMode": "extractiveData",
  "knowledgeSources": [{ "name": "${KS_NAME}" }],
  "models": [{
    "kind": "azureOpenAI",
    "azureOpenAIParameters": {
      "resourceUri": "${AOAI_OPENAI_ENDPOINT}",
      "deploymentId": "${MODEL_DEPLOY}",
      "modelName": "gpt-4.1"
    }
  }],
  "retrievalReasoningEffort": { "kind": "minimal" }
}
EOF
)

KB_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${SEARCH_ENDPOINT}/knowledgebases/${KB_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${KB_BODY}")

KB_HTTP_CODE=$(echo "$KB_RESPONSE" | tail -1)
if [[ "$KB_HTTP_CODE" -ge 200 && "$KB_HTTP_CODE" -lt 300 ]]; then
  echo "  ✅ Knowledge base created/updated (HTTP ${KB_HTTP_CODE})"
else
  echo "  ⚠️  HTTP ${KB_HTTP_CODE}: $(echo "$KB_RESPONSE" | sed '$d')"
fi

echo "==> AI Search setup complete."
