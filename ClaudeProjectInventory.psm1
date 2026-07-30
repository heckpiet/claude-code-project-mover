Set-StrictMode -Version Latest

function ConvertFrom-ClaudeProjectFolderName {
    param([Parameter(Mandatory)][string]$FolderName)

    if ($FolderName -match '^[A-Za-z]--') {
        $drive = $FolderName.Substring(0, 1)
        $remainder = $FolderName.Substring(3).Replace('--', '\.').Replace('-', '\')
        return '{0}:\{1}' -f $drive, $remainder
    }
    if ($FolderName.StartsWith('-')) {
        return '/' + $FolderName.Substring(1).Replace('--', '/.').Replace('-', '/')
    }
    return $FolderName
}

function ConvertTo-InventoryMessageText {
    param([Parameter()][AllowNull()]$Message)

    if ($null -eq $Message) { return $null }
    if ($Message -is [string]) { return $Message }
    if ($Message.PSObject.Properties.Name -notcontains 'content') { return $null }
    if ($Message.content -is [string]) { return [string]$Message.content }

    $parts = foreach ($part in @($Message.content)) {
        if ($null -eq $part) { continue }
        if ($part -is [string]) { $part; continue }
        if ($part.PSObject.Properties.Name -contains 'type' -and [string]$part.type -ne 'text') { continue }
        if ($part.PSObject.Properties.Name -contains 'text') { [string]$part.text }
    }
    return ($parts -join ' ')
}

function Format-InventoryDescription {
    param(
        [Parameter()][AllowNull()][string]$Text,
        [Parameter()][int]$MaximumLength = 140
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '(no description available)' }
    $clean = [regex]::Replace($Text, '<system-reminder>.*?</system-reminder>', ' ', 'Singleline,IgnoreCase')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return '(no description available)' }
    if ($clean.Length -le $MaximumLength) { return $clean }
    return $clean.Substring(0, $MaximumLength - 3).TrimEnd() + '...'
}

function Test-InventoryProjectMarker {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    foreach ($marker in @('.git', 'CLAUDE.md', '.claude', 'package.json', 'pyproject.toml', 'Cargo.toml', 'go.mod')) {
        if (Test-Path -LiteralPath (Join-Path $Path $marker)) { return $true }
    }
    if (Get-ChildItem -LiteralPath $Path -File -Include '*.sln', '*.csproj' -ErrorAction SilentlyContinue | Select-Object -First 1) { return $true }
    return $false
}

