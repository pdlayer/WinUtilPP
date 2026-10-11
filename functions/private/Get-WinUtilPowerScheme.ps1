function Get-WinUtilPowerScheme {
    <#

    .SYNOPSIS
        Lists the power schemes on this machine

    .DESCRIPTION
        Reads powercfg /list and returns one object per scheme. Names come back localized,
        so a scheme is identified by its GUID and never by its name: comparing names would
        break on every non-English install and silently fail to find a scheme the user can
        see on screen.

        IsBuiltIn marks the three schemes Windows ships. A duplicated scheme carries a fresh
        GUID but often keeps the name it was duplicated from, which is why the Ultimate
        Performance plan shows up under a GUID that is not its own once it has been added.
        Only built-in schemes are protected: powercfg refuses to delete the rest, so Delete
        is offered on exactly the ones it will accept.

    .EXAMPLE
        Get-WinUtilPowerScheme | Where-Object IsActive
    #>

    $defaultSchemeGuids = @(
        "381b4222-f694-41f0-9685-ff5bb260df2e"  # Balanced
        "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"  # High performance
        "a1841308-3541-4fab-bc81-f71556f20b4a"  # Power saver
    )

    $output = & powercfg /list 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg could not list the power schemes (exit code $LASTEXITCODE)."
    }

    # Matches a GUID, its parenthesized name, and the trailing asterisk Windows marks on the
    # active scheme. The active marker is what distinguishes the current plan, not the name.
    $pattern = '(?<guid>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\((?<name>[^)]*)\)(?<active>\s*\*)?'

    $schemes = foreach ($match in [regex]::Matches($output, $pattern)) {
        $guid = $match.Groups['guid'].Value

        [PSCustomObject]@{
            Guid      = $guid
            Name      = $match.Groups['name'].Value.Trim()
            IsActive  = $match.Groups['active'].Success
            IsBuiltIn = $defaultSchemeGuids -contains $guid
        }
    }

    if (-not $schemes) {
        throw "powercfg returned no recognizable power schemes."
    }

    return @($schemes)
}