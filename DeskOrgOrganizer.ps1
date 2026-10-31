
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
if (-not (Test-Path -LiteralPath $RulesFile)) {
    try {
        if (-not (Test-Path -LiteralPath $DataFolder)) {
            New-Item -ItemType Directory -Path $DataFolder -Force | Out-Null
        }
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

function Get-DesktopPath {
    $key = $null
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        )
        if ($null -ne $key) {
            $value = $key.GetValue(
                'Desktop', $null,
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
        Write-DeskOrgLog "WARNING: Desktop registry lookup: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
    }

    $path = [Environment]::GetFolderPath('DesktopDirectory')
    if ($path -and (Test-Path -LiteralPath $path -PathType Container)) {
        return (Get-Item -LiteralPath $path).FullName
    }
    throw 'Could not locate the Windows Desktop folder.'
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
    }
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

        $map = @{}
        foreach ($property in $json.Extensions.PSObject.Properties) {
            $ext = ([string]$property.Name).ToLowerInvariant()
            $category = [string]$property.Value
            if ($ext -notmatch '^\.[a-z0-9_-]+$') {
                throw "Invalid extension: $ext"
            }
            if ([string]::IsNullOrWhiteSpace($category) -or
                $category -match '[\\/:*?"<>|]' -or
                $category -in @('.', '..') -or
                [IO.Path]::IsPathRooted($category)) {
                throw "Invalid folder name for $ext"
            }
            $map[$ext] = $category
        }

        $unknown = [string]$json.UnknownFileBehavior
        if ([string]::IsNullOrWhiteSpace($unknown)) { $unknown = 'Other Files' }
        if ($unknown -ne 'Leave' -and
            ($unknown -match '[\\/:*?"<>|]' -or $unknown -in @('.', '..') -or
             [IO.Path]::IsPathRooted($unknown))) {
            throw 'UnknownFileBehavior must be Leave or a folder name.'
        }

        return @{
            SourceFolder = [string]$json.SourceFolder
            UnknownFileBehavior = $unknown
            ProtectedExtensions = @(
                $json.ProtectedExtensions |
                    ForEach-Object { ([string]$_).ToLowerInvariant() }
            )
            Extensions = $map
        }
    }
    catch {
        Write-DeskOrgLog "INVALID RULES: $($_.Exception.Message)"
        Write-DeskOrgLog 'Using built-in default rules.'
        return $defaults
    }
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
    param([string]$Directory, [string]$FileName)

    $target = Join-Path $Directory $FileName
    if (-not (Test-Path -LiteralPath $target)) { return $target }

    $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [IO.Path]::GetExtension($FileName)
    $n = 1
    do {
        $target = Join-Path $Directory ("{0} ({1}){2}" -f $base, $n, $ext)
        $n++
    } while (Test-Path -LiteralPath $target)

    return $target
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

        $rules = Get-Rules
        if ($rules.SourceFolder -eq 'Desktop') {
            $source = Get-DesktopPath
        }
        else {
            $source = [Environment]::ExpandEnvironmentVariables($rules.SourceFolder)
            if (-not (Test-Path -LiteralPath $source -PathType Container)) {
                throw "Configured source folder does not exist: $source"
            }
            $source = (Get-Item -LiteralPath $source).FullName
        }

        Write-DeskOrgLog "Scan started. Source: $source"
        $moved = 0
        $skipped = 0
        $failed = 0

        # Only scan files directly in the source folder, never recursively.
        $files = @(Get-ChildItem -LiteralPath $source -File -Force)
        foreach ($file in $files) {
            try {
                if ($file.Name -in @(
                    'DeskOrg.bat','DeskOrgOrganizer.ps1',
                    'DeskOrgWatcher.ps1','DeskOrgAutomation.ps1',
                    'DeskOrgRules.json'
                )) {
                    $skipped++
                    continue
                }

                $ext = $file.Extension.ToLowerInvariant()
                if ($rules.ProtectedExtensions -contains $ext) {
                    $skipped++
                    continue
                }

                if ($rules.Extensions.ContainsKey($ext)) {
                    $category = $rules.Extensions[$ext]
                }
                elseif ($rules.UnknownFileBehavior -eq 'Leave') {
                    $skipped++
                    continue
                }
                else {
                    $category = $rules.UnknownFileBehavior
                }

                # Never move a file that is still changing or locked.
                if (-not (Test-StableFile -File $file)) {
                    Write-DeskOrgLog "DEFERRED: File changing or busy: $($file.FullName)"
                    $skipped++
                    continue
                }

                $destination = Join-Path $source $category
                if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                    New-Item -ItemType Directory -Path $destination -ErrorAction Stop |
                        Out-Null
                }

                $target = Get-UniqueDestination -Directory $destination -FileName $file.Name

                # File.Move does not overwrite an existing target.
                [System.IO.File]::Move($file.FullName, $target)
                Write-DeskOrgLog "MOVED: $($file.FullName) -> $target"
                $moved++
            }
            catch {
                Write-DeskOrgLog "ERROR: '$($file.FullName)': $($_.Exception.Message)"
                $failed++
            }
        }

        Write-DeskOrgLog "Scan finished. Moved=$moved Skipped=$skipped Failed=$failed"
    }
    finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

