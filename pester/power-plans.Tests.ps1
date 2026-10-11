#===========================================================================
# Tests - Power Plan Manager
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:config = Get-Content (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilPowerScheme.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilPowerScheme.ps1")

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }

    $script:balanced = "381b4222-f694-41f0-9685-ff5bb260df2e"
    $script:highPerformance = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    $script:powerSaver = "a1841308-3541-4fab-bc81-f71556f20b4a"

    function script:New-PowerCfgOutput {
        param(
            [string]$BalancedName = "Balanced",
            [string]$HighName = "High performance",
            [string]$SaverName = "Power saver",
            [string]$ActiveGuid = "",
            [string]$ExtraLines = ""
        )

        # powercfg is a native command, so the code under test reads $LASTEXITCODE. A Pester
        # mock leaves it $null rather than 0, which the success paths would read as a failure.
        $global:LASTEXITCODE = 0

        $activeLine = if ($ActiveGuid) { "Power Scheme GUID: $ActiveGuid  (Custom plan) *" } else { "" }

        @"
Существующие схемы управления питанием (* - активные)
-----------------------------------
Power Scheme GUID: $script:balanced  ($BalancedName)
Power Scheme GUID: $script:highPerformance  ($HighName)
Power Scheme GUID: $script:powerSaver  ($SaverName)
$ExtraLines
$activeLine
"@
    }

    function script:New-SuccessPowerCfg {
        param([string]$Output = "")

        $global:LASTEXITCODE = 0
        $Output
    }
}

Describe "Get-WinUtilPowerScheme" {
    It "marks only the scheme powercfg starred as active" {
        Mock powercfg { New-PowerCfgOutput -ActiveGuid $script:highPerformance }

        $schemes = @(Get-WinUtilPowerScheme)

        $schemes.Count | Should -Be 4
        @($schemes | Where-Object IsActive).Guid | Should -Be $script:highPerformance
    }

    It "reads schemes on a localized install without matching on names" {
        Mock powercfg {
            New-PowerCfgOutput -BalancedName "Сбалансированная" -HighName "Высокая производительность" -SaverName "Экономия энергии"
        }

        $schemes = @(Get-WinUtilPowerScheme)

        # Three shipped plans and no star on any of them, which is how an untouched machine
        # looks: the names are translated but the GUIDs and the built-in flags still line up.
        $schemes.Count | Should -Be 3
        @($schemes | Where-Object IsActive) | Should -BeNullOrEmpty
        ($schemes | Where-Object Guid -eq $script:balanced).Name | Should -Be "Сбалансированная"
        ($schemes | Where-Object Guid -eq $script:balanced).IsBuiltIn | Should -BeTrue
    }

    It "treats the three shipped plans as built-in and a duplicate as not" {
        # A duplicated Ultimate Performance plan keeps the name it came from and gets a new
        # GUID, so only the GUID identifies it as user added.
        $duplicate = "d9ed93bd-c9b2-4247-a04f-879598dc88ca"
        Mock powercfg { New-PowerCfgOutput -ActiveGuid $duplicate }

        $schemes = @(Get-WinUtilPowerScheme)

        @($schemes | Where-Object IsBuiltIn).Guid | Should -Be @($script:balanced, $script:highPerformance, $script:powerSaver)
        ($schemes | Where-Object Guid -eq $duplicate).IsBuiltIn | Should -BeFalse
        ($schemes | Where-Object Guid -eq $duplicate).IsActive | Should -BeTrue
    }

    It "fails rather than returning nothing when powercfg fails" {
        Mock powercfg { "error"; $global:LASTEXITCODE = 1 }

        { Get-WinUtilPowerScheme } | Should -Throw "*could not list the power schemes*"
    }

    It "fails when the output holds no recognizable scheme" {
        Mock powercfg { $global:LASTEXITCODE = 0; "nothing useful here" }

        { Get-WinUtilPowerScheme } | Should -Throw "*no recognizable power schemes*"
    }
}

