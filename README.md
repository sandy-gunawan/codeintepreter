# Code Interpreter Platform

Secure, end-to-end Code Interpreter platform for banking data analysis using AKS Pod Sandboxing (Kata Containers / microVM isolation).

## Architecture

```
[ User / Analyst ]
        |
        v
[ Next.js UI (Upload + Chat) ]
        |
        v
[ FastAPI Orchestrator ]  <-- LLM Adapter --> [ Azure OpenAI gpt-4.1 ]
        |                                      (Southeast Asia)
        v
[ AKS Sandbox Pod (Kata/microVM) ]
        |                          
        v                          
[ Azure Blob Storage ]              
  (Indonesia Central)              
```

## Components

| Component | Tech | Location |
|-----------|------|----------|
| Frontend | Next.js 14 + Tailwind | Indonesia Central (AKS) |
| Backend API | Python FastAPI | Indonesia Central (AKS) |
| Sandbox | Python 3.11 + Kata VM Isolation | Indonesia Central (AKS) |
| LLM | Azure OpenAI gpt-4.1 | Southeast Asia |
| Storage | Azure Blob Storage | Indonesia Central |
| Registry | Azure Container Registry | Indonesia Central |
| Monitoring | Log Analytics + Container Insights | Indonesia Central |

## Prerequisites

1. **Azure CLI** >= 2.60.0
2. **kubectl**
3. **Docker** (for building images)
4. **jq** (for JSON parsing in scripts)
5. Azure subscription with:
   - Resource providers registered (see below)
   - Azure OpenAI access approved
   - Sufficient VM quota for DSv3 family in Indonesia Central

### Resource Provider Registration

```bash
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.OperationalInsights
```

### Check VM Quota

```bash
az vm list-usage --location indonesiacentral -o table | grep -i "Standard DSv3"
```

## Quick Start

### One-Command Deploy (Linux/macOS/WSL)

```bash
bash scripts/deploy-all.sh
```

### One-Command Deploy (Windows PowerShell)

```powershell
.\scripts\deploy-all.ps1
```

### Step-by-Step Deploy

```bash
# 1. Validate prerequisites
bash scripts/preflight-check.sh

# 2. Deploy infrastructure (AKS, ACR, Storage, OpenAI, etc.)
bash scripts/deploy-infra.sh

# 3. Build images and deploy to AKS
bash scripts/deploy-apps.sh
```

### Configuration

Override defaults via environment variables:

```bash
export RESOURCE_GROUP="my-rg"
export PRIMARY_LOCATION="indonesiacentral"
export OPENAI_LOCATION="southeastasia"
export ENVIRONMENT="dev"
export BASE_NAME="codeinterp"
bash scripts/deploy-all.sh
```

## Project Structure

```
├── infra/                          # Bicep IaC
│   ├── main.bicep                  # Entry point
│   └── modules/
│       ├── aks.bicep               # AKS + sandbox node pool
│       ├── acr.bicep               # Container Registry
│       ├── openai.bicep            # Azure OpenAI + gpt-4.1
│       ├── storage.bicep           # Blob Storage
│       └── monitoring.bicep        # Log Analytics
├── src/
│   ├── backend/                    # FastAPI orchestrator
│   │   ├── app/
│   │   │   ├── main.py             # App entry
│   │   │   ├── config.py           # Settings
│   │   │   ├── orchestrator.py     # LLM + sandbox coordination
│   │   │   ├── sandbox.py          # K8s Job management
│   │   │   ├── storage.py          # Blob Storage client
│   │   │   ├── llm/provider.py     # LLM adapter (Azure OpenAI)
│   │   │   └── routes/             # API endpoints
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   ├── frontend/                   # Next.js chat UI
│   │   ├── src/
│   │   │   ├── app/page.tsx        # Main chat page
│   │   │   ├── components/         # React components
│   │   │   └── lib/api.ts          # API client
│   │   ├── Dockerfile
│   │   └── package.json
│   └── sandbox/                    # Sandbox executor
│       ├── executor.py             # Code execution engine
│       └── Dockerfile
├── k8s/                            # Kubernetes manifests
│   ├── namespaces.yaml
│   ├── rbac.yaml
│   ├── sandbox-networkpolicy.yaml
│   └── app-deployment.yaml
├── scripts/                        # Deployment automation
│   ├── preflight-check.sh
│   ├── deploy-infra.sh
│   ├── deploy-apps.sh
│   ├── deploy-all.sh
│   └── deploy-all.ps1
├── sample-data/                    # Banking sample datasets
│   ├── transactions.csv
│   ├── loans.csv
│   └── branches.csv
└── requirement.md                  # Original requirements
```

## Security Model

| Zone | Components | Credentials |
|------|-----------|-------------|
| **Trusted** | UI, Orchestrator API, LLM calls | OpenAI key, Storage key, K8s SA |
| **Untrusted** | Sandbox pods (Kata VM) | Storage connection string only (scoped) |

### Sandbox Isolation

- **Runtime**: Kata VM Isolation (separate kernel per pod)
- **Network**: All egress blocked except Azure Blob Storage (port 443)
- **Metadata**: Azure IMDS (169.254.169.254) blocked
- **Resources**: 1 CPU / 1Gi memory limit, 5-minute timeout
- **Identity**: No service account token, no managed identity
- **Lifecycle**: Ephemeral — auto-deleted 5 minutes after completion

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| POST | `/api/upload` | Upload dataset (CSV/XLSX) |
| POST | `/api/chat` | Send prompt, get analysis |

## Sample Use Cases

Upload `sample-data/transactions.csv` and try:
- "Identify unusual transactions"
- "Show transactions above normal daily spending"
- "Plot transaction amounts by account"

Upload `sample-data/loans.csv` and try:
- "Which loans are high risk?"
- "Group risk by sector"
- "Show DPD distribution by region"

## Extending the LLM Provider

To add a new LLM backend (e.g., AWS Bedrock):

1. Create a new class in `src/backend/app/llm/provider.py` implementing `LLMProvider`
2. Register it in the `get_llm_provider()` factory
3. Set `LLM_PROVIDER=<name>` environment variable

## Known Limitations

- No authentication (Entra ID integration planned)
- Azure OpenAI gpt-4.1 only available via Global Standard in Southeast Asia (not Indonesia Central)
- Microsoft Defender for Containers does not scan Kata pods
- Sandbox IOPS ~60-70% of standard containers due to hypervisor overhead
