# =============================================================================
# End-to-End Live Test Script
# Tests the full Code Interpreter flow: Upload → Chat → Verify results
# =============================================================================
param(
    [string]$BaseUrl = $(if ($env:INGRESS_IP) { "http://$env:INGRESS_IP" } else { "http://localhost:8000" })
)

$ErrorActionPreference = "Continue"
$pass = 0
$fail = 0

function OK { param([string]$m); $script:pass++; Write-Host "  [PASS] $m" -ForegroundColor Green }
function NG { param([string]$m); $script:fail++; Write-Host "  [FAIL] $m" -ForegroundColor Red }

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Code Interpreter — Live E2E Test"           -ForegroundColor Cyan
Write-Host "  Endpoint: $BaseUrl"                          -ForegroundColor Gray
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────────
# TEST 0: Health Check
# ─────────────────────────────────────────────────────────
Write-Host "--- Test 0: Health Check ---"
try {
    $health = Invoke-RestMethod -Uri "$BaseUrl/api/health" -TimeoutSec 10
    if ($health.status -eq "healthy") { OK "Backend healthy" } else { NG "Backend unhealthy: $($health.status)" }
} catch { NG "Health check failed: $_" }

Write-Host ""

# ─────────────────────────────────────────────────────────
# TEST 1: Transaction Anomaly Detection
# ─────────────────────────────────────────────────────────
Write-Host "--- Test 1: Transaction Anomaly Detection ---"
Write-Host "  Dataset: transactions.csv"
Write-Host "  Prompt:  Identify unusual transactions based on amount"
Write-Host ""

# Upload
Write-Host "  [1/4] Uploading dataset..."
$uploadResult = curl.exe -s -X POST "$BaseUrl/api/upload" -F "file=@sample-data/transactions.csv"
$upload = $uploadResult | ConvertFrom-Json
if ($upload.session_id) {
    OK "Upload: session=$($upload.session_id), blob=$($upload.blob_path)"
} else {
    NG "Upload failed: $uploadResult"
}

# Chat
Write-Host "  [2/4] Sending prompt (may take 1-5 min)..."
$chatJson = @{
    prompt = "Identify unusual transactions based on amount. Flag any that are significantly higher than the mean."
    dataset_blob = $upload.blob_path
    session_id = $upload.session_id
} | ConvertTo-Json
$tempFile = Join-Path $PSScriptRoot "temp_test1.json"
[System.IO.File]::WriteAllText($tempFile, $chatJson, [System.Text.UTF8Encoding]::new($false))
$chatResult = curl.exe -s -X POST "$BaseUrl/api/chat" -H "Content-Type: application/json" --data-binary "@$tempFile" --max-time 660
$chat = $chatResult | ConvertFrom-Json

# Verify results
Write-Host "  [3/4] Verifying response..."
if ($chat.status -eq "completed") { OK "Status: completed" } else { NG "Status: $($chat.status) - $($chat.message)" }
if ($chat.code -and $chat.code.Length -gt 50) { OK "Code generated: $($chat.code.Length) chars" } else { NG "No code generated" }
if ($chat.explanation -and $chat.explanation.Length -gt 100) { OK "Explanation: $($chat.explanation.Length) chars" } else { NG "No explanation" }
$fileNames = ($chat.output_files | ForEach-Object { Split-Path $_.path -Leaf }) -join ', '
if ($chat.output_files.Count -gt 0) { OK "Output files: $($chat.output_files.Count) ($fileNames)" } else { NG "No output files" }

# Content checks
Write-Host "  [4/4] Checking analysis quality..."
if ($chat.explanation -match "unusual|anomal|outlier") { OK "Explanation mentions anomalies" } else { NG "Explanation missing anomaly mentions" }
if ($chat.explanation -match "T006|50.?000.?000|Unknown") { OK "Identified T006 (50M) as anomaly" } else { NG "Missed T006 anomaly" }

Write-Host ""

# ─────────────────────────────────────────────────────────
# TEST 2: Loan Portfolio Risk Analysis
# ─────────────────────────────────────────────────────────
Write-Host "--- Test 2: Loan Portfolio Risk Analysis ---"
Write-Host "  Dataset: loans.csv"
Write-Host "  Prompt:  Which loans are high risk? Classify by DPD and show risk by sector"
Write-Host ""

