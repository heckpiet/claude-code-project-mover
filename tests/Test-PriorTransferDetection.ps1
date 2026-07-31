#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$mover = Join-Path $repositoryRoot 'claude-project-mover.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('cm-repeat-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$configRoot = Join-Path $testRoot '.claude'
$projectsRoot = Join-Path $configRoot 'projects'
$source = Join-Path $testRoot 'source'
$targetRoot = Join-Path $testRoot 'target'
$destination = Join-Path $targetRoot 'project-copy'
$oldConfig = $env:CLAUDE_CONFIG_DIR
$sessionId = '44444444-4444-4444-4444-444444444444'

try {
    [void](New-Item -ItemType Directory -Path $projectsRoot, $source, $destination -Force)
    [System.IO.File]::WriteAllText((Join-Path $source 'CLAUDE.md'), '# source')
    [System.IO.File]::WriteAllText((Join-Path $destination 'CLAUDE.md'), '# destination')
    $metadataName = $source.Replace(':', '-').Replace('\', '-').Replace('/', '-')
    $metadata = Join-Path $projectsRoot $metadataName
    [void](New-Item -ItemType Directory -Path $metadata)
    $escapedSource = $source.Replace('\', '\\')
    [System.IO.File]::WriteAllText(
        (Join-Path $metadata ($sessionId + '.jsonl')),
        '{"type":"user","cwd":"' + $escapedSource + '","message":{"role":"user","content":"Test"}}'
    )
    $bundle = Join-Path $destination '.claude-session-bundle'
    [void](New-Item -ItemType Directory -Path $bundle)
    [System.IO.File]::WriteAllText(
        (Join-Path $bundle 'manifest.json'),
        ('{"sessions":["' + $sessionId + '"]}')
    )

    $env:CLAUDE_CONFIG_DIR = $configRoot
    $blocked = $false
    try {
        & $mover -ProjectPath $source -NewPath $destination -AdoptExistingProjectFolder -CheckOnly -Yes -SkipSpaceCheck
    }
    catch {
        if ($_.Exception.Message -like '*AllowRepeatedTransfer*') { $blocked = $true } else { throw }
    }
    if (-not $blocked) { throw 'Repeated transfer was not blocked.' }

    & $mover -ProjectPath $source -NewPath $destination -AdoptExistingProjectFolder -AllowRepeatedTransfer -CheckOnly -Yes -SkipSpaceCheck
    Write-Host 'Prior transfer detection test passed.' -ForegroundColor Green
}
finally {
    $env:CLAUDE_CONFIG_DIR = $oldConfig
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
