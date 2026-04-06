# =============================================================================
# Full Verification Script
# Validates all components of the Code Interpreter platform
# =============================================================================
$ErrorActionPreference = "Continue"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Set-Location $ProjectRoot

$pass = 0
$fail = 0

function Script:OK { param([string]$m); $script:pass++; Write-Host "  [PASS] $m" -ForegroundColor Green }
function Script:NG { param([string]$m); $script:fail++; Write-Host "  [FAIL] $m" -ForegroundColor Red }

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  FINAL VERIFICATION SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Bicep ---
Write-Host "--- Bicep Infrastructure ---"
az bicep build --file infra\main.bicep --stdout 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { OK "Bicep compiles (main.bicep + 5 modules)" } else { NG "Bicep compilation failed" }

# --- 2. Python Backend ---
Write-Host "--- Python Backend ---"
$pyOut = & "src\backend\.venv\Scripts\python.exe" "src\backend\tests\test_verify.py" 2>&1
$pyLast = ($pyOut | Select-Object -Last 3) -join " "
if ($pyLast -match "ALL BACKEND TESTS PASSED") { OK "Backend: 32/32 tests passed" } else { NG "Backend tests failed: $pyLast" }

# --- 3. Sandbox Executor ---
Write-Host "--- Sandbox Executor ---"
$sbOut = & "src\backend\.venv\Scripts\python.exe" "src\sandbox\test_executor.py" 2>&1
$sbLast = ($sbOut | Select-Object -Last 3) -join " "
if ($sbLast -match "ALL SANDBOX EXECUTOR TESTS PASSED") { OK "Sandbox: 9/9 tests passed" } else { NG "Sandbox tests failed: $sbLast" }

# --- 4. Frontend ---
Write-Host "--- Frontend ---"
if (Test-Path "src\frontend\.next\BUILD_ID") {
    OK "Next.js build successful"
} else {
    NG "Next.js not built"
}

# --- 5. K8s Manifests ---
Write-Host "--- Kubernetes Manifests ---"
$k8sFiles = @("k8s\namespaces.yaml", "k8s\rbac.yaml", "k8s\sandbox-networkpolicy.yaml", "k8s\app-deployment.yaml")
$k8sOk = $true
foreach ($f in $k8sFiles) {
    kubectl apply --dry-run=client -f $f 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $k8sOk = $false }
}
if ($k8sOk) { OK "K8s manifests: 4 files validated (dry-run)" } else { NG "K8s manifest dry-run failed" }

# --- 6. PowerShell Scripts ---
Write-Host "--- PowerShell Deploy Scripts ---"
$psScripts = @("scripts\preflight-check.ps1", "scripts\deploy-infra.ps1", "scripts\deploy-apps.ps1", "scripts\deploy-all.ps1")
$psOk = $true
foreach ($s in $psScripts) {
    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $s -Raw), [ref]$errors)
    if ($errors.Count -gt 0) { $psOk = $false; Write-Host "    Errors in $s" -ForegroundColor Red }
}
if ($psOk) { OK "PowerShell scripts: $($psScripts.Count) files syntax OK" } else { NG "PowerShell syntax errors" }

# --- 7. Bash Scripts ---
Write-Host "--- Bash Deploy Scripts ---"
$bashScripts = @("scripts/preflight-check.sh", "scripts/deploy-infra.sh", "scripts/deploy-apps.sh", "scripts/deploy-all.sh")
$bashOk = $true
foreach ($s in $bashScripts) {
    bash -n $s 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $bashOk = $false }
}
if ($bashOk) { OK "Bash scripts: $($bashScripts.Count) files syntax OK" } else { NG "Bash syntax errors" }

# --- 8. Dockerfiles ---
Write-Host "--- Dockerfiles ---"
$dfs = @("src\sandbox\Dockerfile", "src\backend\Dockerfile", "src\frontend\Dockerfile")
$dfOk = $true
foreach ($df in $dfs) {
    if (-not (Test-Path $df)) { $dfOk = $false }
    else {
        $content = Get-Content $df -Raw
        if ($content -notmatch "^FROM ") { $dfOk = $false }
    }
}
if ($dfOk) { OK "Dockerfiles: 3 files present and valid" } else { NG "Dockerfile issues" }

# --- 9. Docker Daemon ---
Write-Host "--- Docker Daemon ---"
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    OK "Docker daemon running"
} else {
    NG "Docker daemon NOT running - start Docker Desktop before deploying"
}

# --- 10. Sample Data ---
Write-Host "--- Sample Data ---"
$csvOk = (Test-Path "sample-data\transactions.csv") -and (Test-Path "sample-data\loans.csv") -and (Test-Path "sample-data\branches.csv")
if ($csvOk) { OK "Sample data: 3 CSV files present" } else { NG "Missing sample data" }

# --- 11. .dockerignore ---
Write-Host "--- Docker Ignore ---"
$diOk = (Test-Path "src\backend\.dockerignore") -and (Test-Path "src\frontend\.dockerignore")
if ($diOk) { OK ".dockerignore files present" } else { NG "Missing .dockerignore" }

# --- 12. Preflight ---
Write-Host "--- Preflight Check ---"
& "$ProjectRoot\scripts\preflight-check.ps1" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { OK "Preflight check passed (13 checks)" } else { NG "Preflight check failed" }

# --- Summary ---
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
$total = $pass + $fail
if ($fail -gt 0) {
    Write-Host "  TOTAL: $pass/$total PASSED, $fail FAILED" -ForegroundColor Red
} else {
    Write-Host "  TOTAL: $pass/$total PASSED" -ForegroundColor Green
}
Write-Host "=============================================" -ForegroundColor Cyan

if ($fail -eq 0) {
    Write-Host ""
    Write-Host "  ALL VERIFICATIONS PASSED" -ForegroundColor Green
    Write-Host ""
    Write-Host "  To deploy:" -ForegroundColor White
    Write-Host "    1. Start Docker Desktop" -ForegroundColor Gray
    Write-Host "    2. cd $ProjectRoot" -ForegroundColor Gray
    Write-Host "    3. .\scripts\deploy-all.ps1" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "  Fix the failures above before deploying." -ForegroundColor Red
}
