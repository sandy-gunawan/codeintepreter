# =============================================================================
# Destroy / Cleanup Script
# Removes all Azure resources and local artifacts created by this project
# =============================================================================
param(
    [string]$ResourceGroup = $(if ($env:RESOURCE_GROUP) { $env:RESOURCE_GROUP } else { "rg-code-interpreter" }),
    [switch]$SkipAzure,
    [switch]$Force
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host "=============================================" -ForegroundColor Red
Write-Host "  Code Interpreter — DESTROY / CLEANUP"       -ForegroundColor Red
Write-Host "=============================================" -ForegroundColor Red
Write-Host ""
Write-Host "  Resource Group: $ResourceGroup"
Write-Host "  Skip Azure:     $SkipAzure"
Write-Host ""

if (-not $Force) {
    Write-Host "  This will DELETE:" -ForegroundColor Yellow
    Write-Host "    - Azure Resource Group '$ResourceGroup' and ALL resources inside" -ForegroundColor Yellow
    Write-Host "    - Local .env.infra.ps1, temp files, Docker images" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "  Type 'yes' to confirm destruction"
    if ($confirm -ne "yes") {
        Write-Host "  Aborted." -ForegroundColor Gray
        exit 0
    }
}

Write-Host ""

# ─────────────────────────────────────────────────────────
# Step 1: Delete Azure Resources
# ─────────────────────────────────────────────────────────
if (-not $SkipAzure) {
    Write-Host "[1/5] Deleting Azure resource group '$ResourceGroup'..." -ForegroundColor Yellow
    Write-Host "  This deletes: AKS, ACR, Storage, Log Analytics, Managed Identity, Role Assignments"
    Write-Host "  This may take 5-10 minutes..."

    az group delete --name $ResourceGroup --yes --no-wait 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Resource group deletion initiated (running in background)." -ForegroundColor Green
    } else {
        Write-Host "  Resource group not found or already deleted." -ForegroundColor Gray
    }

    # Also clean up federated credential if identity was created outside the RG
    Write-Host "  Cleaning up kubectl context..."
    $infraFile = Join-Path $ProjectRoot ".env.infra.ps1"
    if (Test-Path $infraFile) {
        . $infraFile
        kubectl config delete-context $AksClusterName 2>$null
        kubectl config delete-cluster $AksClusterName 2>$null
        kubectl config delete-user "clusterUser_${ResourceGroup}_${AksClusterName}" 2>$null
        Write-Host "  kubectl context removed."
    }
} else {
    Write-Host "[1/5] Skipping Azure resource deletion (--SkipAzure)" -ForegroundColor Gray
}

Write-Host ""

# ─────────────────────────────────────────────────────────
# Step 2: Remove local environment/config files
# ─────────────────────────────────────────────────────────
Write-Host "[2/5] Removing local environment files..." -ForegroundColor Yellow

$filesToRemove = @(
    ".env.infra.ps1",
    ".env.infra",
    "openai-config.ps1",
    "temp_chat.json",
    "scripts/temp_test1.json",
    "scripts/temp_test2.json",
    "scripts/temp_test3.json",
    "scripts/temp_test4.json"
)

foreach ($f in $filesToRemove) {
    $path = Join-Path $ProjectRoot $f
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Host "  Removed: $f"
    }
}

Write-Host ""

# ─────────────────────────────────────────────────────────
# Step 3: Remove build artifacts
# ─────────────────────────────────────────────────────────
Write-Host "[3/5] Removing build artifacts..." -ForegroundColor Yellow

$dirsToRemove = @(
    "src/frontend/.next",
    "src/frontend/node_modules",
    "src/backend/.venv",
    "src/backend/__pycache__",
    "src/backend/app/__pycache__",
    "src/backend/app/llm/__pycache__",
    "src/backend/app/routes/__pycache__"
)

foreach ($d in $dirsToRemove) {
    $path = Join-Path $ProjectRoot $d
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force
        Write-Host "  Removed: $d/"
    }
}

Write-Host ""

# ─────────────────────────────────────────────────────────
# Step 4: Remove local Docker images
# ─────────────────────────────────────────────────────────
Write-Host "[4/5] Removing local Docker images..." -ForegroundColor Yellow

$images = @("code-interpreter-sandbox", "code-interpreter-backend", "code-interpreter-frontend", "test-fe", "ci-sandbox-test")
foreach ($img in $images) {
    $existing = docker images --format "{{.Repository}}:{{.Tag}}" 2>$null | Select-String $img
    if ($existing) {
        foreach ($match in $existing) {
            docker rmi $match.ToString() --force 2>$null | Out-Null
            Write-Host "  Removed image: $match"
        }
    }
}

Write-Host ""

# ─────────────────────────────────────────────────────────
# Step 5: Summary
# ─────────────────────────────────────────────────────────
Write-Host "[5/5] Cleanup complete." -ForegroundColor Yellow
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Cleanup Summary" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
if (-not $SkipAzure) {
    Write-Host "  Azure: Resource group '$ResourceGroup' deletion in progress"
    Write-Host "         Check status: az group show -n $ResourceGroup -o table"
    Write-Host ""
}
Write-Host "  Local: Environment files, build artifacts, Docker images removed"
Write-Host ""
Write-Host "  To redeploy from scratch:"
Write-Host "    . .\openai-config.ps1"
Write-Host "    .\scripts\deploy-all.ps1"
Write-Host ""
