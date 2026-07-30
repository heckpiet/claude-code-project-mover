#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$mover = Join-Path $repositoryRoot 'claude-project-mover.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-mover-test-' + [guid]::NewGuid().ToString('N'))
$configRoot = Join-Path $testRoot '.claude'
$projectsRoot = Join-Path $configRoot 'projects'
$generalSource = Join-Path $testRoot 'general-source'
$targetRoot = Join-Path $testRoot 'target'
$folderName = 'dedicated-session-project'
$targetProject = Join-Path $targetRoot $folderName
$oldConfig = $env:CLAUDE_CONFIG_DIR

try {
    [void](New-Item -ItemType Directory -Path $projectsRoot, $generalSource, $targetRoot -Force)
    [System.IO.File]::WriteAllText((Join-Path $generalSource 'unrelated.txt'), 'general folder')

    $oldMetadataName = $generalSource.Replace(':', '-').Replace('\', '-').Replace('/', '-')
    $oldMetadata = Join-Path $projectsRoot $oldMetadataName
    [void](New-Item -ItemType Directory -Path $oldMetadata)
    $escapedSource = $generalSource.Replace('\', '\\')
    $record = '{"type":"user","cwd":"' + $escapedSource + '","message":{"role":"user","content":"Test session"}}'
    [System.IO.File]::WriteAllText((Join-Path $oldMetadata 'session.jsonl'), $record + [Environment]::NewLine)

    $env:CLAUDE_CONFIG_DIR = $configRoot
    & $mover -ProjectPath $generalSource -NewPath $targetRoot -CreateProjectFolder `
        -ProjectFolderName $folderName -Yes -SkipSpaceCheck

    if (-not (Test-Path -LiteralPath $targetProject -PathType Container)) { throw 'Dedicated destination folder was not created.' }
    if (Test-Path -LiteralPath $oldMetadata) { throw 'Old metadata directory still exists.' }

    $newMetadataName = $targetProject.Replace(':', '-').Replace('\', '-').Replace('/', '-')
    $newMetadata = Join-Path $projectsRoot $newMetadataName
    if (-not (Test-Path -LiteralPath $newMetadata -PathType Container)) { throw 'New metadata directory was not activated.' }
    $updatedContent = [System.IO.File]::ReadAllText((Join-Path $newMetadata 'session.jsonl'))
    if ($updatedContent -notlike ('*' + $targetProject.Replace('\', '\\') + '*')) { throw 'Updated metadata does not contain the new cwd path.' }

    Write-Host 'Folderless migration integration test passed.' -ForegroundColor Green
}
finally {
    $env:CLAUDE_CONFIG_DIR = $oldConfig
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTest)) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
