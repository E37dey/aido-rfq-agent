# One RFQ -> one session. Uploads the RFQ folder, runs the agent with both memory stores,
# waits, then saves the agent's messages, output files, cost, and a snapshot of quote-history.
# Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\run-rfq.ps1 -RfqDir .\demo\rfq-001
# Collect an existing session again (no new session, no new cost): add -ResumeSessionId sesn_...
param(
    [Parameter(Mandatory = $true)][string]$RfqDir,
    [string]$ResumeSessionId = "",
    [string]$BudgetCents = "500",
    [int]$TimeoutMinutes = 40,
    # For sessions started elsewhere (e.g. by the Make scenario): which history store to snapshot,
    # and a label for the run folder name (runs\<rfq>-<label>-v<N>-<time>).
    [string]$HistoryStoreId = "",
    [string]$RunLabel = ""
)
. "$PSScriptRoot\common.ps1"
$ids = Get-Ids
if (-not $ids.agent_id -or -not $ids.history_store_id) { throw "Run scripts\setup-rfq-agent.ps1 first." }
if ($HistoryStoreId) { $ids.history_store_id = $HistoryStoreId }

$RfqDir = (Resolve-Path $RfqDir).Path
$name = Split-Path $RfqDir -Leaf
$label = if ($RunLabel) { "-" + $RunLabel } else { "" }
$RunDir = Join-Path $Repo ("runs\" + $name + $label + "-v" + $ids.agent_version + "-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

if ($ResumeSessionId) {
    $sid = $ResumeSessionId
    Write-Host "Resuming session $sid (nothing new is created)"
} else {
# 1. Upload every file in the RFQ folder
Step "Uploading $name"
$resources = @()
foreach ($f in Get-ChildItem $RfqDir -File) {
    $up = & curl.exe -s "$ApiBase/files" -H "x-api-key: $Key" -H "anthropic-version: $ApiVersion" -F "file=@$($f.FullName)"
    $file = $up | ConvertFrom-Json
    if (-not $file.id) { throw "Upload failed for $($f.Name): $up" }
    $resources += [pscustomobject]@{ type = "file"; file_id = $file.id; mount_path = "/rfq/$($f.Name)" }
    Write-Host "  $($f.Name) -> $($file.id)"
}

# 2. Session: agent (pinned version) + environment + files + both memory stores + budget + outcome
Step "Starting session (budget $([double]$BudgetCents / 100) USD)"
# Version 1 of the agent keeps its own rubric; version 2 and later use the current template.
$tpl = if ([int]$ids.agent_version -le 1) { "session-rfq.v1.json" } else { "session-rfq.json" }
Write-Host "Agent version $($ids.agent_version), session template $tpl"
$s = Read-Template $tpl
$s.agent.id = $ids.agent_id
$s.agent.version = [int]$ids.agent_version
$s.environment_id = $ids.environment_id
$s.title = "RFQ $name"
$s.resources[0].memory_store_id = $ids.pricing_store_id
$s.resources[1].memory_store_id = $ids.history_store_id
$s.resources = @($s.resources) + $resources
$s.budget.max_list_cost.amount = $BudgetCents
$session = Invoke-Api POST "/sessions" $s
$sid = $session.id
Write-Host "Session: $sid  (watch it live in the Console: Sessions)"
}

# 3. Wait until the session is no longer running
$t0 = Get-Date; $deadline = $t0.AddMinutes($TimeoutMinutes)
do {
    Start-Sleep -Seconds 15
    $st = Invoke-Api GET "/sessions/$sid"
    Write-Host ("  {0,4}s  status={1}" -f [int]((Get-Date) - $t0).TotalSeconds, $st.status)
} while (($st.status -eq "running" -or $st.status -eq "rescheduling") -and (Get-Date) -lt $deadline)
$elapsed = [int]((Get-Date) - $t0).TotalSeconds

# 4. Agent messages and errors
Step "Collecting results"
$all = @(); $page = $null
do {
    $path = "/sessions/$sid/events"; if ($page) { $path += "?page=$page" }
    $r = Invoke-Api GET $path; $all += $r.data; $page = $r.next_page
} while ($page)
$msgs = $all | Where-Object { $_.type -eq "agent.message" } | ForEach-Object { ($_.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join "`n" }
Write-Utf8 (Join-Path $RunDir "agent-messages.md") ($msgs -join "`n`n---`n`n")
$tools = $all | Where-Object { $_.type -eq "agent.tool_use" } | ForEach-Object { $_.name }
$errs = $all | Where-Object { $_.type -eq "session.error" }
if ($errs) { Write-Utf8 (Join-Path $RunDir "session-errors.json") ($errs | ConvertTo-Json -Depth 8); Write-Host "Session errors saved" -ForegroundColor Yellow }

# 5. Output files (short indexing lag after idle)
$outs = $null
for ($i = 0; $i -lt 5 -and -not $outs; $i++) { Start-Sleep -Seconds 3; $outs = (Invoke-Api GET "/files?scope_id=$sid").data }
$outDir = Join-Path $RunDir "outputs"; New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$inputNames = @(Get-ChildItem $RfqDir -File | ForEach-Object { $_.Name })
foreach ($f in $outs) {
    if ($inputNames -contains $f.filename) { continue }   # uploaded inputs are listed too, but cannot be downloaded
    & curl.exe -s -o (Join-Path $outDir $f.filename) "$ApiBase/files/$($f.id)/content" -H "x-api-key: $Key" -H "anthropic-version: $ApiVersion" -H "anthropic-beta: $BetaAgents"
    Write-Host "Downloaded: $($f.filename)"
}

# 5b. HTML outputs -> PDF with the local Chrome (Hebrew RTL renders correctly there)
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
foreach ($h in Get-ChildItem $outDir -Filter *.html -ErrorAction SilentlyContinue) {
    if (-not $chrome) { Write-Host "Chrome not found; skipped PDF for $($h.Name)" -ForegroundColor Yellow; break }
    $pdf = [System.IO.Path]::ChangeExtension($h.FullName, ".pdf")
    $uri = ([System.Uri]$h.FullName).AbsoluteUri
    # Chrome writes harmless warnings to stderr; under ErrorActionPreference=Stop, PowerShell 5.1 treats them as errors.
    $prevPref = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    & $chrome --headless=new --disable-gpu --no-pdf-header-footer "--print-to-pdf=$pdf" $uri 2>&1 | Out-Null
    $ErrorActionPreference = $prevPref
    if (Test-Path $pdf) { Write-Host "PDF: $([System.IO.Path]::GetFileName($pdf))" }
}

# 6. Snapshot of quote-history after the run (shows what the agent wrote to memory)
Step "Snapshot of quote-history"
$memDir = Join-Path $RunDir "memory-after"
$page = $null
do {
    $path = "/memory_stores/$($ids.history_store_id)/memories?path_prefix=/&view=full"; if ($page) { $path += "&page=$page" }
    $r = Invoke-Api GET $path $null $BetaMemory
    foreach ($m in $r.data) {
        if ($m.type -eq "memory") { Write-Utf8 (Join-Path $memDir ($m.path.TrimStart("/").Replace("/", "\"))) $m.content; Write-Host "  $($m.path)" }
    }
    $page = $r.next_page
} while ($page)

# 7. Summary
$st = Invoke-Api GET "/sessions/$sid"
$summary = [pscustomobject]@{
    rfq = $name; session_id = $sid; agent_version = $ids.agent_version
    status = $st.status; stop_reason = $st.stop_reason; wall_seconds = $elapsed
    usage = $st.usage; outcome_evaluations = $st.outcome_evaluations
    tool_calls = ($tools | Group-Object | ForEach-Object { [pscustomobject]@{ tool = $_.Name; count = $_.Count } })
    output_files = @($outs | ForEach-Object { $_.filename })
}
Write-Utf8 (Join-Path $RunDir "run-summary.json") ($summary | ConvertTo-Json -Depth 10)
Step "Done"
Write-Host "Status: $($st.status)   Wall time: $elapsed s"
if ($st.usage.list_cost) { Write-Host ("List cost: {0} {1} (cents)" -f $st.usage.list_cost.amount, $st.usage.list_cost.currency) }
Write-Host "Results: $RunDir"
