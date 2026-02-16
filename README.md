# Foundry IQ – SharePoint Demo

End-to-end demo that deploys [Foundry IQ](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/what-is-foundry-iq) on Azure to build an agentic retrieval knowledge base over **SharePoint Online** content. Users can then query their SharePoint documents through a GPT-4.1-powered agent that respects per-user SharePoint permissions.

## Prerequisites

> **Permissions are the main blocker** — make sure these are sorted before running `azd up`.

| Requirement | Why |
|---|---|
| **Azure subscription** | Owner / Contributor to create resource groups & resources |
| **Azure Developer CLI (`azd`)** | [Install](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) — drives provisioning & deployment |
| **Entra ID privileges** | Ability to create App Registrations, grant **admin consent** for MS Graph `Files.Read.All` + `Sites.Read.All`, and add federated credentials |
| **SharePoint Online (M365)** | Same Entra tenant as the Azure subscription |

## Repo Structure

```
├── infra/                  # Bicep IaC — all Azure resources
│   ├── main.bicep          #   Orchestrator (Foundry, Search, Container App, Monitoring, Entra app)
│   ├── foundry.bicep       #   AI Foundry account + project + GPT-4.1 deployment
│   ├── search.bicep        #   Azure AI Search (+ managed identities)
│   ├── sharepoint-app.bicep#   Entra app registration + federated credential
│   ├── container-app.bicep #   Container App (hosts the enrich-snippet skill)
│   ├── graph-permissions.bicep # MS Graph API permission grants
│   └── monitoring.bicep    #   Log Analytics + App Insights
├── enrich-snippet/         # FastAPI custom Web API Skill (Container App)
│   └── app.py              #   Prepends [Page X] to PDF snippets for the search indexer
├── hooks/
│   ├── postdeploy.sh       #   Creates the Foundry IQ knowledge source + knowledge base
│   └── predown.sh          #   Cleanup on `azd down`
├── test/                   # Test data generators
├── run_foundryiq_agent.ipynb # Notebook to query the KB via a Foundry agent
└── azure.yaml              # azd project definition
```

## Architecture

```
Azure AI Foundry  ──►  Azure AI Search  ──►  SharePoint Online
   (GPT-4.1)         (Knowledge Base +       (indexed via federated
                       managed identity)       credential — passwordless)
                            │
                    Container App
                   (enrich-snippet skill)
```

**Flow:** `azd up` provisions all infrastructure, deploys the Container App, then the `postdeploy` hook calls the Search Management API to create an **indexed** SharePoint knowledge source and knowledge base. The search indexer crawls SharePoint using a federated credential on the Entra app registration (no secrets).

## Quick Start

```bash
azd auth login
azd up          # provisions infra + creates knowledge base
```

`azd up` will prompt for the SharePoint site URL and Azure region.

## References

- [What is Foundry IQ](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/what-is-foundry-iq)
- [Index SharePoint data with managed identity](https://learn.microsoft.com/en-us/azure/search/search-how-to-index-sharepoint-online)
- [Create a remote SharePoint knowledge source](https://learn.microsoft.com/en-us/azure/search/agentic-knowledge-source-how-to-sharepoint-remote)
- [Create a knowledge base in Azure AI Search](https://learn.microsoft.com/en-us/azure/search/agentic-retrieval-how-to-create-knowledge-base)
- [Foundry IQ](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/what-is-foundry-iq)
