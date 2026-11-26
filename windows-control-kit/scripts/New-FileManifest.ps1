#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path $PSScriptRoot
$lines = foreach ($file in Get-ChildItem -LiteralPath $packageRoot -File -Recurse | Sort-Object FullName) {
    if ($file.Name -in @('FILES.sha256', '.DS_Store')) { continue }
    $relative = $file.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
    ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $relative)
}
Set-Content -LiteralPath (Join-Path $packageRoot 'FILES.sha256') -Value $lines -Encoding ASCII
Write-Host 'Installer file manifest generated.'