try {
    Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value (
        "`r`n==========================================`r`n" +
        "DeskOrg scan requested: $(Get-Date)`r`n" +
        'Credits: Nivesh Sahayak - https://niveshsahayak.in'
    )
    Invoke-DeskOrg
    exit 0
}
catch {
    try { Write-DeskOrgLog "FATAL ERROR: $($_.Exception.Message)" } catch {}
    Write-Error $_
    exit 1
}

# SIG # Begin signature block
# MIIcOAYJKoZIhvcNAQcCoIIcKTCCHCUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCALhBmilnn4coUZ
# EGGN/G/bCDCAo8TcaM1vY+oFiSSJe6CCFm4wggMwMIICGKADAgECAhBAfeExfrxD
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
# BgkqhkiG9w0BCQQxIgQgDj3gG+9Uz3fA2wpI/N4QL9HvQWG3bCb0iyPwHamzSSIw
# DQYJKoZIhvcNAQEBBQAEggEAS370pUQ/sCHpI5UF9NlIFGyzm4VHS7b4eP4ZjuvM
# 0Lfj7zry59WAlKNaPz7JIq8Yfj3D5h5m+PRAX4Rzu3CnGy5EuecGqpKXyYfGaw52
# fUTjKFPeOpgMzCAx2xSwbJATKiv/3/Kk5teOcKOB+C/HFtVo//g9ieBfBuoaT4ic
# 56UNfs+KuxPl1Fm17fk10vMzv6SCK7s18T8SbZNnEEBFRU0jFy6Ojrym5J71vMCA
# AndgvXrVy51dO0015EgH+kHt4DyeDNPrYjqfZUcu2q2+3AP2t7INZ6yqX08suGda
# N/ODra9kB2UYBB1uQp/uKAfxRd+9zpXuAWRPoyhFUMddV6GCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjEwMzAwMzE5MTdaMC8GCSqGSIb3DQEJBDEiBCB12oZgGTOx
# 9jD1DgXdgLaWNeC5WPdf9cX3miXqhAcbJTANBgkqhkiG9w0BAQEFAASCAgCLvIos
# JEs5LTn0t2E/9x/SenitY5xYZ4/xvAkHcXDgaFCTxPxNKgtBzMGlnjPFhezt7Klo
# yuKCIU1Pbi7DfOTFS16GEGYpoMeu5GGjWF4R9IMxBWBBDDRy1nwrOiN0F7ycFt8B
# Kh1sDnKn1CJuPg0VgZ2we7Z13cCU1jPwNwAEdPqerJSIkMezmrqbD2+TIlleySpr
# yztJGSOoPulsj0nDbDIZ8mIjS77hmbjcGvi552OAsSVJa0+oeJH1UQzpt1yby6+e
# 9f4/tWfssk60jFVnA+ryjEPNyYF67ViD5Re9LareG5qP0gTJoq8EJ3oZMsGD1taH
# pDTA/4K814UJcNDxqz3ttngQivBERrRx9y3VZv+yF5J1gBUsTmvO+0txUBu6/ATy
# 5v2YHUDALJ+EBsNgzpSJqI3/f9+5mwjYBQTy6LQk80EmpxcEZjaf6Gkb7jRH6vxV
# vTNz5cIjVOBR/NQRMBv3vr2Kv6N99weIa45lX6BgZS0WwuYiun/kf42ZGKquI121
# xanwy+U7n+lA6PNTKfQdr9ol/vEBIxZGF3z61Qgwcv9kDRBNzIt9Ng0iJuepHDBQ
# wUWkg+bYcmH6Ye/j7+EsDLgYFOW6bia3y5ZUAcos5pnvu6L1Djw6VovB4E7IfkQC
# rn15BKYXiWQovVEZNYGg9z2AKWWZuJP7H7IhqA==
# SIG # End signature block
