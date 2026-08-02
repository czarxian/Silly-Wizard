param(
    [Parameter(Mandatory = $true)]
    [string]$BaseSummaryCsv,

    [Parameter(Mandatory = $true)]
    [string]$ActiveSummaryCsv,

    [string]$BaseEventsCsv = "",
    [string]$ActiveEventsCsv = "",

    [int]$FocusPart = 1,
    [int]$FocusMeasure = 25,
    [int]$MaxFocusRows = 200
)

function Get-IntOrZero {
    param([object]$Value)
    if ($null -eq $Value -or "$Value" -eq "") { return 0 }
    return [int]$Value
}

function Get-DoubleOrNaN {
    param([object]$Value)
    if ($null -eq $Value -or "$Value" -eq "") { return [double]::NaN }
    return [double]$Value
}

function Assert-File {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) {
        Write-Error "$Label not found: $Path"
        exit 1
    }
}

function Sort-Events {
    param([object[]]$Rows)
    return $Rows | Sort-Object `
        @{ Expression = { Get-DoubleOrNaN $_.time_ms } }, `
        @{ Expression = { "$($_.event_type)" } }, `
        @{ Expression = { Get-IntOrZero $_.note } }, `
        @{ Expression = { Get-IntOrZero $_.channel } }, `
        @{ Expression = { "$($_.owner_label)" } }
}

Assert-File -Path $BaseSummaryCsv -Label "Base summary CSV"
Assert-File -Path $ActiveSummaryCsv -Label "Active summary CSV"

$base = Import-Csv -Path $BaseSummaryCsv
$active = Import-Csv -Path $ActiveSummaryCsv

$baseMap = @{}
foreach ($row in $base) {
    $key = "$($row.part):$($row.measure)"
    $baseMap[$key] = $row
}

$activeMap = @{}
foreach ($row in $active) {
    $key = "$($row.part):$($row.measure)"
    $activeMap[$key] = $row
}

$keys = @($baseMap.Keys + $activeMap.Keys | Sort-Object -Unique)

$rows = foreach ($key in $keys) {
    $b = $baseMap[$key]
    $a = $activeMap[$key]

    $part = if ($null -ne $a) { Get-IntOrZero $a.part } elseif ($null -ne $b) { Get-IntOrZero $b.part } else { 1 }
    $measure = if ($null -ne $a) { Get-IntOrZero $a.measure } elseif ($null -ne $b) { Get-IntOrZero $b.measure } else { -1 }

    $bEvent = if ($null -ne $b) { Get-IntOrZero $b.event_count } else { 0 }
    $aEvent = if ($null -ne $a) { Get-IntOrZero $a.event_count } else { 0 }

    $bOn = if ($null -ne $b) { Get-IntOrZero $b.note_on_count } else { 0 }
    $aOn = if ($null -ne $a) { Get-IntOrZero $a.note_on_count } else { 0 }

    $bOff = if ($null -ne $b) { Get-IntOrZero $b.note_off_count } else { 0 }
    $aOff = if ($null -ne $a) { Get-IntOrZero $a.note_off_count } else { 0 }

    $bMarker = if ($null -ne $b) { Get-IntOrZero $b.marker_count } else { 0 }
    $aMarker = if ($null -ne $a) { Get-IntOrZero $a.marker_count } else { 0 }

    $bFirst = if ($null -ne $b) { Get-DoubleOrNaN $b.first_time_ms } else { [double]::NaN }
    $aFirst = if ($null -ne $a) { Get-DoubleOrNaN $a.first_time_ms } else { [double]::NaN }

    $bLast = if ($null -ne $b) { Get-DoubleOrNaN $b.last_time_ms } else { [double]::NaN }
    $aLast = if ($null -ne $a) { Get-DoubleOrNaN $a.last_time_ms } else { [double]::NaN }

    [PSCustomObject]@{
        part = $part
        measure = $measure
        status = if (
            $aEvent -eq $bEvent -and
            $aOn -eq $bOn -and
            $aOff -eq $bOff -and
            $aMarker -eq $bMarker
        ) { "OK" } else { "DIFF" }
        base_events = $bEvent
        active_events = $aEvent
        delta_events = $aEvent - $bEvent
        base_note_on = $bOn
        active_note_on = $aOn
        delta_note_on = $aOn - $bOn
        base_note_off = $bOff
        active_note_off = $aOff
        delta_note_off = $aOff - $bOff
        base_markers = $bMarker
        active_markers = $aMarker
        delta_markers = $aMarker - $bMarker
        base_first_ms = $bFirst
        active_first_ms = $aFirst
        delta_first_ms = if ([double]::IsNaN($bFirst) -or [double]::IsNaN($aFirst)) { [double]::NaN } else { $aFirst - $bFirst }
        base_last_ms = $bLast
        active_last_ms = $aLast
        delta_last_ms = if ([double]::IsNaN($bLast) -or [double]::IsNaN($aLast)) { [double]::NaN } else { $aLast - $bLast }
    }
}

$rows = $rows | Sort-Object part, measure

Write-Output "=== Measure Walkthrough (Base vs Active) ==="
$rows | Format-Table -AutoSize

Write-Output ""
Write-Output "=== First Divergence ==="
$firstDiff = $rows | Where-Object { $_.status -eq "DIFF" } | Select-Object -First 1
if ($null -eq $firstDiff) {
    Write-Output "No summary-level divergences found."
} else {
    $firstDiff | Format-Table -AutoSize
}

Write-Output ""
Write-Output "=== Focus Measure Summary (Part $FocusPart, Measure $FocusMeasure) ==="
$focusSummary = $rows | Where-Object { $_.part -eq $FocusPart -and $_.measure -eq $FocusMeasure }
if ($focusSummary) {
    $focusSummary | Format-Table -AutoSize
} else {
    Write-Output "No summary row found for focus measure."
}

$haveEventFiles = $BaseEventsCsv -ne "" -and $ActiveEventsCsv -ne ""
if (-not $haveEventFiles) {
    Write-Output ""
    Write-Output "Event-level deep diff skipped. Provide -BaseEventsCsv and -ActiveEventsCsv to compare event ordering/content in the focus measure."
    exit 0
}

Assert-File -Path $BaseEventsCsv -Label "Base events CSV"
Assert-File -Path $ActiveEventsCsv -Label "Active events CSV"

$baseEventsAll = Import-Csv -Path $BaseEventsCsv
$activeEventsAll = Import-Csv -Path $ActiveEventsCsv

$baseFocus = @(
    $baseEventsAll |
        Where-Object {
            (Get-IntOrZero $_.part) -eq $FocusPart -and
            (Get-IntOrZero $_.measure) -eq $FocusMeasure
        }
)
$activeFocus = @(
    $activeEventsAll |
        Where-Object {
            (Get-IntOrZero $_.part) -eq $FocusPart -and
            (Get-IntOrZero $_.measure) -eq $FocusMeasure
        }
)

$baseFocus = Sort-Events $baseFocus
$activeFocus = Sort-Events $activeFocus

Write-Output ""
Write-Output "=== Focus Measure Event-Type Counts (Base) ==="
$baseFocus | Group-Object event_type | Sort-Object Name | Select-Object Name, Count | Format-Table -AutoSize

Write-Output ""
Write-Output "=== Focus Measure Event-Type Counts (Active) ==="
$activeFocus | Group-Object event_type | Sort-Object Name | Select-Object Name, Count | Format-Table -AutoSize

$max = [Math]::Max($baseFocus.Count, $activeFocus.Count)
$limit = [Math]::Min($max, [Math]::Max($MaxFocusRows, 1))
$paired = @()

for ($i = 0; $i -lt $limit; $i++) {
    $b = if ($i -lt $baseFocus.Count) { $baseFocus[$i] } else { $null }
    $a = if ($i -lt $activeFocus.Count) { $activeFocus[$i] } else { $null }

    $bType = if ($null -ne $b) { "$($b.event_type)" } else { "" }
    $aType = if ($null -ne $a) { "$($a.event_type)" } else { "" }
    $bTime = if ($null -ne $b) { Get-DoubleOrNaN $b.time_ms } else { [double]::NaN }
    $aTime = if ($null -ne $a) { Get-DoubleOrNaN $a.time_ms } else { [double]::NaN }
    $bNote = if ($null -ne $b) { Get-IntOrZero $b.note } else { 0 }
    $aNote = if ($null -ne $a) { Get-IntOrZero $a.note } else { 0 }
    $bOwner = if ($null -ne $b) { "$($b.owner_label)" } else { "" }
    $aOwner = if ($null -ne $a) { "$($a.owner_label)" } else { "" }

    $isMatch = (
        $bType -eq $aType -and
        $bNote -eq $aNote -and
        $bOwner -eq $aOwner -and
        (
            ([double]::IsNaN($bTime) -and [double]::IsNaN($aTime)) -or
            ((-not [double]::IsNaN($bTime)) -and (-not [double]::IsNaN($aTime)) -and ([Math]::Abs($aTime - $bTime) -lt 0.0001))
        )
    )

    $paired += [PSCustomObject]@{
        idx = $i
        match = if ($isMatch) { "OK" } else { "DIFF" }
        base_time_ms = $bTime
        active_time_ms = $aTime
        base_type = $bType
        active_type = $aType
        base_note = if ($null -ne $b) { $bNote } else { $null }
        active_note = if ($null -ne $a) { $aNote } else { $null }
        base_owner = $bOwner
        active_owner = $aOwner
        base_support_tail = if ($null -ne $b) { "$($b.loop_is_support_tail)" } else { "" }
        active_support_tail = if ($null -ne $a) { "$($a.loop_is_support_tail)" } else { "" }
        time_delta_ms = if ([double]::IsNaN($bTime) -or [double]::IsNaN($aTime)) { [double]::NaN } else { $aTime - $bTime }
    }
}

Write-Output ""
Write-Output "=== Focus Measure Event Pairing (first $limit rows) ==="
$paired | Format-Table -AutoSize

Write-Output ""
Write-Output "=== Focus Measure Event-Level Differences ==="
$paired | Where-Object { $_.match -eq "DIFF" } | Format-Table -AutoSize

if ($max -gt $limit) {
    Write-Output ""
    Write-Output "Truncated event pairing output at $limit rows (set -MaxFocusRows higher to inspect all rows)."
}
