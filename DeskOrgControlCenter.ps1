
#requires -Version 5.1
# ==========================================================
# DeskOrg Control Center | Modern WPF UI
# Credits: Nivesh Sahayak
# https://niveshsahayak.in | 8054009300
# ==========================================================

$ErrorActionPreference = 'Stop'

$AppFolder = $PSScriptRoot
$OrganizerFile = Join-Path $AppFolder 'DeskOrg.bat'
$AutomationFile = Join-Path $AppFolder 'DeskOrgAutomation.ps1'
# Editable rules live in a per-user folder so the app works from a read-only
# install location (e.g. C:\Program Files). Seed from the shipped default.
$DataFolder = Join-Path $env:LOCALAPPDATA 'DeskOrg'
$RulesFile = Join-Path $DataFolder 'DeskOrgRules.json'
if (-not (Test-Path -LiteralPath $RulesFile)) {
    try {
        if (-not (Test-Path -LiteralPath $DataFolder)) {
            New-Item -ItemType Directory -Path $DataFolder -Force | Out-Null
        }
        $DefaultRules = Join-Path $AppFolder 'DeskOrgRules.json'
        if (Test-Path -LiteralPath $DefaultRules) {
            Copy-Item -LiteralPath $DefaultRules -Destination $RulesFile -Force
        }
    } catch { }
}
$LogoFile = Join-Path $AppFolder 'DeskOrgLogo.png'
$LogFile = Join-Path $env:TEMP 'DeskOrg.log'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ---------------- THEME ----------------

$script:C = @{
    Background = '#07090F'
    Sidebar    = '#0A0E1A'
    Panel      = '#0E1424'
    Panel2     = '#151D32'
    Border     = '#243049'
    Text       = '#EAF0FF'
    Muted      = '#8A93B2'
    Teal       = '#2FE6C8'
    Purple     = '#8C7BFF'
    Amber      = '#FFB44D'
    Blue       = '#49A6FF'
    Red        = '#FF5C9A'
}

# Bundled display font (Unbounded) with graceful fallback to Segoe UI
try {
    $script:DisplayFont = New-Object System.Windows.Media.FontFamily(
        ('file:///' + ($AppFolder -replace '\\', '/') + '/#Unbounded'))
} catch {
    $script:DisplayFont = New-Object System.Windows.Media.FontFamily('Segoe UI')
}

# Build a left-to-right linear-gradient brush from hex stops
function New-Grad {
    param([string[]]$Hex, [double[]]$Pos, [string]$Start = '0,0', [string]$End = '1,0')
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.StartPoint = $Start; $g.EndPoint = $End
    for ($k = 0; $k -lt $Hex.Count; $k++) {
        [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop (
            [System.Windows.Media.ColorConverter]::ConvertFromString($Hex[$k]), $Pos[$k])))
    }
    return $g
}

$script:CurrentPage = 'Home'
$script:Window = $null
$script:PageHost = $null
$script:PageTitle = $null
$script:PageSubtitle = $null
$script:NavButtons = @{}
$script:StatusLine = $null

# ---------------- HELPERS ----------------

function New-Text {
    param(
        [string]$Text,
        [int]$Size = 13,
        [string]$Color = $script:C.Text,
        [switch]$Bold,
        [switch]$Wrap,
        [switch]$Display
    )

    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontSize = $Size
    $t.Foreground = $Color
    if ($Display) {
        $t.FontFamily = $script:DisplayFont
        $t.FontWeight = [System.Windows.FontWeights]::Bold
    } elseif ($Bold) {
        $t.FontWeight = [System.Windows.FontWeights]::SemiBold
    }
    if ($Wrap) {
        $t.TextWrapping = 'Wrap'
    }
    return $t
}

function New-Stack {
    $s = New-Object System.Windows.Controls.StackPanel
    return $s
}

function New-Card {
    param(
        [string]$Title,
        [string]$Description = '',
        [string]$Accent = '#65E4D4'
    )

    $border = New-Object System.Windows.Controls.Border
    $border.Background = $script:C.Panel
    $border.BorderBrush = $script:C.Border
    $border.BorderThickness = '1'
    $border.CornerRadius = '15'
    $border.Padding = '18'
    $border.Margin = '0,0,0,14'

    $body = New-Stack

    [void]$body.Children.Add((New-Text $Title 16 $Accent -Display))

    if ($Description) {
        $desc = New-Text $Description 11 $script:C.Muted -Wrap
        $desc.Margin = '0,5,0,12'
        [void]$body.Children.Add($desc)
    }

    $border.Child = $body

    return @{
        Border = $border
        Body = $body
    }
}

function Set-DeskOrgButtonStyle {
    param(
        [System.Windows.Controls.Button]$Button,
        [string]$NormalBackground = '#101A2E',
        [string]$NormalBorder = '#263A53',
        [switch]$KeepBackground
    )

    $Button.Background = $NormalBackground
    $Button.BorderBrush = $NormalBorder
    $Button.Foreground = $script:C.Text
    $Button.BorderThickness = '1'
    $Button.Cursor = [System.Windows.Input.Cursors]::Hand

    # Primary (gradient) buttons keep their background on hover; others shift tone.
    $bgHover = if ($KeepBackground) { '' } else { '<Setter TargetName="CardBorder" Property="Background" Value="#15203A"/>' }
    $bgPress = if ($KeepBackground) { '' } else { '<Setter TargetName="CardBorder" Property="Background" Value="#10332E"/>' }

    $template = @"
<ControlTemplate
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    TargetType="{x:Type Button}">
    <Border x:Name="CardBorder"
            Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            CornerRadius="13"
            SnapsToDevicePixels="True">
        <ContentPresenter
            Margin="{TemplateBinding Padding}"
            HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
            VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
            RecognizesAccessKey="True"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            $bgHover
            <Setter TargetName="CardBorder" Property="BorderBrush" Value="#2FE6C8"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
            $bgPress
            <Setter TargetName="CardBorder" Property="BorderBrush" Value="#2FE6C8"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="CardBorder" Property="Opacity" Value="0.55"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@

    $Button.Template =
        [System.Windows.Markup.XamlReader]::Parse($template)
}

