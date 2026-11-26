param([string]$PackageRoot = (Split-Path $PSScriptRoot), [string]$FakeAdb = '')
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
function Check([bool]$Condition, [string]$Message) {
    $script:Assertions++
    if (-not $Condition) { throw $Message }
}
foreach ($file in Get-ChildItem -LiteralPath $PackageRoot -Filter '*.ps1' -Recurse) {
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    Check ($parseErrors.Count -eq 0) ('Parser errors in ' + $file.Name + ': ' + ($parseErrors | Out-String))
}
. (Join-Path $PackageRoot 'scripts/Common.ps1')
$deviceText = "List of devices attached`nABC device usb:1 model:Lenovo_Tab_M9 transport_id:1`n192.168.1.2:4567 offline transport_id:2`nDEF unauthorized usb:2`n* daemon started successfully"
$devices = @(Parse-AdbDevices $deviceText)
Check ($devices.Count -eq 3) 'Device parser count'
Check ($devices[0].Model -eq 'Lenovo Tab M9') 'Model decoding'
Check (-not $devices[0].Wireless) 'USB transport'
Check ($devices[1].Wireless) 'Wireless transport'
Check ($devices[2].State -eq 'unauthorized') 'Authorization state'
Check (@(Parse-AdbDevices 'List of devices attached').Count -eq 0) 'Empty device list'
foreach ($endpoint in @('192.168.1.2:4567','tablet.local:65535','[fe80::1%12]:12345')) {
    Check (Test-DeviceEndpoint $endpoint) ('Valid endpoint: ' + $endpoint)
}
foreach ($endpoint in @('','host','host:0','host:65536','-bad:1234','x;evil:1234',"host`n:1234")) {
    Check (-not (Test-DeviceEndpoint $endpoint)) ('Invalid endpoint: ' + $endpoint)
}
$services = @(Parse-AdbServices "List of discovered mdns services`nadb-ABC _adb-tls-connect._tcp 192.168.1.2:4567`nadb-PAIR _adb-tls-pairing._tcp. [fe80::1%12]:12345`nother _http._tcp x:80`nbad _adb-tls-connect._tcp x:0")
Check ($services.Count -eq 2) 'Service parser count'
Check (-not $services[0].Pairing) 'Connect service'
Check ($services[1].Pairing) 'Pairing service'
Check (Test-PairingCode '012345') 'Leading zero pairing code'
Check (-not (Test-PairingCode '12345')) 'Short pairing code rejected'
Check (-not (Test-PairingCode '12345x')) 'Non-digit pairing code rejected'
foreach ($vector in (Get-Content -LiteralPath (Join-Path $PackageRoot 'tests/quote-vectors.json') -Raw | ConvertFrom-Json)) {
    Check ((Quote-NativeArgument $vector.value) -ceq $vector.expected) ('Native argument quoting failed for: ' + $vector.value)
}
$launcher = Get-Content -LiteralPath (Join-Path $PackageRoot 'scripts/Start-Control.ps1') -Raw
foreach ($flag in @('--no-video','--no-audio','--keyboard=uhid','--mouse=uhid','--shortcut-mod=lalt')) {
    Check ($launcher.Contains($flag)) ('Missing control-only flag: ' + $flag)
}
Check (-not $launcher.Contains('--tcpip')) 'Do not enable unauthenticated tcpip mode'
if ($FakeAdb -ne '') {
    $script:AdbExecutable = $FakeAdb
    $result = Invoke-Adb -CommandArguments @('roundtrip','two words','a"b','C:\tail\') -Timeout 5
    $parsed = $result.Output | ConvertFrom-Json
    Check ($result.ExitCode -eq 0) 'Native process exit status'
    Check ($parsed[1] -ceq 'two words') 'Native argv spaces'
    Check ($parsed[2] -ceq 'a"b') 'Native argv quotes'
    Check ($parsed[3] -ceq 'C:\tail\') 'Native argv trailing slash'
    $result = Invoke-Adb -CommandArguments @('fail')
    Check ($result.ExitCode -eq 7) 'Native nonzero exit status preserved'
    $result = Invoke-Adb -CommandArguments @('large') -Timeout 5
    Check ($result.Output.Length -gt 500000) 'Both process pipes drained without deadlock'
    $timedOut = $false
    try { $null = Invoke-Adb -CommandArguments @('slow') -Timeout 1 } catch { $timedOut = $_.Exception.Message.Contains('timed out') }
    Check $timedOut 'Native timeout path'
}
Write-Output ('PASS: ' + $script:Assertions + ' parser, quoting, connection-state and process assertions')
