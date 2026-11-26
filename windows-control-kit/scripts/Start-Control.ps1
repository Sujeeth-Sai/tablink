#requires -Version 5.1
param([ValidateSet('Menu', 'USB', 'WiFi', 'Diagnostics')][string]$Mode = 'Menu')
. (Join-Path $PSScriptRoot 'Common.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This package runs on Windows.' }
$script:PackageRoot = Split-Path $PSScriptRoot
$script:AdbExecutable = Join-Path $script:PackageRoot 'runtime\adb.exe'
$script:ScrcpyExecutable = Join-Path $script:PackageRoot 'runtime\scrcpy.exe'
$script:StateRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TabLink-Windows-Control'
$script:EndpointFile = Join-Path $script:StateRoot 'last-wireless.txt'
if (-not (Test-Path $script:AdbExecutable) -or -not (Test-Path $script:ScrcpyExecutable)) {
    throw 'Runtime files are missing. Extract the complete ZIP and run Setup.cmd again.'
}

function Start-TabletControl($Device) {
    Write-Host ''
    Write-Host ('Connecting to {0}...' -f $Device.Model) -ForegroundColor Cyan
    Write-Host 'No screen mirroring is enabled.'
    Write-Host 'Click the small control window to use the tablet.'
    Write-Host 'Press LEFT ALT to release the cursor, then click your Windows app.'
    Write-Host 'Click the control window again to resume. Close it to disconnect.'
    $launchArguments = @('--serial', $Device.Serial, '--no-video', '--no-audio',
        '--keyboard=uhid', '--mouse=uhid', '--shortcut-mod=lalt',
        '--window-title', 'Tablet control - Left Alt returns to Windows', '--pause-on-exit=if-error')
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $script:ScrcpyExecutable
    $start.WorkingDirectory = Split-Path $script:ScrcpyExecutable
    $start.Arguments = ($launchArguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
    $start.UseShellExecute = $false
    $start.EnvironmentVariables['ADB'] = $script:AdbExecutable
    $start.EnvironmentVariables['SCRCPY_SERVER_PATH'] = Join-Path (Split-Path $script:ScrcpyExecutable) 'scrcpy-server'
    $process = [System.Diagnostics.Process]::Start($start)
    try {
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw 'Tablet control stopped with an error. Check the scrcpy console message and retry.' }
    } finally { $process.Dispose() }
}

function Connect-USB {
    $all = @(Get-ConnectedDevices)
    $tablet = Select-Tablet -Devices $all -Wireless $false
    if ($null -eq $tablet) {
        if (@($all | Where-Object { $_.State -eq 'unauthorized' }).Count -gt 0) {
            throw 'Unlock the tablet and approve its Allow USB debugging prompt, then retry.'
        }
        throw 'No authorized USB tablet found. Enable USB debugging, use a data cable, and check the OEM ADB driver if needed.'
    }
    Start-TabletControl $tablet
}

function Get-WirelessServices {
    $result = Invoke-Adb -CommandArguments @('mdns', 'services')
    return @(Parse-AdbServices $result.Output)
}

function Find-PairedWireless {
    $all = @(Get-ConnectedDevices)
    $ready = Select-Tablet -Devices $all -Wireless $true
    if ($null -ne $ready) { return $ready }
    $services = @(Get-WirelessServices | Where-Object { -not $_.Pairing })
    $endpoints = @($services | ForEach-Object { $_.Endpoint })
    if (Test-Path $script:EndpointFile) {
        $cached = ([string](Get-Content -LiteralPath $script:EndpointFile -Raw)).Trim()
        if (Test-DeviceEndpoint $cached) { $endpoints += $cached }
    }
    foreach ($endpoint in @($endpoints | Select-Object -Unique)) {
        try { $response = Invoke-Adb -CommandArguments @('connect', $endpoint) -Timeout 8 } catch { continue }
        if ($response.Output -match 'connected to' -and $response.Output -notmatch 'failed') {
            $all = @(Get-ConnectedDevices)
            $ready = @($all | Where-Object { $_.State -eq 'device' -and $_.Serial -eq $endpoint })
            if ($ready.Count -gt 0) {
                try {
                    [void](New-Item -ItemType Directory -Path $script:StateRoot -Force)
                    Set-Content -LiteralPath $script:EndpointFile -Value $endpoint -Encoding ASCII
                } catch { Write-Verbose 'Connected without saving a reconnect hint.' }
                return $ready[0]
            }
        }
    }
    return $null
}

