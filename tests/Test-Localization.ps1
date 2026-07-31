#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'ClaudeProjectLocalization.psm1') -Force

if ((Resolve-ClaudeMoverLanguage -Language en) -ne 'en') { throw 'English language selection failed.' }
if ((Resolve-ClaudeMoverLanguage -Language de) -ne 'de') { throw 'German language selection failed.' }
if ((Get-ClaudeMoverText -English 'Ready' -German 'Bereit' -Language en) -ne 'Ready') { throw 'English translation failed.' }
if ((Get-ClaudeMoverText -English 'Ready' -German 'Bereit' -Language de) -ne 'Bereit') { throw 'German translation failed.' }
if ((Get-ClaudeMoverText -English 'Found {0}' -German '{0} gefunden' -Language en -Arguments 3) -ne 'Found 3') { throw 'Localized formatting failed.' }

foreach ($file in @('claude-project-mover.ps1', 'claude-project-mover-gui.ps1')) {
    $content = Get-Content -LiteralPath (Join-Path $root $file) -Raw
    if ($content -notmatch "ValidateSet\('Auto', 'de', 'en'\)") { throw "$file does not expose the language selector." }
    if ($content -notmatch 'ClaudeProjectLocalization\.psm1') { throw "$file does not load the localization module." }
}

$starter = Get-Content -LiteralPath (Join-Path $root 'Start-ClaudeProjectMover.cmd') -Raw
if ($starter -notmatch 'ClaudeProjectLocalization\.psm1') { throw 'CMD starter does not require the localization module.' }

Write-Host 'Localization tests passed.' -ForegroundColor Green