Describe "Invoke-WinUtilPowerScheme" {
    It "applies a scheme by GUID" {
        Mock powercfg { New-SuccessPowerCfg }

        Invoke-WinUtilPowerScheme -Action "Apply" -Guid $script:highPerformance | Should -BeNullOrEmpty

        Should -Invoke powercfg -Times 1 -ParameterFilter { $args -contains '/setactive' -and $args -contains $script:highPerformance }
    }

    It "deletes a plan the user added" {
        Mock powercfg { New-SuccessPowerCfg }
        Mock Get-WinUtilPowerScheme {
            @([PSCustomObject]@{ Guid = "d9ed93bd-c9b2-4247-a04f-879598dc88ca"; Name = "Custom"; IsActive = $true; IsBuiltIn = $false })
        }

        Invoke-WinUtilPowerScheme -Action "Delete" -Guid "d9ed93bd-c9b2-4247-a04f-879598dc88ca" | Should -BeNullOrEmpty

        Should -Invoke powercfg -Times 1 -ParameterFilter { $args -contains '/delete' }
    }

    It "refuses to delete a built-in plan" {
        Mock powercfg { New-SuccessPowerCfg }
        Mock Get-WinUtilPowerScheme {
            @([PSCustomObject]@{ Guid = $script:balanced; Name = "Balanced"; IsActive = $false; IsBuiltIn = $true })
        }

        { Invoke-WinUtilPowerScheme -Action "Delete" -Guid $script:balanced } | Should -Throw "*built-in*"

        Should -Invoke powercfg -Times 0
    }

    It "refuses to delete a scheme that is not on this machine" {
        Mock powercfg { New-SuccessPowerCfg }
        Mock Get-WinUtilPowerScheme {
            @([PSCustomObject]@{ Guid = $script:balanced; Name = "Balanced"; IsActive = $true; IsBuiltIn = $true })
        }

        { Invoke-WinUtilPowerScheme -Action "Delete" -Guid "00000000-0000-0000-0000-000000000000" } | Should -Throw "*No power scheme*"

        Should -Invoke powercfg -Times 0
    }

    It "duplicates a plan and renames the copy, returning the new GUID" {
        $newGuid = "11111111-2222-3333-4444-555555555555"
        Mock powercfg {
            $global:LASTEXITCODE = 0
            if ($args -contains '/duplicatescheme') {
                "Power Scheme GUID: $newGuid  (Ultimate Performance)*"
            }
        }

        $result = Invoke-WinUtilPowerScheme -Action "Duplicate" -Guid $script:balanced -Name "My plan"

        $result | Should -Be $newGuid
        # Renaming matters: the duplicate otherwise shows the source plan's name, and the user
        # would see the same plan listed twice under one name.
        Should -Invoke powercfg -Times 1 -ParameterFilter {
            $args -contains '/changename' -and $args -contains $newGuid -and $args -contains 'My plan'
        }
    }

    It "does not mistake the source GUID for the new one" {
        # powercfg echoes the source name in its output; taking the first GUID would hand back
        # the plan the user already had and the rename would then hit the original.
        $newGuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        Mock powercfg { New-SuccessPowerCfg -Output "Power Scheme GUID: $newGuid  (Balanced)*" }

        Invoke-WinUtilPowerScheme -Action "Duplicate" -Guid $script:balanced -Name "Copy" | Should -Be $newGuid
    }

    It "refuses to duplicate without a name" {
        Mock powercfg { New-SuccessPowerCfg }

        { Invoke-WinUtilPowerScheme -Action "Duplicate" -Guid $script:balanced -Name "  " } | Should -Throw "*name is required*"

        Should -Invoke powercfg -Times 0
    }

    It "reports a duplicate whose new GUID powercfg did not print" {
        Mock powercfg { New-SuccessPowerCfg -Output "Power Scheme GUID: $script:balanced  (Balanced)*" }

        { Invoke-WinUtilPowerScheme -Action "Duplicate" -Guid $script:balanced -Name "Copy" } | Should -Throw "*did not report the new GUID*"
    }

    It "reports the copy as existing when only the rename failed" {
        $newGuid = "11111111-2222-3333-4444-555555555555"
        Mock powercfg {
            if ($args -contains '/duplicatescheme') {
                $global:LASTEXITCODE = 0
                "Power Scheme GUID: $newGuid  (Balanced)*"
            } else {
                $global:LASTEXITCODE = 1
            }
        }

        # The copy is on disk at this point even though the name did not stick, so the message
        # has to say so rather than implying nothing happened.
        { Invoke-WinUtilPowerScheme -Action "Duplicate" -Guid $script:balanced -Name "Copy" } |
            Should -Throw "*could not rename it*"
    }
}

Describe "Power plan manager entry" {
    It "is offered as a button next to the Ultimate Performance controls" {
        $script:config.WPFManagePowerPlans.Type | Should -Be "Button"
        $script:config.WPFManagePowerPlans.category | Should -Be "Performance Plans - NOT FOR LAPTOPS"
        $script:config.WPFManagePowerPlans.panel | Should -Be "2"
    }

    It "is routed by Invoke-WPFButton" {
        $buttonSource = Get-Content (Join-Path $script:repoRoot "functions\public\Invoke-WPFButton.ps1") -Raw
        $buttonSource | Should -Match '"WPFManagePowerPlans"\s*\{\s*Show-WinUtilPowerPlanManager'
    }
}