param(
    [switch]$Preview,         # work out what would move, move nothing
    [switch]$Undo,            # put back files moved earlier (the last run, or -Run / -File)
    [switch]$Auto,            # started by the background watcher (pause, quiet hours, notification)
    [switch]$FindDuplicates,  # look for identical files; writes duplicates.json, changes nothing
    [string]$Run = '',        # with -Undo: the run record to undo (file name in the Runs folder)
    [string]$File = ''        # with -Undo and -Run: put back just this one file (its current path)
)

# ==========================================================
# DeskOrg - Dynamic Desktop Organizer
# Credits: Nivesh Sahayak
# https://niveshsahayak.in
# ==========================================================

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $env:TEMP 'DeskOrg.log'
# Editable rules live in a per-user folder so the app works from a read-only
# install location (e.g. C:\Program Files). Seed from the shipped default.
$DataFolder = Join-Path $env:LOCALAPPDATA 'DeskOrg'
$RulesFile  = Join-Path $DataFolder 'DeskOrgRules.json'
$RunsFolder = Join-Path $DataFolder 'Runs'
$PauseFile  = Join-Path $DataFolder 'paused.flag'
$PreviewFile = Join-Path $DataFolder 'preview.json'
$LastRunFile = Join-Path $DataFolder 'lastrun.json'
$ProgressFile = Join-Path $DataFolder 'progress.json'
$DupFile = Join-Path $DataFolder 'duplicates.json'
$SettingsFile = Join-Path $DataFolder 'settings.json'
if (-not (Test-Path -LiteralPath $DataFolder)) {
    try { New-Item -ItemType Directory -Path $DataFolder -Force | Out-Null } catch { }
}
if (-not (Test-Path -LiteralPath $RulesFile)) {
    try {
        $DefaultRules = Join-Path $PSScriptRoot 'DeskOrgRules.json'
        if (Test-Path -LiteralPath $DefaultRules) {
            Copy-Item -LiteralPath $DefaultRules -Destination $RulesFile -Force
        }
    } catch { }
}

function Write-DeskOrgLog {
    param([string]$Message)
    Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value (
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    )
}

function Set-Progress {
    # Lets the Control Center show "3 of 12" while a run is going.
    param([string]$Phase, [int]$Done, [int]$Total, [string]$Current = '')
    try {
        (@{ Phase = $Phase; Done = $Done; Total = $Total; Current = $Current } | ConvertTo-Json) |
            Set-Content -LiteralPath $ProgressFile -Encoding UTF8
    } catch { }
}

function Clear-Progress { Remove-Item -LiteralPath $ProgressFile -Force -ErrorAction SilentlyContinue }

function Get-KnownFolder {
    # Resolves 'Desktop' or 'Downloads' from the user's own Windows settings.
    param([string]$Name)
    $guid = @{ Desktop = 'Desktop'; Downloads = '{374DE290-123F-4565-9164-39C4925E467B}' }[$Name]
    $key = $null
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        )
        if ($null -ne $key) {
            $value = $key.GetValue(
                $guid, $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
            )
            if ($value) {
                $path = [Environment]::ExpandEnvironmentVariables([string]$value)
                if (Test-Path -LiteralPath $path -PathType Container) {
                    return (Get-Item -LiteralPath $path).FullName
                }
            }
        }
    }
    catch {
        Write-DeskOrgLog "WARNING: $Name registry lookup: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
    }

    if ($Name -eq 'Desktop') {
        $path = [Environment]::GetFolderPath('DesktopDirectory')
    }
    else {
        $path = Join-Path ([Environment]::GetFolderPath('UserProfile')) $Name
    }
    if ($path -and (Test-Path -LiteralPath $path -PathType Container)) {
        return (Get-Item -LiteralPath $path).FullName
    }
    return $null
}

function Resolve-SourcePath {
    param([string]$Setting)
    if ($Setting -in @('Desktop', 'Downloads')) {
        $p = Get-KnownFolder -Name $Setting
        if (-not $p) { throw "Could not locate the Windows $Setting folder." }
        return $p
    }
    $p = [Environment]::ExpandEnvironmentVariables($Setting)
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
        throw "Configured folder does not exist: $p"
    }
    return (Get-Item -LiteralPath $p).FullName
}

function Test-FolderName {
    param([string]$Name)
    return -not ([string]::IsNullOrWhiteSpace($Name) -or
        $Name -match '[\\/:*?"<>|]' -or
        $Name -in @('.', '..') -or
        [IO.Path]::IsPathRooted($Name))
}

