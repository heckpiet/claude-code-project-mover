#requires -Version 5.1

<#
.SYNOPSIS
Increments the project version consistently.

.DESCRIPTION
Updates VERSION, README, and the embedded version values in the PowerShell,
Bash, and CMD entry points. The version follows Semantic Versioning.

.EXAMPLE
.\scripts\Update-Version.ps1 -Part Minor

.EXAMPLE
.\scripts\Update-Version.ps1 -Part Patch -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Major', 'Minor', 'Patch')]
    [string]$Part
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $repositoryRoot 'VERSION'
$mainScriptPath = Join-Path $repositoryRoot 'claude-project-mover.ps1'
$guiScriptPath = Join-Path $repositoryRoot 'claude-project-mover-gui.ps1'
$bashScriptPath = Join-Path $repositoryRoot 'claude-project-mover.sh'
$cmdScriptPath = Join-Path $repositoryRoot 'Start-ClaudeProjectMover.cmd'
$readmePath = Join-Path $repositoryRoot 'README.md'

if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    throw "VERSION file not found at '$versionPath'."
}
if (-not (Test-Path -LiteralPath $mainScriptPath -PathType Leaf)) {
    throw "Main script not found at '$mainScriptPath'."
}
if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
    throw "README not found at '$readmePath'."
}
foreach ($entryPointPath in @($guiScriptPath, $bashScriptPath, $cmdScriptPath)) {
    if (-not (Test-Path -LiteralPath $entryPointPath -PathType Leaf)) {
        throw "Entry point not found at '$entryPointPath'."
    }
}

$currentVersion = [version](Get-Content -LiteralPath $versionPath -Raw).Trim()
$major = $currentVersion.Major
$minor = $currentVersion.Minor
$patch = $currentVersion.Build

switch ($Part) {
    'Major' { $major++; $minor = 0; $patch = 0 }
    'Minor' { $minor++; $patch = 0 }
    'Patch' { $patch++ }
}

$newVersion = '{0}.{1}.{2}' -f $major, $minor, $patch
$scriptContent = [System.IO.File]::ReadAllText($mainScriptPath)
$guiContent = [System.IO.File]::ReadAllText($guiScriptPath)
$versionPattern = "(?m)^\`$ScriptVersion = '[^']+'\s*$"
if (-not [regex]::IsMatch($scriptContent, $versionPattern)) {
    throw 'Could not find $ScriptVersion in claude-project-mover.ps1.'
}
if (-not [regex]::IsMatch($guiContent, $versionPattern)) {
    throw 'Could not find $ScriptVersion in claude-project-mover-gui.ps1.'
}
$readmeContent = [System.IO.File]::ReadAllText($readmePath)
$bashContent = [System.IO.File]::ReadAllText($bashScriptPath)
$cmdContent = [System.IO.File]::ReadAllText($cmdScriptPath)
$readmeVersionPattern = '(?m)^Aktuelle Version: \*\*[^*]+\*\*\s*$'
if (-not [regex]::IsMatch($readmeContent, $readmeVersionPattern)) {
    throw 'Could not find the current version line in README.md.'
}
$bashVersionPattern = '(?m)^SCRIPT_VERSION="[^"]+"\s*$'
$cmdVersionPattern = '(?mi)^set "SCRIPT_VERSION=[^"]+"\s*$'
if (-not [regex]::IsMatch($bashContent, $bashVersionPattern)) {
    throw 'Could not find SCRIPT_VERSION in claude-project-mover.sh.'
}
if (-not [regex]::IsMatch($cmdContent, $cmdVersionPattern)) {
    throw 'Could not find SCRIPT_VERSION in Start-ClaudeProjectMover.cmd.'
}

if ($PSCmdlet.ShouldProcess($repositoryRoot, "Update version from $currentVersion to $newVersion")) {
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($versionPath, $newVersion + [Environment]::NewLine, $utf8WithoutBom)
    $updatedScript = [regex]::Replace(
        $scriptContent,
        $versionPattern,
        "`$ScriptVersion = '$newVersion'"
    )
    [System.IO.File]::WriteAllText($mainScriptPath, $updatedScript, $utf8WithBom)
    $updatedGui = [regex]::Replace(
        $guiContent,
        $versionPattern,
        "`$ScriptVersion = '$newVersion'"
    )
    [System.IO.File]::WriteAllText($guiScriptPath, $updatedGui, $utf8WithBom)
    $updatedReadme = [regex]::Replace(
        $readmeContent,
        $readmeVersionPattern,
        "Aktuelle Version: **$newVersion**"
    )
    [System.IO.File]::WriteAllText($readmePath, $updatedReadme, $utf8WithoutBom)
    $updatedBash = [regex]::Replace($bashContent, $bashVersionPattern, "SCRIPT_VERSION=`"$newVersion`"")
    [System.IO.File]::WriteAllText($bashScriptPath, $updatedBash, $utf8WithoutBom)
    $updatedCmd = [regex]::Replace($cmdContent, $cmdVersionPattern, "set `"SCRIPT_VERSION=$newVersion`"")
    [System.IO.File]::WriteAllText($cmdScriptPath, $updatedCmd, $utf8WithoutBom)

    Write-Host "Version updated: $currentVersion -> $newVersion" -ForegroundColor Green
    Write-Host 'Next: update CHANGELOG.md, commit, merge, then tag the release.' -ForegroundColor Yellow
}
