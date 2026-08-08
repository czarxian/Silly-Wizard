param(
    [switch]$Delete,
    [switch]$Performances,
    [switch]$Debug,
    [ValidateRange(0, 36500)]
    [int]$OlderThanDays = 0
)

$dataRoot = Join-Path $env:LOCALAPPDATA "Silly_Wizard\datafiles"
$selectedFolders = @()

if (-not $Performances -and -not $Debug) {
    $Performances = $true
    $Debug = $true
}
if ($Performances) {
    $selectedFolders += Join-Path $dataRoot "performances"
}
if ($Debug) {
    $selectedFolders += Join-Path $dataRoot "debug"
}

$files = @(
    $selectedFolders |
        Where-Object { Test-Path -LiteralPath $_ } |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -File -Recurse -ErrorAction Stop }
)
if ($OlderThanDays -gt 0) {
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $files = @($files | Where-Object { $_.LastWriteTime -lt $cutoff })
    Write-Output ("Selecting files older than {0} day(s), before {1:u}." -f $OlderThanDays, $cutoff)
}
$totalBytes = ($files | Measure-Object Length -Sum).Sum
if ($null -eq $totalBytes) {
    $totalBytes = 0
}

Write-Output ("Runtime history: {0} files, {1:N2} MiB" -f $files.Count, ($totalBytes / 1MB))
foreach ($folder in $selectedFolders) {
    $folderFiles = @($files | Where-Object { $_.FullName.StartsWith($folder, [System.StringComparison]::OrdinalIgnoreCase) })
    $folderBytes = ($folderFiles | Measure-Object Length -Sum).Sum
    if ($null -eq $folderBytes) {
        $folderBytes = 0
    }
    Write-Output ("  {0}: {1} files, {2:N2} MiB" -f $folder, $folderFiles.Count, ($folderBytes / 1MB))
}

if (-not $Delete) {
    Write-Output "Dry run only. Re-run with -Delete to remove these files and empty subdirectories."
    exit 0
}

$files | Remove-Item -Force -ErrorAction Stop
foreach ($folder in $selectedFolders) {
    if (-not (Test-Path -LiteralPath $folder)) {
        continue
    }
    Get-ChildItem -LiteralPath $folder -Directory -Recurse -ErrorAction Stop |
        Sort-Object FullName -Descending |
        Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } |
        Remove-Item -Force -ErrorAction Stop
}

Write-Output "Runtime history deleted. Tune content, configuration, and player settings were not touched."