function Get-Language {
    try {
        if (Test-Path -LiteralPath $SettingsFile) {
            $s = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
            if ($s.Language -in @('hi', 'pa')) { return [string]$s.Language }
        }
    } catch { }
    return 'en'
}

function Get-DefaultRules {
    $map = @{}
    $groups = @{
        'PDFs' = @('.pdf')
        'Documents' = @('.doc','.docx','.txt','.rtf','.odt')
        'Spreadsheets' = @('.xls','.xlsx','.xlsm','.xlsb','.csv','.ods')
        'Presentations' = @('.ppt','.pptx','.pptm','.odp')
        'Images' = @('.jpg','.jpeg','.png','.gif','.bmp','.webp','.tif','.tiff','.svg','.heic','.avif')
        'Videos' = @('.mp4','.mkv','.avi','.mov','.wmv','.webm','.mpeg','.mpg','.m4v')
        'Audio' = @('.mp3','.wav','.aac','.flac','.m4a','.ogg','.wma')
        'Archives' = @('.zip','.rar','.7z','.tar','.gz','.bz2')
    }
    foreach ($category in $groups.Keys) {
        foreach ($ext in $groups[$category]) { $map[$ext] = $category }
    }
    return @{
        SourceFolder = 'Desktop'
        UnknownFileBehavior = 'Other Files'
        ProtectedExtensions = @(
            '.lnk','.url','.exe','.com','.scr','.msi','.msp',
            '.bat','.cmd','.ps1','.vbs','.js','.wsf','.hta',
            '.reg','.dll','.sys','.ocx','.drv','.sed'
        )
        Extensions = $map
        SkipRecentMinutes = 1
        SkipFiles = @()
        DatedFolders = 'None'
        Duplicates = 'Rename'
        ExtraFolders = @()
        NameRules = @()
        SizeRules = @()
        OldFiles = @{ Enabled = $false; Days = 90; Folder = 'Old' }
        QuietHours = @{ Enabled = $false; From = '09:00'; To = '18:00' }
    }
}

function ConvertTo-ExtMap {
    param($Obj)
    $map = @{}
    foreach ($property in $Obj.PSObject.Properties) {
        $ext = ([string]$property.Name).ToLowerInvariant()
        $category = [string]$property.Value
        if ($ext -notmatch '^\.[a-z0-9_-]+$') { throw "Invalid extension: $ext" }
        if (-not (Test-FolderName $category)) { throw "Invalid folder name for $ext" }
        $map[$ext] = $category
    }
    return $map
}