function Connect-WiFi {
    Write-Host 'Looking for your paired tablet on Wi-Fi...' -ForegroundColor Cyan
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $tablet = Find-PairedWireless
        if ($null -ne $tablet) { Start-TabletControl $tablet; return }
        Start-Sleep -Milliseconds 700
    }
    Write-Host ''
    Write-Host 'First setup on this Windows PC:' -ForegroundColor Cyan
    Write-Host '  On the tablet, enable Developer options > Wireless debugging.'
    Write-Host '  Keep both devices on the same private Wi-Fi.'
    Write-Host '  Choose Pair device with pairing code on the tablet.'
    [void](Read-Host 'When that screen is open, press Enter here')
    $pairServices = @()
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        $pairServices = @(Get-WirelessServices | Where-Object { $_.Pairing })
        if ($pairServices.Count -gt 0) { break }
        Start-Sleep -Milliseconds 800
    }
    if ($pairServices.Count -eq 0) {
        throw 'Pairing discovery found no tablet. Keep its pairing-code screen open, allow adb on your trusted private network if Windows asks, and retry. Guest Wi-Fi may block discovery.'
    }
    if ($pairServices.Count -gt 1) {
        throw 'More than one tablet is advertising pairing. Close the pairing screen on the other tablets and retry.'
    }
    $pairCode = Read-Host 'Enter the six-digit code shown on the tablet'
    if (-not (Test-PairingCode $pairCode)) { throw 'The pairing code must contain exactly six digits.' }
    $result = Invoke-Adb -CommandArguments @('pair', $pairServices[0].Endpoint, $pairCode) -Timeout 20
    $pairCode = ''
    if ($result.ExitCode -ne 0 -or $result.Output -notmatch 'Successfully paired') {
        throw 'Android did not accept the code. Open a fresh pairing code and retry.'
    }
    Write-Host 'Paired. Connecting automatically...'
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $tablet = Find-PairedWireless
        if ($null -ne $tablet) { Start-TabletControl $tablet; return }
        Start-Sleep -Milliseconds 800
    }
    throw 'Pairing succeeded, but the tablet did not reconnect. Leave Wireless debugging on and run Connect WiFi again.'
}

function Show-Diagnostics {
    Write-Host 'Device authorization states:'
    (Invoke-Adb -CommandArguments @('devices', '-l')).Output | Write-Host
    Write-Host 'Wireless discovery:'
    (Invoke-Adb -CommandArguments @('mdns', 'services')).Output | Write-Host
    Write-Host 'For an empty device list, check the cable, USB debugging and the manufacturer ADB driver.'
}

try {
    if ($Mode -ne 'Menu') {
        switch ($Mode) {
            'USB' { Connect-USB }
            'WiFi' { Connect-WiFi }
            'Diagnostics' { Show-Diagnostics; [void](Read-Host 'Press Enter to close') }
        }
    } else {
        do {
            Write-Host "`nTablet Control for Windows" -ForegroundColor Cyan
            Write-Host '1  Connect USB'
            Write-Host '2  Connect WiFi'
            Write-Host '3  Diagnostics'
            Write-Host '0  Exit'
            $selection = Read-Host 'Choose'
            try {
                switch ($selection) {
                    '1' { Connect-USB }
                    '2' { Connect-WiFi }
                    '3' { Show-Diagnostics }
                    '0' { }
                    default { Write-Host 'Choose 1, 2, 3 or 0.' }
                }
            } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
        } while ($selection -ne '0')
    }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    [void](Read-Host 'Press Enter to close')
    exit 1
}
