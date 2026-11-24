# Full demo in one window: setup, then RFQ-001, then RFQ-002 (the second run tests memory).
# The API key is asked once; the child scripts run in this same process and reuse it.
# Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\run-demo.ps1
$ErrorActionPreference = "Stop"
$Repo = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\setup-rfq-agent.ps1"
& "$PSScriptRoot\run-rfq.ps1" -RfqDir (Join-Path $Repo "demo\rfq-001")
& "$PSScriptRoot\run-rfq.ps1" -RfqDir (Join-Path $Repo "demo\rfq-002")
Write-Host ""
Write-Host "Both runs finished. Results are under runs\" -ForegroundColor Green
