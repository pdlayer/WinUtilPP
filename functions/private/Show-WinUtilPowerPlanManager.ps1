function Show-WinUtilPowerPlanManager {
    <#

    .SYNOPSIS
        Opens the power plan manager window

    .DESCRIPTION
        Lists every power scheme, marks the active one, and lets the user apply a plan,
        duplicate one under their own name, or delete a plan they added.

        Everything is keyed off the scheme GUID rather than its name, because powercfg reports
        names in the user's language and a duplicated Ultimate Performance plan keeps the name
        it came from. Delete is refused for the built-in plans: powercfg rejects them anyway,
        and saying so up front reads as a policy rather than a broken button.

    #>

    if (-not (Test-WinUtilUIAlive)) {
        return
    }

    $styles = $sync.Form.Resources

    $window = New-Object Windows.Window
    $window.Title = "Power Plans"
    $window.Width = 560
    $window.Height = 540
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.ResizeMode = [Windows.ResizeMode]::NoResize
    $window.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterScreen
    $window.Background = $styles.MainBackgroundColor
    $window.Foreground = $styles.MainForegroundColor
    $window.FontFamily = $styles.FontFamily
    $window.FontSize = $styles.FontSize

    $layout = New-Object Windows.Controls.Grid
    $layout.Margin = New-Object Windows.Thickness(16)

    $headerRow = New-Object Windows.Controls.RowDefinition
    $headerRow.Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Auto)
    $listRow = New-Object Windows.Controls.RowDefinition
    $listRow.Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
    $actionRow = New-Object Windows.Controls.RowDefinition
    $actionRow.Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Auto)
    $layout.RowDefinitions.Add($headerRow)
    $layout.RowDefinitions.Add($listRow)
    $layout.RowDefinitions.Add($actionRow)

    $window.Content = $layout

    $header = New-Object Windows.Controls.StackPanel
    $header.Margin = New-Object Windows.Thickness(0, 0, 0, 10)

    $title = New-Object Windows.Controls.TextBlock
    $title.Text = "Power Plans"
    $title.FontSize = $styles.CustomDialogFontSizeHeader
    $title.Foreground = $styles.LabelboxForegroundColor
    $header.Children.Add($title)

    $subtitle = New-Object Windows.Controls.TextBlock
    $subtitle.Text = "Apply a plan, duplicate one under your own name, or delete a plan you added."
    $subtitle.TextWrapping = [Windows.TextWrapping]::Wrap
    $subtitle.Foreground = $styles.MainForegroundColor
    $header.Children.Add($subtitle)

    $layout.Children.Add($header)
    [Windows.Controls.Grid]::SetRow($header, 0)

    $list = New-Object Windows.Controls.ListBox
    $list.DisplayMemberPath = "Label"
    $list.HorizontalAlignment = 'Left'
    $list.Width = 500
    $layout.Children.Add($list)
    [Windows.Controls.Grid]::SetRow($list, 1)

    $actions = New-Object Windows.Controls.StackPanel
    $actions.Orientation = [Windows.Controls.Orientation]::Horizontal
    $actions.Margin = New-Object Windows.Thickness(0, 12, 0, 0)
    $layout.Children.Add($actions)
    [Windows.Controls.Grid]::SetRow($actions, 2)

    # Repopulating from a fresh read is what makes an action land: after a duplicate the new
    # GUID exists nowhere beforehand, and after a delete the stale one is gone. Guessing from
    # the previous contents would leave the list lying about the machine.
    $refresh = {
        param($list)

        $schemes = @(Get-WinUtilPowerScheme)
        $list.ItemsSource = @($schemes | ForEach-Object {
            [PSCustomObject]@{
                Label     = if ($_.IsActive) { "$($_.Name)  (active)" } else { $_.Name }
                Guid      = $_.Guid
                IsBuiltIn = $_.IsBuiltIn
            }
        })

        $active = @($schemes | Where-Object IsActive)
        if ($active.Count -eq 1) {
            $match = @($list.Items) | Where-Object Guid -eq $active[0].Guid | Select-Object -First 1
            if ($match) { $list.SelectedItem = $match }
        }
    }

    & $refresh $list

    # A failure is shown and logged rather than thrown, because an exception inside an event
    # handler surfaces as an unhandled WPF error with nothing to attribute it to.
    $reportFailure = {
        param($Title, $ErrorRecord)

        Write-WinUtilErrorRecord -ErrorRecord $ErrorRecord -Component "Power" -Context $Title
        Show-WinUtilMessage -Title $Title -Icon "Warning" -Message $ErrorRecord.Exception.Message
    }

    $applySelected = {
        param($window, $list, $refresh, $reportFailure)

        $selected = $list.SelectedItem
        if (-not $selected) { return }

        try {
            Invoke-WinUtilPowerScheme -Action "Apply" -Guid $selected.Guid
            & $refresh $list
        } catch {
            & $reportFailure "Power Plans" $_
        }
    }

    $duplicateSelected = {
        param($window, $list, $refresh, $reportFailure)

        $selected = $list.SelectedItem
        if (-not $selected) { return }

        $name = Show-WinUtilPrompt -Title "Duplicate Power Plan" -Message "Name for the new plan"
        if ([string]::IsNullOrWhiteSpace($name)) { return }

        try {
            $newGuid = Invoke-WinUtilPowerScheme -Action "Duplicate" -Guid $selected.Guid -Name $name.Trim()
            & $refresh $list
            $match = @($list.Items) | Where-Object Guid -eq $newGuid | Select-Object -First 1
            if ($match) { $list.SelectedItem = $match }
        } catch {
            & $reportFailure "Power Plans" $_
        }
    }

    $deleteSelected = {
        param($window, $list, $refresh, $reportFailure)

        $selected = $list.SelectedItem
        if (-not $selected) { return }

        if ($selected.IsBuiltIn) {
            Show-WinUtilMessage -Title "Power Plans" -Icon "Warning" `
                -Message "Windows does not allow deleting its built-in power plans.`n`nSelect a plan you added."
            return
        }

        $answer = Show-WinUtilMessage -Title "Power Plans" -Icon "Warning" -Button "YesNo" `
            -Message "Delete the power plan '$($selected.Label)'?"
        if ($answer -ne "Yes") { return }

        try {
            Invoke-WinUtilPowerScheme -Action "Delete" -Guid $selected.Guid
            & $refresh $list
        } catch {
            & $reportFailure "Power Plans" $_
        }
    }

    $closeWindow = {
        param($window)
        $window.Close()
    }

    # Handler bodies travel as parameters. A closure would bind command lookup to a copied
    # scope, so Invoke-WinUtilPowerScheme and friends would resolve somewhere else entirely.
    $buttons = @(
        @{ Label = "Apply";     Tooltip = "Make the selected plan the active one."; Handler = $applySelected }
        @{ Label = "Duplicate"; Tooltip = "Copy the selected plan under your own name."; Handler = $duplicateSelected }
        @{ Label = "Delete";    Tooltip = "Delete the selected plan, if you added it."; Handler = $deleteSelected }
        @{ Label = "Close";     Tooltip = "Close this window."; Handler = $closeWindow }
    )

    foreach ($definition in $buttons) {
        $button = New-Object Windows.Controls.Button
        $button.Content = $definition.Label
        $button.ToolTip = $definition.Tooltip
        $button.Margin = New-Object Windows.Thickness(0, 0, 8, 0)
        $button.Background = $styles.ButtonInstallBackgroundColor
        $button.Foreground = $styles.ButtonInstallForegroundColor
        $button.BorderBrush = $styles.BorderColor

        $handler = $definition.Handler
        $button.Add_Click({
            param($clickSender, $clickArgs)
            $null = $clickSender
            $null = $clickArgs
            & $handler $window $list $refresh $reportFailure
        })

        $actions.Children.Add($button) | Out-Null
    }

    $window.Add_KeyDown({
        param($keySender, $keyArgs)
        if ($keyArgs.Key -eq 'Escape') { $keySender.Close() }
    })

    $null = $window.ShowDialog()
}