# Push templates\agent-rfq-quoter.json as a new version of the same agent, and start a clean
# quote-history store so the two-run memory test starts from the seed again.
# The previous history store is kept (its ID is saved as history_store_id_v<old version>).
# Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\upgrade-agent.ps1
. "$PSScriptRoot\common.ps1"
$ids = Get-Ids
if (-not $ids.agent_id) { throw "Run scripts\setup-rfq-agent.ps1 first." }
$old = [int]$ids.agent_version

Step "Updating agent $($ids.agent_id) (current version $old)"
$body = Read-Template "agent-rfq-quoter.json"
$body | Add-Member -NotePropertyName version -NotePropertyValue $old -Force   # 409 if someone else changed it meanwhile
$a = Invoke-Api POST "/agents/$($ids.agent_id)" $body
Set-Id $ids "agent_version" $a.version; Save-Ids $ids
Write-Host "Agent is now version $($a.version)"

Step "New quote-history store (clean seed)"
Set-Id $ids ("history_store_id_v" + $old) $ids.history_store_id
$m = Invoke-Api POST "/memory_stores" (Read-Template "store-quote-history.json") $BetaMemory
$root = Join-Path $Repo "seed\history"
Get-ChildItem $root -Recurse -File | ForEach-Object {
    $rel = "/" + $_.FullName.Substring($root.Length + 1).Replace("\", "/")
    Invoke-Api POST "/memory_stores/$($m.id)/memories" @{ path = $rel; content = (Read-Utf8 $_.FullName) } $BetaMemory | Out-Null
    Write-Host "  seeded $rel"
}
Set-Id $ids "history_store_id" $m.id; Save-Ids $ids
Write-Host "history_store_id: $($m.id)"
