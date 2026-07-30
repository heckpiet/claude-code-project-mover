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
The new absolute path of the project. The directory must already exist.

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

.PARAMETER LastSessions
Maximum number of sessions shown by ListSessions. The default is 10.

.EXAMPLE
.\claude-project-mover.ps1

.EXAMPLE
.\claude-project-mover.ps1 -ListSessions -LastSessions 20

.EXAMPLE
.\claude-project-mover.ps1 -ProjectPath 'C:\Users\Peter\Code\OldProject' -NewPath 'D:\Code\OldProject' -Backup -Yes

.EXAMPLE
.\claude-project-mover.ps1 -ProjectPath 'C:\Code\OldProject' -NewPath 'D:\Code\OldProject' -CheckOnly
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
    [ValidateRange(1, 1000)]
    [int]$LastSessions = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.0.0'
$ScriptAuthor = 'heckpiet'
$ProjectUrl = 'https://github.com/heckpiet/claude-code-project-mover'

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

    $projects = foreach ($directory in Get-ChildItem -LiteralPath $ProjectsDirectory -Directory -ErrorAction Stop) {
        if ($directory.Name.StartsWith('BACKUP__', [StringComparison]::OrdinalIgnoreCase) -or
            $directory.Name.StartsWith('.MIGRATION__', [StringComparison]::OrdinalIgnoreCase) -or
            $directory.Name.StartsWith('.ROLLBACK__', [StringComparison]::OrdinalIgnoreCase)) {
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
            $parsedSelection -ge 1 -and $parsedSelection -le $Projects.Count) {
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
    if ($summary.FileCount -eq 0) { [void]$warnings.Add('The destination project contains no files.') }
    if ($foundMarkers.Count -eq 0) { [void]$warnings.Add('No common project marker was found. This may still be valid for a simple project.') }

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

function Get-ReplacementPairs {
    param(
        [Parameter(Mandatory)][string]$OldPath,
        [Parameter(Mandatory)][string]$NewPath
    )

    $pairs = [ordered]@{}
    $pairs[$OldPath] = $NewPath
    $pairs[$OldPath.Replace('\', '\\')] = $NewPath.Replace('\', '\\')
    $pairs[$OldPath.Replace('\', '/')] = $NewPath.Replace('\', '/')
    return $pairs
}

function Update-ProjectMetadataFiles {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][string]$OldPath,
        [Parameter(Mandatory)][string]$NewPath
    )

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $replacementPairs = Get-ReplacementPairs -OldPath $OldPath -NewPath $NewPath
    $candidateFiles = @(Get-ChildItem -LiteralPath $ProjectDirectory -File -Recurse | Where-Object { $_.Extension -in '.jsonl', '.json' })
    $updatedFiles = 0

    foreach ($file in $candidateFiles) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $updatedContent = $content
        foreach ($oldValue in $replacementPairs.Keys) {
            if ([string]::IsNullOrEmpty([string]$oldValue)) { continue }
            $updatedContent = $updatedContent.Replace([string]$oldValue, [string]$replacementPairs[$oldValue])
        }

        if ($updatedContent -cne $content) {
            $temporaryFile = $file.FullName + '.tmp'
            [System.IO.File]::WriteAllText($temporaryFile, $updatedContent, $utf8WithoutBom)
            Move-Item -LiteralPath $temporaryFile -Destination $file.FullName -Force
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
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer -match '^(y|yes|j|ja)$'
}

Show-ScriptHeader

$projectsDirectory = Get-ClaudeProjectsDirectory
if (-not (Test-Path -LiteralPath $projectsDirectory -PathType Container)) {
    throw "Claude Code projects directory not found at '$projectsDirectory'."
}

$projects = Get-ClaudeProjects -ProjectsDirectory $projectsDirectory
if ($projects.Count -eq 0) { throw "No Claude Code projects were found in '$projectsDirectory'." }

if ($ListSessions.IsPresent) {
    $sessions = Get-ClaudeSessions -Projects $projects -Limit $LastSessions
    Show-ClaudeSessions -Sessions $sessions
    return
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
            if (-not [System.IO.Path]::IsPathRooted($normalizedCandidate)) { throw 'Path must be absolute.' }
            if (-not (Test-Path -LiteralPath $normalizedCandidate -PathType Container)) { throw "Folder does not exist: $normalizedCandidate" }
            $NewPath = $normalizedCandidate
            break
        }
        catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    }
}
else {
    $NewPath = Normalize-ProjectPath -Path $NewPath
}

if (-not [System.IO.Path]::IsPathRooted($NewPath)) { throw 'NewPath must be an absolute path.' }
if (-not (Test-Path -LiteralPath $NewPath -PathType Container)) { throw "Destination folder does not exist: '$NewPath'. Move the project folder first." }
if ($oldPath -ieq $NewPath) { throw 'The old and new project paths are identical.' }

$newFolderName = ConvertTo-ClaudeProjectFolderName -Path $NewPath
$newMetadataPath = Join-Path $projectsDirectory $newFolderName
if (Test-Path -LiteralPath $newMetadataPath) { throw "Claude Code metadata already exists for '$NewPath' at '$newMetadataPath'." }

Write-Section 'Preflight checks'
$projectHealth = Test-ProjectContent -Path $NewPath
$metadataSummary = Get-DirectorySummary -Path $selectedProject.Directory.FullName
$metadataHealth = Test-MetadataHealth -Path $selectedProject.Directory.FullName -ExpectedCwd $oldPath -RequireExpectedCwd

Write-Host ("Destination project: {0} files, {1}, markers: {2}" -f $projectHealth.Summary.FileCount, (Format-ByteSize $projectHealth.Summary.Bytes), (($projectHealth.Markers -join ', ')))
Write-Host ("Claude metadata: {0} JSONL files, {1} valid records, {2}" -f $metadataHealth.JsonlFileCount, $metadataHealth.ValidRecords, (Format-ByteSize $metadataSummary.Bytes))

foreach ($warning in $projectHealth.Warnings) { Write-Warning $warning }
if ($projectHealth.Warnings.Count -gt 0 -and -not $Force.IsPresent) {
    throw 'Project-content validation produced warnings. Review the destination or use -Force to continue.'
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

try {
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

    throw
}