function New-ActionButton {
    param(
        [string]$Title,
        [string]$Description = '',
        [scriptblock]$Action,
        [string]$Accent = '#65E4D4',
        [switch]$Primary
    )

    $b = New-Object System.Windows.Controls.Button
    $b.Padding = '13,11'
    $b.Margin = '0,0,0,9'
    $b.HorizontalContentAlignment = 'Stretch'
    $b.Background = if ($Primary) { New-Grad @('#149B86','#5A49C7','#B83B78') @(0.0,0.55,1.0) } else { $script:C.Panel2 }
    $b.Foreground = if ($Primary) { '#FFFFFF' } else { $script:C.Text }
    $b.BorderBrush = if ($Primary) { 'Transparent' } else { $script:C.Border }
    $b.BorderThickness = '1'
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    # Smooth-looking hover effect without hiding text
$b.Add_MouseEnter({
    if ($Primary) {
        $this.Background = New-Grad @('#1BB8A0','#6E5CE0','#D44E8E') @(0.0,0.55,1.0)
    } else {
        $this.Background = '#15463E'
        $this.BorderBrush = $script:C.Teal
    }
}.GetNewClosure())

$b.Add_MouseLeave({
    if ($Primary) {
        $this.Background = New-Grad @('#149B86','#5A49C7','#B83B78') @(0.0,0.55,1.0)
    }
    else {
        $this.Background = $script:C.Panel2
        $this.BorderBrush = $script:C.Border
    }
}.GetNewClosure())
    $b.HorizontalAlignment = 'Stretch'

    $titleColor = if ($Primary) { '#FFFFFF' } else { $script:C.Text }
    $descColor  = if ($Primary) { '#E6ECFB' } else { $script:C.Muted }

    $s = New-Stack
    [void]$s.Children.Add((New-Text $Title 13 $titleColor -Bold))

    if ($Description) {
        $d = New-Text $Description 10 $descColor -Wrap
        $d.Margin = '0,3,0,0'
        [void]$s.Children.Add($d)
    }

    $b.Content = $s
if ($Primary) {
    Set-DeskOrgButtonStyle -Button $b -NormalBackground '#10332E' -NormalBorder 'Transparent' -KeepBackground
    $b.Background = New-Grad @('#2FE6C8','#8C7BFF','#FF5C9A') @(0.0,0.6,1.0)
} else {
    Set-DeskOrgButtonStyle -Button $b -NormalBackground $script:C.Panel2 -NormalBorder $script:C.Border
}
    if ($Action) {
        $b.Add_Click($Action)
    }

    return $b
}

