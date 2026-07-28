#requires -Version 5.1

<#
.SYNOPSIS
Updates Claude Code project references after a project folder has been moved.

.DESCRIPTION
Claude Code stores session data below ~/.claude/projects in a directory whose
name is derived from the absolute project path. This script updates path
references in JSON/JSONL metadata files and renames the Claude project metadata
directory to match the new path.

The actual project directory must be moved before running this script.

.PARAMETER ProjectPath
The previous absolute path of the project. When omitted, an interactive project
selection is shown.

.PARAMETER NewPath
The new absolute path of the project. The directory must already exist.

.PARAMETER Backup
Creates a ZIP backup before changing files. In interactive mode, the script asks
whether a backup should be created when this switch is not supplied.

.PARAMETER Yes
Skips the final confirmation prompt. Intended for automation.

.EXAMPLE
.\claude-project-mover.ps1

.EXAMPLE
.\claude-project-mover.ps1 -ProjectPath 'C:\Users\Peter\Code\OldProject' -NewPath 'D:\Code\OldProject' -Backup -Yes
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$ProjectPath,

    [Parameter()]
    [string]$NewPath,

    [Parameter()]
    [switch]$Backup,

    [Parameter()]
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('─' * $Title.Length) -ForegroundColor Cyan
}

function Get-ClaudeConfigDirectory {
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CONFIG_DIR)) {
        return [System.IO.Path]::GetFullPath($env:CLAUDE_CONFIG_DIR)
    }

    return Join-Path $HOME '.claude'
}

function Get-ClaudeProjectsDirectory {
    return Join-Path (Get-ClaudeConfigDirectory) 'projects'
}

function Normalize-ProjectPath {
    param([Parameter(Mandatory)][string]$Path)

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    $fullPath = [System.IO.Path]::GetFullPath($expandedPath)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    $directorySeparator = [string][System.IO.Path]::DirectorySeparatorChar
    $alternateSeparator = [string][System.IO.Path]::AltDirectorySeparatorChar

    while ($fullPath.Length -gt $root.Length -and
           ($fullPath.EndsWith($directorySeparator) -or
            $fullPath.EndsWith($alternateSeparator))) {
        $fullPath = $fullPath.Substring(0, $fullPath.Length - 1)
    }

    return $fullPath
}

function ConvertTo-ClaudeProjectFolderName {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = Normalize-ProjectPath -Path $Path

    # Claude Code derives the metadata folder from the absolute path by replacing
    # path separators and path punctuation with dashes. Examples:
    # C:\Users\Jane\Code\demo -> C--Users-Jane-Code-demo
    # /Users/jane/.config/demo -> -Users-jane--config-demo
    return [regex]::Replace($normalized, '[\\/:.]', '-')
}

function ConvertFrom-ClaudeProjectFolderName {
    param([Parameter(Mandatory)][string]$FolderName)

    if ($FolderName -match '^[A-Za-z]--') {
        $drive = $FolderName.Substring(0, 1)
        $remainder = $FolderName.Substring(3)
        $remainder = $remainder.Replace('--', '\.')
        $remainder = $remainder.Replace('-', '\')
        return '{0}:\{1}' -f $drive, $remainder
    }

    if ($FolderName.StartsWith('-')) {
        $remainder = $FolderName.Substring(1)
        $remainder = $remainder.Replace('--', '/.')
        $remainder = $remainder.Replace('-', '/')
        return '/' + $remainder
    }

    return $FolderName
}

function Get-PathFromSessionFile {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    foreach ($line in [System.IO.File]::ReadLines($File.FullName)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.IndexOf('"cwd"', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        try {
            $entry = $line | ConvertFrom-Json -ErrorAction Stop
            if ($entry.PSObject.Properties.Name -contains 'cwd' -and
                -not [string]::IsNullOrWhiteSpace([string]$entry.cwd)) {
                return [string]$entry.cwd
            }
        }
        catch {
            # Continue scanning. A damaged line should not hide otherwise valid sessions.
        }
    }

    return $null
}

function Get-ReadableProjectPath {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$Directory)

    $sessionFiles = Get-ChildItem -LiteralPath $Directory.FullName -File -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $sessionFiles) {
        $cwd = Get-PathFromSessionFile -File $file
        if (-not [string]::IsNullOrWhiteSpace($cwd)) {
            return $cwd
        }
    }

    return ConvertFrom-ClaudeProjectFolderName -FolderName $Directory.Name
}

