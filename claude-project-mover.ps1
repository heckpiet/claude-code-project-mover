#requires -Version 5.1

<#
.SYNOPSIS
Updates Claude Code project references after a project folder has been moved.

.DESCRIPTION
Claude Code stores project sessions below ~/.claude/projects in a directory whose
name is derived from the absolute project path. This script validates the moved
project and its Claude Code metadata, checks available disk space, creates an
optional ZIP backup, updates path references in a staging copy, verifies the
result and swaps the metadata directory only after all checks pass.

The actual project directory must be moved before running this script. This
preserves the workflow and behavior of the original Bash project mover.

.PARAMETER ProjectPath
The previous absolute path of the project. When omitted, an interactive project
selection is shown.

.PARAMETER NewPath
The new absolute path of the project. With CreateProjectFolder, this is the
existing parent directory for the new dedicated folder.

.PARAMETER CreateProjectFolder
Creates a dedicated destination folder for a session group that previously
used a general directory.

.PARAMETER ProjectFolderName
Name of the dedicated folder created below NewPath.

.PARAMETER TransferMode
Records how project files reached the destination: Move, Copy, MetadataOnly, or CreateFolder.

.PARAMETER NoOriginMetadata
Disables the portable .claude-project-origin.json record in the destination.

.PARAMETER NoSessionBundle
Disables the portable .claude-session-bundle copy in the destination.

.PARAMETER NoArtifactCopy
Disables discovery and copying of safe files created by folderless sessions.

.PARAMETER AdoptExistingProjectFolder
Uses an already existing suggested destination folder for a folderless session
instead of creating it. Existing files are preserved and never overwritten.

.PARAMETER AllowRepeatedTransfer
Allows a transfer even when provenance or bundle data at the destination
indicates that the same project or session was transferred there before.

.PARAMETER Backup
Creates a ZIP backup before changing files. Interactive mode asks whether a
backup should be created when this switch is not supplied.

.PARAMETER Yes
Skips confirmation prompts. Intended for automation.

.PARAMETER CheckOnly
Runs all preflight checks without changing Claude Code metadata.

.PARAMETER MinimumFreeSpaceGB
Minimum free space required on the destination volume. The default is 1 GB.
The script may require more when the project or metadata is larger.

.PARAMETER SkipSpaceCheck
Skips disk-space validation. Use only when free-space information cannot be
retrieved, for example on some network shares.

.PARAMETER Force
Continues when only non-critical project-content warnings are found. Metadata
corruption and insufficient disk space remain blocking errors.

.PARAMETER ListSessions
Lists the most recent Claude Code sessions from the Claude configuration
directory and exits without changing any files.

.PARAMETER ListProjects
Lists all detected Claude Code projects with latest-session timestamp, session
count, description, and full path, then exits without changing any files.

.PARAMETER LastSessions
Maximum number of sessions shown by ListSessions. The default is 10.

.EXAMPLE
.\claude-project-mover.ps1

.EXAMPLE
.\claude-project-mover.ps1 -ListSessions -LastSessions 20

.EXAMPLE
.\claude-project-mover.ps1 -ListProjects

.EXAMPLE
.\claude-project-mover.ps1 -ProjectPath 'C:\Users\Peter\Code\OldProject' -NewPath 'D:\Code\OldProject' -Backup -Yes

.EXAMPLE
.\claude-project-mover.ps1 -ProjectPath 'C:\Code\OldProject' -NewPath 'D:\Code\OldProject' -CheckOnly

.EXAMPLE
.\claude-project-mover.ps1 -ProjectPath 'C:\Users\Peter' -NewPath 'D:\Projekte' -CreateProjectFolder -ProjectFolderName 'MeinProjekt' -Backup -Yes
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$ProjectPath,

    [Parameter()]
    [string]$NewPath,

    [Parameter()]
    [switch]$CreateProjectFolder,

    [Parameter()]
    [string]$ProjectFolderName,

    [Parameter()]
    [ValidateSet('Move', 'Copy', 'MetadataOnly', 'CreateFolder')]
    [string]$TransferMode = 'MetadataOnly',

    [Parameter()]
    [switch]$NoOriginMetadata,

    [Parameter()]
    [switch]$NoSessionBundle,

    [Parameter()]
    [switch]$NoArtifactCopy,

    [Parameter()]
    [switch]$AdoptExistingProjectFolder,

    [Parameter()]
    [switch]$AllowRepeatedTransfer,

    [Parameter()]
    [switch]$Backup,

    [Parameter()]
    [switch]$Yes,

    [Parameter()]
    [switch]$CheckOnly,

    [Parameter()]
    [ValidateRange(0.1, 10240)]
    [double]$MinimumFreeSpaceGB = 1,

    [Parameter()]
    [switch]$SkipSpaceCheck,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$ListSessions,

    [Parameter()]
    [switch]$ListProjects,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$LastSessions = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.8.3'
$ScriptAuthor = 'heckpiet'
$ProjectUrl = 'https://github.com/heckpiet/claude-code-project-mover'
$InventoryModulePath = Join-Path $PSScriptRoot 'ClaudeProjectInventory.psm1'
if (Test-Path -LiteralPath $InventoryModulePath -PathType Leaf) {
    Import-Module -Name $InventoryModulePath -Force
}

function Show-ScriptHeader {
    $border = '=' * 78
    Write-Host $border -ForegroundColor Green
    Write-Host ("  Claude Code Project Mover v{0}" -f $ScriptVersion) -ForegroundColor Green
    Write-Host '  Moves projects and safely updates their Claude Code session metadata.'
    Write-Host ("  By {0} | {1}" -f $ScriptAuthor, $ProjectUrl) -ForegroundColor Cyan
    Write-Host $border -ForegroundColor Green
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('-' * $Title.Length) -ForegroundColor Cyan
}

function Format-ByteSize {
    param([Parameter(Mandatory)][long]$Bytes)

    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Get-ClaudeConfigDirectory {
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CONFIG_DIR)) {
        return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($env:CLAUDE_CONFIG_DIR))
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
           ($fullPath.EndsWith($directorySeparator) -or $fullPath.EndsWith($alternateSeparator))) {
        $fullPath = $fullPath.Substring(0, $fullPath.Length - 1)
    }

    return $fullPath
}

function ConvertTo-ClaudeProjectFolderName {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = Normalize-ProjectPath -Path $Path
    return [regex]::Replace($normalized, '[\\/:.]', '-')
}

function ConvertFrom-ClaudeProjectFolderName {
    param([Parameter(Mandatory)][string]$FolderName)

    if ($FolderName -match '^[A-Za-z]--') {
        $drive = $FolderName.Substring(0, 1)
        $remainder = $FolderName.Substring(3).Replace('--', '\.').Replace('-', '\')
        return '{0}:\{1}' -f $drive, $remainder
    }

    if ($FolderName.StartsWith('-')) {
        $remainder = $FolderName.Substring(1).Replace('--', '/.').Replace('-', '/')
        return '/' + $remainder
    }

    return $FolderName
}

function Get-DirectorySummary {
    param([Parameter(Mandatory)][string]$Path)

    $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction Stop)
    $directories = @(Get-ChildItem -LiteralPath $Path -Directory -Recurse -Force -ErrorAction Stop)
    $bytes = [long]0
    foreach ($file in $files) { $bytes += $file.Length }

    return [pscustomobject]@{
        FileCount      = $files.Count
        DirectoryCount = $directories.Count
        Bytes          = $bytes
    }
}

function Get-FreeSpaceInfo {
    param([Parameter(Mandatory)][string]$Path)

    $root = [System.IO.Path]::GetPathRoot((Normalize-ProjectPath -Path $Path))
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "Unable to determine the volume for '$Path'."
    }

    if ($root.StartsWith('\\')) {
        throw "Free-space detection for UNC path '$root' is not supported reliably. Use -SkipSpaceCheck after checking it manually."
    }

    $driveInfo = New-Object System.IO.DriveInfo($root)
    if (-not $driveInfo.IsReady) {
        throw "Volume '$root' is not ready."
    }

    return [pscustomobject]@{
        Root       = $root
        FreeBytes  = [long]$driveInfo.AvailableFreeSpace
        TotalBytes = [long]$driveInfo.TotalSize
    }
}

