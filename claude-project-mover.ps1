#requires -Version 7.0
<#
.SYNOPSIS
Updates Claude Code project metadata after a project directory has been moved.

.DESCRIPTION
Claude Code stores project sessions below ~/.claude/projects using directory names
derived from the absolute project path. This script updates path references in the
stored project metadata and renames the corresponding Claude Code project directory.

The actual source project must be moved before this script is executed.

.PARAMETER OldPath
Original absolute project path. When omitted, an interactive project selection is shown.

.PARAMETER NewPath
New absolute project path. When omitted, the script asks for it interactively.

.PARAMETER NoBackup
Skips creation of a ZIP backup. Backups are enabled by default.

.PARAMETER Force
Skips the final confirmation prompt.

.EXAMPLE
./claude-project-mover.ps1

.EXAMPLE
./claude-project-mover.ps1 -OldPath 'C:\Dev\OldProject' -NewPath 'D:\Projects\OldProject'

.EXAMPLE
./claude-project-mover.ps1 -NewPath 'D:\Projects\MyProject' -Force
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string]$OldPath,

    [Parameter()]
    [string]$NewPath,

    [Parameter()]
    [switch]$NoBackup,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectsDirectory = Join-Path $HOME '.claude/projects'
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('─' * $Title.Length) -ForegroundColor Cyan
}

function Resolve-NormalizedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$RequireExisting
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'The path must not be empty.'
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))

    if (-not [System.IO.Path]::IsPathFullyQualified($expanded)) {
        throw "The path must be absolute: $expanded"
    }

    if ($RequireExisting -and -not (Test-Path -LiteralPath $expanded -PathType Container)) {
        throw "The directory does not exist: $expanded"
    }

    if (Test-Path -LiteralPath $expanded) {
        return (Resolve-Path -LiteralPath $expanded).Path.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    }

    return [System.IO.Path]::GetFullPath($expanded).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function ConvertTo-ClaudeProjectFolderName {
    param([Parameter(Mandatory)][string]$Path)

    # Claude Code uses a flattened representation of the absolute path.
    # Examples:
    #   /Users/martin/project       -> -Users-martin-project
    #   /Users/martin/.config/app   -> -Users-martin--config-app
    #   C:\Users\Martin\project     -> C--Users-Martin-project
    $portablePath = $Path -replace '\\', '/'
    $portablePath = $portablePath -replace '/\.', '--'
    $portablePath = $portablePath -replace '[:/]', '-'

    return $portablePath
}

function Get-CwdFromJsonLine {
    param([Parameter(Mandatory)][string]$Line)

    try {
        $record = $Line | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $record.PSObject.Properties['cwd'] -and
            -not [string]::IsNullOrWhiteSpace([string]$record.cwd)) {
            return [string]$record.cwd
        }
    }
    catch {
        # Some JSONL records may be incomplete or contain content that cannot be
        # parsed independently. The regex fallback below only extracts cwd.
    }

    $match = [regex]::Match($Line, '"cwd"\s*:\s*"(?<cwd>(?:\\.|[^"\\])*)"')
    if ($match.Success) {
        try {
            return ('"' + $match.Groups['cwd'].Value + '"') | ConvertFrom-Json
        }
        catch {
            return $match.Groups['cwd'].Value
        }
    }

    return $null
}

function Get-ClaudeProjectReadablePath {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$ProjectDirectory)

    $jsonlFiles = Get-ChildItem -LiteralPath $ProjectDirectory.FullName -Filter '*.jsonl' -File |
        Sort-Object LastWriteTime -Descending

    foreach ($file in $jsonlFiles) {
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            $cwd = Get-CwdFromJsonLine -Line $line
            if (-not [string]::IsNullOrWhiteSpace($cwd)) {
                return $cwd
            }
        }
    }

    # This is only a display fallback. Folder names are not always fully reversible.
    return $ProjectDirectory.Name
}

