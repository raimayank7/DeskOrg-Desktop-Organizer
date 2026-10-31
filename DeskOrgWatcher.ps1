
# ==========================================================
# DeskOrg Smart Automation - Background Watcher
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
$Organizer = Join-Path $PSScriptRoot 'DeskOrgOrganizer.ps1'
$StopFile = Join-Path $env:TEMP 'DeskOrgWatcher.stop'
$Mutex = $null
$OwnsMutex = $false
$Watcher = $null
$Sources = @('DeskOrg.Created', 'DeskOrg.Changed', 'DeskOrg.Renamed')

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value (
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] WATCHER: $Message"
    )
}

function Get-SourceFolder {
    $source = 'Desktop'

    if (Test-Path -LiteralPath $RulesFile -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $RulesFile -Raw | ConvertFrom-Json
            if ($config.SourceFolder) { $source = [string]$config.SourceFolder }
        }
        catch {
            Write-Log 'Rules file could not be read. Watching the Desktop fallback.'
        }
    }

    if ($source -eq 'Desktop') {
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
        finally {
            if ($null -ne $key) { $key.Dispose() }
        }

        return [Environment]::GetFolderPath('DesktopDirectory')
    }

    $source = [Environment]::ExpandEnvironmentVariables($source)
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Configured watch folder does not exist: $source"
    }

    return (Get-Item -LiteralPath $source).FullName
}