function Assert-FreeSpace {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$RequiredBytes,
        [Parameter(Mandatory)][string]$Purpose
    )

    $space = Get-FreeSpaceInfo -Path $Path
    Write-Host ("{0} volume {1}: {2} free, {3} required" -f $Purpose, $space.Root, (Format-ByteSize $space.FreeBytes), (Format-ByteSize $RequiredBytes))

    if ($space.FreeBytes -lt $RequiredBytes) {
        throw "Insufficient free space on '$($space.Root)' for $Purpose."
    }
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
            # The full validation reports malformed records later.
        }
    }

    return $null
}

function Get-ReadableProjectPath {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$Directory)

    $sessionFiles = @(Get-ChildItem -LiteralPath $Directory.FullName -File -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue)
    foreach ($file in $sessionFiles) {
        $cwd = Get-PathFromSessionFile -File $file
        if (-not [string]::IsNullOrWhiteSpace($cwd)) { return $cwd }
    }

    return ConvertFrom-ClaudeProjectFolderName -FolderName $Directory.Name
}

function Get-ClaudeProjects {
    param([Parameter(Mandatory)][string]$ProjectsDirectory)

    if (Get-Command -Name Get-ClaudeProjectInventory -ErrorAction SilentlyContinue) {
        return @(Get-ClaudeProjectInventory -ProjectsDirectory $ProjectsDirectory)
    }

    $projects = foreach ($directory in Get-ChildItem -LiteralPath $ProjectsDirectory -Directory -ErrorAction Stop) {
        if ($directory.Name.StartsWith('BACKUP__', [StringComparison]::OrdinalIgnoreCase) -or
            $directory.Name.StartsWith('.MIGRATION__', [StringComparison]::OrdinalIgnoreCase) -or
            $directory.Name.StartsWith('.ROLLBACK__', [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $sessionFiles = @(Get-ChildItem -LiteralPath $directory.FullName -File -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue)
        $sessionInfo = @($sessionFiles | ForEach-Object { Get-ClaudeSessionInfo -File $_ })
        $latestSession = $sessionInfo | Sort-Object LastActivity -Descending | Select-Object -First 1
        $lastActivity = if ($null -ne $latestSession) { $latestSession.LastActivity } else { $directory.LastWriteTime }
        $latestDescription = if ($null -ne $latestSession) { $latestSession.Description } else { '(no description available)' }

        [pscustomobject]@{
            FolderName = $directory.Name
            Directory  = $directory
            Path       = Get-ReadableProjectPath -Directory $directory
            SessionCount = $sessionInfo.Count
            LastSession = $lastActivity
            Description = $latestDescription
        }
    }

    return @($projects | Sort-Object LastSession -Descending)
}

function ConvertTo-SessionMessageText {
    param([Parameter()][AllowNull()]$Message)

    if ($null -eq $Message) { return $null }
    if ($Message -is [string]) { return $Message }

    if ($Message.PSObject.Properties.Name -contains 'content') {
        $content = $Message.content
        if ($content -is [string]) { return $content }

        $textParts = foreach ($part in @($content)) {
            if ($null -eq $part) { continue }
            if ($part -is [string]) { $part; continue }
            if ($part.PSObject.Properties.Name -contains 'type' -and
                [string]$part.type -ne 'text') { continue }
            if ($part.PSObject.Properties.Name -contains 'text') {
                [string]$part.text
            }
        }
        return ($textParts -join ' ')
    }

    return $null
}

function Format-SessionDescription {
    param(
        [Parameter()][AllowNull()][string]$Text,
        [Parameter()][int]$MaximumLength = 100
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '(no description available)' }

    $cleanText = [regex]::Replace($Text, '<system-reminder>.*?</system-reminder>', ' ', 'Singleline,IgnoreCase')
    $cleanText = [regex]::Replace($cleanText, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($cleanText)) { return '(no description available)' }
    if ($cleanText.Length -le $MaximumLength) { return $cleanText }
    return $cleanText.Substring(0, $MaximumLength - 1).TrimEnd() + [char]0x2026
}

function Get-ClaudeSessionInfo {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [Parameter()][string]$ProjectPath
    )

    $latestTimestamp = $null
    $title = $null
    $firstUserMessage = $null
    $cwd = $null

    foreach ($line in [System.IO.File]::ReadLines($File.FullName)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try { $entry = $line | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }

        if ($entry.PSObject.Properties.Name -contains 'timestamp' -and
            -not [string]::IsNullOrWhiteSpace([string]$entry.timestamp)) {
            $parsedTimestamp = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse(
                    [string]$entry.timestamp,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::AssumeUniversal,
                    [ref]$parsedTimestamp) -and
                ($null -eq $latestTimestamp -or $parsedTimestamp -gt $latestTimestamp)) {
                $latestTimestamp = $parsedTimestamp
            }
        }

        if ([string]::IsNullOrWhiteSpace($cwd) -and
            $entry.PSObject.Properties.Name -contains 'cwd' -and
            -not [string]::IsNullOrWhiteSpace([string]$entry.cwd)) {
            $cwd = [string]$entry.cwd
        }

        if ([string]::IsNullOrWhiteSpace($title) -and
            $entry.PSObject.Properties.Name -contains 'aiTitle' -and
            -not [string]::IsNullOrWhiteSpace([string]$entry.aiTitle)) {
            $title = [string]$entry.aiTitle
        }

        $isMeta = $entry.PSObject.Properties.Name -contains 'isMeta' -and [bool]$entry.isMeta
        if ([string]::IsNullOrWhiteSpace($firstUserMessage) -and -not $isMeta -and
            $entry.PSObject.Properties.Name -contains 'type' -and
            [string]$entry.type -eq 'user' -and
            $entry.PSObject.Properties.Name -contains 'message') {
            $candidateMessage = ConvertTo-SessionMessageText -Message $entry.message
            if (-not [string]::IsNullOrWhiteSpace($candidateMessage)) {
                $firstUserMessage = $candidateMessage
            }
        }
    }

    $activity = if ($null -ne $latestTimestamp) {
        $latestTimestamp.ToLocalTime().DateTime
    }
    else {
        $File.LastWriteTime
    }
    $resolvedProjectPath = if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) {
        $ProjectPath
    }
    elseif (-not [string]::IsNullOrWhiteSpace($cwd)) {
        $cwd
    }
    else {
        ConvertFrom-ClaudeProjectFolderName -FolderName $File.Directory.Name
    }
    $description = if (-not [string]::IsNullOrWhiteSpace($title)) { $title } else { $firstUserMessage }

    return [pscustomobject]@{
        LastActivity = $activity
        Project      = $resolvedProjectPath
        Description  = Format-SessionDescription -Text $description
        SessionId    = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
        File         = $File.FullName
    }
}

function Get-ClaudeSessions {
    param(
        [Parameter(Mandatory)][object[]]$Projects,
        [Parameter(Mandatory)][int]$Limit
    )

    $sessions = foreach ($project in $Projects) {
        foreach ($file in Get-ChildItem -LiteralPath $project.Directory.FullName -File -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue) {
            Get-ClaudeSessionInfo -File $file -ProjectPath $project.Path
        }
    }

    return @($sessions | Sort-Object LastActivity -Descending | Select-Object -First $Limit)
}

function Show-ClaudeSessions {
    param([Parameter(Mandatory)][object[]]$Sessions)

    Write-Section 'Most recent Claude Code sessions'
    if ($Sessions.Count -eq 0) {
        Write-Host 'No Claude Code sessions were found.' -ForegroundColor Yellow
        return
    }

    $Sessions |
        Select-Object @{ Name = 'Last session'; Expression = { $_.LastActivity.ToString('dd.MM.yyyy HH:mm:ss') } },
                      Project,
                      Description,
                      SessionId |
        Format-Table -AutoSize -Wrap |
        Out-Host
}