function Get-Rules {
    $defaults = Get-DefaultRules
    if (-not (Test-Path -LiteralPath $RulesFile -PathType Leaf)) {
        Write-DeskOrgLog 'Rules file missing; using built-in defaults.'
        return $defaults
    }

    try {
        $json = Get-Content -LiteralPath $RulesFile -Raw | ConvertFrom-Json
        if (-not $json.SourceFolder -or -not $json.Extensions -or
            $null -eq $json.ProtectedExtensions) {
            throw 'Required properties are missing.'
        }

        $map = ConvertTo-ExtMap $json.Extensions

        $unknown = [string]$json.UnknownFileBehavior
        if ([string]::IsNullOrWhiteSpace($unknown)) { $unknown = 'Other Files' }
        if ($unknown -ne 'Leave' -and -not (Test-FolderName $unknown)) {
            throw 'UnknownFileBehavior must be Leave or a folder name.'
        }

        # Optional settings (older rule files do not have them).
        $recent = 1
        if ($null -ne $json.SkipRecentMinutes) {
            $recent = [int]$json.SkipRecentMinutes
            if ($recent -lt 0 -or $recent -gt 1440) { throw 'SkipRecentMinutes must be 0 to 1440.' }
        }
        $dated = 'None'
        if ($json.DatedFolders) {
            $dated = [string]$json.DatedFolders
            if ($dated -notin @('None', 'Month', 'Year')) { throw 'DatedFolders must be None, Month or Year.' }
        }
        $dup = 'Rename'
        if ($json.Duplicates) {
            $dup = [string]$json.Duplicates
            if ($dup -notin @('Rename', 'Skip')) { throw 'Duplicates must be Rename or Skip.' }
        }
        $skipFiles = @()
        if ($json.SkipFiles) { $skipFiles = @($json.SkipFiles | ForEach-Object { [string]$_ }) }

        $extra = @()
        if ($json.ExtraFolders) {
            foreach ($e in @($json.ExtraFolders)) {
                $p = [string]$e.Path
                if ([string]::IsNullOrWhiteSpace($p)) { throw 'An extra folder has no Path.' }
                $u = 'Leave'
                if ($e.UnknownFileBehavior) { $u = [string]$e.UnknownFileBehavior }
                if ($u -ne 'Leave' -and -not (Test-FolderName $u)) { throw "Invalid UnknownFileBehavior for $p" }
                $ed = $dated
                if ($e.DatedFolders) {
                    $ed = [string]$e.DatedFolders
                    if ($ed -notin @('None', 'Month', 'Year')) { throw "Invalid DatedFolders for $p" }
                }
                $edup = $dup
                if ($e.Duplicates) {
                    $edup = [string]$e.Duplicates
                    if ($edup -notin @('Rename', 'Skip')) { throw "Invalid Duplicates for $p" }
                }
                $emap = $null
                if ($e.Extensions) { $emap = ConvertTo-ExtMap $e.Extensions }
                $extra += @{ Path = $p; UnknownFileBehavior = $u; DatedFolders = $ed; Duplicates = $edup; Extensions = $emap }
            }
        }

        $nameRules = @()
        foreach ($n in @($json.NameRules)) {
            if (-not $n) { continue }
            $m = [string]$n.Match; $f = [string]$n.Folder
            if ([string]::IsNullOrWhiteSpace($m)) { throw 'A name rule has no pattern.' }
            if (-not (Test-FolderName $f)) { throw "Invalid folder name for name rule '$m'" }
            $nameRules += @{ Match = $m; Folder = $f }
        }

        $sizeRules = @()
        foreach ($s in @($json.SizeRules)) {
            if (-not $s) { continue }
            $mb = [double]$s.MinMB; $f = [string]$s.Folder
            if ($mb -le 0) { throw 'A size rule needs MinMB above 0.' }
            if (-not (Test-FolderName $f)) { throw "Invalid folder name for size rule ($mb MB)" }
            $types = @()
            if ($s.Extensions) { $types = @($s.Extensions | ForEach-Object { ([string]$_).ToLowerInvariant() }) }
            $sizeRules += @{ MinMB = $mb; Folder = $f; Extensions = $types }
        }
        $sizeRules = @($sizeRules | Sort-Object { $_.MinMB } -Descending)

        $old = @{ Enabled = $false; Days = 90; Folder = 'Old' }
        if ($json.OldFiles) {
            $old.Enabled = [bool]$json.OldFiles.Enabled
            if ($null -ne $json.OldFiles.Days) { $old.Days = [int]$json.OldFiles.Days }
            if ($json.OldFiles.Folder) { $old.Folder = [string]$json.OldFiles.Folder }
            if ($old.Days -lt 1 -or $old.Days -gt 3650) { throw 'OldFiles.Days must be 1 to 3650.' }
            if (-not (Test-FolderName $old.Folder)) { throw 'Invalid OldFiles.Folder.' }
        }

        $quiet = @{ Enabled = $false; From = '09:00'; To = '18:00' }
        if ($json.QuietHours) {
            $quiet.Enabled = [bool]$json.QuietHours.Enabled
            if ($json.QuietHours.From) { $quiet.From = [string]$json.QuietHours.From }
            if ($json.QuietHours.To) { $quiet.To = [string]$json.QuietHours.To }
            $tmp = [TimeSpan]::Zero
            if (-not [TimeSpan]::TryParse($quiet.From, [ref]$tmp) -or -not [TimeSpan]::TryParse($quiet.To, [ref]$tmp)) {
                throw 'QuietHours times must look like 09:00.'
            }
        }

        return @{
            SourceFolder = [string]$json.SourceFolder
            UnknownFileBehavior = $unknown
            ProtectedExtensions = @(
                $json.ProtectedExtensions |
                    ForEach-Object { ([string]$_).ToLowerInvariant() }
            )
            Extensions = $map
            SkipRecentMinutes = $recent
            SkipFiles = $skipFiles
            DatedFolders = $dated
            Duplicates = $dup
            ExtraFolders = $extra
            NameRules = $nameRules
            SizeRules = $sizeRules
            OldFiles = $old
            QuietHours = $quiet
        }
    }
    catch {
        Write-DeskOrgLog "INVALID RULES: $($_.Exception.Message)"
        Write-DeskOrgLog 'Using built-in default rules.'
        return $defaults
    }
}

function Test-QuietNow {
    param($Rules)
    if (-not $Rules.QuietHours.Enabled) { return $false }
    $from = [TimeSpan]::Parse($Rules.QuietHours.From)
    $to = [TimeSpan]::Parse($Rules.QuietHours.To)
    $now = (Get-Date).TimeOfDay
    if ($from -le $to) { return ($now -ge $from -and $now -lt $to) }
    return ($now -ge $from -or $now -lt $to)   # overnight, e.g. 22:00 to 06:00
}

