#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Run this uninstaller on Windows.' }
$targetRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\TabLink-Windows-Control'
$markerPath = Join-Path $targetRoot 'package.json'
if (-not (Test-Path $markerPath)) { throw 'This installed package was not found.' }
$package = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
if ($package.id -ne 'tablink.windows.controlkit') { throw 'The destination is not this package.' }
Write-Host 'Close all tablet-control windows before uninstalling.'
$answer = Read-Host 'Move this control kit and its shortcuts to the Recycle Bin? Type YES'
if ($answer -cne 'YES') { Write-Host 'Cancelled.'; exit 0 }
Add-Type -AssemblyName Microsoft.VisualBasic
$shell = New-Object -ComObject WScript.Shell
$programFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'TabLink Tablet Control'
foreach ($folder in @($programFolder, [Environment]::GetFolderPath('DesktopDirectory'))) {
    foreach ($name in @('TabLink - USB', 'TabLink - WiFi', 'TabLink - Menu')) {
        $path = Join-Path $folder ($name + '.lnk')
        if (Test-Path $path) {
            $shortcut = $shell.CreateShortcut($path)
            if ($shortcut.Arguments.Contains($targetRoot)) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
            }
        }
    }
}
[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($targetRoot, 'OnlyErrorDialogs', 'SendToRecycleBin')
Write-Host 'Uninstalled. Your shared Android ADB pairing keys were kept.'