function Get-ClaudeProjects {
    param([Parameter(Mandatory)][string]$ProjectsDirectory)

    $projects = foreach ($directory in Get-ChildItem -LiteralPath $ProjectsDirectory -Directory -ErrorAction Stop) {
        if ($directory.Name.StartsWith('BACKUP__', [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        [pscustomobject]@{
            FolderName = $directory.Name
            Directory  = $directory
            Path       = Get-ReadableProjectPath -Directory $directory
        }
    }

    return @($projects | Sort-Object Path)
}

function Select-ClaudeProject {
    param([Parameter(Mandatory)][object[]]$Projects)

    Write-Section 'Select a project to update'

    for ($index = 0; $index -lt $Projects.Count; $index++) {
        Write-Host ('{0,3}) {1}' -f ($index + 1), $Projects[$index].Path)
    }

    while ($true) {
        $selection = Read-Host "Enter project number (1-$($Projects.Count))"
        $parsedSelection = 0
        if ([int]::TryParse($selection, [ref]$parsedSelection) -and
            $parsedSelection -ge 1 -and
            $parsedSelection -le $Projects.Count) {
            return $Projects[$parsedSelection - 1]
        }

        Write-Host 'Invalid selection.' -ForegroundColor Red
    }
}

function Find-ClaudeProject {
    param(
        [Parameter(Mandatory)][object[]]$Projects,
        [Parameter(Mandatory)][string]$Path
    )

    $normalizedPath = Normalize-ProjectPath -Path $Path
    $folderName = ConvertTo-ClaudeProjectFolderName -Path $normalizedPath

    foreach ($project in $Projects) {
        if ($project.FolderName -ceq $folderName) {
            return $project
        }

        try {
            if ((Normalize-ProjectPath -Path $project.Path) -ieq $normalizedPath) {
                return $project
            }
        }
        catch {
            # Ignore undecodable fallback folder names and continue searching.
        }
    }

    throw "No Claude Code metadata was found for '$normalizedPath'."
}

function New-ProjectBackup {
    param(
        [Parameter(Mandatory)][System.IO.DirectoryInfo]$ProjectDirectory,
        [Parameter(Mandatory)][string]$ProjectsDirectory
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupName = 'BACKUP__{0}__{1}.zip' -f $ProjectDirectory.Name, $timestamp
    $backupPath = Join-Path $ProjectsDirectory $backupName

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $ProjectDirectory.FullName,
        $backupPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true
    )

    return $backupPath
}

function Get-ReplacementPairs {
    param(
        [Parameter(Mandatory)][string]$OldPath,
        [Parameter(Mandatory)][string]$NewPath
    )

    $pairs = [ordered]@{}
    $pairs[$OldPath] = $NewPath

    $oldJsonEscaped = $OldPath.Replace('\', '\\')
    $newJsonEscaped = $NewPath.Replace('\', '\\')
    if (-not $pairs.Contains($oldJsonEscaped)) {
        $pairs[$oldJsonEscaped] = $newJsonEscaped
    }

    $oldForwardSlash = $OldPath.Replace('\', '/')
    $newForwardSlash = $NewPath.Replace('\', '/')
    if (-not $pairs.Contains($oldForwardSlash)) {
        $pairs[$oldForwardSlash] = $newForwardSlash
    }

    return $pairs
}

function Update-ProjectMetadataFiles {
    param(
        [Parameter(Mandatory)][System.IO.DirectoryInfo]$ProjectDirectory,
        [Parameter(Mandatory)][string]$OldPath,
        [Parameter(Mandatory)][string]$NewPath
    )

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $replacementPairs = Get-ReplacementPairs -OldPath $OldPath -NewPath $NewPath
    $candidateFiles = Get-ChildItem -LiteralPath $ProjectDirectory.FullName -File -Recurse | Where-Object {
        $_.Extension -in '.jsonl', '.json'
    }

    $updatedFiles = 0
    foreach ($file in $candidateFiles) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $updatedContent = $content

        foreach ($oldValue in $replacementPairs.Keys) {
            $updatedContent = $updatedContent.Replace([string]$oldValue, [string]$replacementPairs[$oldValue])
        }

        if ($updatedContent -cne $content) {
            [System.IO.File]::WriteAllText($file.FullName, $updatedContent, $utf8WithoutBom)
            $updatedFiles++
        }
    }

    return $updatedFiles
}

function Read-YesNo {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $false
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $answer = (Read-Host "$Prompt $suffix").Trim()

    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $Default
    }

    return $answer -match '^(y|yes|j|ja)$'
}

Write-Host '=======================================' -ForegroundColor Green
Write-Host '  Claude Code Project Mover PowerShell' -ForegroundColor Green
Write-Host '=======================================' -ForegroundColor Green

$projectsDirectory = Get-ClaudeProjectsDirectory
if (-not (Test-Path -LiteralPath $projectsDirectory -PathType Container)) {
    throw "Claude Code projects directory not found at '$projectsDirectory'."
}

$projects = Get-ClaudeProjects -ProjectsDirectory $projectsDirectory
if ($projects.Count -eq 0) {
    throw "No Claude Code projects were found in '$projectsDirectory'."
}

$selectedProject = if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    Select-ClaudeProject -Projects $projects
}
else {
    Find-ClaudeProject -Projects $projects -Path $ProjectPath
}

$oldPath = Normalize-ProjectPath -Path $selectedProject.Path

if ([string]::IsNullOrWhiteSpace($NewPath)) {
    Write-Section 'Enter the new project location'
    Write-Host "Current: $oldPath" -ForegroundColor Yellow

    while ($true) {
        $candidatePath = Read-Host 'New path'
        try {
            $normalizedCandidate = Normalize-ProjectPath -Path $candidatePath
            if (-not [System.IO.Path]::IsPathRooted($normalizedCandidate)) {
                throw 'Path must be absolute.'
            }
            if (-not (Test-Path -LiteralPath $normalizedCandidate -PathType Container)) {
                throw "Folder does not exist: $normalizedCandidate"
            }

            $NewPath = $normalizedCandidate
            break
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host 'Move the project folder first, then run this script.' -ForegroundColor Yellow
        }
    }
}
else {
    $NewPath = Normalize-ProjectPath -Path $NewPath
}

if (-not [System.IO.Path]::IsPathRooted($NewPath)) {
    throw 'NewPath must be an absolute path.'
}
if (-not (Test-Path -LiteralPath $NewPath -PathType Container)) {
    throw "Destination folder does not exist: '$NewPath'. Move the project folder first."
}
if ($oldPath -ieq $NewPath) {
    throw 'The old and new project paths are identical.'
}

$newFolderName = ConvertTo-ClaudeProjectFolderName -Path $NewPath
$newMetadataPath = Join-Path $projectsDirectory $newFolderName
if (Test-Path -LiteralPath $newMetadataPath) {
    throw "Claude Code metadata already exists for '$NewPath' at '$newMetadataPath'."
}

Write-Section 'Path references will be updated'
Write-Host "From: $oldPath" -ForegroundColor Yellow
Write-Host "  To: $NewPath" -ForegroundColor Green
Write-Host "Metadata: $($selectedProject.Directory.FullName)"
Write-Host "      To: $newMetadataPath"

$createBackup = $Backup.IsPresent
if (-not $Backup.IsPresent -and -not $Yes.IsPresent -and -not $WhatIfPreference) {
    $createBackup = Read-YesNo -Prompt 'Create a ZIP backup?' -Default $true
}

if (-not $Yes.IsPresent -and -not $WhatIfPreference -and -not (Read-YesNo -Prompt 'Proceed with update?')) {
    Write-Host 'Operation cancelled.' -ForegroundColor Yellow
    return
}

if (-not $PSCmdlet.ShouldProcess($oldPath, "Update Claude Code metadata to '$NewPath'")) {
    return
}

if ($createBackup) {
    $backupPath = New-ProjectBackup -ProjectDirectory $selectedProject.Directory -ProjectsDirectory $projectsDirectory
    Write-Host "Backup created: $backupPath" -ForegroundColor Green
}

Write-Host 'Updating metadata files...' -ForegroundColor Yellow
$updatedFileCount = Update-ProjectMetadataFiles `
    -ProjectDirectory $selectedProject.Directory `
    -OldPath $oldPath `
    -NewPath $NewPath

Write-Host 'Renaming Claude Code project metadata folder...' -ForegroundColor Yellow
Rename-Item -LiteralPath $selectedProject.Directory.FullName -NewName $newFolderName

Write-Host ''
Write-Host '=====================================' -ForegroundColor Green
Write-Host '  Project updated successfully' -ForegroundColor Green
Write-Host '=====================================' -ForegroundColor Green
Write-Host "Project path: $NewPath"
Write-Host "Metadata:     $newMetadataPath"
Write-Host "Files updated: $updatedFileCount"