function Test-StableFile {
    param([System.IO.FileInfo]$File)

    # Require identical length and last-write time across three observations.
    # This reduces the chance of moving a file while it is being copied/saved.
    try {
        $previous = Get-Item -LiteralPath $File.FullName -ErrorAction Stop
        for ($i = 0; $i -lt 2; $i++) {
            Start-Sleep -Seconds 2
            $current = Get-Item -LiteralPath $File.FullName -ErrorAction Stop
            if ($current.Length -ne $previous.Length -or
                $current.LastWriteTimeUtc -ne $previous.LastWriteTimeUtc) {
                return $false
            }
            $previous = $current
        }

        # Skip files currently held open with restrictive sharing.
        $stream = [System.IO.File]::Open(
            $File.FullName,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None
        )
        $stream.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

function Get-UniqueDestination {
    param([string]$Directory, [string]$FileName, $Planned)

    $target = Join-Path $Directory $FileName
    if (-not (Test-Path -LiteralPath $target) -and
        -not ($Planned -and $Planned.ContainsKey($target.ToLowerInvariant()))) { return $target }

    $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [IO.Path]::GetExtension($FileName)
    $n = 1
    do {
        $target = Join-Path $Directory ("{0} ({1}){2}" -f $base, $n, $ext)
        $n++
    } while ((Test-Path -LiteralPath $target) -or
             ($Planned -and $Planned.ContainsKey($target.ToLowerInvariant())))

    return $target
}

function Save-LastRun {
    param([hashtable]$Info)
    try {
        $Info.Time = (Get-Date).ToString('s')
        ($Info | ConvertTo-Json -Depth 4) |
            Set-Content -LiteralPath $LastRunFile -Encoding UTF8
    } catch { }
}

function Show-Toast {
    param([string]$Title, [string]$Text)
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $esc = { param($s) [System.Security.SecurityElement]::Escape($s) }
        $xml.LoadXml(
            "<toast><visual><binding template='ToastGeneric'><text>$(& $esc $Title)</text>" +
            "<text>$(& $esc $Text)</text></binding></visual></toast>")
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    }
    catch { Write-DeskOrgLog "Notification not shown: $($_.Exception.Message)" }
}

function Get-Plan {
    # Works out which files would move where, and why. Moves nothing.
    param($Rules, $Spec, [hashtable]$Planned, [bool]$CheckStable)

    $plan = @()
    $skipped = 0
    $now = Get-Date
    $internal = @(
        'DeskOrg.bat','DeskOrgOrganizer.ps1','DeskOrgWatcher.ps1',
        'DeskOrgAutomation.ps1','DeskOrgRules.json','desktop.ini','thumbs.db'
    )

    # Only scan files directly in the folder, never recursively.
    $files = @(Get-ChildItem -LiteralPath $Spec.Path -File -Force)
    $total = $files.Count
    $seen = 0
    foreach ($file in $files) {
        $seen++
        if ($CheckStable -and ($seen % 3 -eq 0 -or $total -le 12)) { Set-Progress 'Checking' $seen $total $file.Name }
        if ($file.Name -in $internal -or
            ($file.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System))) {
            $skipped++; continue
        }
        $name = $file.Name
        if (@($Rules.SkipFiles | Where-Object { $name -like $_ }).Count -gt 0) {
            $skipped++; continue
        }
        $ext = $file.Extension.ToLowerInvariant()
        if ($Rules.ProtectedExtensions -contains $ext) { $skipped++; continue }

        # Which folder does this file go to, and why? First match wins.
        $category = $null; $why = ''; $yearOnly = $false
        $ageDays = ($now - $file.LastWriteTime).TotalDays
        if ($Rules.OldFiles.Enabled -and $ageDays -ge $Rules.OldFiles.Days) {
            $category = $Rules.OldFiles.Folder
            $why = "Not touched for $([int]$Rules.OldFiles.Days)+ days"
            $yearOnly = $true
        }
        if (-not $category) {
            foreach ($nr in $Rules.NameRules) {
                if ($name -like $nr.Match) { $category = $nr.Folder; $why = "Name matches '$($nr.Match)'"; break }
            }
        }
        if (-not $category) {
            $mb = $file.Length / 1MB
            foreach ($sr in $Rules.SizeRules) {
                if ($mb -ge $sr.MinMB -and ($sr.Extensions.Count -eq 0 -or $sr.Extensions -contains $ext)) {
                    $category = $sr.Folder; $why = "Bigger than $($sr.MinMB) MB"; break
                }
            }
        }
        if (-not $category) {
            if ($Spec.Ext.ContainsKey($ext)) { $category = $Spec.Ext[$ext]; $why = "File type $ext" }
            elseif ($Spec.Unknown -eq 'Leave') { $skipped++; continue }
            else {
                $category = $Spec.Unknown
                $why = if ($ext) { "Type $ext has no rule" } else { 'File has no type' }
            }
        }

        if ($Rules.SkipRecentMinutes -gt 0 -and
            ($now - $file.LastWriteTime).TotalMinutes -lt $Rules.SkipRecentMinutes) {
            Write-DeskOrgLog "DEFERRED: Changed in the last $($Rules.SkipRecentMinutes) minute(s): $($file.FullName)"
            $skipped++; continue
        }

        if ($CheckStable -and -not (Test-StableFile -File $file)) {
            Write-DeskOrgLog "DEFERRED: File changing or busy: $($file.FullName)"
            $skipped++; continue
        }

        $folder = Join-Path $Spec.Path $category
        if ($yearOnly) { $folder = Join-Path $folder $file.LastWriteTime.ToString('yyyy') }
        elseif ($Spec.Dated -eq 'Month') { $folder = Join-Path $folder $file.LastWriteTime.ToString('yyyy-MM') }
        elseif ($Spec.Dated -eq 'Year') { $folder = Join-Path $folder $file.LastWriteTime.ToString('yyyy') }

        $plain = Join-Path $folder $name
        $exists = (Test-Path -LiteralPath $plain) -or $Planned.ContainsKey($plain.ToLowerInvariant())
        if ($exists -and $Spec.Dup -eq 'Skip') {
            Write-DeskOrgLog "SKIPPED (same name already there): $($file.FullName)"
            $skipped++; continue
        }

        $target = Get-UniqueDestination -Directory $folder -FileName $name -Planned $Planned
        $Planned[$target.ToLowerInvariant()] = $true
        $plan += [pscustomobject]@{
            From = $file.FullName; To = $target; Folder = $folder
            Renamed = ($target -ne $plain); Why = $why
        }
    }
    return @{ Plan = $plan; Skipped = $skipped }
}