function Get-ClaudeProjects {
    if (-not (Test-Path -LiteralPath $ProjectsDirectory -PathType Container)) {
        throw "Claude Code projects directory not found: $ProjectsDirectory"
    }

    $projects = foreach ($directory in Get-ChildItem -LiteralPath $ProjectsDirectory -Directory) {
        if ($directory.Name -like 'BACKUP__*') {
            continue
        }

        [pscustomobject]@{
            Folder        = $directory.Name
            FullName      = $directory.FullName
            ReadablePath  = Get-ClaudeProjectReadablePath -ProjectDirectory $directory
            LastWriteTime = $directory.LastWriteTime
        }
    }

    return @($projects | Sort-Object ReadablePath)
}

function Select-ClaudeProject {
    param([Parameter(Mandatory)][array]$Projects)

    if ($Projects.Count -eq 0) {
        throw "No Claude Code projects found below $ProjectsDirectory"
    }

    $fzf = Get-Command fzf -ErrorAction SilentlyContinue
    if ($null -ne $fzf) {
        $selection = $Projects |
            ForEach-Object { "$($_.ReadablePath)`t$($_.Folder)" } |
            & $fzf.Source --delimiter "`t" --with-nth 1 --prompt 'Search project: ' --height '40%' --reverse

        if ([string]::IsNullOrWhiteSpace($selection)) {
            throw 'No project selected.'
        }

        $selectedFolder = ($selection -split "`t", 2)[1]
        return $Projects | Where-Object Folder -EQ $selectedFolder | Select-Object -First 1
    }

    Write-Section 'Select a Claude Code project'
    for ($index = 0; $index -lt $Projects.Count; $index++) {
        Write-Host ('{0,3}) {1}' -f ($index + 1), $Projects[$index].ReadablePath)
    }

    while ($true) {
        $answer = Read-Host "Enter project number (1-$($Projects.Count))"
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and
            $number -ge 1 -and $number -le $Projects.Count) {
            return $Projects[$number - 1]
        }

        Write-Warning "Enter a number between 1 and $($Projects.Count)."
    }
}

function New-ProjectBackup {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$ProjectDirectory)

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupName = "BACKUP__$($ProjectDirectory.Name)__$timestamp.zip"
    $backupPath = Join-Path $ProjectsDirectory $backupName

    Compress-Archive -LiteralPath $ProjectDirectory.FullName -DestinationPath $backupPath -CompressionLevel Optimal
    return $backupPath
}

function Get-JsonEscapedPath {
    param([Parameter(Mandatory)][string]$Path)

    # ConvertTo-Json gives us exactly the escaping used inside JSON strings.
    $jsonString = $Path | ConvertTo-Json -Compress
    return $jsonString.Substring(1, $jsonString.Length - 2)
}

function Update-ProjectMetadataFiles {
    param(
        [Parameter(Mandatory)][System.IO.DirectoryInfo]$ProjectDirectory,
        [Parameter(Mandatory)][string]$OriginalPath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $oldVariants = [System.Collections.Generic.List[string]]::new()
    $newVariants = [System.Collections.Generic.List[string]]::new()

    $oldVariants.Add($OriginalPath)
    $newVariants.Add($DestinationPath)

    $oldJson = Get-JsonEscapedPath -Path $OriginalPath
    $newJson = Get-JsonEscapedPath -Path $DestinationPath
    if ($oldJson -ne $OriginalPath) {
        $oldVariants.Add($oldJson)
        $newVariants.Add($newJson)
    }

    $files = Get-ChildItem -LiteralPath $ProjectDirectory.FullName -File -Recurse
    $updatedFiles = 0
    $replacementCount = 0

    foreach ($file in $files) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)

        # Skip binary files. Claude metadata is text, but project folders may gain
        # attachments or caches in future versions.
        if ($bytes -contains 0) {
            continue
        }

        $content = $Utf8NoBom.GetString($bytes)
        $updatedContent = $content
        $fileReplacements = 0

        for ($i = 0; $i -lt $oldVariants.Count; $i++) {
            $before = $updatedContent
            $updatedContent = $updatedContent.Replace($oldVariants[$i], $newVariants[$i])
            if ($updatedContent -ne $before) {
                $fileReplacements += ([regex]::Matches(
                    $before,
                    [regex]::Escape($oldVariants[$i])
                )).Count
            }
        }

        if ($updatedContent -ne $content) {
            [System.IO.File]::WriteAllText($file.FullName, $updatedContent, $Utf8NoBom)
            $updatedFiles++
            $replacementCount += $fileReplacements
        }
    }

    return [pscustomobject]@{
        UpdatedFiles = $updatedFiles
        Replacements = $replacementCount
    }
}

