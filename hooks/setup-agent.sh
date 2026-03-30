#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Foundry setup — creates the KB MCP connection, cleans up duplicates,
# and deploys the prompt agent with the KB tool.
#
# Called by postdeploy.sh.  Expects all environment variables to be set.
# ---------------------------------------------------------------------------
set -euo pipefail

# ── 1. KB MCP connection ─────────────────────────────────────────────────
echo "==> Creating KB MCP connection…"

FOUNDRY_HOST="${PROJECT_EP#https://}"
FOUNDRY_HOST="${FOUNDRY_HOST%%.*}"
FOUNDRY_ACCOUNT_NAME="${FOUNDRY_HOST}"
FOUNDRY_PROJECT_NAME="${PROJECT_EP##*/}"

SUB_ID=$(az account show --query id -o tsv)
ARM_TOKEN=$(az account get-access-token --resource "https://management.azure.com" --query accessToken -o tsv)
RG="${AZURE_RESOURCE_GROUP:?'AZURE_RESOURCE_GROUP is required'}"
CONNECTION_NAME="kb-${KB_NAME}"

CONNECTIONS_BASE="https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT_NAME}/projects/${FOUNDRY_PROJECT_NAME}/connections"

MCP_BODY=$(cat <<EOF
{
  "properties": {
    "authType": "ProjectManagedIdentity",
    "audience": "https://search.azure.com",
    "category": "RemoteTool",
    "group": "GenericProtocol",
    "target": "https://${SEARCH_NAME}.search.windows.net/knowledgebases/${KB_NAME}/mcp?api-version=${API_VERSION}",
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
  "${CONNECTIONS_BASE}/${CONNECTION_NAME}?api-version=2025-04-01-preview" \
  -H "Authorization: Bearer ${ARM_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${MCP_BODY}")

MCP_HTTP_CODE=$(echo "$MCP_RESPONSE" | tail -1)
if [[ "$MCP_HTTP_CODE" -ge 200 && "$MCP_HTTP_CODE" -lt 300 ]]; then
  echo "  ✅ MCP connection '${CONNECTION_NAME}' (HTTP ${MCP_HTTP_CODE})"
else
  echo "  ⚠️  HTTP ${MCP_HTTP_CODE}: $(echo "$MCP_RESPONSE" | sed '$d')"
fi

# ── 2. Clean up duplicate connections ─────────────────────────────────────
DUPLICATES=$(curl -s "${CONNECTIONS_BASE}?api-version=2025-04-01-preview" \
  -H "Authorization: Bearer ${ARM_TOKEN}" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data.get('value', []):
    p = c.get('properties', {})
    name = c.get('name', '')
    if p.get('metadata', {}).get('type') == 'knowledgeBase_MCP' \
       and p.get('metadata', {}).get('knowledgeBaseName') == '${KB_NAME}' \
       and name != '${CONNECTION_NAME}':
        print(name)
" 2>/dev/null)

if [[ -n "$DUPLICATES" ]]; then
  while IFS= read -r dup_name; do
    echo "  🗑️  Deleting duplicate '${dup_name}'…"
    curl -s -o /dev/null -w "  HTTP %{http_code}\n" -X DELETE \
      "${CONNECTIONS_BASE}/${dup_name}?api-version=2025-04-01-preview" \
      -H "Authorization: Bearer ${ARM_TOKEN}"
  done <<< "$DUPLICATES"
fi

# ── 3. Deploy prompt agent ────────────────────────────────────────────────
AGENT_NAME="${AGENT_NAME:-foundryiq-sharepoint-agent}"
AGENT_DESC="${AGENT_DESCRIPTION:-HR SharePoint agent using Foundry IQ KB via MCP}"
INSTRUCTIONS_FILE="${SCRIPT_DIR}/../agent/instructions.txt"

if [[ ! -f "$INSTRUCTIONS_FILE" ]]; then
  echo "  ⚠️  ${INSTRUCTIONS_FILE} not found — skipping agent deployment."
else
  echo "==> Deploying agent '${AGENT_NAME}'…"
  pip install -q "azure-ai-projects>=2.0.0b1" 2>/dev/null

  python3 - "${PROJECT_EP}" "${MODEL_DEPLOY}" "${CONNECTION_NAME}" \
             "${AGENT_NAME}" "${AGENT_DESC}" "${INSTRUCTIONS_FILE}" << 'PYEOF'
import sys
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import MCPTool, PromptAgentDefinition

project_endpoint, model, conn_name, agent_name, agent_desc, instr_file = sys.argv[1:7]

with open(instr_file) as f:
    instructions = f.read().strip()

credential = DefaultAzureCredential()
client = AIProjectClient(endpoint=project_endpoint, credential=credential)

kb_conn = client.connections.get(conn_name)
print(f"  KB MCP URL : {kb_conn.target}")
print(f"  Connection : {kb_conn.id}")

mcp_tool = MCPTool(
    server_label="kb_" + conn_name.replace("-", "_"),
    server_url=kb_conn.target,
    require_approval="never",
    project_connection_id=kb_conn.id,
)

agent = client.agents.create_version(
    agent_name=agent_name,
    definition=PromptAgentDefinition(
        model=model,
        instructions=instructions,
        tools=[mcp_tool],
    ),
    description=agent_desc,
)
print(f"  ✅ Agent '{agent.name}' deployed (version {agent.version})")
PYEOF

  if [[ $? -ne 0 ]]; then
    echo "  ⚠️  Agent deployment failed — create it manually in the Foundry portal."
  fi
fi

echo "==> Foundry setup complete."