function Add-Action {
    param(
        $Card,
        [string]$Title,
        [string]$Description,
        [scriptblock]$Action,
        [string]$Accent = '#65E4D4',
        [switch]$Primary
    )

    $button = New-ActionButton `
        -Title $Title `
        -Description $Description `
        -Action $Action `
        -Accent $Accent `
        -Primary:$Primary

    [void]$Card.Body.Children.Add($button)
}

function Show-Message {
    param(
        [string]$Message,
        [string]$Title = 'DeskOrg',
        [System.Windows.MessageBoxImage]$Icon =
            [System.Windows.MessageBoxImage]::Information
    )

    $MessageBox = New-Object System.Windows.Window
    $MessageBox.Title = $Title
    $MessageBox.Width = 440
    $MessageBox.SizeToContent = 'Height'
    $MessageBox.WindowStartupLocation = 'CenterScreen'
    $MessageBox.ResizeMode = 'NoResize'
    $MessageBox.ShowInTaskbar = $false
    $MessageBox.Background = [System.Windows.Media.Brushes]::White
    $MessageBox.Padding = '20'

    $Panel = New-Object System.Windows.Controls.StackPanel

    $Text = New-Object System.Windows.Controls.TextBlock
    $Text.Text = $Message
    $Text.TextWrapping = 'Wrap'
    $Text.Margin = '0,0,0,20'
    $Text.FontSize = 14

    $Button = New-Object System.Windows.Controls.Button
    $Button.Content = 'OK'
    $Button.Width = 90
    $Button.Height = 32
    $Button.HorizontalAlignment = 'Right'
    $Button.IsDefault = $true

    $Button.Add_Click({
        $MessageBox.Close()
    })

    $Panel.Children.Add($Text) | Out-Null
    $Panel.Children.Add($Button) | Out-Null

    $MessageBox.Content = $Panel

    # Enter closes the window through the default OK button.
    $MessageBox.ShowDialog() | Out-Null
}

function Set-Status {
    param([string]$Message)

    if ($script:StatusLine) {
        $script:StatusLine.Text = $Message
    }
}

function Open-FileSafely {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Show-Message (
            "$Description was not found." +
            [Environment]::NewLine +
            $Path
        ) 'DeskOrg' ([System.Windows.MessageBoxImage]::Warning)
        return
    }

    try {
        Start-Process -FilePath $Path -ErrorAction Stop
        Set-Status "Opened $Description."
    }
    catch {
        Show-Message (
            "Unable to open $Description." +
            [Environment]::NewLine +
            $_.Exception.Message
        ) 'DeskOrg' ([System.Windows.MessageBoxImage]::Error)
    }
}

function Invoke-Organizer {
    if (-not (Test-Path -LiteralPath $OrganizerFile -PathType Leaf)) {
        Show-Message (
            "The organizer launcher was not found." +
            [Environment]::NewLine +
            $OrganizerFile
        ) 'DeskOrg' ([System.Windows.MessageBoxImage]::Warning)
        return
    }

    try {
        Start-Process `
            -FilePath $env:ComSpec `
            -ArgumentList @('/c', "`"$OrganizerFile`"") `
            -WorkingDirectory $AppFolder `
            -ErrorAction Stop

        Set-Status 'Organizer launched.'
    }
    catch {
        Show-Message (
            "Unable to launch DeskOrg Organizer." +
            [Environment]::NewLine +
            $_.Exception.Message
        ) 'DeskOrg' ([System.Windows.MessageBoxImage]::Error)
    }
}

function Invoke-Automation {
    param(
        [ValidateSet('Install', 'Status', 'Disable', 'Uninstall', 'Test')]
        [string]$Action
    )

    if (-not (Test-Path -LiteralPath $AutomationFile -PathType Leaf)) {
        Show-Message (
            "The automation script was not found." +
            [Environment]::NewLine +
            $AutomationFile
        ) 'DeskOrg Automation' ([System.Windows.MessageBoxImage]::Warning)
        return
    }

    try {
        # Run the automation command and keep its console open.
$command = '& "' + $AutomationFile + '" ' + $Action +
    '; Write-Host ""; [void](Read-Host "Press Enter to close this window"); exit'

        $encodedCommand = [Convert]::ToBase64String(
            [System.Text.Encoding]::Unicode.GetBytes($command)
        )

        Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList @(
                '-NoProfile',
                '-ExecutionPolicy', 'AllSigned',
                '-NoExit',
                '-EncodedCommand', $encodedCommand
            ) `
            -WorkingDirectory $AppFolder `
            -ErrorAction Stop

        Set-Status "Automation command started: $Action"
    }
    catch {
        Show-Message (
            "Unable to start the automation command." +
            [Environment]::NewLine +
            $_.Exception.Message
        ) 'DeskOrg Automation' ([System.Windows.MessageBoxImage]::Error)
    }
}

function Get-StatusSummary {
    $rulesState = if (Test-Path -LiteralPath $RulesFile -PathType Leaf) {
        'Available'
    } else {
        'Missing'
    }

    $automationState = if (
        Test-Path -LiteralPath $AutomationFile -PathType Leaf
    ) {
        'Available'
    } else {
        'Missing'
    }

    $logState = if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        'Log created'
    } else {
        'No log yet'
    }

    return [PSCustomObject]@{
        Rules = $rulesState
        Automation = $automationState
        Log = $logState
    }
}

function Navigate-To {
    param([string]$Page)

    $script:CurrentPage = $Page

    foreach ($key in $script:NavButtons.Keys) {
        $btn = $script:NavButtons[$key]
        if ($key -eq $Page) {
            $btn.Background = '#10332E'
            $btn.BorderBrush = $script:C.Teal
            $btn.Foreground = $script:C.Teal
        } else {
            $btn.Background = $script:C.Sidebar
            $btn.BorderBrush = $script:C.Sidebar
            $btn.Foreground = $script:C.Muted
        }
    }

    $script:PageHost.Children.Clear()

    switch ($Page) {
        'Home' {
            $script:PageTitle.Text = 'Welcome back.'
            $script:PageSubtitle.Text = 'Your desktop. Your flow. Everything in its place.'
            Build-HomePage
        }
        'Organize' {
            $script:PageTitle.Text = 'Organize'
            $script:PageSubtitle.Text = 'Your desktop cleanup tools, all in one place.'
            Build-OrganizePage
        }
        'Automation' {
            $script:PageTitle.Text = 'Smart automation'
            $script:PageSubtitle.Text = 'Choose how DeskOrg watches and maintains your desktop.'
            Build-AutomationPage
        }
        'Settings' {
            $script:PageTitle.Text = 'Rules & settings'
            $script:PageSubtitle.Text = 'Customize file categories and inspect your configuration.'
            Build-SettingsPage
        }
        'Activity' {
            $script:PageTitle.Text = 'Activity'
            $script:PageSubtitle.Text = 'Open the activity log and review your current setup.'
            Build-ActivityPage
        }
    }
}

# ---------------- PAGE LAYOUT HELPERS ----------------

function New-PageStack {
    $stack = New-Stack
    $stack.Margin = '0,0,12,0'
    return $stack
}

function Add-PageCard {
    param($Target, $Card)
    [void]$Target.Children.Add($Card.Border)
}

function Build-HomePage {
    $root = New-PageStack

    $welcome = New-Object System.Windows.Controls.Border
    $welcome.Background = New-Grad @('#0E1A2E','#15132B','#201033') @(0.0,0.55,1.0) '0,0' '1,1'
    $welcome.BorderBrush = '#2A2550'
    $welcome.BorderThickness = '1'
    $welcome.CornerRadius = '18'
    $welcome.Padding = '22'
    $welcome.Margin = '0,0,0,18'

    $welcomeStack = New-Stack
    [void]$welcomeStack.Children.Add(
        (New-Text 'MAKE SPACE FOR WHAT MATTERS.' 10 $script:C.Teal -Bold)
    )

    $welcomeTitle = New-Text 'Your desktop, sorted.' 30 $script:C.Text -Display -Wrap
    $welcomeTitle.Margin = '0,8,0,7'
    [void]$welcomeStack.Children.Add($welcomeTitle)

    [void]$welcomeStack.Children.Add(
        (New-Text 'Organize files, manage automation, and keep your workflow simple.' 12 $script:C.Muted -Wrap)
    )

    $welcome.Child = $welcomeStack
    [void]$root.Children.Add($welcome)

    $section = New-Text 'YOUR WORKSPACE' 10 $script:C.Muted -Bold
    $section.Margin = '2,0,0,10'
    [void]$root.Children.Add($section)

    $cardsGrid = New-Object System.Windows.Controls.Grid
    $cardsGrid.Margin = '0,0,0,15'

    foreach ($i in 1..2) {
        $col = New-Object System.Windows.Controls.ColumnDefinition
        $col.Width = New-Object System.Windows.GridLength(
            1, [System.Windows.GridUnitType]::Star
        )
        [void]$cardsGrid.ColumnDefinitions.Add($col)
    }

    foreach ($i in 1..2) {
        $row = New-Object System.Windows.Controls.RowDefinition
        $row.Height = [System.Windows.GridLength]::Auto
        [void]$cardsGrid.RowDefinitions.Add($row)
    }

    $items = @(
        @{
            Title = 'Organize'
            Desc = 'Sort and manage desktop files.'
            Accent = $script:C.Teal
            Page = 'Organize'
            Icon = '01'
        },
        @{
            Title = 'Smart automation'
            Desc = 'Configure watching and scheduled actions.'
            Accent = $script:C.Purple
            Page = 'Automation'
            Icon = '02'
        },
        @{
            Title = 'Rules & settings'
            Desc = 'Edit your saved organization rules.'
            Accent = $script:C.Amber
            Page = 'Settings'
            Icon = '03'
        },
        @{
            Title = 'Activity & logs'
            Desc = 'Review activity and configuration health.'
            Accent = $script:C.Blue
            Page = 'Activity'
            Icon = '04'
        }
    )

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $card = New-Object System.Windows.Controls.Button
        $card.Background = $script:C.Panel
        $card.BorderBrush = $script:C.Border
        $card.BorderThickness = '1'

# Custom dark-theme template: prevents the default pale-blue hover
$card.Template = [System.Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    TargetType="{x:Type Button}">
    <Border
        x:Name="CardBorder"
        Background="{TemplateBinding Background}"
        BorderBrush="{TemplateBinding BorderBrush}"
        BorderThickness="{TemplateBinding BorderThickness}"
        SnapsToDevicePixels="True">
        <ContentPresenter
            Margin="{TemplateBinding Padding}"
            HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
            VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
            RecognizesAccessKey="True"
            SnapsToDevicePixels="{TemplateBinding SnapsToDevicePixels}"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="CardBorder"
                    Property="Background"
                    Value="#1B2A40"/>
            <Setter TargetName="CardBorder"
                    Property="BorderBrush"
                    Value="#65E4D4"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="CardBorder"
                    Property="Background"
                    Value="#1C3D43"/>
            <Setter TargetName="CardBorder"
                    Property="BorderBrush"
                    Value="#65E4D4"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="CardBorder"
                    Property="Opacity"
                    Value="0.55"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
'@)

        $card.Padding = '17'
        $card.Margin = '0,0,10,10'
        $card.HorizontalContentAlignment = 'Stretch'
        $card.VerticalContentAlignment = 'Stretch'
        $card.Cursor = [System.Windows.Input.Cursors]::Hand

Set-DeskOrgButtonStyle -Button $card `
    -NormalBackground $script:C.Panel `
    -NormalBorder $script:C.Border


        $body = New-Stack
        [void]$body.Children.Add(
            (New-Text $item.Icon 10 $item.Accent -Bold)
        )

        $title = New-Text $item.Title 16 $script:C.Text -Display -Wrap
        $title.Margin = '0,9,0,5'
        [void]$body.Children.Add($title)

        [void]$body.Children.Add(
            (New-Text $item.Desc 11 $script:C.Muted -Wrap)
        )

        $open = New-Text 'OPEN SECTION  >' 9 $item.Accent -Bold
        $open.Margin = '0,14,0,0'
        [void]$body.Children.Add($open)

        $card.Content = $body
        $pageName = $item.Page

        $card.Add_Click({
            Navigate-To $pageName
        }.GetNewClosure())

        $rowIndex = [math]::Floor($i / 2)
        $colIndex = $i % 2
        [System.Windows.Controls.Grid]::SetRow($card, [int]$rowIndex)
        [System.Windows.Controls.Grid]::SetColumn($card, [int]$colIndex)
        [void]$cardsGrid.Children.Add($card)
    }

    [void]$root.Children.Add($cardsGrid)

    $summary = Get-StatusSummary
    $statusCard = New-Card 'System overview' 'A quick look at the files DeskOrg uses.' $script:C.Blue

    foreach ($entry in @(
        @{ Name = 'Saved rules'; Value = $summary.Rules },
        @{ Name = 'Automation script'; Value = $summary.Automation },
        @{ Name = 'Activity log'; Value = $summary.Log }
    )) {
        $line = New-Object System.Windows.Controls.DockPanel
        $line.Margin = '0,4,0,4'

        $left = New-Text $entry.Name 12 $script:C.Muted
        [System.Windows.Controls.DockPanel]::SetDock(
            $left, [System.Windows.Controls.Dock]::Left
        )
        [void]$line.Children.Add($left)

        $right = New-Text $entry.Value 12 $script:C.Text -Bold
        $right.HorizontalAlignment = 'Right'
        [void]$line.Children.Add($right)

        [void]$statusCard.Body.Children.Add($line)
    }

    Add-PageCard $root $statusCard
    [void]$script:PageHost.Children.Add($root)
}

function Build-OrganizePage {
    $root = New-PageStack

    $intro = New-Card 'Desktop organization' 'Choose an action. Your existing organizer and rules remain in use.' $script:C.Teal

    Add-Action $intro `
        'Organize Now' `
        'Run the current DeskOrg organizer.' `
        { Invoke-Organizer } `
        $script:C.Teal -Primary

    Add-Action $intro `
        'Open desktop folder' `
        'Open the Windows Desktop folder.' `
        {
            try {
                $desktop = [Environment]::GetFolderPath('Desktop')
                if (-not (Test-Path -LiteralPath $desktop -PathType Container)) {
                    throw "Desktop folder not found: $desktop"
                }
                Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$desktop`""
                Set-Status 'Opened Desktop folder.'
            }
            catch {
                Show-Message $_.Exception.Message 'DeskOrg' ([System.Windows.MessageBoxImage]::Error)
            }
        } `
        $script:C.Teal

    Add-Action $intro `
        'Open DeskOrg application folder' `
        'Browse the launcher, scripts, logo, and rules.' `
        {
            try {
                Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$AppFolder`""
                Set-Status 'Opened DeskOrg application folder.'
            }
            catch {
                Show-Message $_.Exception.Message 'DeskOrg' ([System.Windows.MessageBoxImage]::Error)
            }
        } `
        $script:C.Teal

    Add-PageCard $root $intro

    $note = New-Card 'Before you organize' 'DeskOrg uses your saved rules to classify files. Protected extensions are handled by your organizer script.' $script:C.Amber
    [void]$root.Children.Add($note.Border)

    [void]$script:PageHost.Children.Add($root)
}

function Build-AutomationPage {
    $root = New-PageStack

    $card = New-Card 'Smart automation controls' 'Manage the background watcher and scheduled automation.' $script:C.Purple

    Add-Action $card `
        'Install / Enable automation' `
        'Enable automation using the existing management script.' `
        { Invoke-Automation 'Install' } `
        $script:C.Purple -Primary

    Add-Action $card `
        'View automation status' `
        'Inspect the current automation setup.' `
        { Invoke-Automation 'Status' } `
        $script:C.Purple

    Add-Action $card `
        'Disable automation' `
        'Disable automatic watching.' `
        { Invoke-Automation 'Disable' } `
        $script:C.Purple

    Add-Action $card `
        'Uninstall automation' `
        'Remove automation configuration through the management script.' `
        { Invoke-Automation 'Uninstall' } `
        $script:C.Purple

    Add-Action $card `
        'Configuration check' `
        'Run the automation configuration test.' `
        { Invoke-Automation 'Test' } `
        $script:C.Purple

    Add-PageCard $root $card
    [void]$script:PageHost.Children.Add($root)
}

function Build-SettingsPage {
    $root = New-PageStack

    $card = New-Card 'Rules & configuration' 'Change saved rules carefully. Keep a backup before making major edits.' $script:C.Amber

    Add-Action $card `
        'Edit saved rules' `
        'Open DeskOrgRules.json in Notepad.' `
        {
            if (-not (Test-Path -LiteralPath $RulesFile -PathType Leaf)) {
                Show-Message (
                    "Rules file not found:" +
                    [Environment]::NewLine +
                    $RulesFile
                ) 'DeskOrg' ([System.Windows.MessageBoxImage]::Warning)
                return
            }

            Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$RulesFile`""
            Set-Status 'Opened saved rules.'
        } `
        $script:C.Amber -Primary

    Add-Action $card `
        'Open application folder' `
        'View the DeskOrg scripts and configuration files.' `
        {
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$AppFolder`""
        } `
        $script:C.Amber

    Add-Action $card `
        'Refresh configuration status' `
        'Refresh the information shown on the home screen.' `
        {
            $summary = Get-StatusSummary
            Show-Message (
                "Saved rules: " + $summary.Rules +
                [Environment]::NewLine +
                "Automation: " + $summary.Automation +
                [Environment]::NewLine +
                "Activity log: " + $summary.Log
            ) 'DeskOrg Configuration'
            Set-Status 'Configuration status refreshed.'
        } `
        $script:C.Amber

    Add-PageCard $root $card
    [void]$script:PageHost.Children.Add($root)
}

function Build-ActivityPage {
    $root = New-PageStack

    $card = New-Card 'Activity & diagnostics' 'Open the existing log and check the supporting scripts.' $script:C.Blue

    Add-Action $card `
        'View DeskOrg log' `
        'Open the log file stored in the Windows temporary folder.' `
        {
            Open-FileSafely $LogFile 'DeskOrg log'
        } `
        $script:C.Blue -Primary

    Add-Action $card `
        'Check organizer file' `
        'Confirm that the organizer launcher is present.' `
        {
            if (Test-Path -LiteralPath $OrganizerFile -PathType Leaf) {
                Show-Message "Organizer launcher found.`n$OrganizerFile" 'DeskOrg'
            } else {
                Show-Message "Organizer launcher is missing.`n$OrganizerFile" 'DeskOrg' ([System.Windows.MessageBoxImage]::Warning)
            }
        } `
        $script:C.Blue

    Add-Action $card `
        'Check automation file' `
        'Confirm that the automation management script is present.' `
        {
            if (Test-Path -LiteralPath $AutomationFile -PathType Leaf) {
                Show-Message "Automation script found.`n$AutomationFile" 'DeskOrg'
            } else {
                Show-Message "Automation script is missing.`n$AutomationFile" 'DeskOrg' ([System.Windows.MessageBoxImage]::Warning)
            }
        } `
        $script:C.Blue

    Add-PageCard $root $card
    [void]$script:PageHost.Children.Add($root)
}

# ---------------- MAIN WINDOW ----------------

$Window = New-Object System.Windows.Window
$script:Window = $Window
$Window.Title = 'DeskOrg | Control Center'
$Window.Width = 1120
$Window.Height = 790
$Window.MinWidth = 850
$Window.MinHeight = 650
$Window.WindowStartupLocation = 'CenterScreen'
$Window.Background = $script:C.Background
$Window.Foreground = $script:C.Text
# Body/labels use Cambria; headings opt into Unbounded via New-Text -Display.
$Window.FontFamily = New-Object System.Windows.Media.FontFamily('Cambria')
$Window.UseLayoutRounding = $true

$main = New-Object System.Windows.Controls.Grid

$sidebarCol = New-Object System.Windows.Controls.ColumnDefinition
$sidebarCol.Width = '230'

$contentCol = New-Object System.Windows.Controls.ColumnDefinition
$contentCol.Width = New-Object System.Windows.GridLength(
    1, [System.Windows.GridUnitType]::Star
)

[void]$main.ColumnDefinitions.Add($sidebarCol)
[void]$main.ColumnDefinitions.Add($contentCol)

# ---------------- SIDEBAR ----------------

$sidebar = New-Object System.Windows.Controls.DockPanel
$sidebar.Background = $script:C.Sidebar
$sidebar.LastChildFill = $true
$sidebar.Margin = '0'
[System.Windows.Controls.Grid]::SetColumn($sidebar, 0)
[void]$main.Children.Add($sidebar)

$sideRoot = New-Stack
$sideRoot.Margin = '17,20,17,18'
[void]$sidebar.Children.Add($sideRoot)


$brandStack = New-Stack
$brandStack.Orientation = 'Horizontal'
$brandStack.VerticalAlignment = 'Center'
$brandStack.Margin = '5,4,5,27'

# Keep the logo at its existing sidebar position
if (Test-Path -LiteralPath $LogoFile -PathType Leaf) {
    try {
        $img = New-Object System.Windows.Controls.Image
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage

        $bmp.BeginInit()
        $bmp.UriSource = [System.Uri]::new($LogoFile)
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.EndInit()
        $bmp.Freeze()

        $img.Source = $bmp
        $img.Width = 48
        $img.Height = 48
        $img.HorizontalAlignment = 'Left'
        $img.VerticalAlignment = 'Center'
        $img.Margin = '0,0,10,0'

        [void]$brandStack.Children.Add($img)
    }
    catch {
        # Logo is optional.
    }
}

# Place DeskOrg beside the logo
$brandText = New-Stack
$brandText.VerticalAlignment = 'Center'

[void]$brandText.Children.Add(
    (New-Text 'DeskOrg' 24 $script:C.Teal -Display)
)

[void]$brandText.Children.Add(
    (New-Text 'DESKTOP WORKSPACE' 8 $script:C.Muted -Bold)
)

[void]$brandStack.Children.Add($brandText)
[void]$sideRoot.Children.Add($brandStack)


$navLabel = New-Text 'WORKSPACE' 9 '#71839D' -Bold
$navLabel.Margin = '7,0,0,9'
[void]$sideRoot.Children.Add($navLabel)

$navItems = @(
    @{ Key = 'Home';       Label = '01   Overview' },
    @{ Key = 'Organize';   Label = '02   Organize' },
    @{ Key = 'Automation'; Label = '03   Smart Automation' },
    @{ Key = 'Settings';   Label = '04   Rules and Settings' },
    @{ Key = 'Activity';   Label = '05   Activity and Logs' }
)

foreach ($item in $navItems) {

    $b = New-Object System.Windows.Controls.Button

    $b.Content = $item.Label
    $b.HorizontalContentAlignment = 'Left'
    $b.Padding = '12,12'
    $b.Margin = '0,0,0,6'
    $b.Background = $script:C.Sidebar
    $b.Foreground = $script:C.Muted
    $b.BorderBrush = $script:C.Sidebar
    $b.BorderThickness = '1'
    $b.FontSize = 12
    $b.Cursor = [System.Windows.Input.Cursors]::Hand

    Set-DeskOrgButtonStyle -Button $b `
        -NormalBackground $script:C.Sidebar `
        -NormalBorder $script:C.Sidebar

    $pageKey = $item.Key
    $b.Add_Click({
        Navigate-To $pageKey
    }.GetNewClosure())

    $script:NavButtons[$item.Key] = $b
    [void]$sideRoot.Children.Add($b)
}

$sideSpacer = New-Object System.Windows.Controls.Border
$sideSpacer.Height = 1
$sideSpacer.Background = $script:C.Border
$sideSpacer.Margin = '0,15,0,15'
[void]$sideRoot.Children.Add($sideSpacer)

# ---------------- SIDEBAR CREDITS ----------------

$sideBottom = New-Object System.Windows.Controls.Border
$sideBottom.Background = '#172A39'
$sideBottom.BorderBrush = '#28565A'
$sideBottom.BorderThickness = '1'
$sideBottom.CornerRadius = '10'
$sideBottom.Padding = '12'
$sideBottom.Margin = '0,5,0,0'

$creditPanel = New-Stack

$creditHeading = New-Text 'MADE FOR YOUR FLOW' 9 $script:C.Teal -Bold
$creditHeading.Margin = '0,0,0,7'
[void]$creditPanel.Children.Add($creditHeading)

$creditBrand = New-Text 'Designed & Developed by:' 10 $script:C.Muted
[void]$creditPanel.Children.Add($creditBrand)

$creditName = New-Text 'Nivesh Sahayak' 14 $script:C.Text -Bold
$creditName.Margin = '0,2,0,5'
[void]$creditPanel.Children.Add($creditName)

# Clickable website link with a native globe icon
$siteLink = New-Object System.Windows.Documents.Hyperlink

$globeIcon = New-Object System.Windows.Controls.TextBlock
$globeIcon.Text = '[WEB]'
$globeIcon.FontSize = 9
$globeIcon.FontWeight = 'Bold'
$globeIcon.Margin = '0,0,6,0'
$globeIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($script:C.Teal)

$siteText = New-Object System.Windows.Controls.TextBlock
$siteText.FontSize = 10
$siteText.Margin = '0,0,0,5'

[void]$siteLink.Inlines.Add(
    (New-Object System.Windows.Documents.Run('Visit niveshsahayak.in'))
)

$siteLink.NavigateUri = [Uri]'https://www.niveshsahayak.in/'
$siteLink.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($script:C.Teal)
$siteLink.TextDecorations = $null
$siteLink.ToolTip = 'Open the Nivesh Sahayak website'

$siteLink.Add_RequestNavigate({
    param($sender, $e)
    Start-Process -FilePath $e.Uri.AbsoluteUri
    $e.Handled = $true
})

[void]$siteText.Inlines.Add($siteLink)
[void]$creditPanel.Children.Add($siteText)

$phoneText = New-Text 'Contact: 8054009300' 10 $script:C.Muted
[void]$creditPanel.Children.Add($phoneText)

$sideBottom.Child = $creditPanel
[void]$sideRoot.Children.Add($sideBottom)

# ---------------- MAIN CONTENT ----------------

$content = New-Object System.Windows.Controls.DockPanel
$content.LastChildFill = $true
$content.Margin = '26,23,18,17'
[System.Windows.Controls.Grid]::SetColumn($content, 1)
[void]$main.Children.Add($content)

# Footer
$footer = New-Object System.Windows.Controls.DockPanel
$footer.Margin = '0,12,0,0'
[System.Windows.Controls.DockPanel]::SetDock(
    $footer, [System.Windows.Controls.Dock]::Bottom
)
[void]$content.Children.Add($footer)

$script:StatusLine = New-Text 'DeskOrg is ready.' 10 $script:C.Muted -Wrap
$script:StatusLine.VerticalAlignment = 'Center'
[void]$footer.Children.Add($script:StatusLine)

$exit = New-Object System.Windows.Controls.Button
$exit.Content = 'Exit'
$exit.Padding = '16,8'
$exit.Margin = '12,0,0,0'
$exit.Background = '#482433'
$exit.Foreground = '#FFDCE5'
$exit.BorderBrush = '#774054'
$exit.BorderThickness = '1'
$exit.Cursor = [System.Windows.Input.Cursors]::Hand

# Custom hover template for the Exit button
$exit.Template = [System.Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    TargetType="{x:Type Button}">
    <Border x:Name="ExitBorder"
            Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            SnapsToDevicePixels="True">
        <ContentPresenter
            Margin="{TemplateBinding Padding}"
            HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
            VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
            RecognizesAccessKey="True"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="ExitBorder"
                    Property="Background" Value="#653044"/>
            <Setter TargetName="ExitBorder"
                    Property="BorderBrush" Value="#FF899F"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="ExitBorder"
                    Property="Background" Value="#7A3049"/>
            <Setter TargetName="ExitBorder"
                    Property="BorderBrush" Value="#FF899F"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="ExitBorder"
                    Property="Opacity" Value="0.55"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
'@)

$exit.HorizontalAlignment = 'Right'
$exit.Add_Click({ $Window.Close() })

[System.Windows.Controls.DockPanel]::SetDock(
    $exit, [System.Windows.Controls.Dock]::Right
)
[void]$footer.Children.Add($exit)

$footerRule = New-Object System.Windows.Controls.Border
$footerRule.Height = 1
$footerRule.Background = $script:C.Border
$footerRule.Margin = '0,0,0,12'
[System.Windows.Controls.DockPanel]::SetDock(
    $footerRule, [System.Windows.Controls.Dock]::Bottom
)
[void]$content.Children.Add($footerRule)

# ---------------- HEADER ----------------

$header = New-Object System.Windows.Controls.DockPanel
$header.LastChildFill = $true
$header.Margin = '0,0,0,18'

[System.Windows.Controls.DockPanel]::SetDock(
    $header, [System.Windows.Controls.Dock]::Top
)
[void]$content.Children.Add($header)

# RIGHT SIDE: USER, DATE AND LIVE CLOCK
$userCard = New-Object System.Windows.Controls.Border
$userCard.Background = '#172A39'
$userCard.BorderBrush = '#28565A'
$userCard.BorderThickness = '1'
$userCard.CornerRadius = '10'
$userCard.Padding = '13,9'
$userCard.Margin = '15,0,22,0'
$userCard.VerticalAlignment = 'Top'
$userCard.MinWidth = 205

[System.Windows.Controls.DockPanel]::SetDock(
    $userCard, [System.Windows.Controls.Dock]::Right
)

$userPanel = New-Stack

$userGreeting = New-Text (
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
) 12 $script:C.Teal -Bold

$userDate = New-Text '' 10 $script:C.Muted
$userDate.Margin = '0,4,0,0'

$userClock = New-Text '' 15 $script:C.Text -Bold
$userClock.Margin = '0,3,0,0'

[void]$userPanel.Children.Add($userGreeting)
[void]$userPanel.Children.Add($userDate)
[void]$userPanel.Children.Add($userClock)

$userCard.Child = $userPanel
[void]$header.Children.Add($userCard)

# LEFT SIDE: KEEP THE EXISTING WELCOME TITLE AND SUBTITLE
$headerLeft = New-Stack
$headerLeft.VerticalAlignment = 'Top'

$script:PageTitle = New-Text 'Welcome back.' 28 $script:C.Text -Display
[void]$headerLeft.Children.Add($script:PageTitle)

$script:PageSubtitle = New-Text 'Your desktop. Your flow. Everything in its place.' 12 $script:C.Muted -Wrap
$script:PageSubtitle.Margin = '0,5,0,0'
[void]$headerLeft.Children.Add($script:PageSubtitle)

[void]$header.Children.Add($headerLeft)

# UPDATE THE DATE AND TIME EVERY SECOND
$script:HeaderClockTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:HeaderClockTimer.Interval = [TimeSpan]::FromSeconds(1)

$script:UpdateHeaderClock = {
    $now = Get-Date
    $userDate.Text = $now.ToString('dddd, dd MMM yyyy')
    $userClock.Text = $now.ToString('hh:mm:ss tt')
}

& $script:UpdateHeaderClock

$script:HeaderClockTimer.Add_Tick({
    & $script:UpdateHeaderClock
})

$script:HeaderClockTimer.Start()

$Window.Add_Closed({
    if ($script:HeaderClockTimer) {
        $script:HeaderClockTimer.Stop()
    }
})
# ---------------- PAGE HOST ----------------

# Create the container used by all DeskOrg pages.
$pageScroll = New-Object System.Windows.Controls.ScrollViewer
$pageScroll.VerticalScrollBarVisibility = 'Auto'
$pageScroll.HorizontalScrollBarVisibility = 'Disabled'
$pageScroll.Margin = '0'

# Navigate-To and all Build-*Page functions use this StackPanel.
$script:PageHost = New-Stack
$script:PageHost.Margin = '0'

# Allow the pages to scroll when the window is not tall enough.
$pageScroll.Content = $script:PageHost

# Add the page area after the header and footer.
# DockPanel fills the remaining space with its last child.
[void]$content.Children.Add($pageScroll)

# ---------------- START ----------------

# Attach the complete interface to the window.
$Window.Content = $main

# Build the home page.
Navigate-To 'Home'

# Display DeskOrg Control Center.
[void]$Window.ShowDialog()

# SIG # Begin signature block
# MIIcOAYJKoZIhvcNAQcCoIIcKTCCHCUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDA9ZNzSkku6Y+X
# z30nSBfbbO+hxRxZJQ41EcvmefjWa6CCFm4wggMwMIICGKADAgECAhBAfeExfrxD
# qU1Saw4d1EDgMA0GCSqGSIb3DQEBCwUAMDAxLjAsBgNVBAMMJURlc2tPcmcgQ29k
# ZSBTaWduaW5nIChOaXZlc2ggU2FoYXlhaykwHhcNMjYxMDMwMDEwMDQ5WhcNMzYx
# MDMwMDExMDQ5WjAwMS4wLAYDVQQDDCVEZXNrT3JnIENvZGUgU2lnbmluZyAoTml2
# ZXNoIFNhaGF5YWspMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvE4v
# prYvvRAEIy8X47cy3iL4T+uNLkWXpXJpVg5z+OXf38NcrB/5rjwDRUNNXIIFGA8X
# 4e1obz+avmLMbahaBPtKrSjRx47JkOrJh6Ysdh1YHuCsL2pb8BtqM7xXbDsw7/kF
# nalG+/VnSDfhjQIqv8wQfn2xSIfHcRL3+2s5hzG+ePZHrkTaOQlX1dlxPwBqocPL
# APq3zRvt/XgzzZ2yVbDiVouLfYQZRwhz4CIbbZch1E+DiL9wAlBBeoYzD4s3ZGhw
# STRQd1GVRX3DxR1wykL5BbO3FEw4czwSE7PXV0sgKpgLH5t+VUqdSCbpZX5EPgLk
# LPMLAm1Hmz+gjGapxQIDAQABo0YwRDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAww
# CgYIKwYBBQUHAwMwHQYDVR0OBBYEFPvlioepdVL8MeNd+np67jS/ZZjlMA0GCSqG
# SIb3DQEBCwUAA4IBAQAru4kY6BCVH9PznqvUtgxFSFpzTEXHfqUyIED/6mhDPI8a
# JTIAfeqreBNksH2sZ4+MaPattQcfoROiz31rqdCtTSGB4ytPqXArmjaR1QrAMWBN
# DpDhJPNArD30wXmrG8sKU8HSQSxoL5M8awibcWj1RmsoeMqbCoY7tt6t3F+AsWfW
# BkZpUZ1oqUq1ZzzelBA8AXtQCC4ZwqVnaPlOx5RwV7WNVvxzJ+o65fwxJiJXXy7N
# Dsh57QQuIlgidjPV8/aUp2KPA/X6EtwhIr9aSlBBxRQbf7HDLx4oZO88To3gFyFl
# dDOW0SoyetYTITBLNWiEY/Zcc71xTHoNJmW5k8P+MIIFjTCCBHWgAwIBAgIQDpsY
# jvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
# IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAw
# MDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57
# G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9o
# k3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFh
# mzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463J
# T17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFw
# q1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yh
# Tzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU
# 75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LV
# jHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJ
# bOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8Qg
# UWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IB
# OjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6
# mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/
# BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4
# oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBw
# oL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0
# E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtD
# IeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlU
# sLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFig
# DkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwY
# w02fc7cBqZ9Xql4o4rmUMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMiDDpJhjAN
# BgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2Vy
# dCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0MjM1OTU5
# WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNV
# BAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hB
# MjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtHgx
# 0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxCqvkbsDpz
# 4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qchUP+AbdJ
# gMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbDhAktVJMQ
# bzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pnYJU3Gmq6
# bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI2Wv82wnJ
# RfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS638ZxqU1
# 4lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZxst7VvwDD
# jAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17yVp2NL+cn
# T6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTnYCTKIsDq
# 1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4yUozZtqg
# PrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZMBIGA1Ud
# EwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ7MtOMB8G
# A1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjAT
# BgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYD
# VR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9
# bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0pn/N0IfF
# iBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN2n7Jd2E4
# /iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a+Z1jEMK/
# DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7pGdogP8HR
# trYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZruMvNYY2
# o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspIHBldNE2K
# 9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku/qjTY6hc
# 3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZZd/BdHLi
# Ru7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeukcyIPbAv
# jSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA6TD8dC3J
# E3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvFoW2jNrbM
# 1pD2T7m3XDCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MPj/mSGDUwDQYJKoZIhvcN
# AQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEw
# PwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2
# IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBaFw0zNzExMDQyMzU5NTla
# MGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UE
# AxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3BvbmRlciAy
# MDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2e6byyf7NSvjU
# m0xls/04xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH3KSl5YEYpMuFgGsA31N2
# D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnDdAElETC+bhSEvNLGbA8D
# twUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6XxhF4jJZ3iSAuf2Cros1cz
# RSmWRHqMv9AfGZvp8ygYElhudpQjtcPpwoOl6QrZJUyV3iINvN4cO05prGV0fkjG
# 426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEzwKPW++Wa+E2ujI91EZtu
# kGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oNHnjs5mekExYN96LV/mxU
# bCKJb8pBNY4r3uD7hEmk/M81XhVgwDA7aMzYC3LZBg9WY5BMmbSay5ecmtJuXaB/
# 0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXbJ2/yLVSov9p16UDTLtT0
# +aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKgEED/btwIvbfuXkNNhg8M
# tDg43c4tMZae9FvqMOt/9PvmAxF9TNIsIFB8G6yb36ZJZGUL8N/pL971DyLXcK6H
# M5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCCAZEwDAYDVR0TAQH/BAIw
# ADAdBgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIwHwYDVR0jBBgwFoAU729T
# SunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB/wQMMAoG
# CCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYYaHR0cDov
# L29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2FjZXJ0cy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2
# U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL2NybDMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5
# NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG
# /WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrfmawJgH59KECxa9Ji8sEi
# 2g10CBDaMiqsaxWyW5cwlT/6ZF5sFznazqVsoC85U9dqLOYqQwst+UQQoNlDHgKR
# La3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h+tNLuA+0Zzhn/Fo+FDYA
# HWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfDYf7YZ+oR9t3flbDwK+hg
# GMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9xoU4stD8aWsD7RkcmgVRs6vlIk3z
# PKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE9qEVQZtyRE42ox7oNgC/
# r+Y4bSlZ3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/+lnME8F5kPZTgiy2HLEH
# klpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywpEWFZ4QNg+9xS43tTuW9x
# 0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn2TOXajveJW1L3joiQSPs
# WRGxkbDDW15jERFE4LvjnGu2O9zD1nLJSMdlYZEikl4w2w+q4IN/R+TIe0H4ngCI
# 1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViXWHng0RgsmrX/EdYUo80r
# 3TfMlkD0/YMxggUgMIIFHAIBATBEMDAxLjAsBgNVBAMMJURlc2tPcmcgQ29kZSBT
# aWduaW5nIChOaXZlc2ggU2FoYXlhaykCEEB94TF+vEOpTVJrDh3UQOAwDQYJYIZI
# AWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0B
# CQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAv
# BgkqhkiG9w0BCQQxIgQgn066YQ92Ff2IfvAZmZK8x89wnEB4U/tJZxHJANg1sfEw
# DQYJKoZIhvcNAQEBBQAEggEAa0yfj12D61HbWjtAFSSgfPZL/ORJvoKWNNdbv6wU
# CdnxNEv8qDS3MMUnARGQC10hCmQ3W8tsAr3lij8ZwxSOuo2jKUtmXKvQ9nX1I1Qx
# PNldaMJJFXyA527YeRGE74aIo+MaqRDGBkkZydKfvx+hrTGRE4l1ByjQTjV1wXsQ
# IiGb8bcqi0L3LcnbqmwIhnIktjPCg4eU4gG7hGEJChqkiIgvf1/mf1vVoWjTcCdC
# Q/wbp+mJSQRCUJOCm15PsMUOUZFCFlmlcsi9kycVy6EW44ylnR2zvDtXfRowswHF
# Nh+3V6YKIfUFIqaratIsrLPaFbgm6WQ6d2Qt2PPjDbcxCaGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjEwMzAwMzE5MTdaMC8GCSqGSIb3DQEJBDEiBCDA/RZhUqin
# GockEyKysshV2wJcJAenQJb4EDQ6aWTnOTANBgkqhkiG9w0BAQEFAASCAgABgjYN
# unwEidX2iJhuzk6g0zgHqF2iecYiLtzo9zGtpZIxi+mobPAS42rnyDFc/WVTc68Q
# F1EgZMYMdspYtx7LwL3N5GBq/wTbk3IGmAMcm8tmy9XiVY5NsChX3/JSadQVoFqG
# TwWXV+zYvsKLX18CiVsvp2gjE9kKhwuuH5Y5H9KgFsDiT7Ammg3d2vD94y5OeT7L
# ZMhOGs1QMj52ad+QCdZ8hlc7xfUAC7Z+oqAhfKqpYQ5iL/1M6V/VPoEJlrtC2SQ+
# EnqCdCCKKe+lrgos2VZG+x1Uw8TonzWxOe+c+qCFV7OFrCZT3jYmxBI0kScQ7LF6
# UZEEvuctPs+s3lpAMnKtMNsDnlJvGoR/m8Y4C2WaTp6pTN9R90Mud3Tv2C7H5FhC
# cQxGt9b62Pe9PvUonzpkS5jc7h0CI54+97xig+5QhIZNUNzTPzqHR7EK0JVttP+e
# 2tF1oXSOjokZhDOqiqTjYKKqIMjrIHtiJ/qyKz0Q4k6NqXPcgWq0h7mcTnZZCpqJ
# 7tXdeSa8qffYHL1Eu+34v1VZ+sU2qR3vxYatg17CAoxoiY1xYiOrhw3iViEx20c5
# /SRloIO77J9S1ZTubwfaGDXREt77PoHaO/d590h4zRWcrBwHpmf1rFWr1eh8b+Xv
# bKnWN9bTBxU1d4UFg//ZwPzqbI2KpYAZOR+yMg==
# SIG # End signature block
