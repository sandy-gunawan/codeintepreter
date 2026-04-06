# =============================================================================
# Application Deployment Script (PowerShell Native)
# Builds Docker images, pushes to ACR, and deploys to AKS
# =============================================================================
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Load infrastructure outputs
$infraEnv = Join-Path $ProjectRoot ".env.infra.ps1"
if (-not (Test-Path $infraEnv)) {
    Write-Host "ERROR: $infraEnv not found. Run deploy-infra.ps1 first." -ForegroundColor Red
    exit 1
}
. $infraEnv

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Code Interpreter - Application Deploy"       -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ACR:     $AcrLoginServer"
Write-Host "  AKS:     $AksClusterName"
Write-Host "  Storage: $StorageAccountName"
Write-Host ""

# Step 1: Login to ACR
Write-Host "[1/6] Logging in to ACR..." -ForegroundColor Yellow
az acr login --name $AcrName --output none
Write-Host "  ACR login successful."

# Step 2: Build and push Docker images
# Tries ACR Tasks (cloud build) first, falls back to local Docker build
Write-Host "[2/6] Building Docker images..." -ForegroundColor Yellow

function Build-Image {
    param([string]$ImageName, [string]$ContextPath)
    Write-Host "  Building $ImageName..."
    # Try ACR Tasks (no local Docker needed)
    $acrBuild = az acr build --registry $AcrName --image "${ImageName}:latest" $ContextPath --no-logs --output none 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Built via ACR Tasks (cloud)."
    } else {
        # Fallback to local Docker build
        Write-Host "    ACR Tasks unavailable, building locally..."
        docker build -t "$AcrLoginServer/${ImageName}:latest" $ContextPath
        docker push "$AcrLoginServer/${ImageName}:latest"
        Write-Host "    Built and pushed via local Docker."
    }
}

Build-Image "code-interpreter-sandbox" "$ProjectRoot\src\sandbox"
Build-Image "code-interpreter-backend" "$ProjectRoot\src\backend"
Build-Image "code-interpreter-frontend" "$ProjectRoot\src\frontend"

Write-Host "  All images ready."

# Step 3: Retrieve secrets for K8s
Write-Host "[3/6] Retrieving secrets..." -ForegroundColor Yellow

# OpenAI key: use existing key from infra output, or fetch from newly created resource
if ($ExistingOpenAiKey) {
    $openAiKey = $ExistingOpenAiKey
    Write-Host "  Using existing OpenAI key."
} elseif ($OpenAiCreated) {
    $openAiResourceName = (az cognitiveservices account list --resource-group $ResourceGroup --query "[0].name" -o tsv)
    $openAiKey = (az cognitiveservices account keys list `
        --resource-group $ResourceGroup `
        --name $openAiResourceName `
        --query "key1" -o tsv)
    Write-Host "  OpenAI key retrieved from new resource."
} else {
    # Prompt user for key
    $openAiKey = Read-Host -Prompt "Enter your Azure OpenAI API key"
    if (-not $openAiKey) {
        Write-Host "ERROR: OpenAI key is required." -ForegroundColor Red
        exit 1
    }
}

# Storage uses Managed Identity (DefaultAzureCredential) — no keys needed
Write-Host "  Secrets retrieved."

# Step 4: Apply Kubernetes manifests
Write-Host "[4/6] Applying Kubernetes manifests..." -ForegroundColor Yellow

kubectl apply -f "$ProjectRoot\k8s\namespaces.yaml"
kubectl apply -f "$ProjectRoot\k8s\rbac.yaml"
kubectl apply -f "$ProjectRoot\k8s\sandbox-networkpolicy.yaml"

Write-Host "  Namespaces, RBAC, and NetworkPolicies applied."

# Step 5: Substitute placeholders and apply app deployment
Write-Host "[5/6] Deploying application..." -ForegroundColor Yellow

$appYaml = Get-Content "$ProjectRoot\k8s\app-deployment.yaml" -Raw
$appYaml = $appYaml -replace "__ACR_LOGIN_SERVER__", $AcrLoginServer
$appYaml = $appYaml -replace "__OPENAI_ENDPOINT__", $OpenAiEndpoint
$appYaml = $appYaml -replace "__OPENAI_KEY__", $openAiKey
$appYaml = $appYaml -replace "__OPENAI_DEPLOYMENT__", $OpenAiDeploymentName
$appYaml = $appYaml -replace "__STORAGE_ACCOUNT_NAME__", $StorageAccountName

$appYaml | kubectl apply -f -

Write-Host "  Application manifests applied."

# Step 6: Wait for pods to be ready
Write-Host "[6/6] Waiting for pods to be ready..." -ForegroundColor Yellow

kubectl rollout status deployment/backend -n codeinterpreter --timeout=120s 2>$null
kubectl rollout status deployment/frontend -n codeinterpreter --timeout=120s 2>$null

Write-Host ""

# Get Ingress IP
Write-Host "Waiting for Ingress external IP (may take 1-2 minutes)..."
$ingressIp = ""
for ($i = 0; $i -lt 30; $i++) {
    $ingressIp = kubectl get ingress code-interpreter-ingress -n codeinterpreter -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($ingressIp) { break }
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Application deployment complete!"             -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
if ($ingressIp) {
    Write-Host "  Access the application at: http://$ingressIp"
} else {
    Write-Host "  Ingress IP not yet available. Check with:"
    Write-Host "  kubectl get ingress -n codeinterpreter"
}
Write-Host ""
Write-Host "  Backend API:  http://$ingressIp/api/health"
Write-Host "  Frontend UI:  http://$ingressIp/"
Write-Host ""
Write-Host "  Useful commands:"
Write-Host "    kubectl get pods -n codeinterpreter"
Write-Host "    kubectl get pods -n sandbox"
Write-Host "    kubectl logs -f deployment/backend -n codeinterpreter"
Write-Host "============================================="