function Invoke-Organizer {
    if (Test-Path -LiteralPath $StopFile) { return }

    Write-Log 'Starting organizer scan.'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -NoLogo -NoProfile -ExecutionPolicy AllSigned `
        -File $Organizer

    Write-Log "Organizer exit code: $LASTEXITCODE"
}

try {
    # A mutex prevents multiple watcher instances for this Windows user.
    $Mutex = New-Object System.Threading.Mutex(
        $false, 'Local\DeskOrgSmartWatcher'
    )
    try {
        $OwnsMutex = $Mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $OwnsMutex = $true
    }

    if (-not $OwnsMutex) {
        Write-Log 'Another watcher is already running; exiting.'
        exit 0
    }

    if (Test-Path -LiteralPath $StopFile) {
        Remove-Item -LiteralPath $StopFile -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $Organizer -PathType Leaf)) {
        throw "Organizer script not found: $Organizer"
    }

    $source = Get-SourceFolder
    Write-Log "Monitoring: $source"

    $Watcher = New-Object System.IO.FileSystemWatcher
    $Watcher.Path = $source
    $Watcher.Filter = '*'
    $Watcher.IncludeSubdirectories = $false
    $Watcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size, CreationTime'

    Register-ObjectEvent -InputObject $Watcher -EventName Created `
        -SourceIdentifier 'DeskOrg.Created' | Out-Null
    Register-ObjectEvent -InputObject $Watcher -EventName Changed `
        -SourceIdentifier 'DeskOrg.Changed' | Out-Null
    Register-ObjectEvent -InputObject $Watcher -EventName Renamed `
        -SourceIdentifier 'DeskOrg.Renamed' | Out-Null

    $Watcher.EnableRaisingEvents = $true

    # Run once when the watcher starts.
    Invoke-Organizer
    $nextScan = (Get-Date).AddMinutes(5)

    while (-not (Test-Path -LiteralPath $StopFile)) {
        # Short waits allow a disable request to be noticed promptly.
        $event = Wait-Event -Timeout 5

        if (Test-Path -LiteralPath $StopFile) { break }

        if ($null -ne $event) {
            if ($event.SourceIdentifier -in $Sources) {
                Remove-Event -EventIdentifier $event.EventIdentifier `
                    -ErrorAction SilentlyContinue

                # Debounce event bursts. The organizer then independently
                # checks that each file is stable and not locked.
                Start-Sleep -Seconds 8

                Get-Event |
                    Where-Object { $_.SourceIdentifier -in $Sources } |
                    Remove-Event -ErrorAction SilentlyContinue

                if (-not (Test-Path -LiteralPath $StopFile)) {
                    Invoke-Organizer
                }
            }
            else {
                Remove-Event -EventIdentifier $event.EventIdentifier `
                    -ErrorAction SilentlyContinue
            }
        }

        if ((Get-Date) -ge $nextScan) {
            if (-not (Test-Path -LiteralPath $StopFile)) {
                Write-Log 'Five-minute reconciliation scan.'
                Invoke-Organizer
            }
            $nextScan = (Get-Date).AddMinutes(5)
        }
    }

    Write-Log 'Stop requested. Watcher shutting down.'
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
}
finally {
    if ($null -ne $Watcher) {
        $Watcher.EnableRaisingEvents = $false
        $Watcher.Dispose()
    }

    foreach ($sourceId in $Sources) {
        Unregister-Event -SourceIdentifier $sourceId `
            -ErrorAction SilentlyContinue
        Get-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue |
            Remove-Event -ErrorAction SilentlyContinue
    }

    if ($OwnsMutex -and $null -ne $Mutex) {
        $Mutex.ReleaseMutex()
    }
    if ($null -ne $Mutex) { $Mutex.Dispose() }
}

# SIG # Begin signature block
# MIIcOAYJKoZIhvcNAQcCoIIcKTCCHCUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAJDTUrs7avvmY4
# /g/pKmwZ/InPso29cb5Ms0qJxBzUdqCCFm4wggMwMIICGKADAgECAhBAfeExfrxD
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
# BgkqhkiG9w0BCQQxIgQgP4esrP5+jSoWN7fcDXoUbtz8YbzI0SKRgXZeRGqWAKkw
# DQYJKoZIhvcNAQEBBQAEggEAvD4osM27Zo80b6Nst5rw6mK7DHHO4o76jY+k6SA6
# 9YDS+Ewy41mkeEDcA3NE6oliHdU/HuVsowgp52eIDvgtpbh1YzsUIMphfXRuqi69
# R8WJGkldbdzkWykzmd8nSKs1rz9vOxrz3zDLHqVMcU+6LQith3gMbBUoHNZ5N9Hb
# QDB3CbyLDDGoCHw5ISuarJf42IlDe28tFw1n3/mRsWIsEY2CIgVeMZwBdcDrFlZ4
# hvLV3crLYgdBgNZSGwV8ClBrQJWPW4wJRBoyO5DyqaQnzU4pOihVIV1X3/ZF4ydl
# kTd2IZpfvMIRoW8f0bkFf+dcoImNFDNyxtDHdQnzJZnQxKGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjEwMzAwMzE5MThaMC8GCSqGSIb3DQEJBDEiBCBc42FVDif3
# e4Vytyro8cEYmJSiip4wz5AR1kyYgioiWDANBgkqhkiG9w0BAQEFAASCAgCEpSZB
# bZSC/1xuFlLhNcACq8TmuteWFhHS9M3J1iZnUPxrMzOaX9ESJFVAj38O/n9Xzgbv
# RUtRK098qqdeuKLa+w48TxexIIwGU6VwDHq6Ky7SYBs6MEtzmu11+YwawQua0n3Q
# /+tCebAl9FlPlQ+gdAwFvqMzJ8sIkISK2pVSspnBA0kSFb62F4q29UxJ/jy/wUYD
# cNveCkZ9LTdJLWho/stLOpG1CCxBNcWPfzaDjTZKXN5u7b3MWbgJG0If2e8leVrp
# FplEGlqPMAm4SD9Ps/MqPpedxmU3MNVDas5CaEdWkd5Wt8ySAVfC5ZEEkxr/ssgi
# 9Ab5s7Z3xj7+uGorjbesTefFNrVZuDJQlsvokSAJKvbs3z/q0TAD1oL06+9eeBRY
# 3AY5cwrOwU0q1j1Q0ZVKSj6Ek0uLKvy1Hk3nNIw8r3H/gX7hD3ePcP72nhj5BStI
# qAd6yyY/IQemrdV2U3AY/IzdvIBGNL+86bMt8zLleiypMx2D8EE+zYcpiWPlVTJ+
# +yb2AFR7+qELk2u9l2eNJnsswgAYvL2+i5Un960xbNLiAVsff7Pg4qAzE5sTGqSo
# B4zEG4Oll26zeQKTMueqZ9ki6ku1salpJT8bOfJPkWWlfOajOepUm0XwrpC9LFIQ
# XDwOmB/vtyMEvLBI6Af5JWK+DfhMhhVBlj+oqA==
# SIG # End signature block
