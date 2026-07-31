#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$BundlePath = $PSScriptRoot,

    [Parameter()]
    [string]$ClaudeConfigDirectory,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$bundle = [System.IO.Path]::GetFullPath($BundlePath)
$manifestPath = Join-Path $bundle 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Bundle manifest not found: $manifestPath" }
$manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -ErrorAction Stop
$projectPath = Split-Path -Parent $bundle
$config = if ($ClaudeConfigDirectory) {
    [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ClaudeConfigDirectory))
}
elseif ($env:CLAUDE_CONFIG_DIR) {
    [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($env:CLAUDE_CONFIG_DIR))
}
else {
    Join-Path $HOME '.claude'
}
$projects = Join-Path $config 'projects'
[void](New-Item -ItemType Directory -Path $projects -Force)
$folderName = $projectPath.Replace(':', '-').Replace('\', '-').Replace('/', '-')
$destination = Join-Path $projects $folderName
if (Test-Path -LiteralPath $destination) {
    if (-not $Force.IsPresent) { throw "Claude metadata already exists: $destination. Use -Force only after reviewing it." }
    $backup = $destination + '.restore-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Move-Item -LiteralPath $destination -Destination $backup
    Write-Host "Existing metadata backed up: $backup" -ForegroundColor Yellow
}
Copy-Item -LiteralPath (Join-Path $bundle 'metadata') -Destination $destination -Recurse -Force

$oldJson = ([string]$manifest.currentPath | ConvertTo-Json -Compress).Trim('"')
$newJson = ($projectPath | ConvertTo-Json -Compress).Trim('"')
$pattern = '("cwd"\s*:\s*")' + [regex]::Escape($oldJson) + '(")'
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($file in Get-ChildItem -LiteralPath $destination -Filter '*.jsonl' -File -Recurse) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    $updated = [regex]::Replace(
        $content,
        $pattern,
        [Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + $newJson + $match.Groups[2].Value },
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    [System.IO.File]::WriteAllText($file.FullName, $updated, $utf8)
}

$historySource = Join-Path $bundle 'file-history'
if (Test-Path -LiteralPath $historySource -PathType Container) {
    $historyTarget = Join-Path $config 'file-history'
    [void](New-Item -ItemType Directory -Path $historyTarget -Force)
    foreach ($directory in Get-ChildItem -LiteralPath $historySource -Directory) {
        Copy-Item -LiteralPath $directory.FullName -Destination (Join-Path $historyTarget $directory.Name) -Recurse -Force
    }
}
$runtimeSource = Join-Path $bundle 'runtime'
if (Test-Path -LiteralPath $runtimeSource -PathType Container) {
    $runtimeTarget = Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) 'claude') $folderName
    [void](New-Item -ItemType Directory -Path $runtimeTarget -Force)
    foreach ($directory in Get-ChildItem -LiteralPath $runtimeSource -Directory) {
        Copy-Item -LiteralPath $directory.FullName -Destination (Join-Path $runtimeTarget $directory.Name) -Recurse -Force
    }
}

Write-Host "Claude session restored for: $projectPath" -ForegroundColor Green
Write-Host "Metadata: $destination"
