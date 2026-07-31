#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$guiPath = Join-Path $repositoryRoot 'claude-project-mover-gui.ps1'
$content = [System.IO.File]::ReadAllText($guiPath)

if ($content -notmatch '(?m)^\$projectVersion = \$ScriptVersion\s*$') {
    throw 'The GUI does not use its embedded version as the authoritative display version.'
}
if ($content -match '(?m)^\$versionFile\s*=') {
    throw 'The GUI still allows a neighboring VERSION file to override its embedded version.'
}

Write-Host 'GUI version source test passed.' -ForegroundColor Green
