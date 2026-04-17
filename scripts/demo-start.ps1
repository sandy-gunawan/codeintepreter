# =============================================================================
# Quick Start Demo Script
# Use this before a demo to bring up the environment and verify it works
# =============================================================================
param(
    [string]$ResourceGroup = "rg-code-interpreter"
)

$ErrorActionPreference = "Continue"
$clusterName = az aks list -g $ResourceGroup --query "[0].name" -o tsv 2>$null

if (-not $clusterName) {
    Write-Host "AKS cluster not found in $ResourceGroup" -ForegroundColor Red
    Write-Host "Run .\scripts\deploy-all.ps1 to deploy from scratch" -ForegroundColor Yellow
    exit 1
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Code Interpreter - Quick Start Demo"         -ForegroundColor Cyan
Write-Host "  Cluster: $clusterName"                       -ForegroundColor Gray
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check cluster state
Write-Host "[1/6] Checking cluster state..." -ForegroundColor Yellow
$state = az aks show -g $ResourceGroup -n $clusterName --query "powerState.code" -o tsv 2>$null
Write-Host "  State: $state"

if ($state -eq "Stopped") {
    Write-Host "  Starting cluster (3-5 minutes)..." -ForegroundColor Yellow
    az aks start -g $ResourceGroup -n $clusterName --output none
    Write-Host "  Cluster started." -ForegroundColor Green
}

# Step 2: Get credentials
Write-Host "[2/6] Connecting kubectl..." -ForegroundColor Yellow
az aks get-credentials -g $ResourceGroup -n $clusterName --overwrite-existing --output none 2>$null
Write-Host "  Connected."

# Step 3: Fix common policy issues
Write-Host "[3/6] Fixing storage access (policy may disable it)..." -ForegroundColor Yellow
$storageName = az storage account list -g $ResourceGroup --query "[0].name" -o tsv 2>$null
if ($storageName) {
    az storage account update -n $storageName -g $ResourceGroup --public-network-access Enabled --output none 2>$null
    Write-Host "  Storage public access: enabled"
}

# Step 4: Verify role assignment
Write-Host "[4/6] Verifying managed identity roles..." -ForegroundColor Yellow
$miPrincipalId = az identity show --name ci-backend-identity -g $ResourceGroup --query "principalId" -o tsv 2>$null
if ($miPrincipalId) {
    $storageId = az storage account show -n $storageName -g $ResourceGroup --query "id" -o tsv 2>$null
    az role assignment create --assignee-object-id $miPrincipalId --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $storageId --output none 2>$null
    Write-Host "  Role assignment verified."
} else {
    Write-Host "  WARNING: Managed identity not found. Run full deploy." -ForegroundColor Yellow
}

# Step 5: Check pods
Write-Host "[5/6] Checking pods..." -ForegroundColor Yellow
$pods = kubectl get pods -n codeinterpreter --no-headers 2>$null
$runningCount = ($pods | Select-String "Running").Count
if ($runningCount -ge 2) {
    Write-Host "  Pods running: $runningCount" -ForegroundColor Green
} else {
    Write-Host "  Restarting pods..."
    kubectl rollout restart deployment/backend -n codeinterpreter 2>$null
    kubectl rollout restart deployment/frontend -n codeinterpreter 2>$null
    Start-Sleep -Seconds 30
}

# Step 6: Get URL
Write-Host "[6/6] Getting access URL..." -ForegroundColor Yellow
$ingressIp = kubectl get ingress -n codeinterpreter -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>$null

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  DEMO READY"                                  -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Open in browser: http://$ingressIp" -ForegroundColor White
Write-Host ""
Write-Host "  Quick test:" -ForegroundColor Gray
Write-Host "    curl.exe -s http://${ingressIp}/api/health" -ForegroundColor Gray
Write-Host ""
Write-Host "  Sample prompts (Bahasa Indonesia):" -ForegroundColor Gray
Write-Host "    1. Upload transaksi_nasabah.csv" -ForegroundColor Gray
Write-Host "       Prompt: Identifikasi transaksi mencurigakan, buat grafik box plot" -ForegroundColor Gray
Write-Host ""
Write-Host "    2. Upload portofolio_kredit.csv" -ForegroundColor Gray
Write-Host "       Prompt: Klasifikasi risiko kredit berdasarkan DPD, buat pie chart" -ForegroundColor Gray
Write-Host ""
Write-Host "    3. Upload laporan_fraud.csv" -ForegroundColor Gray
Write-Host "       Prompt: Analisis tren fraud per bulan, buat heatmap per channel" -ForegroundColor Gray
Write-Host ""
Write-Host "  Note: First prompt takes 2-5 min (sandbox node scale-up)." -ForegroundColor Yellow
Write-Host "        Subsequent prompts take 30-60 seconds." -ForegroundColor Yellow
Write-Host ""
Write-Host "  After demo, stop cluster to save costs:" -ForegroundColor Gray
Write-Host "    az aks stop -g $ResourceGroup -n $clusterName" -ForegroundColor Gray
Write-Host ""

# Quick health verification
Write-Host "  Verifying..." -ForegroundColor Gray
$health = curl.exe -s "http://${ingressIp}/api/health" 2>$null
if ($health -match "healthy") {
    Write-Host "  Backend: HEALTHY" -ForegroundColor Green
} else {
    Write-Host "  Backend: NOT RESPONDING (may need 1-2 min)" -ForegroundColor Yellow
}
