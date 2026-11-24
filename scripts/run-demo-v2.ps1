# Version 2 demo in one window: upgrade the agent, then RFQ-001 and RFQ-002 on a clean history.
# Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\run-demo-v2.ps1
$ErrorActionPreference = "Stop"
$Repo = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\upgrade-agent.ps1"
& "$PSScriptRoot\run-rfq.ps1" -RfqDir (Join-Path $Repo "demo\rfq-001")
& "$PSScriptRoot\run-rfq.ps1" -RfqDir (Join-Path $Repo "demo\rfq-002")
Write-Host ""
Write-Host "Version 2: both runs finished. Results are under runs\" -ForegroundColor Green
