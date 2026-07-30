#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'ClaudeProjectInventory.psm1'
Import-Module -Name $modulePath -Force

$activity = [datetime]'2026-07-30T21:19:00'
$fromContent = New-InventoryFolderSuggestion -Description 'Bitte Server SSH access pruefen und absichern' -LastActivity $activity -SessionId 'abcdef123456'
if ($fromContent -ne 'server-ssh-access-pruefen-und-absichern') { throw "Unexpected content suggestion: '$fromContent'." }

$fallback = New-InventoryFolderSuggestion -Description '(no description available)' -LastActivity $activity -SessionId 'abcdef123456'
if ($fallback -ne 'claude-projekt-20260730-2119-abcdef12') { throw "Unexpected fallback suggestion: '$fallback'." }

if ($fromContent.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) { throw 'Suggestion contains invalid filename characters.' }
Write-Host 'Smart folder suggestion tests passed.' -ForegroundColor Green
