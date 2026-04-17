# Code Interpreter Platform

Secure, end-to-end Code Interpreter platform for banking data analysis using AKS Pod Sandboxing (Kata Containers / microVM isolation).

## How to Run the Demo

```powershell
# 1. From your laptop PowerShell — start the platform (1-5 min):
cd C:\labs\tech\codeintepreter
.\scripts\demo-start.ps1

# 2. Open the printed URL in any browser:
#    http://<ip-address>

# 3. Upload a CSV file and ask a question. Examples:
#    - Upload transaksi_nasabah.csv → "Identifikasi transaksi mencurigakan, buat grafik"
#    - Upload portofolio_kredit.csv → "Klasifikasi risiko kredit berdasarkan DPD"
#    - Upload laporan_fraud.csv     → "Analisis tren fraud per bulan, buat heatmap"

# 4. After demo — stop cluster to save costs:
az aks stop -g rg-code-interpreter -n codeinterp-aks-smnjwoou2sgh6
```

> **Your laptop is only needed to start/stop the cluster.** Once running, anyone can access the
> platform from any browser using the URL — no installation needed on the client side.
> 
> **First analysis takes 2-5 min** (sandbox node scales from 0). Subsequent ones take 30-60 sec.

---

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

### Running the Demo (Already Deployed)

If the platform is already deployed to AKS, use the one-command demo script:

```powershell
cd C:\labs\tech\codeintepreter
.\scripts\demo-start.ps1
```

This script automatically:
- Starts the AKS cluster if stopped
- Fixes storage access (enterprise policy disables it daily)
- Verifies managed identity role assignments
- Checks pods are running
- **Prints the access URL**

After the script completes, open the printed URL in your browser (e.g. `http://<ip-address>`).

> **Note on IP address:** The Ingress IP is dynamic — it stays the same as long as the
> NGINX LoadBalancer Service exists, but may change if the cluster is redeployed.
> Always run `demo-start.ps1` or `kubectl get ingress -n codeinterpreter` to get the current IP.

After your demo, stop the cluster to save costs:
```powershell
az aks stop -g rg-code-interpreter -n codeinterp-aks-smnjwoou2sgh6
```

### Known Enterprise Policy Issues

| Issue | Symptom | Fix (automated by demo-start.ps1) |
|-------|---------|-----------------------------------|
| Storage `publicNetworkAccess` disabled daily by policy | Upload returns "Internal Server Error" / "AuthorizationFailure" | `az storage account update -n <name> --public-network-access Enabled` |
| AKS cluster auto-stopped by policy | `kubectl` returns "no such host" | `az aks start -g <rg> -n <cluster>` |
| Role assignment removed by policy | Storage returns "not authorized" | `az role assignment create` for Storage Blob Data Contributor |

All three are handled automatically by `.\scripts\demo-start.ps1`.

### First-Time Deployment (From Scratch)

```powershell
# 1. Configure your existing Azure OpenAI (copy and edit)
cp openai-config.example.ps1 openai-config.ps1
# Edit openai-config.ps1 with your endpoint, deployment name, and key

# 2. Load config and deploy everything
. .\openai-config.ps1
.\scripts\deploy-all.ps1
```

Or step-by-step:
```powershell
.\scripts\preflight-check.ps1      # Validate prerequisites
. .\openai-config.ps1
.\scripts\deploy-infra.ps1         # Deploy AKS, ACR, Storage (~10 min)
.\scripts\deploy-apps.ps1          # Build images, deploy to AKS (~5 min)
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
├── scripts/                        # Deployment & demo automation
│   ├── demo-start.ps1              # Quick start for demos (fixes policy issues)
│   ├── destroy.ps1                 # Cleanup all Azure resources
│   ├── deploy-all.ps1              # One-command full deployment
│   ├── deploy-infra.ps1            # Deploy infrastructure (Bicep)
│   ├── deploy-apps.ps1             # Build + deploy apps to AKS
│   ├── preflight-check.ps1         # Validate prerequisites
│   ├── test-e2e-live.ps1           # E2E test (English)
│   └── test-usecase-indo.ps1       # 5 use cases test (Bahasa Indonesia)
├── sample-data/                    # Banking sample datasets
│   ├── transactions.csv            # Basic transactions (15 records)
│   ├── loans.csv                   # Basic loans (12 records)
│   ├── branches.csv                # Basic branches (8 records)
│   ├── transaksi_nasabah.csv       # Transaction anomaly (150 records)
│   ├── portofolio_kredit.csv       # Loan risk analysis (120 records)
│   ├── kinerja_cabang.csv          # Branch performance (100 records)
│   ├── tabungan_deposito.csv       # Savings segmentation (130 records)
│   └── laporan_fraud.csv           # Fraud analysis (110 records)
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

### Quick Demo (English)
Upload `sample-data/transactions.csv` and try:
- "Identify unusual transactions"
- "Show transactions above normal daily spending"

### Banking Use Cases (Bahasa Indonesia — 100+ records each)

| # | Dataset | Records | Sample Prompt |
|---|---------|---------|---------------|
| 1 | `transaksi_nasabah.csv` | 150 | "Identifikasi transaksi mencurigakan, buat box plot dan bar chart" |
| 2 | `portofolio_kredit.csv` | 120 | "Klasifikasi risiko kredit berdasarkan DPD, buat pie chart dan heatmap per sektor" |
| 3 | `kinerja_cabang.csv` | 100 | "Ranking 20 cabang berdasarkan skor komposit, buat line chart tren pendapatan" |
| 4 | `tabungan_deposito.csv` | 130 | "Analisis segmentasi nasabah per produk dan usia, buat stacked bar chart" |
| 5 | `laporan_fraud.csv` | 110 | "Analisis tren fraud per bulan, buat heatmap jenis fraud vs channel" |

Run all 5 automatically: `.\scripts\test-usecase-indo.ps1 -BaseUrl "http://<ip>"`

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
- **Ingress IP is dynamic** — may change if cluster is redeployed. Always check with `kubectl get ingress -n codeinterpreter` or `demo-start.ps1`
- **Enterprise policy workarounds** — lab/sandbox subscriptions may auto-disable storage public access and stop AKS clusters daily. Run `demo-start.ps1` before each demo session to fix automatically
- First analysis after idle takes 2-5 min extra (sandbox node scale-up from 0)
