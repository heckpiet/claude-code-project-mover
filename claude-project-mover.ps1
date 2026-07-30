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

$ScriptVersion = '1.3.0'
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

Show-ScriptHeader

$projectsDirectory = Get-ClaudeProjectsDirectory
if (-not (Test-Path -LiteralPath $projectsDirectory -PathType Container)) {
    throw "Claude Code projects directory not found at '$projectsDirectory'."
}

$projects = @(Get-ClaudeProjects -ProjectsDirectory $projectsDirectory)
if ($projects.Count -eq 0) { throw "No Claude Code projects were found in '$projectsDirectory'." }

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
$createDedicatedFolder = $CreateProjectFolder.IsPresent

if ($interactiveDestination -and (Test-Path -LiteralPath $oldPath -PathType Container)) {
    $sourceHealth = Test-ProjectContent -Path $oldPath
    if ($sourceHealth.Markers.Count -eq 0 -and (Test-IsGeneralSourcePath -Path $oldPath)) {
        Write-Host ''
        Write-Host 'Für diese Sitzungsgruppe wurde kein eigener Projektordner erkannt.' -ForegroundColor Yellow
        $createDedicatedFolder = Read-YesNo -Prompt 'Am Ziel einen eigenen Projektordner anlegen?' -Default $true
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
    $candidatePath = if ($interactiveDestination) { Read-Host 'Neuer Projektpfad' } else { $NewPath }
    try {
        if ($createDedicatedFolder) {
            $targetRoot = Normalize-ProjectPath -Path $candidatePath
            if (-not [System.IO.Path]::IsPathRooted($targetRoot) -or -not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
                throw "Der Ziel-Sammelordner existiert nicht: '$targetRoot'."
            }
            $folderName = $ProjectFolderName
            if ([string]::IsNullOrWhiteSpace($folderName) -and $interactiveDestination) {
                $defaultName = ConvertTo-SafeProjectFolderName -Name $selectedProject.Description
                $enteredName = Read-Host "Name des neuen Projektordners [$defaultName]"
                $folderName = if ([string]::IsNullOrWhiteSpace($enteredName)) { $defaultName } else { $enteredName }
            }
            if ([string]::IsNullOrWhiteSpace($folderName)) { throw 'ProjectFolderName is required with CreateProjectFolder.' }
            $folderName = ConvertTo-SafeProjectFolderName -Name $folderName
            $plannedPath = Join-Path $targetRoot $folderName
            if (Test-Path -LiteralPath $plannedPath) { throw "Der neue Projektordner existiert bereits: '$plannedPath'." }
            $metadataFolderName = ConvertTo-ClaudeProjectFolderName -Path $plannedPath
            $metadataPath = Join-Path $projectsDirectory $metadataFolderName
            if (Test-Path -LiteralPath $metadataPath) { throw "Für '$plannedPath' existieren bereits Claude-Code-Metadaten." }
            $candidateAssessment = [pscustomobject]@{
                Path = $plannedPath
                FolderName = $metadataFolderName
                MetadataPath = $metadataPath
                ProjectHealth = [pscustomobject]@{
                    Summary = [pscustomobject]@{ FileCount = 0; Bytes = 0 }
                    Markers = @()
                    Warnings = @()
                }
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

    if ($candidateAssessment.ProjectHealth.Warnings.Count -gt 0 -and -not $Force.IsPresent) {
        if (-not $interactiveDestination) {
            throw 'Der Zielordner konnte nicht eindeutig als Projekt erkannt werden. Verwende den vollständigen Projektordner oder bestätige bewusst mit -Force.'
        }

        Write-Host ''
        Write-Host 'Der Zielpfad wirkt wie ein Sammelordner oder ein noch unvollständiges Projekt.' -ForegroundColor Yellow
        Write-Host 'Beispiel: D:\Projekte\MeinProjekt statt nur D:\Projekte' -ForegroundColor DarkGray
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

Write-Section 'Vorprüfungen'
$metadataSummary = Get-DirectorySummary -Path $selectedProject.Directory.FullName
$metadataHealth = Test-MetadataHealth -Path $selectedProject.Directory.FullName -ExpectedCwd $oldPath -RequireExpectedCwd

Write-Host ("Zielprojekt: {0} Dateien, {1}, Merkmale: {2}" -f $projectHealth.Summary.FileCount, (Format-ByteSize $projectHealth.Summary.Bytes), (($projectHealth.Markers -join ', ')))
Write-Host ("Claude-Metadaten: {0} JSONL-Dateien, {1} gültige Datensätze, {2}" -f $metadataHealth.JsonlFileCount, $metadataHealth.ValidRecords, (Format-ByteSize $metadataSummary.Bytes))

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
    if ($destinationCreated -and (Test-Path -LiteralPath $NewPath -PathType Container)) {
        $remainingItems = @(Get-ChildItem -LiteralPath $NewPath -Force -ErrorAction SilentlyContinue)
        if ($remainingItems.Count -eq 0) {
            Remove-Item -LiteralPath $NewPath -Force -ErrorAction SilentlyContinue
        }
    }

    throw
}