function Invoke-DeskOrg {
    # A named mutex prevents overlapping scans by the watcher and manual run.
    $mutex = New-Object System.Threading.Mutex($false, 'Local\DeskOrgOrganizer')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $locked = $true }

        if (-not $locked) {
            Write-DeskOrgLog 'Scan skipped: another DeskOrg scan is already running.'
            return
        }

        if ($Auto -and (Test-Path -LiteralPath $PauseFile)) {
            Write-DeskOrgLog 'Scan skipped: DeskOrg is paused.'
            return
        }

        $rules = Get-Rules
        if ($Auto -and (Test-QuietNow $rules)) {
            Write-DeskOrgLog 'Scan skipped: quiet hours.'
            return
        }

        # Folders to look at: the main one, then any extra folders.
        $folders = @()
        $folders += @{
            Path = (Resolve-SourcePath $rules.SourceFolder); Unknown = $rules.UnknownFileBehavior
            Dated = $rules.DatedFolders; Dup = $rules.Duplicates; Ext = $rules.Extensions
        }
        foreach ($e in $rules.ExtraFolders) {
            try {
                $p = Resolve-SourcePath $e.Path
                if (-not ($folders | Where-Object { $_.Path -eq $p })) {
                    $ext = if ($e.Extensions) { $e.Extensions } else { $rules.Extensions }
                    $folders += @{
                        Path = $p; Unknown = $e.UnknownFileBehavior
                        Dated = $e.DatedFolders; Dup = $e.Duplicates; Ext = $ext
                    }
                }
            }
            catch { Write-DeskOrgLog "WARNING: Extra folder skipped: $($_.Exception.Message)" }
        }

        $mode = if ($Preview) { 'Preview' } else { 'Scan' }
        Write-DeskOrgLog "$mode started. Folders: $(($folders | ForEach-Object { $_.Path }) -join '; ')"

        $planned = @{}
        $all = @()
        $skipped = 0
        foreach ($f in $folders) {
            $r = Get-Plan -Rules $rules -Spec $f -Planned $planned -CheckStable (-not $Preview)
            $all += $r.Plan
            $skipped += $r.Skipped
        }

        if ($Preview) {
            $items = @($all | ForEach-Object {
                @{ From = $_.From; To = $_.To; Renamed = $_.Renamed; Why = $_.Why }
            })
            (@{ Time = (Get-Date).ToString('s'); Skipped = $skipped; Items = $items } |
                ConvertTo-Json -Depth 4) |
                Set-Content -LiteralPath $PreviewFile -Encoding UTF8
            Write-DeskOrgLog "Preview finished. WouldMove=$($all.Count) Skipped=$skipped"
            Write-Host "Preview: $($all.Count) file(s) would move, $skipped left alone."
            foreach ($i in $all) { Write-Host "  $($i.From)  ->  $($i.To)   [$($i.Why)]" }
            return
        }

        $moves = @()
        $failed = 0
        $created = @()
        $done = 0
        foreach ($i in $all) {
            $done++
            Set-Progress 'Moving' $done $all.Count ([IO.Path]::GetFileName($i.From))
            try {
                # Re-check just before moving: the file may have gone or the name been taken.
                if (-not (Test-Path -LiteralPath $i.From -PathType Leaf)) { continue }
                if (-not (Test-Path -LiteralPath $i.Folder -PathType Container)) {
                    # Remember every folder we have to create (category and dated sub-folder).
                    $walk = $i.Folder
                    while ($walk -and -not (Test-Path -LiteralPath $walk -PathType Container)) {
                        if ($created -notcontains $walk) { $created += $walk }
                        $walk = Split-Path -Parent $walk
                    }
                    New-Item -ItemType Directory -Path $i.Folder -Force -ErrorAction Stop | Out-Null
                }
                $target = $i.To
                if (Test-Path -LiteralPath $target) {
                    $target = Get-UniqueDestination -Directory $i.Folder -FileName ([IO.Path]::GetFileName($i.From)) -Planned $null
                }
                # File.Move does not overwrite an existing target.
                [System.IO.File]::Move($i.From, $target)
                Write-DeskOrgLog "MOVED: $($i.From) -> $target"
                $moves += @{ From = $i.From; To = $target; Why = $i.Why }
            }
            catch {
                Write-DeskOrgLog "ERROR: '$($i.From)': $($_.Exception.Message)"
                $failed++
            }
        }
        Clear-Progress

        # Keep a record of this run so it can be undone.
        if ($moves.Count -gt 0) {
            if (-not (Test-Path -LiteralPath $RunsFolder)) {
                New-Item -ItemType Directory -Path $RunsFolder -Force | Out-Null
            }
            $runFile = Join-Path $RunsFolder ('run-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
            (@{ Time = (Get-Date).ToString('s'); Auto = [bool]$Auto; Created = $created; Moves = $moves } |
                ConvertTo-Json -Depth 5) |
                Set-Content -LiteralPath $runFile -Encoding UTF8
            # Keep the newest 60 records.
            Get-ChildItem -LiteralPath $RunsFolder -Filter 'run-*.json' |
                Sort-Object Name -Descending | Select-Object -Skip 60 |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }

        Write-DeskOrgLog "Scan finished. Moved=$($moves.Count) Skipped=$skipped Failed=$failed"
        Save-LastRun @{ Action = 'organize'; Moved = $moves.Count; Skipped = $skipped; Failed = $failed }
        if ($Auto -and $moves.Count -gt 0) {
            $msg = switch (Get-Language) {
                'hi' { "{0} फ़ाइलें व्यवस्थित की गईं। पूर्ववत करने के लिए DeskOrg खोलें।" }
                'pa' { "{0} ਫ਼ਾਈਲਾਂ ਸੰਭਾਲੀਆਂ ਗਈਆਂ। ਵਾਪਸ ਕਰਨ ਲਈ DeskOrg ਖੋਲ੍ਹੋ।" }
                default { "{0} file(s) tidied. Open DeskOrg to undo." }
            }
            Show-Toast 'DeskOrg' ($msg -f $moves.Count)
        }
    }
    finally {
        Clear-Progress
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Invoke-Undo {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\DeskOrgOrganizer')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'A scan is running right now. Try again in a moment.' }

        $run = $null
        if ($Run) {
            $candidate = Join-Path $RunsFolder ([IO.Path]::GetFileName($Run))
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $run = Get-Item -LiteralPath $candidate }
        }
        elseif (Test-Path -LiteralPath $RunsFolder) {
            $run = Get-ChildItem -LiteralPath $RunsFolder -Filter 'run-*.json' |
                Where-Object { $_.Name -notlike '*.undone.json' } |
                Sort-Object Name -Descending | Select-Object -First 1
        }
        if (-not $run -or $run.Name -like '*.undone.json') {
            Write-Host 'There is nothing to undo.'
            Write-DeskOrgLog 'Undo: nothing to undo.'
            Save-LastRun @{ Action = 'undo'; Restored = 0; Missing = 0; Failed = 0; Nothing = $true }
            return
        }

        $data = Get-Content -LiteralPath $run.FullName -Raw | ConvertFrom-Json
        $all = @($data.Moves)
        $todo = if ($File) { @($all | Where-Object { $_.To -eq $File }) } else { $all }
        $restored = 0; $missing = 0; $failed = 0
        $handled = @()
        foreach ($m in $todo) {
            try {
                if (-not (Test-Path -LiteralPath $m.To -PathType Leaf)) { $missing++; $handled += $m.To; continue }
                $dir = Split-Path -Parent $m.From
                if (-not (Test-Path -LiteralPath $dir -PathType Container)) { $missing++; continue }
                $back = $m.From
                if (Test-Path -LiteralPath $back) {
                    $back = Get-UniqueDestination -Directory $dir -FileName ([IO.Path]::GetFileName($m.From)) -Planned $null
                }
                [System.IO.File]::Move($m.To, $back)
                Write-DeskOrgLog "UNDONE: $($m.To) -> $back"
                $restored++
                $handled += $m.To
            }
            catch {
                Write-DeskOrgLog "UNDO ERROR: '$($m.To)': $($_.Exception.Message)"
                $failed++
            }
        }

        # Remove folders this run created, only if they are now empty.
        foreach ($c in @($data.Created) | Sort-Object { $_.Length } -Descending) {
            try {
                if ($c -and (Test-Path -LiteralPath $c -PathType Container) -and
                    -not (Get-ChildItem -LiteralPath $c -Force)) {
                    Remove-Item -LiteralPath $c -Force
                }
            } catch { }
        }

        if ($File) {
            # One file put back: take it out of the record; the run is "undone" when none is left.
            $left = @($all | Where-Object { $_.To -notin $handled })
            if ($left.Count -eq 0) {
                Rename-Item -LiteralPath $run.FullName -NewName ($run.BaseName + '.undone.json') -Force
            }
            else {
                (@{ Time = $data.Time; Auto = $data.Auto; Created = @($data.Created); Moves = $left } |
                    ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $run.FullName -Encoding UTF8
            }
        }
        else {
            # Mark the record as used so the next undo goes one run further back.
            Rename-Item -LiteralPath $run.FullName -NewName ($run.BaseName + '.undone.json') -Force
        }
        Write-DeskOrgLog "Undo finished. Restored=$restored Missing=$missing Failed=$failed"
        Write-Host "Undo: $restored file(s) put back, $missing could not be found, $failed failed."
        Save-LastRun @{ Action = 'undo'; Restored = $restored; Missing = $missing; Failed = $failed }
    }
    finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Invoke-FindDuplicates {
    # Groups identical files (same size, then same SHA-256). Changes nothing.
    $rules = Get-Rules
    $roots = @(Resolve-SourcePath $rules.SourceFolder)
    foreach ($e in $rules.ExtraFolders) {
        try { $roots += (Resolve-SourcePath $e.Path) } catch { }
    }
    $roots = @($roots | Select-Object -Unique)
    Write-DeskOrgLog "Duplicate search started: $($roots -join '; ')"

    $files = @()
    foreach ($r in $roots) {
        $files += @(Get-ChildItem -LiteralPath $r -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 0 -and
                -not ($_.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)) })
        if ($files.Count -gt 50000) { break }
    }
    $bySize = $files | Group-Object Length | Where-Object { $_.Count -gt 1 }
    $candidates = @($bySize | ForEach-Object { $_.Group })
    $groups = @()
    $n = 0
    $hashes = @{}
    foreach ($f in $candidates) {
        $n++
        if ($n % 5 -eq 0) { Set-Progress 'Comparing' $n $candidates.Count $f.Name }
        try {
            $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $key = "$($f.Length)|$h"
            if (-not $hashes.ContainsKey($key)) { $hashes[$key] = @() }
            $hashes[$key] += $f
        } catch { }
    }
    foreach ($key in $hashes.Keys) {
        $g = @($hashes[$key])
        if ($g.Count -gt 1) {
            $groups += @{
                Size = $g[0].Length
                Files = @($g | Sort-Object LastWriteTime | ForEach-Object {
                    @{ Path = $_.FullName; Modified = $_.LastWriteTime.ToString('s') }
                })
            }
        }
    }
    $groups = @($groups | Sort-Object { $_.Size * ($_.Files.Count - 1) } -Descending)
    (@{ Time = (Get-Date).ToString('s'); Scanned = $files.Count; Groups = $groups } |
        ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $DupFile -Encoding UTF8
    Clear-Progress
    Write-DeskOrgLog "Duplicate search finished. Files=$($files.Count) Groups=$($groups.Count)"
    Write-Host "Found $($groups.Count) group(s) of identical files among $($files.Count) file(s)."
}

