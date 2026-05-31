param(
    [string]$LogPath = "datafiles/debug/perf_benchmark.log",
    [int]$RunCount = 2
)

if (-not (Test-Path $LogPath)) {
    Write-Output "Log file not found: $LogPath"
    exit 1
}

$raw = Get-Content $LogPath
$events = @()
for ($i = 0; $i -lt $raw.Count; $i++) {
    try {
        $obj = $raw[$i] | ConvertFrom-Json
        $obj | Add-Member -NotePropertyName line -NotePropertyValue ($i + 1)
        $events += $obj
    }
    catch {
    }
}

$completedRuns = @()
$current = $null

foreach ($e in $events) {
    if ($e.event -eq "play_start") {
        $current = [ordered]@{
            start = $e
            stop = $null
            metrics = @{}
            startLine = $e.line
            stopLine = $null
        }
        continue
    }

    if ($e.event -eq "play_stop" -and $null -ne $current) {
        $current.stop = $e
        $current.stopLine = $e.line
        $completedRuns += [pscustomobject]$current
        $current = $null
        continue
    }

    if ($e.event -eq "rt_budget" -and $null -ne $current) {
        $msg = [string]$e.message
        if ($msg -match '^\[RT_BUDGET\] ([^ ]+) ') {
            $key = $matches[1]
            if ($msg -match 'kind=([^ ]+)') {
                $key = "$key/$($matches[1])"
            }
            $current.metrics[$key] = $msg
        }
    }
}

if ($completedRuns.Count -eq 0) {
    Write-Output "No complete play runs found in $LogPath"
    exit 0
}

$pickCount = [Math]::Max(1, [Math]::Min($RunCount, $completedRuns.Count))
$selected = $completedRuns | Select-Object -Last $pickCount

$targetKeys = @(
    "controller_step_interval_ms",
    "draw_interval_ms",
    "scheduler_late_ms",
    "anchor_draw_ms/timeline",
    "anchor_draw_ms/timeline_base",
    "anchor_draw_ms/timeline_base_refresh",
    "anchor_draw_ms/timeline_overlay",
    "controller_phase_ms/scheduler_tick",
    "controller_phase_ms/timeline_tick",
    "controller_phase_ms/deferred_tick"
)

foreach ($run in $selected) {
    Write-Output ("RUN lines {0}-{1} | {2} -> {3}" -f $run.startLine, $run.stopLine, $run.start.ts_local, $run.stop.ts_local)

    foreach ($key in $targetKeys) {
        if ($run.metrics.ContainsKey($key)) {
            Write-Output $run.metrics[$key]
        }
    }

    Write-Output ""
}
