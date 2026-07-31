Set-StrictMode -Version Latest

function Resolve-ClaudeMoverLanguage {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'de', 'en')]
        [string]$Language = 'Auto'
    )

    $requested = if ($Language -ne 'Auto') { $Language } else { $env:CLAUDE_MOVER_LANGUAGE }
    if ($requested -match '^(?i:de|de-de|german|deutsch)$') { return 'de' }
    if ($requested -match '^(?i:en|en-us|en-gb|english)$') { return 'en' }
    if ($Language -eq 'Auto' -and [Globalization.CultureInfo]::CurrentUICulture.Name -like 'de*') { return 'de' }
    return 'en'
}

function Get-ClaudeMoverText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$English,
        [Parameter(Mandatory)][string]$German,
        [ValidateSet('de', 'en')][string]$Language,
        [object[]]$Arguments
    )

    $text = if ($Language -eq 'de') { $German } else { $English }
    if ($null -ne $Arguments -and $Arguments.Count -gt 0) {
        return $text -f $Arguments
    }
    return $text
}

Export-ModuleMember -Function Resolve-ClaudeMoverLanguage, Get-ClaudeMoverText