Write-Host '=======================================' -ForegroundColor Green
Write-Host ' Claude Code Project Mover PowerShell' -ForegroundColor Green
Write-Host '=======================================' -ForegroundColor Green

$projects = Get-ClaudeProjects

if (-not [string]::IsNullOrWhiteSpace($OldPath)) {
    $normalizedOldPath = Resolve-NormalizedPath -Path $OldPath
    $project = $projects | Where-Object {
        try {
            (Resolve-NormalizedPath -Path $_.ReadablePath) -eq $normalizedOldPath
        }
        catch {
            $_.ReadablePath -eq $OldPath
        }
    } | Select-Object -First 1

    if ($null -eq $project) {
        throw "No Claude Code metadata entry found for: $OldPath"
    }
}
else {
    $project = Select-ClaudeProject -Projects $projects
    $normalizedOldPath = Resolve-NormalizedPath -Path $project.ReadablePath
}

if ([string]::IsNullOrWhiteSpace($NewPath)) {
    Write-Section 'Enter the new project location'
    Write-Host "Current: $normalizedOldPath" -ForegroundColor Yellow
    $NewPath = Read-Host 'New path'
}

$normalizedNewPath = Resolve-NormalizedPath -Path $NewPath -RequireExisting

if ($normalizedOldPath -eq $normalizedNewPath) {
    throw 'The old and new project paths are identical.'
}

$newFolderName = ConvertTo-ClaudeProjectFolderName -Path $normalizedNewPath
$newMetadataPath = Join-Path $ProjectsDirectory $newFolderName

if (Test-Path -LiteralPath $newMetadataPath) {
    throw "A Claude Code project entry already exists for the destination: $newMetadataPath"
}

Write-Section 'Planned metadata update'
Write-Host "From: $normalizedOldPath" -ForegroundColor Yellow
Write-Host "To:   $normalizedNewPath" -ForegroundColor Green
Write-Host "Data: $($project.FullName)"
Write-Host "New:  $newMetadataPath"

if (-not $Force) {
    $confirmation = Read-Host 'Proceed with the update? (y/n)'
    if ($confirmation -notmatch '^[YyJj]$') {
        Write-Warning 'Operation cancelled.'
        return
    }
}

if (-not $PSCmdlet.ShouldProcess(
    $project.FullName,
    "Replace project paths and rename metadata directory to '$newFolderName'"
)) {
    return
}

$backupPath = $null
try {
    if (-not $NoBackup) {
        Write-Host 'Creating backup...' -ForegroundColor Yellow
        $backupPath = New-ProjectBackup -ProjectDirectory ([System.IO.DirectoryInfo]$project.FullName)
        Write-Host "Backup: $backupPath" -ForegroundColor Green
    }

    Write-Host 'Updating path references...' -ForegroundColor Yellow
    $result = Update-ProjectMetadataFiles `
        -ProjectDirectory ([System.IO.DirectoryInfo]$project.FullName) `
        -OriginalPath $normalizedOldPath `
        -DestinationPath $normalizedNewPath

    if ($result.Replacements -eq 0) {
        Write-Warning 'No path references were found. The metadata directory will still be renamed.'
    }

    Write-Host 'Renaming Claude Code project metadata directory...' -ForegroundColor Yellow
    Move-Item -LiteralPath $project.FullName -Destination $newMetadataPath

    Write-Host ''
    Write-Host 'Project metadata updated successfully.' -ForegroundColor Green
    Write-Host "Updated files: $($result.UpdatedFiles)"
    Write-Host "Replacements:  $($result.Replacements)"
    Write-Host "Project path:  $normalizedNewPath" -ForegroundColor Cyan
    Write-Host "Metadata path: $newMetadataPath"
}
catch {
    Write-Error "The update failed: $($_.Exception.Message)"
    if ($backupPath) {
        Write-Warning "A backup is available at: $backupPath"
    }
    throw
}