# Upload
Write-Host "  [1/4] Uploading dataset..."
$uploadResult2 = curl.exe -s -X POST "$BaseUrl/api/upload" -F "file=@sample-data/loans.csv"
$upload2 = $uploadResult2 | ConvertFrom-Json
if ($upload2.session_id) { OK "Upload: session=$($upload2.session_id)" } else { NG "Upload failed" }

# Chat
Write-Host "  [2/4] Sending prompt..."
$chatJson2 = @{
    prompt = "Which loans are high risk? Classify risk based on DPD (days past due): 0=current, 1-30=watch, 31-60=substandard, 61-90=doubtful, 90+=loss. Group risk by sector and create a bar chart."
    dataset_blob = $upload2.blob_path
    session_id = $upload2.session_id
} | ConvertTo-Json
$tempFile2 = Join-Path $PSScriptRoot "temp_test2.json"
[System.IO.File]::WriteAllText($tempFile2, $chatJson2, [System.Text.UTF8Encoding]::new($false))
$chatResult2 = curl.exe -s -X POST "$BaseUrl/api/chat" -H "Content-Type: application/json" --data-binary "@$tempFile2" --max-time 660
$chat2 = $chatResult2 | ConvertFrom-Json

# Verify
Write-Host "  [3/4] Verifying response..."
if ($chat2.status -eq "completed") { OK "Status: completed" } else { NG "Status: $($chat2.status)" }
if ($chat2.code) { OK "Code generated: $($chat2.code.Length) chars" } else { NG "No code" }
if ($chat2.explanation) { OK "Explanation: $($chat2.explanation.Length) chars" } else { NG "No explanation" }

# Content checks
Write-Host "  [4/4] Checking analysis quality..."
if ($chat2.explanation -match "risk|high|loss|doubtful") { OK "Risk classification mentioned" } else { NG "Missing risk classification" }
if ($chat2.explanation -match "sector|Construction|Retail|Manufactur") { OK "Sector analysis present" } else { NG "Missing sector analysis" }
$hasChart2 = $chat2.output_files | Where-Object { $_.path -match "\.png$" }
if ($hasChart2) { OK "Chart generated: $(Split-Path $hasChart2[0].path -Leaf)" } else { NG "No chart generated" }

Write-Host ""

# ─────────────────────────────────────────────────────────
# TEST 3: Branch Performance Analysis
# ─────────────────────────────────────────────────────────
Write-Host "--- Test 3: Branch Performance Analysis ---"
Write-Host "  Dataset: branches.csv"
Write-Host "  Prompt:  Compare branch performance and identify service quality issues"
Write-Host ""

# Upload
Write-Host "  [1/4] Uploading dataset..."
$uploadResult3 = curl.exe -s -X POST "$BaseUrl/api/upload" -F "file=@sample-data/branches.csv"
$upload3 = $uploadResult3 | ConvertFrom-Json
if ($upload3.session_id) { OK "Upload: session=$($upload3.session_id)" } else { NG "Upload failed" }

# Chat
Write-Host "  [2/4] Sending prompt..."
$chatJson3 = @{
    prompt = "Compare branch performance using monthly_revenue, new_accounts, and complaints. Rank branches. Which branch has the worst service quality (highest complaints relative to size)? Visualize the comparison."
    dataset_blob = $upload3.blob_path
    session_id = $upload3.session_id
} | ConvertTo-Json
$tempFile3 = Join-Path $PSScriptRoot "temp_test3.json"
[System.IO.File]::WriteAllText($tempFile3, $chatJson3, [System.Text.UTF8Encoding]::new($false))
$chatResult3 = curl.exe -s -X POST "$BaseUrl/api/chat" -H "Content-Type: application/json" --data-binary "@$tempFile3" --max-time 660
$chat3 = $chatResult3 | ConvertFrom-Json

# Verify
Write-Host "  [3/4] Verifying response..."
if ($chat3.status -eq "completed") { OK "Status: completed" } else { NG "Status: $($chat3.status)" }
if ($chat3.code) { OK "Code generated: $($chat3.code.Length) chars" } else { NG "No code" }
if ($chat3.explanation) { OK "Explanation: $($chat3.explanation.Length) chars" } else { NG "No explanation" }

