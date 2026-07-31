#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$module = Join-Path $repositoryRoot 'ClaudeProjectInventory.psm1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('cm-inventory-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$projectsRoot = Join-Path $testRoot 'projects'
$collection = Join-Path $testRoot 'Claude-Sammlung'
$child = Join-Path $collection 'unifi'

try {
    [void](New-Item -ItemType Directory -Path $projectsRoot, $collection, $child -Force)
    [System.IO.File]::WriteAllText((Join-Path $child 'CLAUDE.md'), '# UniFi')
    $collectionMetadata = Join-Path $projectsRoot 'collection'
    $childMetadata = Join-Path $projectsRoot 'child'
    [void](New-Item -ItemType Directory -Path $collectionMetadata, $childMetadata)
    $description = 'Server SSH-Zugriff {0}berpr{0}fen' -f [char]0x00FC
    $collectionJson = '{"type":"user","timestamp":"2026-07-30T20:00:00Z","cwd":"' + $collection.Replace('\', '\\') + '","message":{"role":"user","content":"' + $description + '"}}'
    $childJson = '{"type":"user","timestamp":"2026-07-29T20:00:00Z","cwd":"' + $child.Replace('\', '\\') + '","message":{"role":"user","content":"UniFi prüfen"}}'
    [System.IO.File]::WriteAllText((Join-Path $collectionMetadata '11111111-1111-1111-1111-111111111111.jsonl'), $collectionJson)
    [System.IO.File]::WriteAllText((Join-Path $childMetadata '22222222-2222-2222-2222-222222222222.jsonl'), $childJson)

    Import-Module $module -Force
    $inventory = @(Get-ClaudeProjectInventory -ProjectsDirectory $projectsRoot)
    $collectionProject = $inventory | Where-Object Path -EQ $collection
    $childProject = $inventory | Where-Object Path -EQ $child

    if ($null -eq $collectionProject) { throw 'Collection project was not found.' }
    if (-not $collectionProject.NeedsDedicatedFolder -or $collectionProject.FolderStatus -ne 'SAMMELORDNER') {
        throw 'A markerless parent containing another Claude project was not classified as a collection folder.'
    }
    if (-not $collectionProject.ContainsKnownProject) { throw 'Nested Claude project was not recorded.' }
    if ($childProject.NeedsDedicatedFolder) { throw 'Dedicated child project was incorrectly classified as a collection folder.' }
    $expectedSuggestion = 'server-ssh-zugriff-{0}berpr{0}fen' -f [char]0x00FC
    if ($collectionProject.SuggestedFolderName -ne $expectedSuggestion) {
        throw "Unexpected smart folder suggestion: $($collectionProject.SuggestedFolderName)"
    }

    Write-Host 'Collection folder detection test passed.' -ForegroundColor Green
}
finally {
    Remove-Module ClaudeProjectInventory -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
