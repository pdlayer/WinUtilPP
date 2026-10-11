function Show-WinUtilPrompt {
    <#

    .SYNOPSIS
        Asks the user for a line of text

    .DESCRIPTION
        A single TextBox in a small modal window, because WPF has no built-in equivalent of
        the WinForms input box and WinUtil does not otherwise carry a dialog library.

        Cancelling returns null rather than an empty string, so a caller can tell "the user
        changed their mind" from "the user accepted a blank name" and decide for itself
        whether empty is even valid. When there is no window to ask on, the answer is null:
        a prompt nobody saw must never stand in for a name the user chose.

    .PARAMETER Title
        Window title.

    .PARAMETER Message
        The question shown above the input.

    .PARAMETER DefaultText
        Pre-filled text.

    .OUTPUTS
        The entered text, or $null if the window was cancelled or closed.

    #>
    param(
        [string]$Title = "Winutil",
        [string]$Message = "",
        [string]$DefaultText = ""
    )

    Write-WinUtilLog -Component "Dialog" -Message "$Title : $Message"

    if (-not (Test-WinUtilUIAlive)) {
        Write-WinUtilLog -Level "WARN" -Component "Dialog" -Message "No window to ask on, answering nothing for: $Title"
        return $null
    }

    return Invoke-WPFUIThread -PassThru -Parameters @{
        Title       = $Title
        Message     = $Message
        DefaultText = $DefaultText
    } -ScriptBlock {
        param($Title, $Message, $DefaultText)

        $styles = $sync.Form.Resources

        $dialog = New-Object Windows.Window
        $dialog.Title = $Title
        $dialog.Width = 420
        $dialog.Height = 190
        $dialog.WindowStyle = [Windows.WindowStyle]::None
        $dialog.ResizeMode = [Windows.ResizeMode]::NoResize
        $dialog.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterScreen
        $dialog.Background = $styles.MainBackgroundColor
        $dialog.Foreground = $styles.MainForegroundColor
        $dialog.FontFamily = $styles.FontFamily
        $dialog.FontSize = $styles.FontSize

        $layout = New-Object Windows.Controls.Grid
        $layout.Margin = New-Object Windows.Thickness(16)

        foreach ($height in @('Auto', 'Auto', '*', 'Auto')) {
            $row = New-Object Windows.Controls.RowDefinition
            $row.Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Auto)
            if ($height -eq '*') {
                $row.Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
            }
            $layout.RowDefinitions.Add($row)
        }

        $dialog.Content = $layout

        $messageText = New-Object Windows.Controls.TextBlock
        $messageText.Text = $Message
        $messageText.TextWrapping = [Windows.TextWrapping]::Wrap
        $messageText.Margin = New-Object Windows.Thickness(0, 0, 0, 8)
        $layout.Children.Add($messageText)
        [Windows.Controls.Grid]::SetRow($messageText, 0)

        # Not named $input: that is an automatic variable, and a pipeline assigning through
        # it would land here instead of in the TextBox.
        $textBox = New-Object Windows.Controls.TextBox
        $textBox.Text = $DefaultText
        $textBox.Margin = New-Object Windows.Thickness(0, 0, 0, 12)
        $layout.Children.Add($textBox)
        [Windows.Controls.Grid]::SetRow($textBox, 1)

        $buttons = New-Object Windows.Controls.StackPanel
        $buttons.Orientation = [Windows.Controls.Orientation]::Horizontal
        $buttons.HorizontalAlignment = [Windows.HorizontalAlignment]::Right
        $layout.Children.Add($buttons)
        [Windows.Controls.Grid]::SetRow($buttons, 3)

        # A reference type, so the click handler's assignment survives the scope it runs in.
        # A plain variable would be set in a child scope and lost by the time the window closes.
        $answer = [pscustomobject]@{ Value = $null }

        $confirmButton = New-Object Windows.Controls.Button
        $confirmButton.Content = "OK"
        $confirmButton.IsDefault = $true
        $confirmButton.Margin = New-Object Windows.Thickness(0, 0, 8, 0)
        $confirmButton.Background = $styles.ButtonInstallBackgroundColor
        $confirmButton.Foreground = $styles.ButtonInstallForegroundColor
        $confirmButton.BorderBrush = $styles.BorderColor
        $confirmButton.Add_Click({
            $answer.Value = $textBox.Text
            $dialog.Close()
        })
        $buttons.Children.Add($confirmButton)

        $cancelButton = New-Object Windows.Controls.Button
        $cancelButton.Content = "Cancel"
        $cancelButton.IsCancel = $true
        $cancelButton.Background = $styles.ButtonInstallBackgroundColor
        $cancelButton.Foreground = $styles.ButtonInstallForegroundColor
        $cancelButton.BorderBrush = $styles.BorderColor
        $cancelButton.Add_Click({ $dialog.Close() })
        $buttons.Children.Add($cancelButton)

        $dialog.Add_KeyDown({
            if ($_.Key -eq 'Escape') { $dialog.Close() }
        })

        $null = $dialog.ShowDialog()
        $answer.Value
    }
}