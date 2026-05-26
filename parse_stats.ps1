$path = "c:\Users\xian\AppData\Roaming\Code\User\workspaceStorage\c8306b1f9f71e521abcb633b0df0b7df\GitHub.copilot-chat\transcripts\ecb54cd1-c587-4e2c-a3ec-bee1fbd9c4e9.jsonl"
$lines = Get-Content $path
$results = @()
foreach ($line in $lines) {
    if ($line -like "*MIDI loopback complete*") {
        $truncated = if ($line.Length -gt 220) { $line.Substring(0, 220) } else { $line }
        $offset = $null
        $jitter = $null
        if ($line -match "offset_ms[=:]\s*([-+]?\d*\.?\d+)") { $offset = [double]$Matches[1] }
        if ($line -match "jitter_ms[=:]\s*([-+]?\d*\.?\d+)") { $jitter = [double]$Matches[1] }
        if ($offset -ne $null -and $jitter -ne $null) {
            $results += [PSCustomObject]@{
                Line = $truncated
                Offset = $offset
                Jitter = $jitter
            }
        }
    }
}
function Get-Median($values) {
    if ($values.Count -eq 0) { return $null }
    $sorted = $values | Sort-Object
    $count = $sorted.Count
    if ($count % 2 -eq 1) { return $sorted[[math]::Floor($count / 2)] }
    else { return ($sorted[$count / 2 - 1] + $sorted[$count / 2]) / 2 }
}
if ($results.Count -gt 0) {
    $results | ForEach-Object { $_.Line }
    Write-Output "---"
    Write-Output "Count: $($results.Count)"
    $offsets = $results.Offset
    $jitters = $results.Jitter
    $offStats = $offsets | Measure-Object -Average -Minimum -Maximum
    $jitStats = $jitters | Measure-Object -Average -Minimum -Maximum
    $offMedian = Get-Median $offsets
    $jitMedian = Get-Median $jitters
    Write-Output "Offset Statistics:"
    Write-Output "  Mean:   $($offStats.Average)"
    Write-Output "  Median: $offMedian"
    Write-Output "  Min:    $($offStats.Minimum)"
    Write-Output "  Maximum: $($offStats.Maximum)"
    Write-Output "Jitter Statistics:"
    Write-Output "  Mean:   $($jitStats.Average)"
    Write-Output "  Median: $jitMedian"
    Write-Output "  Min:    $($jitStats.Minimum)"
    Write-Output "  Maximum: $($jitStats.Maximum)"
} else {
    Write-Output "No matching lines found."
}
