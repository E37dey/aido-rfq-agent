# Finish the version 2 demo after the collect step failed on RFQ-001:
# collect the existing RFQ-001 session again (no new cost), then run RFQ-002.
# Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\resume-demo-v2.ps1 -Rfq1SessionId sesn_...
param([Parameter(Mandatory = $true)][string]$Rfq1SessionId)
$ErrorActionPreference = "Stop"
$Repo = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\run-rfq.ps1" -RfqDir (Join-Path $Repo "demo\rfq-001") -ResumeSessionId $Rfq1SessionId
& "$PSScriptRoot\run-rfq.ps1" -RfqDir (Join-Path $Repo "demo\rfq-002")
Write-Host ""
Write-Host "Version 2: both runs finished. Results are under runs\" -ForegroundColor Green