try {
    Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value (
        "`r`n==========================================`r`n" +
        "DeskOrg run requested: $(Get-Date)`r`n" +
        'Designed & Developed by: Nivesh Sahayak - https://www.niveshsahayak.in'
    )
    if ($FindDuplicates) { Invoke-FindDuplicates }
    elseif ($Undo) { Invoke-Undo }
    else { Invoke-DeskOrg }
    exit 0
}
catch {
    try { Write-DeskOrgLog "FATAL ERROR: $($_.Exception.Message)" } catch {}
    try { Save-LastRun @{ Action = 'error'; Error = $_.Exception.Message } } catch {}
    try { Clear-Progress } catch {}
    Write-Error $_
    exit 1
}


# SIG # Begin signature block
# MIIcOAYJKoZIhvcNAQcCoIIcKTCCHCUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAMQcStt1KrURI6
# +3AnEV9jXfej4w2FFlfG6zMZPOT2HaCCFm4wggMwMIICGKADAgECAhBAfeExfrxD
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
# BgkqhkiG9w0BCQQxIgQg8ltnSR9dhO3hZPrY6D9/gGfEeACpqAojCYYANEGMecQw
# DQYJKoZIhvcNAQEBBQAEggEAViwMvyWuocx6gD39uFiRIFseQlxDknYxEkM0pm8r
# Y4A3mhobINtjOyTAtjk9OafIwHqFhgwD0aLTSCLCFGHkoJDz1Rxx5HjnRF2Rge2P
# 3bm4cnIl1+DRJOtV8BODmKlX2cfuNCwVyTLXLeMivIh+GCAulIXLDk1n7ZbNAQHJ
# nzDDP7DxUaT85or6Zw/EHoaRR3QjoJtVVG2M79uN6l4ODI8Fy8koVy9AUT58BDuq
# SdKaw/70e2XJ7J/OWQGE1TcxFoW1aaQTK0gyoWaZz6KQaiNJH0QdFgX44DFPhRG2
# w5LJ8e4/TC3Gnqvou5qgGJ9R16UnqAOFVh2cUELx83mpeqGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjExMTMwMjM4MDRaMC8GCSqGSIb3DQEJBDEiBCCQN2EljjyB
# gXWrSIrb/HcmBNuV1VmbjhrZYj1o4ilCQDANBgkqhkiG9w0BAQEFAASCAgBkZO9v
# sI/jVQUVV43AWV3Cwgp49iPWK/0389z3wBlC/t9EQThnt7S1vXVt5/xZqbvWtSvg
# fHDQsPmgMIp3JqZNzWa0C+BxyLd61VT7PdBHqDvPHoZPXMP2HkRl7drIXtAs9BqT
# MWd81em//5tR309jgSUaozhkegby6L8r5tbP97Gvt4aQEVv5M5f/8N6433l2nae/
# 8vN3qruZxFy7pYnU4+sgaDZl46h03TRjftjU+mH/Mo89isYJclmh3ArMb5hrUYNJ
# U7kJ0AChvKM25bPq79+24aiVMvZky6b1HdKeY3690m/DDVXVNpK5dOVOuPpZ/ela
# nOfFEvBVA+5l43pmsNlHcN48nCWq8GW6jSRreycnfgksoPV6uoLNRtbDElWG3dtK
# x91nbAkodUq8Q07WKOUuiBexTwG/XJiIhlNoJ6v9y8dBMKh1OgB/2jJ2UPHkryTX
# 9P6BScUjMnYrjcwkGKKDT9Wc1o4IdGWAZGKvk8kNS8ooKbfE5TEIM4ntYEapGCQH
# EMNUKCjhCBGxhHtNAlN1a+o1+sqbPI9ncAhZ+RNprJ4+CoKXftsCGVheA9llOD+p
# U88HcFhr9nr0yuk+qI7a0w/I8WIS+EVVHrnqoVrouW+A7sAGf/7KCpiUUYx93YEu
# Xyy4S4NQtNnE91pVumEJkBcSiSAwZ02o7+NTLw==
# SIG # End signature block
