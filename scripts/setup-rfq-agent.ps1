# One-time setup: environment, agent, two memory stores, and the seed memories.
# Safe to run again: anything already created (IDs in state\ids.json) is skipped.
# Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\setup-rfq-agent.ps1
. "$PSScriptRoot\common.ps1"
$ids = Get-Ids

if (-not $ids.environment_id) {
    Step "Creating environment (cloud, limited networking, no hosts)"
    $e = Invoke-Api POST "/environments" (Read-Template "env-rfq-offline.json")
    Set-Id $ids "environment_id" $e.id; Save-Ids $ids
}
Write-Host "Environment: $($ids.environment_id)"

if (-not $ids.agent_id) {
    Step "Creating agent"
    $a = Invoke-Api POST "/agents" (Read-Template "agent-rfq-quoter.json")
    Set-Id $ids "agent_id" $a.id; Set-Id $ids "agent_version" $a.version; Save-Ids $ids
}
Write-Host "Agent: $($ids.agent_id) (version $($ids.agent_version))"

foreach ($s in @(@{ key = "pricing_store_id"; tpl = "store-shop-pricing.json"; seed = "pricing" },
                 @{ key = "history_store_id"; tpl = "store-quote-history.json"; seed = "history" })) {
    if (-not $ids.($s.key)) {
        Step "Creating memory store from $($s.tpl)"
        $m = Invoke-Api POST "/memory_stores" (Read-Template $s.tpl) $BetaMemory
        Set-Id $ids $s.key $m.id; Save-Ids $ids

        $root = Join-Path $Repo ("seed\" + $s.seed)
        Get-ChildItem $root -Recurse -File | ForEach-Object {
            $rel = "/" + $_.FullName.Substring($root.Length + 1).Replace("\", "/")
            $body = @{ path = $rel; content = (Read-Utf8 $_.FullName) }
            Invoke-Api POST "/memory_stores/$($m.id)/memories" $body $BetaMemory | Out-Null
            Write-Host "  seeded $rel"
        }
    }
    Write-Host "$($s.key): $($ids.($s.key))"
}

Step "Done. IDs saved in state\ids.json (not committed)."
