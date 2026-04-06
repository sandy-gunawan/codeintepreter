
End-to-End Code Interpreter Platform (Sandbox Pods)

Target audience: Engineering agent / team (GHCP)
Industry: Banking (Indonesia)
Goal: Build an end-to-end, secure Code Interpreter platform using sandbox pods (microVM / Kata Containers on AKS), with a UI for data upload, LLM-driven reasoning, and configurable LLM backend (Azure now, extensible to AWS / others later).




1. High-Level Objectives

Provide Code Interpreter–like functionality (run Python on uploaded data, generate results, charts, insights).
Ensure strong isolation for untrusted / LLM-generated code using sandbox pods (microVMs).
Support banking-grade security and Indonesia data residency.
Deliver an end-to-end solution: Frontend (UI)
Backend (orchestration + LLM)
Sandbox execution layer
Storage & audit
Make the LLM backend configurable (Azure LLM now, pluggable later).


2. Architecture Overview (Logical)
[ User / Analyst ]
        |
        v
[ Web UI (Upload + Chat) ]
        |
        v
[ Orchestrator API ]  <---- Configurable LLM Adapter ----> [ LLM Provider ]
        |                                               (Azure now, others later)
        |
        v
[ Sandbox Execution Service ]
  (AKS Pod Sandboxing - Kata / microVM)
        |
        v
[ Object Storage + Logs + Audit ]


Key separation of trust

Trusted zone: UI, Orchestrator, LLM calls
Untrusted zone: Code execution (sandbox pods)


3. Core Components
3.1 Frontend / UI
Purpose: Allow users (bank analysts) to upload data and interact with the Code Interpreter.
Key features:

Secure login (bank SSO / Entra ID – integration later)
File upload (CSV, XLSX)
Chat-style interface ("Ask questions about my data")
Display: Tables
Charts (PNG)
Text explanations
Tech suggestion (example, not mandatory):

React / Next.js
HTTPS only


3.2 Orchestrator API (Control Plane)
Role: Brain of the system.
Responsibilities:

Receive user prompt + uploaded file reference
Call LLM for reasoning and tool decision
Decide when to invoke code execution
Send code + data reference to sandbox service
Collect execution output
Ask LLM to generate final explanation
Important:

This service owns credentials (LLM keys)
Sandbox pods do NOT have LLM credentials


3.3 LLM Adapter (Configurable)
Goal: Avoid lock-in.
Design:

Define a common interface:
interface LLMProvider {
  generate(prompt: string, context: object): LLMResponse;
}


Initial implementation:

Azure-hosted LLM
Future implementations:

AWS Bedrock
Other providers
Why:

Banking clients want flexibility
Region / cost / regulation may change


3.4 Sandbox Execution Layer (Critical)
Purpose: Execute LLM-generated Python code safely.
Implementation choice:

AKS Pod Sandboxing (Kata Containers)
Each execution runs in a microVM-backed pod
Characteristics:

Separate kernel per pod
Strong isolation from host & other pods
Short-lived (ephemeral)
Sandbox pod responsibilities:

Fetch input data from object storage
Execute Python code
Generate: stdout / stderr
output files (CSV, PNG)
Upload results back to storage
Explicit restrictions:

No cloud credentials
Limited or no outbound internet
CPU / memory / time limits


3.5 Storage & Audit
Object storage:

Uploaded datasets
Execution outputs
Audit logs:

User ID
Prompt
Code executed
Execution time & status
Reason:

Required for banking compliance
Incident investigation


4. Security & Compliance (Banking – Indonesia)
4.1 Data Residency

All data stored and processed in Indonesia Azure region (where possible)
Sandbox execution happens inside same Azure environment
4.2 Isolation Model

Why microVM (Kata): Containers alone share kernel (not sufficient)
MicroVM adds kernel boundary
4.3 Least Privilege

Sandbox pods: No secrets
No managed identity
Read/write only to specific storage path


5. End-to-End Flow

User logs into UI
User uploads dataset (e.g., CSV)
User asks a question
Orchestrator: Sends prompt to LLM
LLM decides to run code
Orchestrator sends code + dataset reference to sandbox pod
Sandbox pod executes code
Results stored
Orchestrator asks LLM to explain results
UI displays insights + charts


6. Banking Use Cases (Sample Data Included)
Use Case 1: Transaction Anomaly Detection
Scenario:

Retail banking transactions
Sample data:
transaction_id,account_id,amount,merchant,channel,date
T001,A123,150000,Tokopedia,Online,2025-01-02
T002,A123,8500000,Unknown,Online,2025-01-03
T003,A123,200000,Indomaret,Offline,2025-01-03


User questions:

"Identify unusual transactions"
"Show transactions above normal daily spending"
Interpreter actions:

Calculate mean / std dev
Flag outliers
Plot transaction amounts


Use Case 2: Loan Portfolio Risk Analysis
Scenario:

SME loan monitoring
Sample data:
loan_id,customer_id,loan_amount,dpd,sector,region
L001,C001,500000000,0,Manufacturing,Jakarta
L002,C002,300000000,45,Retail,Bandung
L003,C003,800000000,90,Construction,Surabaya


User questions:

"Which loans are high risk?"
"Group risk by sector"
Interpreter actions:

Risk classification
Aggregation
Bar chart by sector


Use Case 3: Branch Performance Analysis
Scenario:

Branch KPI review
Sample data:
branch_id,city,monthly_revenue,new_accounts,complaints
B001,Jakarta,1200000000,320,5
B002,Medan,650000000,210,12
B003,Surabaya,900000000,250,8


User questions:

"Compare branch performance"
"Which branch has service quality issues?"
Interpreter actions:

KPI normalization
Ranking
Visualization


7. Future Extensions

Swap LLM provider via adapter
Add prompt / code evaluation
Integrate with bank DWH (read-only)
Replace sandbox with managed Foundry Code Interpreter when available


8. Summary
This design:

Delivers Code Interpreter capability without Foundry
Uses microVM sandbox pods for strong isolation
Meets banking & Indonesia compliance needs
Is end-to-end and future-proof
This document is ready to be handed to an engineering agent (GHCP) for implementation.
