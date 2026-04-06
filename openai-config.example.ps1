# =============================================================================
# Azure OpenAI Configuration (EXAMPLE — copy to openai-config.ps1 and fill in)
# =============================================================================
# Usage:
#   Copy this file to openai-config.ps1
#   Fill in your actual values
#   Then: . .\openai-config.ps1
#         .\scripts\deploy-all.ps1
# =============================================================================

$env:AZURE_OPENAI_ENDPOINT = "https://your-openai-resource.openai.azure.com"
$env:AZURE_OPENAI_DEPLOYMENT = "gpt-4.1"
$env:AZURE_OPENAI_KEY = "your-api-key-here"

Write-Host "OpenAI config loaded:" -ForegroundColor Green
Write-Host "  Endpoint:   $env:AZURE_OPENAI_ENDPOINT"
Write-Host "  Deployment: $env:AZURE_OPENAI_DEPLOYMENT"
Write-Host "  Key:        ***$(($env:AZURE_OPENAI_KEY).Substring(($env:AZURE_OPENAI_KEY).Length - 6))"
