# =============================================================================
# All-in-One Deployment Script (PowerShell Native)
# Runs preflight, infrastructure, and application deployment
# =============================================================================
param(
    [string]$ResourceGroup = "rg-code-interpreter",
    [string]$PrimaryLocation = "indonesiacentral",
    [string]$OpenAiLocation = "southeastasia",
    [string]$Environment = "dev",
    [string]$BaseName = "codeinterp",
    # Set these to use an EXISTING Azure OpenAI resource (skip creating new one)
    [string]$ExistingOpenAiEndpoint = $(if ($env:AZURE_OPENAI_ENDPOINT) { $env:AZURE_OPENAI_ENDPOINT } else { "" }),
    [string]$ExistingOpenAiDeployment = $(if ($env:AZURE_OPENAI_DEPLOYMENT) { $env:AZURE_OPENAI_DEPLOYMENT } else { "" }),
    [string]$ExistingOpenAiKey = $(if ($env:AZURE_OPENAI_KEY) { $env:AZURE_OPENAI_KEY } else { "" })
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Set environment variables for child scripts
$env:RESOURCE_GROUP = $ResourceGroup
$env:PRIMARY_LOCATION = $PrimaryLocation
$env:OPENAI_LOCATION = $OpenAiLocation
$env:ENVIRONMENT = $Environment
$env:BASE_NAME = $BaseName

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Code Interpreter Platform - Full Deploy"     -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Preflight
Write-Host ">>> Step 1: Preflight Check" -ForegroundColor Yellow
Write-Host "-------------------------------------------"
& "$ScriptDir\preflight-check.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Preflight check failed. Aborting." -ForegroundColor Red
    exit 1
}

# Step 2: Infrastructure
Write-Host ""
Write-Host ">>> Step 2: Infrastructure Deployment" -ForegroundColor Yellow
Write-Host "-------------------------------------------"
& "$ScriptDir\deploy-infra.ps1" `
    -ResourceGroup $ResourceGroup `
    -PrimaryLocation $PrimaryLocation `
    -OpenAiLocation $OpenAiLocation `
    -Environment $Environment `
    -BaseName $BaseName `
    -ExistingOpenAiEndpoint $ExistingOpenAiEndpoint `
    -ExistingOpenAiDeployment $ExistingOpenAiDeployment `
    -ExistingOpenAiKey $ExistingOpenAiKey
if ($LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed. Aborting." -ForegroundColor Red
    exit 1
}

# Step 3: Applications
Write-Host ""
Write-Host ">>> Step 3: Application Deployment" -ForegroundColor Yellow
Write-Host "-------------------------------------------"
& "$ScriptDir\deploy-apps.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Application deployment failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Full deployment complete!"                    -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