# Content checks
Write-Host "  [4/4] Checking analysis quality..."
if ($chat3.explanation -match "rank|performance|compar") { OK "Performance comparison present" } else { NG "Missing comparison" }
if ($chat3.explanation -match "Makassar|Medan|complaint|service") { OK "Service quality issues identified" } else { NG "Missing service quality analysis" }

Write-Host ""

# ─────────────────────────────────────────────────────────
# TEST 4: Follow-up prompt (same session)
# ─────────────────────────────────────────────────────────
Write-Host "--- Test 4: Follow-up Question (same session as Test 1) ---"
Write-Host "  Prompt: Show the daily spending pattern for account A123"
Write-Host ""

Write-Host "  [1/2] Sending follow-up prompt..."
$chatJson4 = @{
    prompt = "Show the daily spending pattern for account A123. Plot amount over date."
    dataset_blob = $upload.blob_path
    session_id = $upload.session_id
} | ConvertTo-Json
$tempFile4 = Join-Path $PSScriptRoot "temp_test4.json"
[System.IO.File]::WriteAllText($tempFile4, $chatJson4, [System.Text.UTF8Encoding]::new($false))
$chatResult4 = curl.exe -s -X POST "$BaseUrl/api/chat" -H "Content-Type: application/json" --data-binary "@$tempFile4" --max-time 660
$chat4 = $chatResult4 | ConvertFrom-Json

Write-Host "  [2/2] Verifying..."
if ($chat4.status -eq "completed") { OK "Follow-up completed" } else { NG "Follow-up status: $($chat4.status)" }
if ($chat4.explanation -match "A123|spending|pattern") { OK "Account-specific analysis" } else { NG "Not account-specific" }
$hasChart4 = $chat4.output_files | Where-Object { $_.path -match "\.png$" }
if ($hasChart4) { OK "Chart generated" } else { NG "No chart" }

Write-Host ""

# ─────────────────────────────────────────────────────────
# TEST 5: Error handling — bad prompt
# ─────────────────────────────────────────────────────────
Write-Host "--- Test 5: Error Handling ---"

Write-Host "  [1/2] Empty prompt..."
$emptyResult = curl.exe -s -X POST "$BaseUrl/api/chat" -H "Content-Type: application/json" -d '{\"prompt\":\"\",\"dataset_blob\":\"x\",\"session_id\":\"x\"}'
if ($emptyResult -match "400|empty|detail") { OK "Empty prompt rejected" } else { NG "Empty prompt not handled" }

Write-Host "  [2/2] No file upload..."
$noFileResult = curl.exe -s -X POST "$BaseUrl/api/upload"
if ($noFileResult -match "400|422|detail|file") { OK "Missing file rejected" } else { NG "Missing file not handled" }

Write-Host ""

# ─────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────
# Cleanup temp files
Remove-Item -Path (Join-Path $PSScriptRoot "temp_test*.json") -ErrorAction SilentlyContinue

Write-Host "=============================================" -ForegroundColor Cyan
$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host "  ALL TESTS PASSED: $pass/$total" -ForegroundColor Green
} else {
    Write-Host "  RESULTS: $pass/$total passed, $fail failed" -ForegroundColor $(if ($fail -gt 3) { "Red" } else { "Yellow" })
}
Write-Host "=============================================" -ForegroundColor Cyan

# Print quick summary of each test
Write-Host ""
Write-Host "  Test 1 (Transactions): $($chat.status)" -ForegroundColor $(if ($chat.status -eq "completed") {"Green"} else {"Red"})
Write-Host "  Test 2 (Loans):        $($chat2.status)" -ForegroundColor $(if ($chat2.status -eq "completed") {"Green"} else {"Red"})
Write-Host "  Test 3 (Branches):     $($chat3.status)" -ForegroundColor $(if ($chat3.status -eq "completed") {"Green"} else {"Red"})
Write-Host "  Test 4 (Follow-up):    $($chat4.status)" -ForegroundColor $(if ($chat4.status -eq "completed") {"Green"} else {"Red"})
Write-Host "  Test 5 (Errors):       validated"
Write-Host ""

if ($fail -eq 0) {
    Write-Host "  Platform is fully operational!" -ForegroundColor Green
}