function Show-ClaudeProjectOverview {
    param([Parameter(Mandatory)][object[]]$Projects)

    Write-Section 'Claude-Code-Projektübersicht'
    Write-Host 'Die zuletzt verwendeten Projekte werden zuerst angezeigt.' -ForegroundColor DarkGray
    Write-Host ''
    for ($index = 0; $index -lt $Projects.Count; $index++) {
        $project = $Projects[$index]
        $lastSession = if ($project.PSObject.Properties.Name -contains 'LastSession' -and $null -ne $project.LastSession) {
            $project.LastSession.ToString('dd.MM.yyyy HH:mm')
        }
        else {
            '-'
        }
        $sessionCount = if ($project.PSObject.Properties.Name -contains 'SessionCount') { $project.SessionCount } else { '?' }
        $description = if ($project.PSObject.Properties.Name -contains 'Description') {
            Format-SessionDescription -Text $project.Description -MaximumLength 90
        }
        else {
            '(no description available)'
        }

        Write-Host ('{0,3}) {1} | {2,3} Sitzung(en) | {3}' -f ($index + 1), $lastSession, $sessionCount, $description) -ForegroundColor White
        Write-Host ('     {0}' -f $project.Path) -ForegroundColor DarkGray
        if ($project.PSObject.Properties.Name -contains 'NeedsDedicatedFolder' -and $project.NeedsDedicatedFolder) {
            Write-Host ('     ORDNER FEHLT | Vorschlag: {0}' -f $project.SuggestedFolderName) -ForegroundColor Yellow
        }
        else {
            Write-Host '     Eigener Projektordner erkannt' -ForegroundColor DarkGray
        }
        if ($project.PSObject.Properties.Name -contains 'SafeArtifactCount') {
            Write-Host ('     Session-Dateien: {0} sichere Bereiche, {1} sensible/systemgebundene Pfade' -f `
                $project.SafeArtifactCount, $project.SensitiveArtifactCount) -ForegroundColor DarkGray
        }
    }
}

function Select-ClaudeProject {
    param([Parameter(Mandatory)][object[]]$Projects)

    Show-ClaudeProjectOverview -Projects $Projects
    Write-Host ''
    Write-Host 'Wähle ein Projekt anhand der Nummer aus.' -ForegroundColor Cyan

    while ($true) {
        $selection = Read-Host "Projektnummer (1-$($Projects.Count))"
        $parsedSelection = 0
        if ([int]::TryParse($selection, [ref]$parsedSelection) -and
            $parsedSelection -ge 1 -and $parsedSelection -le $Projects.Count) {
            return $Projects[$parsedSelection - 1]
        }
        Write-Host 'Ungültige Auswahl.' -ForegroundColor Red
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
        if ($project.FolderName -ceq $folderName) { return $project }
        try {
            if ((Normalize-ProjectPath -Path $project.Path) -ieq $normalizedPath) { return $project }
        }
        catch { }
    }

    throw "No Claude Code metadata was found for '$normalizedPath'."
}

function Test-ProjectContent {
    param([Parameter(Mandatory)][string]$Path)

    $summary = Get-DirectorySummary -Path $Path
    $markers = @('.git', 'CLAUDE.md', '.claude', 'package.json', 'pyproject.toml', 'Cargo.toml', 'go.mod', '*.sln', '*.csproj')
    $foundMarkers = New-Object System.Collections.Generic.List[string]

    foreach ($marker in $markers) {
        if ($marker.Contains('*')) {
            if (Get-ChildItem -LiteralPath $Path -Filter $marker -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
                [void]$foundMarkers.Add($marker)
            }
        }
        elseif (Test-Path -LiteralPath (Join-Path $Path $marker)) {
            [void]$foundMarkers.Add($marker)
        }
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    if ($summary.FileCount -eq 0) { [void]$warnings.Add('Der Ziel-Projektordner enthält keine Dateien.') }
    if ($foundMarkers.Count -eq 0) { [void]$warnings.Add('Keine typische Projektdatei gefunden. Der Ordner kann dennoch ein einfaches Projekt sein.') }

    return [pscustomobject]@{
        Summary = $summary
        Markers = @($foundMarkers)
        Warnings = @($warnings)
    }
}

function Test-MetadataHealth {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$ExpectedCwd,
        [Parameter()][switch]$RequireExpectedCwd
    )

    $jsonlFiles = @(Get-ChildItem -LiteralPath $Path -File -Filter '*.jsonl' -Recurse -ErrorAction Stop)
    $jsonFiles = @(Get-ChildItem -LiteralPath $Path -File -Filter '*.json' -Recurse -ErrorAction Stop)
    $invalidRecords = 0
    $validRecords = 0
    $cwdValues = New-Object System.Collections.Generic.List[string]

    foreach ($file in $jsonlFiles) {
        $lineNumber = 0
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            $lineNumber++
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $entry = $line | ConvertFrom-Json -ErrorAction Stop
                $validRecords++
                if ($entry.PSObject.Properties.Name -contains 'cwd' -and -not [string]::IsNullOrWhiteSpace([string]$entry.cwd)) {
                    [void]$cwdValues.Add([string]$entry.cwd)
                }
            }
            catch {
                $invalidRecords++
            }
        }
    }

    foreach ($file in $jsonFiles) {
        try { [void]([System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json -ErrorAction Stop) }
        catch { $invalidRecords++ }
    }

    $expectedFound = $false
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCwd)) {
        foreach ($cwd in $cwdValues) {
            try {
                if ((Normalize-ProjectPath -Path $cwd) -ieq (Normalize-ProjectPath -Path $ExpectedCwd)) {
                    $expectedFound = $true
                    break
                }
            }
            catch { }
        }
    }

    $errors = New-Object System.Collections.Generic.List[string]
    if ($jsonlFiles.Count -eq 0) { [void]$errors.Add('No JSONL session file was found.') }
    if ($validRecords -eq 0) { [void]$errors.Add('No valid JSONL session record was found.') }
    if ($invalidRecords -gt 0) { [void]$errors.Add("$invalidRecords malformed JSON or JSONL record(s) were found.") }
    if ($RequireExpectedCwd.IsPresent -and -not $expectedFound) { [void]$errors.Add("No session record references the expected path '$ExpectedCwd'.") }

    return [pscustomobject]@{
        JsonlFileCount = $jsonlFiles.Count
        JsonFileCount = $jsonFiles.Count
        ValidRecords = $validRecords
        InvalidRecords = $invalidRecords
        CwdValues = @($cwdValues | Select-Object -Unique)
        ExpectedCwdFound = $expectedFound
        Errors = @($errors)
    }
}

function New-ProjectBackup {
    param(
        [Parameter(Mandatory)][System.IO.DirectoryInfo]$ProjectDirectory,
        [Parameter(Mandatory)][string]$ProjectsDirectory
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupPath = Join-Path $ProjectsDirectory ('BACKUP__{0}__{1}.zip' -f $ProjectDirectory.Name, $timestamp)
    [System.IO.Compression.ZipFile]::CreateFromDirectory($ProjectDirectory.FullName, $backupPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    return $backupPath
}

function Update-ProjectMetadataFiles {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][string]$OldPath,
        [Parameter(Mandatory)][string]$NewPath
    )

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $candidateFiles = @(Get-ChildItem -LiteralPath $ProjectDirectory -File -Recurse -Filter '*.jsonl')
    $updatedFiles = 0
    $oldJson = ($OldPath | ConvertTo-Json -Compress).Trim('"')
    $newJson = ($NewPath | ConvertTo-Json -Compress).Trim('"')
    $pattern = '("cwd"\s*:\s*")' + [regex]::Escape($oldJson) + '(")'

    foreach ($file in $candidateFiles) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $updatedContent = [regex]::Replace(
            $content,
            $pattern,
            [Text.RegularExpressions.MatchEvaluator]{
                param($match)
                return $match.Groups[1].Value + $newJson + $match.Groups[2].Value
            },
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($updatedContent -cne $content) {
            $temporaryFile = $file.FullName + '.tmp'
            [System.IO.File]::WriteAllText($temporaryFile, $updatedContent, $utf8WithoutBom)
            Move-Item -LiteralPath $temporaryFile -Destination $file.FullName -Force
            $updatedFiles++
        }
    }

    return $updatedFiles
}

function Get-SessionTransferInventory {
    param(
        [Parameter(Mandatory)][object]$Project,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$ProjectsDirectory
    )

    $sourceRoot = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd('\', '/')
    $sessionFiles = @(Get-ChildItem -LiteralPath $Project.Directory.FullName -File -Filter '*.jsonl' -Recurse)
    $sessionIds = @($sessionFiles | ForEach-Object { $_.BaseName } | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | Select-Object -Unique)
    $safeRoots = New-Object System.Collections.Generic.List[string]
    $sensitive = New-Object System.Collections.Generic.List[string]

    foreach ($file in $sessionFiles) {
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            try { $record = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($record.PSObject.Properties.Name -notcontains 'message' -or $null -eq $record.message -or
                $record.message.PSObject.Properties.Name -notcontains 'content') { continue }
            foreach ($part in @($record.message.content)) {
                if ($null -eq $part -or $part.PSObject.Properties.Name -notcontains 'type' -or
                    [string]$part.type -ne 'tool_use' -or $part.PSObject.Properties.Name -notcontains 'name' -or
                    [string]$part.name -notin @('Write', 'Edit', 'NotebookEdit') -or
                    $part.PSObject.Properties.Name -notcontains 'input' -or $null -eq $part.input) { continue }
                $pathValue = $null
                foreach ($property in @('file_path', 'notebook_path', 'path')) {
                    if ($part.input.PSObject.Properties.Name -contains $property) {
                        $pathValue = [string]$part.input.$property
                        if (-not [string]::IsNullOrWhiteSpace($pathValue)) { break }
                    }
                }
                if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
                try {
                    $absolute = if ([System.IO.Path]::IsPathRooted($pathValue)) {
                        [System.IO.Path]::GetFullPath($pathValue)
                    }
                    else {
                        [System.IO.Path]::GetFullPath((Join-Path $sourceRoot $pathValue))
                    }
                }
                catch { continue }
                $prefix = $sourceRoot + [System.IO.Path]::DirectorySeparatorChar
                if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
                $relative = $absolute.Substring($prefix.Length)
                $firstSegment = ($relative -split '[\\/]')[0]
                if ($firstSegment -in @('.ssh', '.claude', '.codex', 'AppData') -or $firstSegment.StartsWith('.')) {
                    [void]$sensitive.Add($absolute)
                    continue
                }
                $root = Join-Path $sourceRoot $firstSegment
                if (Test-Path -LiteralPath $root) { [void]$safeRoots.Add($root) }
            }
        }
    }

    $claudeConfig = Split-Path -Parent $ProjectsDirectory
    $oldFolderName = ConvertTo-ClaudeProjectFolderName -Path $sourceRoot
    $tempProjectRoot = Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) 'claude') $oldFolderName
    $historyDirectories = foreach ($id in $sessionIds) {
        $candidate = Join-Path (Join-Path $claudeConfig 'file-history') $id
        if (Test-Path -LiteralPath $candidate -PathType Container) { Get-Item -LiteralPath $candidate }
    }
    $runtimeDirectories = foreach ($id in $sessionIds) {
        $candidate = Join-Path $tempProjectRoot $id
        if (Test-Path -LiteralPath $candidate -PathType Container) { Get-Item -LiteralPath $candidate }
    }

    return [pscustomobject]@{
        SessionIds = $sessionIds
        SessionFiles = $sessionFiles
        SafeArtifactRoots = @($safeRoots | Select-Object -Unique)
        SensitivePaths = @($sensitive | Select-Object -Unique)
        HistoryDirectories = @($historyDirectories)
        RuntimeDirectories = @($runtimeDirectories)
    }
}

function Copy-SessionArtifacts {
    param(
        [Parameter(Mandatory)][object]$Inventory,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $copied = New-Object System.Collections.Generic.List[string]
    $sourceRoot = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd('\', '/')
    foreach ($root in @($Inventory.SafeArtifactRoots)) {
        $relative = $root.Substring($sourceRoot.Length).TrimStart('\', '/')
        $destination = Join-Path $DestinationPath $relative
        if (Test-Path -LiteralPath $destination) { continue }
        Copy-Item -LiteralPath $root -Destination $destination -Recurse -Force
        [void]$copied.Add($relative)
    }
    return @($copied)
}

function Write-PortableSessionBundle {
    param(
        [Parameter(Mandatory)][object]$Inventory,
        [Parameter(Mandatory)][string]$MetadataPath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CopiedArtifacts
    )
    $bundlePath = Join-Path $DestinationPath '.claude-session-bundle'
    $temporaryPath = $bundlePath + '.tmp'
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Recurse -Force }
    if (Test-Path -LiteralPath $bundlePath -PathType Container) {
        Copy-Item -LiteralPath $bundlePath -Destination $temporaryPath -Recurse -Force
    }
    else {
        [void](New-Item -ItemType Directory -Path $temporaryPath)
    }
    $metadataDestination = Join-Path $temporaryPath 'metadata'
    if (Test-Path -LiteralPath $metadataDestination) { Remove-Item -LiteralPath $metadataDestination -Recurse -Force }
    Copy-Item -LiteralPath $MetadataPath -Destination $metadataDestination -Recurse -Force
    foreach ($directory in @($Inventory.HistoryDirectories)) {
        $historyRoot = Join-Path $temporaryPath 'file-history'
        [void](New-Item -ItemType Directory -Path $historyRoot -Force)
        Copy-Item -LiteralPath $directory.FullName -Destination (Join-Path $historyRoot $directory.Name) -Recurse -Force
    }
    foreach ($directory in @($Inventory.RuntimeDirectories)) {
        $runtimeRoot = Join-Path $temporaryPath 'runtime'
        [void](New-Item -ItemType Directory -Path $runtimeRoot -Force)
        Copy-Item -LiteralPath $directory.FullName -Destination (Join-Path $runtimeRoot $directory.Name) -Recurse -Force
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        createdAtUtc = [datetime]::UtcNow.ToString('o')
        sourcePath = $SourcePath
        currentPath = $DestinationPath
        sessions = @($Inventory.SessionIds)
        copiedArtifacts = @($CopiedArtifacts)
        skippedSensitivePaths = @($Inventory.SensitivePaths)
        metadataDirectory = 'metadata'
        fileHistoryDirectory = 'file-history'
        runtimeDirectory = 'runtime'
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $temporaryPath 'manifest.json'),
        ($manifest | ConvertTo-Json -Depth 6),
        (New-Object System.Text.UTF8Encoding($false))
    )
    $restoreScript = Join-Path $PSScriptRoot 'scripts\Restore-ClaudeSession.ps1'
    if (Test-Path -LiteralPath $restoreScript -PathType Leaf) {
        Copy-Item -LiteralPath $restoreScript -Destination (Join-Path $temporaryPath 'Restore-ClaudeSession.ps1') -Force
    }
    if (Test-Path -LiteralPath $bundlePath) { Remove-Item -LiteralPath $bundlePath -Recurse -Force }
    Move-Item -LiteralPath $temporaryPath -Destination $bundlePath
    return $bundlePath
}

function Read-YesNo {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $false
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $answer = (Read-Host "$Prompt $suffix").Trim()
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer -match '^(y|yes|j|ja)$'
}

function ConvertTo-SafeProjectFolderName {
    param([Parameter(Mandatory)][string]$Name)
    $cleanName = $Name.Trim()
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $cleanName = $cleanName.Replace([string]$character, '-')
    }
    $cleanName = ($cleanName -replace '\s+', '-').Trim('.', '-', ' ')
    if ([string]::IsNullOrWhiteSpace($cleanName)) { throw 'Der Name für den neuen Projektordner ist ungültig.' }
    return $cleanName
}

function Test-IsGeneralSourcePath {
    param([Parameter(Mandatory)][string]$Path)
    $normalized = (Normalize-ProjectPath -Path $Path).TrimEnd('\', '/')
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @(
        $HOME,
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('MyDocuments'),
        (Join-Path $HOME 'Downloads'),
        $env:OneDrive,
        $env:OneDriveConsumer,
        $env:OneDriveCommercial
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            try { [void]$candidates.Add((Normalize-ProjectPath -Path $candidate).TrimEnd('\', '/')) } catch { }
        }
    }
    return @($candidates | Where-Object { $_ -ieq $normalized }).Count -gt 0
}

function Get-SmartProjectFolderSuggestion {
    param(
        [Parameter()][AllowNull()][string]$Description,
        [Parameter(Mandatory)][datetime]$LastActivity,
        [Parameter()][AllowNull()][string]$SessionId
    )
    $candidate = Format-SessionDescription -Text $Description -MaximumLength 100
    if ($candidate -in @('(no description available)', '(keine Beschreibung verfügbar)')) { $candidate = '' }
    $candidate = [regex]::Replace($candidate, '^(bitte|kannst du|ich möchte|ich will|erstelle|baue|prüfe|schau(?:e)?(?: mal)?)\s+', '', 'IgnoreCase')
    $words = @([regex]::Matches($candidate, '[\p{L}\p{Nd}]+') | ForEach-Object { $_.Value } | Select-Object -First 8)
    $suggestion = ($words -join '-').ToLowerInvariant()
    if ($suggestion.Length -gt 56) { $suggestion = $suggestion.Substring(0, 56).TrimEnd('-') }
    if ([string]::IsNullOrWhiteSpace($suggestion)) {
        $shortSession = if ([string]::IsNullOrWhiteSpace($SessionId)) { 'session' } else { $SessionId.Substring(0, [Math]::Min(8, $SessionId.Length)) }
        $suggestion = 'claude-projekt-{0}-{1}' -f $LastActivity.ToString('yyyyMMdd-HHmm'), $shortSession
    }
    return $suggestion
}

function Get-DestinationAssessment {
    param(
        [Parameter(Mandatory)][string]$CandidatePath,
        [Parameter(Mandatory)][string]$OldPath,
        [Parameter(Mandatory)][string]$ProjectsDirectory
    )

    $normalizedPath = Normalize-ProjectPath -Path $CandidatePath
    if (-not [System.IO.Path]::IsPathRooted($normalizedPath)) {
        throw 'Der Zielpfad muss ein absoluter Pfad sein.'
    }
    if (-not (Test-Path -LiteralPath $normalizedPath -PathType Container)) {
        throw "Der Zielordner existiert nicht: '$normalizedPath'. Verschiebe oder kopiere zuerst den vollständigen Projektordner."
    }
    if ($OldPath -ieq $normalizedPath) {
        throw 'Alter und neuer Projektpfad sind identisch.'
    }

    $newFolderName = ConvertTo-ClaudeProjectFolderName -Path $normalizedPath
    $newMetadataPath = Join-Path $ProjectsDirectory $newFolderName
    if (Test-Path -LiteralPath $newMetadataPath) {
        throw "Für '$normalizedPath' existieren bereits Claude-Code-Metadaten unter '$newMetadataPath'."
    }

    return [pscustomobject]@{
        Path = $normalizedPath
        FolderName = $newFolderName
        MetadataPath = $newMetadataPath
        ProjectHealth = Test-ProjectContent -Path $normalizedPath
    }
}

function Write-ProjectOriginManifest {
    param(
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][object]$Project,
        [Parameter(Mandatory)][object]$ProjectHealth,
        [Parameter(Mandatory)][object]$MetadataHealth,
        [Parameter(Mandatory)][string]$OldMetadataPath,
        [Parameter(Mandatory)][string]$NewMetadataPath
    )

    $manifestPath = Join-Path $DestinationPath '.claude-project-origin.json'
    $existing = $null
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try { $existing = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -ErrorAction Stop } catch { }
    }
    $projectId = if ($null -ne $existing -and $existing.PSObject.Properties.Name -contains 'projectId') {
        [string]$existing.projectId
    }
    else {
        [guid]::NewGuid().ToString()
    }
    $history = New-Object System.Collections.Generic.List[object]
    if ($null -ne $existing -and $existing.PSObject.Properties.Name -contains 'transfers') {
        foreach ($entry in @($existing.transfers)) { [void]$history.Add($entry) }
    }

    $now = [datetimeoffset]::Now
    $computerName = if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { $env:COMPUTERNAME } else { [System.Net.Dns]::GetHostName() }
    $osDescription = if ($PSVersionTable.PSObject.Properties.Name -contains 'OS' -and -not [string]::IsNullOrWhiteSpace([string]$PSVersionTable.OS)) {
        [string]$PSVersionTable.OS
    }
    else {
        [Environment]::OSVersion.VersionString
    }
    [void]$history.Add([pscustomobject]@{
        transferId = [guid]::NewGuid().ToString()
        transferredAtUtc = $now.UtcDateTime.ToString('o')
        transferredAtLocal = $now.ToString('o')
        timeZone = [TimeZoneInfo]::Local.Id
        mode = $Mode
        tool = [pscustomobject]@{ name = 'Claude Code Project Mover'; version = $ScriptVersion; projectUrl = $ProjectUrl }
        source = [pscustomobject]@{
            path = $SourcePath
            computerName = $computerName
            userName = [Environment]::UserName
            userDomain = [Environment]::UserDomainName
            operatingSystem = $osDescription
            metadataPath = $OldMetadataPath
            fileCount = $ProjectHealth.Summary.FileCount
            bytes = $ProjectHealth.Summary.Bytes
            projectMarkers = @($ProjectHealth.Markers)
        }
        destination = [pscustomobject]@{
            path = $DestinationPath
            computerName = $computerName
            userName = [Environment]::UserName
            metadataPath = $NewMetadataPath
        }
        claude = [pscustomobject]@{
            sessionFiles = $Project.SessionCount
            validRecords = $MetadataHealth.ValidRecords
            invalidRecords = $MetadataHealth.InvalidRecords
            lastActivity = if ($null -ne $Project.LastSession) { $Project.LastSession.ToString('o') } else { $null }
        }
        verification = [pscustomobject]@{
            destinationFolderExists = $true
            metadataValid = ($MetadataHealth.Errors.Count -eq 0)
            cwdUpdated = ($MetadataHealth.Errors.Count -eq 0)
        }
    })

    $manifest = [ordered]@{
        schemaVersion = 1
        projectId = $projectId
        currentPath = $DestinationPath
        updatedAtUtc = $now.UtcDateTime.ToString('o')
        transfers = @($history | ForEach-Object { $_ })
    }
    $temporaryPath = $manifestPath + '.tmp'
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($temporaryPath, ($manifest | ConvertTo-Json -Depth 8), $utf8WithoutBom)
        $validated = [System.IO.File]::ReadAllText($temporaryPath) | ConvertFrom-Json -ErrorAction Stop
        if ([string]$validated.currentPath -ne $DestinationPath -or @($validated.transfers).Count -eq 0) {
            throw 'Herkunftsmetadaten konnten nicht validiert werden.'
        }
        Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    return $manifestPath
}

function Find-PriorProjectTransfers {
    param(
        [Parameter(Mandatory)][string]$SearchRoot,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string[]]$SessionIds
    )

    if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) { return @() }
    $normalizedSource = Normalize-ProjectPath -Path $SourcePath
    $matches = New-Object System.Collections.Generic.List[object]
    foreach ($manifestFile in Get-ChildItem -LiteralPath $SearchRoot -Filter '.claude-project-origin.json' -File -Recurse -ErrorAction SilentlyContinue) {
        try {
            $manifest = [System.IO.File]::ReadAllText($manifestFile.FullName) | ConvertFrom-Json -ErrorAction Stop
            $sourceMatches = @($manifest.transfers | Where-Object {
                $_.PSObject.Properties.Name -contains 'source' -and
                $_.source.PSObject.Properties.Name -contains 'path' -and
                (Normalize-ProjectPath -Path ([string]$_.source.path)) -ieq $normalizedSource
            }).Count -gt 0
            if ($sourceMatches) {
                [void]$matches.Add([pscustomobject]@{
                    ProjectPath = Split-Path -Parent $manifestFile.FullName
                    Reason = 'gleicher ursprünglicher Quellpfad'
                    ManifestPath = $manifestFile.FullName
                })
            }
        }
        catch { Write-Warning "Herkunftsdatei konnte nicht geprüft werden: $($manifestFile.FullName)" }
    }
    foreach ($bundleFile in Get-ChildItem -LiteralPath $SearchRoot -Filter 'manifest.json' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq '.claude-session-bundle' }) {
        try {
            $bundle = [System.IO.File]::ReadAllText($bundleFile.FullName) | ConvertFrom-Json -ErrorAction Stop
            $duplicates = @($SessionIds | Where-Object { $_ -in @($bundle.sessions) })
            if ($duplicates.Count -gt 0) {
                [void]$matches.Add([pscustomobject]@{
                    ProjectPath = Split-Path -Parent $bundleFile.Directory.FullName
                    Reason = "$($duplicates.Count) identische Session-ID(s)"
                    ManifestPath = $bundleFile.FullName
                })
            }
        }
        catch { Write-Warning "Session-Paket konnte nicht geprüft werden: $($bundleFile.FullName)" }
    }
    return @($matches | Sort-Object ProjectPath, Reason -Unique)
}

Show-ScriptHeader

$projectsDirectory = Get-ClaudeProjectsDirectory
if (-not (Test-Path -LiteralPath $projectsDirectory -PathType Container)) {
    throw "Claude Code projects directory not found at '$projectsDirectory'."
}

$projects = @(Get-ClaudeProjects -ProjectsDirectory $projectsDirectory)
if ($projects.Count -eq 0) { throw "No Claude Code projects were found in '$projectsDirectory'." }
foreach ($project in $projects) {
    if ($project.PSObject.Properties.Name -notcontains 'SuggestedFolderName') {
        $latestSessionId = if ($project.PSObject.Properties.Name -contains 'LatestSessionId') { $project.LatestSessionId } else { $null }
        $suggestion = Get-SmartProjectFolderSuggestion -Description $project.Description -LastActivity $project.LastSession -SessionId $latestSessionId
        $needsFolder = Test-IsGeneralSourcePath -Path $project.Path
        $project | Add-Member -NotePropertyName NeedsDedicatedFolder -NotePropertyValue $needsFolder
        $project | Add-Member -NotePropertyName FolderStatus -NotePropertyValue $(if ($needsFolder) { 'ORDNER FEHLT' } else { 'Eigener Ordner' })
        $project | Add-Member -NotePropertyName SuggestedFolderName -NotePropertyValue $suggestion
    }
}

if ($ListSessions.IsPresent) {
    $sessions = Get-ClaudeSessions -Projects $projects -Limit $LastSessions
    Show-ClaudeSessions -Sessions $sessions
    return
}

if ($ListProjects.IsPresent) {
    Show-ClaudeProjectOverview -Projects $projects
    return
}

$selectedProject = if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    Select-ClaudeProject -Projects $projects
}
else {
    Find-ClaudeProject -Projects $projects -Path $ProjectPath
}

$oldPath = Normalize-ProjectPath -Path $selectedProject.Path
$interactiveDestination = [string]::IsNullOrWhiteSpace($NewPath)
$destinationAssessment = $null
$queuedCandidatePath = $null
$createDedicatedFolder = $CreateProjectFolder.IsPresent
$folderlessMigration = $CreateProjectFolder.IsPresent -or $AdoptExistingProjectFolder.IsPresent

if ($interactiveDestination -and (Test-Path -LiteralPath $oldPath -PathType Container)) {
    $needsFolder = (Test-IsGeneralSourcePath -Path $oldPath) -or
        ($selectedProject.PSObject.Properties.Name -contains 'NeedsDedicatedFolder' -and $selectedProject.NeedsDedicatedFolder)
    if ($needsFolder) {
        Write-Host ''
        Write-Host "Für diese Sitzungsgruppe wurde kein eigener Projektordner erkannt ($($selectedProject.FolderStatus))." -ForegroundColor Yellow
        $createDedicatedFolder = Read-YesNo -Prompt 'Am Ziel einen eigenen Projektordner anlegen?' -Default $true
        $folderlessMigration = $createDedicatedFolder
    }
}

if ($interactiveDestination) {
    Write-Section 'Neuen Projektpfad eingeben'
    Write-Host "Bisheriger Pfad: $oldPath" -ForegroundColor Yellow
    if ($createDedicatedFolder) {
        Write-Host 'Gib den vorhandenen Ziel-Sammelordner an. Darin wird ein eigener Projektordner angelegt.' -ForegroundColor DarkGray
    }
    else {
        Write-Host 'Gib den vollständigen Ziel-Projektordner an, nicht nur dessen übergeordneten Sammelordner.' -ForegroundColor DarkGray
    }
}

while ($null -eq $destinationAssessment) {
    $candidatePath = if (-not [string]::IsNullOrWhiteSpace($queuedCandidatePath)) {
        $value = $queuedCandidatePath
        $queuedCandidatePath = $null
        Write-Host "Prüfe vorgeschlagenen Zielpfad: $value" -ForegroundColor Cyan
        $value
    }
    elseif ($interactiveDestination) { Read-Host 'Neuer Projektpfad' } else { $NewPath }
    try {
        if ($createDedicatedFolder) {
            $targetRoot = Normalize-ProjectPath -Path $candidatePath
            if (-not [System.IO.Path]::IsPathRooted($targetRoot) -or -not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
                throw "Der Ziel-Sammelordner existiert nicht: '$targetRoot'."
            }
            $folderName = $ProjectFolderName
            if ([string]::IsNullOrWhiteSpace($folderName) -and $interactiveDestination) {
                $defaultName = if ($selectedProject.PSObject.Properties.Name -contains 'SuggestedFolderName') {
                    $selectedProject.SuggestedFolderName
                }
                else {
                    Get-SmartProjectFolderSuggestion -Description $selectedProject.Description -LastActivity $selectedProject.LastSession -SessionId $null
                }
                $enteredName = Read-Host "Name des neuen Projektordners [$defaultName]"
                $folderName = if ([string]::IsNullOrWhiteSpace($enteredName)) { $defaultName } else { $enteredName }
            }
            if ([string]::IsNullOrWhiteSpace($folderName)) { throw 'ProjectFolderName is required with CreateProjectFolder.' }
            $folderName = ConvertTo-SafeProjectFolderName -Name $folderName
            $plannedPath = Join-Path $targetRoot $folderName
            $metadataFolderName = ConvertTo-ClaudeProjectFolderName -Path $plannedPath
            $metadataPath = Join-Path $projectsDirectory $metadataFolderName
            if (Test-Path -LiteralPath $metadataPath) { throw "Für '$plannedPath' existieren bereits Claude-Code-Metadaten." }
            if (Test-Path -LiteralPath $plannedPath) {
                if (-not $interactiveDestination) {
                    throw "Der vorgeschlagene Projektordner existiert bereits: '$plannedPath'. Verwende -AdoptExistingProjectFolder oder wähle einen anderen Namen."
                }
                Write-Host ''
                Write-Host "Der vorgeschlagene Projektordner existiert bereits: $plannedPath" -ForegroundColor Yellow
                Write-Host '[V] Vorhandenen Ordner verwenden  [N] Anderen Namen wählen  [A] Abbrechen' -ForegroundColor Cyan
                $conflictChoice = (Read-Host 'Auswahl [V/N/A]').Trim()
                if ($conflictChoice -match '^(a|abbrechen|c|cancel)$') {
                    Write-Host 'Vorgang abgebrochen.' -ForegroundColor Yellow
                    return
                }
                if ($conflictChoice -notmatch '^(v|verwenden|u|use)$') {
                    $ProjectFolderName = $null
                    continue
                }
                $createDedicatedFolder = $false
                $AdoptExistingProjectFolder = $true
                $folderlessMigration = $true
                $candidateHealth = Test-ProjectContent -Path $plannedPath
            }
            else {
                $candidateHealth = [pscustomobject]@{
                    Summary = [pscustomobject]@{ FileCount = 0; Bytes = 0 }
                    Markers = @()
                    Warnings = @()
                }
            }
            $candidateAssessment = [pscustomobject]@{
                Path = $plannedPath
                FolderName = $metadataFolderName
                MetadataPath = $metadataPath
                ProjectHealth = $candidateHealth
            }
            $ProjectFolderName = $folderName
        }
        else {
            $candidateAssessment = Get-DestinationAssessment -CandidatePath $candidatePath -OldPath $oldPath -ProjectsDirectory $projectsDirectory
        }
    }
    catch {
        if (-not $interactiveDestination) { throw }
        Write-Host $_.Exception.Message -ForegroundColor Red
        continue
    }

    foreach ($warning in $candidateAssessment.ProjectHealth.Warnings) {
        Write-Warning $warning
    }

    if ($candidateAssessment.ProjectHealth.Warnings.Count -gt 0 -and
        -not $Force.IsPresent -and -not $AdoptExistingProjectFolder.IsPresent) {
        if (-not $interactiveDestination) {
            throw 'Der Zielordner konnte nicht eindeutig als Projekt erkannt werden. Verwende den vollständigen Projektordner oder bestätige bewusst mit -Force.'
        }

        Write-Host ''
        Write-Host 'Der Zielpfad wirkt wie ein Sammelordner oder ein noch unvollständiges Projekt.' -ForegroundColor Yellow
        Write-Host 'Beispiel: D:\Projekte\MeinProjekt statt nur D:\Projekte' -ForegroundColor DarkGray
        $sourceLeaf = Split-Path -Path $oldPath -Leaf
        if (-not [string]::IsNullOrWhiteSpace($sourceLeaf) -and
            (Read-YesNo -Prompt 'Soll das System einen vollständigen Ziel-Projektordner vorschlagen?' -Default $true)) {
            $systemSuggestion = Join-Path $candidateAssessment.Path (ConvertTo-SafeProjectFolderName -Name $sourceLeaf)
            $enteredSuggestion = Read-Host "Ziel-Projektordner [$systemSuggestion]"
            $queuedCandidatePath = if ([string]::IsNullOrWhiteSpace($enteredSuggestion)) {
                $systemSuggestion
            }
            else {
                $enteredSuggestion
            }
            if (-not (Test-Path -LiteralPath $queuedCandidatePath -PathType Container)) {
                Write-Host "Der vorgeschlagene Projektordner existiert noch nicht: $queuedCandidatePath" -ForegroundColor Yellow
                Write-Host 'Verschiebe oder kopiere den Projektordner zuerst dorthin oder gib einen vorhandenen Ordner an.' -ForegroundColor DarkGray
                $queuedCandidatePath = $null
            }
            else {
                continue
            }
        }
        if (-not (Read-YesNo -Prompt 'Diesen Ordner trotzdem als Projektpfad verwenden?' -Default $false)) {
            Write-Host 'Bitte einen anderen Ziel-Projektordner eingeben.' -ForegroundColor Cyan
            continue
        }
    }

    $destinationAssessment = $candidateAssessment
}

$NewPath = $destinationAssessment.Path
$newFolderName = $destinationAssessment.FolderName
$newMetadataPath = $destinationAssessment.MetadataPath
$projectHealth = $destinationAssessment.ProjectHealth
$effectiveTransferMode = if ($createDedicatedFolder) { 'CreateFolder' } else { $TransferMode }
$sessionTransfer = Get-SessionTransferInventory `
    -Project $selectedProject `
    -SourcePath $oldPath `
    -ProjectsDirectory $projectsDirectory

$duplicateSearchRoot = if ($createDedicatedFolder) {
    Split-Path -Parent $NewPath
}
elseif (Test-Path -LiteralPath $NewPath -PathType Container) {
    Split-Path -Parent $NewPath
}
else {
    Split-Path -Parent $NewPath
}
$priorTransfers = @(Find-PriorProjectTransfers -SearchRoot $duplicateSearchRoot -SourcePath $oldPath -SessionIds $sessionTransfer.SessionIds)
if ($priorTransfers.Count -gt 0) {
    Write-Host ''
    Write-Host 'Dieses Projekt oder eine seiner Sessions wurde am Ziel bereits gefunden:' -ForegroundColor Yellow
    foreach ($match in $priorTransfers) {
        Write-Host ("  {0} ({1})" -f $match.ProjectPath, $match.Reason) -ForegroundColor Yellow
    }
    if (-not $AllowRepeatedTransfer.IsPresent) {
        if (-not $interactiveDestination -or $Yes.IsPresent) {
            throw 'Eine frühere Übertragung wurde am Ziel erkannt. Prüfe den vorhandenen Zielordner oder verwende bewusst -AllowRepeatedTransfer.'
        }
        if (-not (Read-YesNo -Prompt 'Trotzdem erneut übertragen?' -Default $false)) {
            Write-Host 'Vorgang abgebrochen.' -ForegroundColor Yellow
            return
        }
    }
}

Write-Section 'Vorprüfungen'
$metadataSummary = Get-DirectorySummary -Path $selectedProject.Directory.FullName
$metadataHealth = Test-MetadataHealth -Path $selectedProject.Directory.FullName -ExpectedCwd $oldPath -RequireExpectedCwd

Write-Host ("Zielprojekt: {0} Dateien, {1}, Merkmale: {2}" -f $projectHealth.Summary.FileCount, (Format-ByteSize $projectHealth.Summary.Bytes), (($projectHealth.Markers -join ', ')))
Write-Host ("Claude-Metadaten: {0} JSONL-Dateien, {1} gültige Datensätze, {2}" -f $metadataHealth.JsonlFileCount, $metadataHealth.ValidRecords, (Format-ByteSize $metadataSummary.Bytes))
Write-Host ("Session-Paket: {0} Session(s), {1} sichere Artefaktbereiche, {2} Dateiverläufe, {3} Runtime-Ordner" -f `
    $sessionTransfer.SessionIds.Count,
    $sessionTransfer.SafeArtifactRoots.Count,
    $sessionTransfer.HistoryDirectories.Count,
    $sessionTransfer.RuntimeDirectories.Count)
if ($sessionTransfer.SafeArtifactRoots.Count -gt 0) {
    Write-Host ('Sichere Artefakte: ' + (($sessionTransfer.SafeArtifactRoots | ForEach-Object { Split-Path -Leaf $_ }) -join ', ')) -ForegroundColor Green
}
if ($sessionTransfer.SensitivePaths.Count -gt 0) {
    Write-Warning ("Nicht automatisch kopierte sensible/systemgebundene Pfade: {0}" -f ($sessionTransfer.SensitivePaths -join ', '))
}

if ($metadataHealth.Errors.Count -gt 0) {
    throw ('Metadata validation failed: ' + ($metadataHealth.Errors -join ' '))
}

$minimumBytes = [long]($MinimumFreeSpaceGB * 1GB)
$destinationHeadroom = [long][Math]::Max($minimumBytes, [Math]::Max(256MB, $projectHealth.Summary.Bytes * 0.1))
$createBackup = $Backup.IsPresent
if (-not $Backup.IsPresent -and -not $Yes.IsPresent -and -not $CheckOnly.IsPresent -and -not $WhatIfPreference) {
    $createBackup = Read-YesNo -Prompt 'Create a ZIP backup?' -Default $true
}
$metadataWorkingSpace = [long]($metadataSummary.Bytes + 100MB)
if ($createBackup) { $metadataWorkingSpace += $metadataSummary.Bytes }

if (-not $SkipSpaceCheck.IsPresent) {
    Assert-FreeSpace -Path $NewPath -RequiredBytes $destinationHeadroom -Purpose 'Destination project'
    Assert-FreeSpace -Path $projectsDirectory -RequiredBytes $metadataWorkingSpace -Purpose 'Metadata migration'
}
else {
    Write-Warning 'Disk-space checks were skipped.'
}

Write-Section 'Migration plan'
Write-Host "From:     $oldPath" -ForegroundColor Yellow
Write-Host "To:       $NewPath" -ForegroundColor Green
Write-Host "Metadata: $($selectedProject.Directory.FullName)"
Write-Host "New name: $newMetadataPath"
Write-Host "Backup:   $createBackup"
Write-Host "Eigenen Projektordner anlegen: $createDedicatedFolder"
Write-Host "Übertragungsart: $effectiveTransferMode"
Write-Host "Herkunftsmetadaten: $(-not $NoOriginMetadata.IsPresent)"
Write-Host "Portables Session-Paket: $(-not $NoSessionBundle.IsPresent)"
Write-Host "Sichere Session-Artefakte kopieren: $($folderlessMigration -and -not $NoArtifactCopy.IsPresent)"

if ($CheckOnly.IsPresent) {
    Write-Host ''
    Write-Host 'All preflight checks passed. No files were changed.' -ForegroundColor Green
    return
}

if (-not $Yes.IsPresent -and -not $WhatIfPreference -and -not (Read-YesNo -Prompt 'Proceed with update?')) {
    Write-Host 'Operation cancelled.' -ForegroundColor Yellow
    return
}

if (-not $PSCmdlet.ShouldProcess($oldPath, "Update Claude Code metadata to '$NewPath'")) { return }

$stagingName = '.MIGRATION__' + [guid]::NewGuid().ToString('N')
$rollbackName = '.ROLLBACK__' + [guid]::NewGuid().ToString('N')
$stagingPath = Join-Path $projectsDirectory $stagingName
$rollbackPath = Join-Path $projectsDirectory $rollbackName
$originalRenamed = $false
$destinationCreated = $false
$originManifestPath = Join-Path $NewPath '.claude-project-origin.json'
$originManifestExisted = Test-Path -LiteralPath $originManifestPath -PathType Leaf
$originManifestPreviousContent = if ($originManifestExisted) { [System.IO.File]::ReadAllText($originManifestPath) } else { $null }
$copiedArtifacts = @()
$sessionBundlePath = $null

try {
    if ($createDedicatedFolder) {
        [void](New-Item -ItemType Directory -Path $NewPath -ErrorAction Stop)
        $destinationCreated = $true
        Write-Host "Projektordner angelegt: $NewPath" -ForegroundColor Green
    }
    if ($createBackup) {
        $backupPath = New-ProjectBackup -ProjectDirectory $selectedProject.Directory -ProjectsDirectory $projectsDirectory
        Write-Host "Backup created: $backupPath" -ForegroundColor Green
    }

    Write-Host 'Creating validated staging copy...' -ForegroundColor Yellow
    Copy-Item -LiteralPath $selectedProject.Directory.FullName -Destination $stagingPath -Recurse -Force

    $stagingBefore = Get-DirectorySummary -Path $stagingPath
    if ($stagingBefore.FileCount -ne $metadataSummary.FileCount) { throw 'The staging copy is incomplete.' }

    $updatedFileCount = Update-ProjectMetadataFiles -ProjectDirectory $stagingPath -OldPath $oldPath -NewPath $NewPath
    if ($updatedFileCount -eq 0) { throw 'No metadata file contained the old project path. Nothing was changed.' }

    $stagingHealth = Test-MetadataHealth -Path $stagingPath -ExpectedCwd $NewPath -RequireExpectedCwd
    if ($stagingHealth.Errors.Count -gt 0) { throw ('Updated metadata validation failed: ' + ($stagingHealth.Errors -join ' ')) }
    if ($stagingHealth.InvalidRecords -ne $metadataHealth.InvalidRecords) { throw 'Metadata validity changed unexpectedly during migration.' }

    Write-Host 'Activating updated metadata...' -ForegroundColor Yellow
    Rename-Item -LiteralPath $selectedProject.Directory.FullName -NewName $rollbackName
    $originalRenamed = $true
    Rename-Item -LiteralPath $stagingPath -NewName $newFolderName

    $finalHealth = Test-MetadataHealth -Path $newMetadataPath -ExpectedCwd $NewPath -RequireExpectedCwd
    if ($finalHealth.Errors.Count -gt 0) { throw ('Final metadata validation failed: ' + ($finalHealth.Errors -join ' ')) }
    if (-not (Test-Path -LiteralPath $NewPath -PathType Container)) {
        throw "Der neue Projektordner fehlt nach der Migration: '$NewPath'."
    }
    if ($folderlessMigration -and -not $NoArtifactCopy.IsPresent) {
        $copiedArtifacts = @(Copy-SessionArtifacts -Inventory $sessionTransfer -SourcePath $oldPath -DestinationPath $NewPath)
        if ($copiedArtifacts.Count -gt 0) {
            Write-Host ('Session-Artefakte kopiert: ' + ($copiedArtifacts -join ', ')) -ForegroundColor Green
        }
    }
    if (-not $NoSessionBundle.IsPresent) {
        $sessionBundlePath = Write-PortableSessionBundle `
            -Inventory $sessionTransfer `
            -MetadataPath $newMetadataPath `
            -DestinationPath $NewPath `
            -SourcePath $oldPath `
            -CopiedArtifacts $copiedArtifacts
        Write-Host "Portables Session-Paket: $sessionBundlePath" -ForegroundColor Green
    }
    if (-not $NoOriginMetadata.IsPresent) {
        $originManifestPath = Write-ProjectOriginManifest `
            -DestinationPath $NewPath `
            -SourcePath $oldPath `
            -Mode $effectiveTransferMode `
            -Project $selectedProject `
            -ProjectHealth $projectHealth `
            -MetadataHealth $finalHealth `
            -OldMetadataPath $selectedProject.Directory.FullName `
            -NewMetadataPath $newMetadataPath
        Write-Host "Herkunftsmetadaten: $originManifestPath" -ForegroundColor Green
    }

    Remove-Item -LiteralPath $rollbackPath -Recurse -Force
    $originalRenamed = $false

    Write-Host ''
    Write-Host '=====================================' -ForegroundColor Green
    Write-Host '  Project updated successfully' -ForegroundColor Green
    Write-Host '=====================================' -ForegroundColor Green
    Write-Host "Project path:  $NewPath"
    Write-Host "Metadata:      $newMetadataPath"
    Write-Host "Files updated: $updatedFileCount"
    Write-Host "Sessions:      $($finalHealth.ValidRecords) valid records"
    if ($null -ne $sessionBundlePath) { Write-Host "Session bundle: $sessionBundlePath" }
    if (-not $NoOriginMetadata.IsPresent) { Write-Host "Origin record: $originManifestPath" }
}
catch {
    Write-Host "Migration failed: $($_.Exception.Message)" -ForegroundColor Red

    if (Test-Path -LiteralPath $newMetadataPath) {
        Remove-Item -LiteralPath $newMetadataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($originalRenamed -and (Test-Path -LiteralPath $rollbackPath) -and -not (Test-Path -LiteralPath $selectedProject.Directory.FullName)) {
        Rename-Item -LiteralPath $rollbackPath -NewName $selectedProject.FolderName -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $stagingPath) {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($originManifestExisted -and $null -ne $originManifestPreviousContent) {
        [System.IO.File]::WriteAllText($originManifestPath, $originManifestPreviousContent, (New-Object System.Text.UTF8Encoding($false)))
    }
    elseif (-not $originManifestExisted -and (Test-Path -LiteralPath $originManifestPath -PathType Leaf)) {
        Remove-Item -LiteralPath $originManifestPath -Force -ErrorAction SilentlyContinue
    }
    if ($destinationCreated -and (Test-Path -LiteralPath $NewPath -PathType Container)) {
        Remove-Item -LiteralPath $NewPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    throw
}
