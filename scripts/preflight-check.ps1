# =============================================================================
# Preflight Check Script (PowerShell Native)
# Validates prerequisites before deploying the Code Interpreter platform
# =============================================================================
$ErrorActionPreference = "Continue"

$Pass = 0
$Fail = 0
$Warn = 0

function Check-Pass { param([string]$Msg); $script:Pass++; Write-Host "  [PASS] $Msg" -ForegroundColor Green }
function Check-Fail { param([string]$Msg); $script:Fail++; Write-Host "  [FAIL] $Msg" -ForegroundColor Red }
function Check-Warn { param([string]$Msg); $script:Warn++; Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Code Interpreter Platform - Preflight Check" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# --- CLI Tools ---
Write-Host "Checking CLI tools..."

if (Get-Command az -ErrorAction SilentlyContinue) {
    $azVer = (az version --output tsv --query '"azure-cli"' 2>$null)
    Check-Pass "Azure CLI installed (v$azVer)"
} else {
    Check-Fail "Azure CLI not installed - https://learn.microsoft.com/cli/azure/install-azure-cli"
}

if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Check-Pass "kubectl installed"
} else {
    Check-Fail "kubectl not installed"
}

if (Get-Command docker -ErrorAction SilentlyContinue) {
    Check-Pass "Docker installed"
} else {
    Check-Fail "Docker not installed - required for building images"
}

Write-Host ""

# --- Azure Login ---
Write-Host "Checking Azure authentication..."
try {
    $account = az account show 2>$null | ConvertFrom-Json
    if ($account) {
        Check-Pass "Logged in to Azure: $($account.name)"
        Check-Pass "Subscription: $($account.id)"
    } else {
        Check-Fail "Not logged in to Azure - run: az login"
    }
} catch {
    Check-Fail "Not logged in to Azure - run: az login"
}

Write-Host ""

# --- Resource Providers ---
Write-Host "Checking resource provider registrations..."
$providers = @(
    "Microsoft.ContainerService",
    "Microsoft.CognitiveServices",
    "Microsoft.ContainerRegistry",
    "Microsoft.Storage",
    "Microsoft.OperationalInsights"
)

foreach ($provider in $providers) {
    try {
        $state = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
        if ($state -eq "Registered") {
            Check-Pass "$provider`: Registered"
        } else {
            Check-Warn "$provider`: $state - run: az provider register --namespace $provider"
        }
    } catch {
        Check-Warn "$provider`: Unknown state"
    }
}

Write-Host ""

# --- Region Availability ---
Write-Host "Checking region availability..."

$primaryLocation = if ($env:PRIMARY_LOCATION) { $env:PRIMARY_LOCATION } else { "indonesiacentral" }
$openAiLocation = if ($env:OPENAI_LOCATION) { $env:OPENAI_LOCATION } else { "southeastasia" }

try {
    $regions = az account list-locations --query "[].name" -o tsv 2>$null
    if ($regions -contains $primaryLocation) {
        Check-Pass "Primary location '$primaryLocation' available"
    } else {
        Check-Fail "Primary location '$primaryLocation' NOT available"
    }

    if ($regions -contains $openAiLocation) {
        Check-Pass "OpenAI location '$openAiLocation' available"
    } else {
        Check-Fail "OpenAI location '$openAiLocation' NOT available"
    }
} catch {
    Check-Warn "Could not check region availability"
}

Write-Host ""

# --- VM Quota ---
Write-Host "Checking VM quota..."
try {
    $dsv3 = az vm list-usage --location $primaryLocation --query "[?contains(name.value, 'standardDSv3Family')]" 2>$null | ConvertFrom-Json
    if ($dsv3) {
        $avail = $dsv3[0].limit - $dsv3[0].currentValue
        if ($avail -ge 12) {
            Check-Pass "DSv3 VM quota: $avail vCPUs available (need ~12)"
        } elseif ($avail -gt 0) {
            Check-Warn "DSv3 VM quota: only $avail vCPUs available (recommended: 12+)"
        } else {
            Check-Fail "DSv3 VM quota: 0 vCPUs available - request increase via Azure Portal"
        }
    } else {
        Check-Warn "Could not check DSv3 quota for $primaryLocation"
    }
} catch {
    Check-Warn "Could not check VM quota"
}

Write-Host ""

# --- Summary ---
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Results: $Pass passed, $Fail failed, $Warn warnings" -ForegroundColor $(if ($Fail -gt 0) { "Red" } else { "Green" })
Write-Host "=============================================" -ForegroundColor Cyan

if ($Fail -gt 0) {
    Write-Host ""
    Write-Host "Preflight check FAILED. Fix the above issues before deploying." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "Preflight check PASSED. Ready to deploy." -ForegroundColor Green
    exit 0
}