function Test-InventoryGeneralPath {
    param([Parameter(Mandatory)][string]$Path)
    try { $normalized = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') } catch { return $false }
    $candidates = @(
        $HOME,
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('MyDocuments'),
        (Join-Path $HOME 'Downloads'),
        $env:OneDrive,
        $env:OneDriveConsumer,
        $env:OneDriveCommercial
    )
    return @($candidates | Where-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { return $false }
        try { return [System.IO.Path]::GetFullPath($_).TrimEnd('\', '/') -ieq $normalized } catch { return $false }
    }).Count -gt 0
}

function New-InventoryFolderSuggestion {
    param(
        [Parameter()][AllowNull()][string]$Description,
        [Parameter(Mandatory)][datetime]$LastActivity,
        [Parameter()][AllowNull()][string]$SessionId
    )

    $candidate = Format-InventoryDescription -Text $Description -MaximumLength 100
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

function Read-ClaudeProjectSessions {
    param([Parameter(Mandatory)][System.IO.FileInfo[]]$Files)

    $cwdValues = New-Object System.Collections.Generic.List[string]
    $sessions = New-Object System.Collections.Generic.List[object]
    $validRecords = 0
    $invalidRecords = 0

    foreach ($file in $Files) {
        $latestTimestamp = $null
        $title = $null
        $firstUserMessage = $null

        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $record = $line | ConvertFrom-Json -ErrorAction Stop
                $validRecords++
            }
            catch {
                $invalidRecords++
                continue
            }

            if ($record.PSObject.Properties.Name -contains 'cwd' -and
                -not [string]::IsNullOrWhiteSpace([string]$record.cwd)) {
                try { [void]$cwdValues.Add([System.IO.Path]::GetFullPath([string]$record.cwd)) }
                catch { [void]$cwdValues.Add([string]$record.cwd) }
            }

            if ($record.PSObject.Properties.Name -contains 'timestamp' -and
                -not [string]::IsNullOrWhiteSpace([string]$record.timestamp)) {
                $parsed = [datetimeoffset]::MinValue
                if ([datetimeoffset]::TryParse(
                        [string]$record.timestamp,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [Globalization.DateTimeStyles]::AssumeUniversal,
                        [ref]$parsed) -and
                    ($null -eq $latestTimestamp -or $parsed -gt $latestTimestamp)) {
                    $latestTimestamp = $parsed
                }
            }

            if ([string]::IsNullOrWhiteSpace($title) -and
                $record.PSObject.Properties.Name -contains 'aiTitle' -and
                -not [string]::IsNullOrWhiteSpace([string]$record.aiTitle)) {
                $title = [string]$record.aiTitle
            }

            $isMeta = $record.PSObject.Properties.Name -contains 'isMeta' -and [bool]$record.isMeta
            if ([string]::IsNullOrWhiteSpace($firstUserMessage) -and -not $isMeta -and
                $record.PSObject.Properties.Name -contains 'type' -and
                [string]$record.type -eq 'user' -and
                $record.PSObject.Properties.Name -contains 'message') {
                $candidate = ConvertTo-InventoryMessageText -Message $record.message
                if (-not [string]::IsNullOrWhiteSpace($candidate)) { $firstUserMessage = $candidate }
            }
        }

        $activity = if ($null -ne $latestTimestamp) { $latestTimestamp.ToLocalTime().DateTime } else { $file.LastWriteTime }
        $description = if (-not [string]::IsNullOrWhiteSpace($title)) { $title } else { $firstUserMessage }
        [void]$sessions.Add([pscustomobject]@{
            LastActivity = $activity
            Description = Format-InventoryDescription -Text $description
            SessionId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        })
    }

    return [pscustomobject]@{
        Values = @($cwdValues | Select-Object -Unique)
        ValidRecords = $validRecords
        InvalidRecords = $invalidRecords
        Sessions = @($sessions | Sort-Object LastActivity -Descending)
    }
}

function Get-ClaudeProjectInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectsDirectory)

    $projects = foreach ($directory in Get-ChildItem -LiteralPath $ProjectsDirectory -Directory -ErrorAction Stop) {
        if ($directory.Name -match '^(BACKUP__|\.MIGRATION__|\.ROLLBACK__)') { continue }
        $files = @(Get-ChildItem -LiteralPath $directory.FullName -File -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) { continue }

        $sessionData = Read-ClaudeProjectSessions -Files $files
        $path = if ($sessionData.Values.Count -gt 0) {
            $sessionData.Values[0]
        }
        else {
            ConvertFrom-ClaudeProjectFolderName -FolderName $directory.Name
        }
        $latest = $sessionData.Sessions | Select-Object -First 1
        $hasMarker = Test-InventoryProjectMarker -Path $path
        $needsDedicatedFolder = Test-InventoryGeneralPath -Path $path
        $suggestedFolderName = New-InventoryFolderSuggestion `
            -Description $latest.Description `
            -LastActivity $latest.LastActivity `
            -SessionId $latest.SessionId

        [pscustomobject]@{
            FolderName = $directory.Name
            Directory = $directory
            Path = $path
            DisplayName = $path
            SourcePath = $path
            MetadataPath = $directory.FullName
            JsonlFiles = $files
            SessionData = $sessionData
            SessionCount = $sessionData.Sessions.Count
            LastSession = $latest.LastActivity
            Description = $latest.Description
            LatestSessionId = $latest.SessionId
            HasProjectMarker = $hasMarker
            NeedsDedicatedFolder = $needsDedicatedFolder
            FolderStatus = if ($needsDedicatedFolder) { 'ORDNER FEHLT' } else { 'Eigener Ordner' }
            SuggestedFolderName = $suggestedFolderName
            Validation = $null
        }
    }

    return @($projects | Sort-Object LastSession -Descending)
}

Export-ModuleMember -Function Get-ClaudeProjectInventory, New-InventoryFolderSuggestion
