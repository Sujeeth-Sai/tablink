#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Run Setup.cmd on Windows.' }
if (-not [Environment]::Is64BitOperatingSystem) { throw 'This package requires 64-bit Windows.' }
$sourceRoot = Split-Path $PSScriptRoot
$targetRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\TabLink-Windows-Control'
$marker = Join-Path $targetRoot 'package.json'
if ((Test-Path $targetRoot) -and -not (Test-Path $marker)) {
    throw 'The destination already exists and is not marked as this package. Rename it before installing.'
}
if (Test-Path $marker) {
    $existing = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    if ($existing.id -ne 'tablink.windows.controlkit') { throw 'The destination belongs to another package.' }
}
Write-Host 'Checking setup files...'
foreach ($entry in Get-Content -LiteralPath (Join-Path $sourceRoot 'FILES.sha256')) {
    if ($entry -notmatch '^([a-fA-F0-9]{64})  (.+)$') { throw 'Invalid file-integrity manifest.' }
    $expected = $Matches[1]
    $relative = $Matches[2]
    $full = [IO.Path]::GetFullPath((Join-Path $sourceRoot $relative))
    if (-not $full.StartsWith($sourceRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid file path in manifest.' }
    if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ne $expected) { throw ('A setup file is damaged: ' + $relative) }
}
[void](New-Item -ItemType Directory -Path $targetRoot -Force)
if (-not $sourceRoot.Equals($targetRoot, [StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $targetRoot -Recurse -Force
}
$shell = New-Object -ComObject WScript.Shell
$programFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'TabLink Tablet Control'
[void](New-Item -ItemType Directory -Path $programFolder -Force)
$desktopFolder = [Environment]::GetFolderPath('DesktopDirectory')
foreach ($destination in @($programFolder, $desktopFolder)) {
    foreach ($entry in @(@('TabLink - USB', 'USB'), @('TabLink - WiFi', 'WiFi'), @('TabLink - Menu', 'Menu'))) {
        $shortcut = $shell.CreateShortcut((Join-Path $destination ($entry[0] + '.lnk')))
        $shortcut.TargetPath = Join-Path $PSHOME 'powershell.exe'
        $shortcut.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $targetRoot 'scripts\Start-Control.ps1') + '" -Mode ' + $entry[1]
        $shortcut.WorkingDirectory = [Environment]::GetFolderPath('LocalApplicationData')
        $shortcut.IconLocation = (Join-Path $targetRoot 'runtime\scrcpy.exe') + ',0'
        $shortcut.Save()
    }
}
Write-Host ''
Write-Host 'Installed successfully. No administrator rights were needed for this copy.' -ForegroundColor Green
Write-Host 'Use TabLink - USB or TabLink - WiFi on your desktop.'
Write-Host 'Read SETUP-INSTRUCTIONS.txt before the first connection.'
Write-Host ('Installed files: ' + $targetRoot)
