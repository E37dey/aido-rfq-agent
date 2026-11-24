# Shared helpers for the RFQ agent scripts. Dot-source it: . "$PSScriptRoot\common.ps1"
# ASCII only on purpose: Windows PowerShell 5.1 misreads non-ASCII in .ps1 files without a BOM.

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Repo = Split-Path $PSScriptRoot -Parent
$StateDir = Join-Path $Repo "state"
$IdsFile = Join-Path $StateDir "ids.json"
$ApiBase = "https://api.anthropic.com/v1"
$ApiVersion = "2026-10-21"
$BetaAgents = "managed-agents-2026-04-01"
$BetaMemory = "agent-memory-2026-07-22"

function Get-ApiKey {
    $k = $env:ANTHROPIC_API_KEY
    if (-not $k) { $k = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User") }
    if (-not $k) {
        foreach ($f in @((Join-Path $Repo ".env"), (Join-Path (Split-Path $Repo -Parent) "AI-Implementer-Kit\.env"))) {
            if (Test-Path $f) {
                $line = Get-Content $f | Where-Object { $_ -match '^\s*ANTHROPIC_API_KEY\s*=\s*\S' } | Select-Object -First 1
                if ($line) { $k = ($line -split '=', 2)[1].Trim().Trim('"').Trim("'"); Write-Host "Using API key from $f"; break }
            }
        }
    }
    if (-not $k) {
        $secure = Read-Host "ANTHROPIC_API_KEY (input hidden)" -AsSecureString
        $k = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    }
    $env:ANTHROPIC_API_KEY = $k   # this process only, so a second script in the same window does not ask again
    return $k
}
$Key = Get-ApiKey

function Invoke-Api([string]$Method, [string]$Path, $Body = $null, [string]$Beta = $BetaAgents) {
    $headers = @{ "x-api-key" = $Key; "anthropic-version" = $ApiVersion; "anthropic-beta" = $Beta }
    $p = @{ Method = $Method; Uri = "$ApiBase$Path"; Headers = $headers; UseBasicParsing = $true }
    if ($null -ne $Body) {
        $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 }
        $p.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
        $p.ContentType = "application/json; charset=utf-8"
    }
    try { $r = Invoke-WebRequest @p }
    catch {
        $msg = $_.Exception.Message
        if ($_.Exception.Response) {
            $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $msg = $sr.ReadToEnd()
        }
        throw "API $Method $Path failed: $msg"
    }
    $t = [System.Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    if ($t) { return $t | ConvertFrom-Json }
}

function Read-Utf8([string]$path) { [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) }
function Write-Utf8([string]$path, [string]$text) {
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}
function Read-Template([string]$name) { Read-Utf8 (Join-Path $Repo "templates\$name") | ConvertFrom-Json }
function Step([string]$s) { Write-Host ""; Write-Host "== $s" -ForegroundColor Cyan }

function Get-Ids {
    if (Test-Path $IdsFile) { return Get-Content $IdsFile -Raw | ConvertFrom-Json }
    return [pscustomobject]@{}
}
function Save-Ids($ids) {
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force -Path $StateDir | Out-Null }
    $ids | ConvertTo-Json | Set-Content -Path $IdsFile -Encoding UTF8
}
function Set-Id($ids, [string]$name, $value) {
    if ($ids.PSObject.Properties[$name]) { $ids.$name = $value } else { $ids | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
