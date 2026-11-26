Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Quote-NativeArgument([string]$Value) {
    $text = New-Object System.Text.StringBuilder
    [void]$text.Append([char]34)
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ([int]$character -eq 92) { $slashes++; continue }
        if ([int]$character -eq 34) {
            [void]$text.Append([char]92, [int]($slashes * 2 + 1))
            [void]$text.Append([char]34)
        } else {
            [void]$text.Append([char]92, [int]$slashes)
            [void]$text.Append($character)
        }
        $slashes = 0
    }
    [void]$text.Append([char]92, [int]($slashes * 2))
    [void]$text.Append([char]34)
    return $text.ToString()
}

function Test-DeviceEndpoint([string]$Value) {
    $match = [regex]::Match($Value, '^(?<address>\[[0-9a-fA-F:.%]+\]|[A-Za-z0-9][A-Za-z0-9.-]*):(?<port>[0-9]{1,5})$')
    if (-not $match.Success) { return $false }
    $portNumber = [int]$match.Groups['port'].Value
    return $portNumber -ge 1 -and $portNumber -le 65535
}

function Parse-AdbDevices([string]$Text) {
    foreach ($line in ($Text -split '\r?\n')) {
        $parts = @($line.Trim() -split '\s+')
        if ($parts.Count -lt 2 -or $parts[1] -notin @('device', 'offline', 'unauthorized')) { continue }
        $deviceModel = $parts[0]
        foreach ($part in $parts) {
            if ($part.StartsWith('model:')) { $deviceModel = $part.Substring(6).Replace('_', ' ') }
        }
        [pscustomobject]@{
            Serial = $parts[0]; State = $parts[1]; Model = $deviceModel
            Wireless = $parts[0].Contains(':') -or $parts[0].Contains('_adb-tls')
        }
    }
}

function Parse-AdbServices([string]$Text) {
    foreach ($line in ($Text -split '\r?\n')) {
        $match = [regex]::Match($line, '^\s*(\S+)\s+(_adb-tls-(connect|pairing)\._tcp\.?)\s+(\S+)\s*$')
        if ($match.Success -and (Test-DeviceEndpoint $match.Groups[4].Value)) {
            [pscustomobject]@{
                Name = $match.Groups[1].Value; Endpoint = $match.Groups[4].Value
                Pairing = $match.Groups[3].Value -eq 'pairing'
            }
        }
    }
}

function Test-PairingCode([string]$Code) { return $Code -cmatch '^[0-9]{6}$' }

function Invoke-Adb {
    param([string[]]$CommandArguments, [int]$Timeout = 12)
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $script:AdbExecutable
    $start.WorkingDirectory = Split-Path $script:AdbExecutable
    $start.Arguments = ($CommandArguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Timeout * 1000)) {
            $process.Kill()
            [void]$process.WaitForExit(2000)
            throw 'The tablet connection timed out. Check the cable, authorization or Wi-Fi and retry.'
        }
        $result = [pscustomobject]@{
            Output = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
            ExitCode = $process.ExitCode
        }
        return $result
    } finally { $process.Dispose() }
}

function Get-ConnectedDevices {
    $result = Invoke-Adb -CommandArguments @('devices', '-l')
    if ($result.ExitCode -ne 0) { throw 'Android device discovery failed. Run Diagnostics from the menu.' }
    return @(Parse-AdbDevices $result.Output)
}

function Select-Tablet {
    param([object[]]$Devices, [bool]$Wireless)
    $ready = @($Devices | Where-Object { $_.State -eq 'device' -and $_.Wireless -eq $Wireless })
    if ($ready.Count -eq 0) { return $null }
    if ($ready.Count -eq 1) { return $ready[0] }
    Write-Host 'Choose your tablet:'
    for ($index = 0; $index -lt $ready.Count; $index++) {
        Write-Host ('  {0}. {1}' -f ($index + 1), $ready[$index].Model)
    }
    $choice = Read-Host 'Tablet number'
    if ($choice -notmatch '^[0-9]+$' -or [int]$choice -lt 1 -or [int]$choice -gt $ready.Count) {
        throw 'Choose a valid tablet number and retry.'
    }
    return $ready[[int]$choice - 1]
}
