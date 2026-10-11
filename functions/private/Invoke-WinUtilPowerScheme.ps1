function Invoke-WinUtilPowerScheme {
    <#

    .SYNOPSIS
        Applies, duplicates or deletes a power scheme

    .DESCRIPTION
        The powercfg half of the power plan manager, kept separate from the window so each
        operation can be exercised without a form.

        Schemes are always addressed by GUID. powercfg reports names localized, so a name is
        only ever used as text for the user, never as a way to find a scheme.

        Every operation re-reads the scheme list afterwards rather than assuming the call
        worked: /duplicatescheme hands back a new GUID that exists nowhere beforehand, and
        that GUID is the only reliable proof the copy was made.

    .PARAMETER Action
        Apply, Duplicate or Delete.

    .PARAMETER Guid
        The scheme to act on.

    .PARAMETER Name
        The name to give a duplicate. Required for Duplicate, ignored otherwise.

    .OUTPUTS
        For Duplicate, the GUID of the new scheme. Otherwise nothing.

    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Apply", "Duplicate", "Delete")]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$Guid,

        [string]$Name
    )

    Write-WinUtilLog -Component "Power" -Message "Power scheme ${Action}: $Guid"

    switch ($Action) {
        "Apply" {
            $output = & powercfg /setactive $Guid 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                throw "powercfg could not activate the scheme $Guid (exit code $LASTEXITCODE).`n$($output.Trim())"
            }
        }

        "Duplicate" {
            if ([string]::IsNullOrWhiteSpace($Name)) {
                throw "A name is required to duplicate a power scheme."
            }

            $output = & powercfg /duplicatescheme $Guid 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                throw "powercfg could not duplicate the scheme $Guid (exit code $LASTEXITCODE).`n$($output.Trim())"
            }

            # The duplicate keeps a fresh GUID, and with it whatever name the source had, so it
            # has to be renamed or the user sees the same plan twice under one name.
            $newGuid = ([regex]'(?<guid>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})').Matches($output) |
                ForEach-Object { $_.Groups['guid'].Value } |
                Where-Object { $_ -ne $Guid } |
                Select-Object -First 1

            if (-not $newGuid) {
                throw "powercfg duplicated the scheme but did not report the new GUID, so the copy cannot be renamed."
            }

            $renameOutput = & powercfg /changename $newGuid $Name 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                # The copy exists but is unnamed. Say so rather than reporting a total failure,
                # because deleting it is now the user's cleanup.
                throw "powercfg created a scheme ($newGuid) but could not rename it.`n$($renameOutput.Trim())"
            }

            Write-WinUtilLog -Component "Power" -Message "Duplicated $Guid as '$Name' ($newGuid)."
            return $newGuid
        }

        "Delete" {
            $scheme = Get-WinUtilPowerScheme | Where-Object Guid -eq $Guid | Select-Object -First 1
            if (-not $scheme) {
                throw "No power scheme with GUID $Guid exists on this system."
            }

            if ($scheme.IsBuiltIn) {
                throw "Windows does not allow its built-in power plans to be deleted."
            }

            $output = & powercfg /delete $Guid 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                throw "powercfg could not delete the scheme $Guid (exit code $LASTEXITCODE).`n$($output.Trim())"
            }
        }
    }

    return $null
}