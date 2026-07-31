#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$mover = Join-Path $repositoryRoot 'claude-project-mover.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('cm-adopt-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$configRoot = Join-Path $testRoot '.claude'
$projectsRoot = Join-Path $configRoot 'projects'
$collection = Join-Path $testRoot 'collection'
$destination = Join-Path (Join-Path $testRoot 'target') 'server-ssh-zugriff-pruefen'
$oldConfig = $env:CLAUDE_CONFIG_DIR

try {
    [void](New-Item -ItemType Directory -Path $projectsRoot, $collection, $destination -Force)
    [System.IO.File]::WriteAllText((Join-Path $destination 'existing.txt'), 'keep me')
    $artifactRoot = Join-Path $collection 'server-docs'
    [void](New-Item -ItemType Directory -Path $artifactRoot)
    [System.IO.File]::WriteAllText((Join-Path $artifactRoot 'report.md'), '# report')
    $oldMetadataName = $collection.Replace(':', '-').Replace('\', '-').Replace('/', '-')
    $oldMetadata = Join-Path $projectsRoot $oldMetadataName
    [void](New-Item -ItemType Directory -Path $oldMetadata)
    $sessionId = '33333333-3333-3333-3333-333333333333'
    $escapedCollection = $collection.Replace('\', '\\')
    $escapedArtifact = (Join-Path $artifactRoot 'report.md').Replace('\', '\\')
    $json = @(
        '{"type":"user","cwd":"' + $escapedCollection + '","message":{"role":"user","content":"Server prüfen"}}'
        '{"type":"assistant","cwd":"' + $escapedCollection + '","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"' + $escapedArtifact + '"}}]}}'
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText((Join-Path $oldMetadata ($sessionId + '.jsonl')), $json + [Environment]::NewLine)

    $env:CLAUDE_CONFIG_DIR = $configRoot
    & $mover -ProjectPath $collection -NewPath $destination -AdoptExistingProjectFolder -Yes -SkipSpaceCheck

    if (-not (Test-Path -LiteralPath (Join-Path $destination 'existing.txt') -PathType Leaf)) {
        throw 'Existing destination content was not preserved.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'server-docs\report.md') -PathType Leaf)) {
        throw 'Safe session artifact was not copied into the adopted folder.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destination '.claude-session-bundle\manifest.json') -PathType Leaf)) {
        throw 'Session bundle was not created in the adopted folder.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destination '.claude-project-origin.json') -PathType Leaf)) {
        throw 'Origin metadata was not created in the adopted folder.'
    }

    Write-Host 'Existing destination adoption test passed.' -ForegroundColor Green
}
finally {
    $env:CLAUDE_CONFIG_DIR = $oldConfig
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
