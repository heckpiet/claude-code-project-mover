#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$mover = Join-Path $repositoryRoot 'claude-project-mover.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('cm-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$configRoot = Join-Path $testRoot '.claude'
$projectsRoot = Join-Path $configRoot 'projects'
$generalSource = Join-Path $testRoot 'general-source'
$targetRoot = Join-Path $testRoot 'target'
$folderName = 'server-ssh-zugriff-{0}berpr{0}fen' -f [char]0x00FC
$targetProject = Join-Path $targetRoot $folderName
$oldConfig = $env:CLAUDE_CONFIG_DIR
$sessionId = '28e4307f-feb3-4911-b3b3-f3dd264b6a58'
$runtimeRoot = $null

try {
    [void](New-Item -ItemType Directory -Path $projectsRoot, $generalSource, $targetRoot -Force)
    [System.IO.File]::WriteAllText((Join-Path $generalSource 'unrelated.txt'), 'general folder')
    $artifactRoot = Join-Path $generalSource 'server-docs'
    [void](New-Item -ItemType Directory -Path $artifactRoot)
    $artifactPath = Join-Path $artifactRoot 'server-report.md'
    [System.IO.File]::WriteAllText($artifactPath, '# Server report')
    $sensitiveRoot = Join-Path $generalSource '.ssh'
    [void](New-Item -ItemType Directory -Path $sensitiveRoot)
    [System.IO.File]::WriteAllText((Join-Path $sensitiveRoot 'config'), 'Host test')

    $oldMetadataName = $generalSource.Replace(':', '-').Replace('\', '-').Replace('/', '-')
    $oldMetadata = Join-Path $projectsRoot $oldMetadataName
    [void](New-Item -ItemType Directory -Path $oldMetadata)
    $escapedSource = $generalSource.Replace('\', '\\')
    $escapedArtifact = $artifactPath.Replace('\', '\\')
    $escapedSensitive = (Join-Path $sensitiveRoot 'config').Replace('\', '\\')
    $records = @(
        ('{"type":"user","cwd":"' + $escapedSource + '","message":{"role":"user","content":"Test session"}}')
        ('{"type":"assistant","cwd":"' + $escapedSource + '","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"' + $escapedArtifact + '"}}]}}')
        ('{"type":"assistant","cwd":"' + $escapedSource + '","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"' + $escapedSensitive + '"}}]}}')
        ('{"type":"file-history-delta","cwd":"' + $escapedSource + '","trackingPath":"server-docs\\server-report.md","backup":{"backupFileName":"report@v1","realParentDir":"' + $escapedSource + '"}}')
    )
    [System.IO.File]::WriteAllText((Join-Path $oldMetadata ($sessionId + '.jsonl')), ($records -join [Environment]::NewLine) + [Environment]::NewLine)
    $historyRoot = Join-Path (Join-Path $configRoot 'file-history') $sessionId
    [void](New-Item -ItemType Directory -Path $historyRoot -Force)
    [System.IO.File]::WriteAllText((Join-Path $historyRoot 'report@v1'), '# Earlier report')
    $tempProjectName = $generalSource.Replace(':', '-').Replace('\', '-').Replace('/', '-')
    $runtimeRoot = Join-Path (Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) 'claude') $tempProjectName) $sessionId
    [void](New-Item -ItemType Directory -Path (Join-Path $runtimeRoot 'scratchpad'), (Join-Path $runtimeRoot 'tasks') -Force)
    [System.IO.File]::WriteAllText((Join-Path $runtimeRoot 'scratchpad\helper.ps1'), 'Write-Host helper')
    [System.IO.File]::WriteAllText((Join-Path $runtimeRoot 'tasks\task.output'), 'done')

    $env:CLAUDE_CONFIG_DIR = $configRoot
    & $mover -ProjectPath $generalSource -NewPath $targetRoot -CreateProjectFolder `
        -ProjectFolderName $folderName -Yes -SkipSpaceCheck

    if (-not (Test-Path -LiteralPath $targetProject -PathType Container)) { throw 'Dedicated destination folder was not created.' }
    if (Test-Path -LiteralPath $oldMetadata) { throw 'Old metadata directory still exists.' }

    $newMetadataName = $targetProject.Replace(':', '-').Replace('\', '-').Replace('/', '-')
    $newMetadata = Join-Path $projectsRoot $newMetadataName
    if (-not (Test-Path -LiteralPath $newMetadata -PathType Container)) { throw 'New metadata directory was not activated.' }
    $updatedContent = [System.IO.File]::ReadAllText((Join-Path $newMetadata ($sessionId + '.jsonl')))
    if ($updatedContent -notlike ('*' + $targetProject.Replace('\', '\\') + '*')) { throw 'Updated metadata does not contain the new cwd path.' }
    if ($updatedContent -notlike ('*' + $escapedArtifact + '*')) { throw 'Historical tool path was modified instead of preserving the original artifact path.' }

    if (-not (Test-Path -LiteralPath (Join-Path $targetProject 'server-docs\server-report.md') -PathType Leaf)) { throw 'Safe session artifact was not copied.' }
    if (Test-Path -LiteralPath (Join-Path $targetProject '.ssh\config') -PathType Leaf) { throw 'Sensitive session artifact was copied without approval.' }
    $bundle = Join-Path $targetProject '.claude-session-bundle'
    if (-not (Test-Path -LiteralPath (Join-Path $bundle ('metadata\' + $sessionId + '.jsonl')) -PathType Leaf)) { throw 'Portable metadata copy is missing.' }
    if (-not (Test-Path -LiteralPath (Join-Path $bundle ('file-history\' + $sessionId + '\report@v1')) -PathType Leaf)) { throw 'Portable file history is missing.' }
    if (-not (Test-Path -LiteralPath (Join-Path $bundle ('runtime\' + $sessionId + '\scratchpad\helper.ps1')) -PathType Leaf)) { throw 'Portable scratchpad is missing.' }
    if (-not (Test-Path -LiteralPath (Join-Path $bundle ('runtime\' + $sessionId + '\tasks\task.output')) -PathType Leaf)) { throw 'Portable task output is missing.' }
    $restoreScript = Join-Path $bundle 'Restore-ClaudeSession.ps1'
    if (-not (Test-Path -LiteralPath $restoreScript -PathType Leaf)) { throw 'PowerShell restore helper is missing.' }
    $restoreConfig = Join-Path $testRoot 'restored-claude'
    & $restoreScript -ClaudeConfigDirectory $restoreConfig
    $restoredMetadata = Join-Path (Join-Path $restoreConfig 'projects') $newMetadataName
    if (-not (Test-Path -LiteralPath (Join-Path $restoredMetadata ($sessionId + '.jsonl')) -PathType Leaf)) { throw 'Restore helper did not install session metadata.' }
    if (-not (Test-Path -LiteralPath (Join-Path $restoreConfig ('file-history\' + $sessionId + '\report@v1')) -PathType Leaf)) { throw 'Restore helper did not install file history.' }

    $originPath = Join-Path $targetProject '.claude-project-origin.json'
    if (-not (Test-Path -LiteralPath $originPath -PathType Leaf)) { throw 'Origin metadata manifest was not created.' }
    $origin = [System.IO.File]::ReadAllText($originPath) | ConvertFrom-Json
    if ($origin.schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$origin.projectId)) { throw 'Origin metadata schema or project ID is invalid.' }
    if ($origin.currentPath -ne $targetProject -or @($origin.transfers).Count -ne 1) { throw 'Origin metadata path or transfer history is invalid.' }
    $transfer = @($origin.transfers)[0]
    if ($transfer.source.path -ne $generalSource -or $transfer.mode -ne 'CreateFolder') { throw 'Origin source path or transfer mode is invalid.' }
    if (-not $transfer.verification.metadataValid -or -not $transfer.verification.cwdUpdated) { throw 'Origin verification flags are invalid.' }

    $firstProjectId = [string]$origin.projectId
    $secondTarget = Join-Path $targetRoot 'dedicated-session-project-moved'
    Move-Item -LiteralPath $targetProject -Destination $secondTarget
    & $mover -ProjectPath $targetProject -NewPath $secondTarget -TransferMode Move -Yes -SkipSpaceCheck -Force

    $secondOriginPath = Join-Path $secondTarget '.claude-project-origin.json'
    $secondOrigin = [System.IO.File]::ReadAllText($secondOriginPath) | ConvertFrom-Json
    if ([string]$secondOrigin.projectId -ne $firstProjectId) { throw 'Project ID was not preserved across transfers.' }
    if ($secondOrigin.currentPath -ne $secondTarget -or @($secondOrigin.transfers).Count -ne 2) { throw 'Transfer history was not appended.' }
    $secondTransfer = @($secondOrigin.transfers)[1]
    if ($secondTransfer.source.path -ne $targetProject -or $secondTransfer.mode -ne 'Move') { throw 'Second transfer history entry is invalid.' }

    Write-Host 'Folderless migration integration test passed.' -ForegroundColor Green
}
finally {
    $env:CLAUDE_CONFIG_DIR = $oldConfig
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTest)) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
    if ($runtimeRoot -and (Test-Path -LiteralPath $runtimeRoot)) {
        Remove-Item -LiteralPath $runtimeRoot -Recurse -Force
    }
}
