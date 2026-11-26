#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path $PSScriptRoot
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('tablink-runtime-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporary)
try {
    $archive = Join-Path $temporary 'scrcpy-win64-v5.0.1.zip'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/Genymobile/scrcpy/releases/download/v5.0.1/scrcpy-win64-v5.0.1.zip' -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne 'b12a2c4ee8be317422451fc7dcf8ee20a71b5ea7ef9ad73ddd825a25316227a5') { throw 'Upstream runtime checksum mismatch.' }
    $expanded = Join-Path $temporary 'expanded'
    Expand-Archive -LiteralPath $archive -DestinationPath $expanded
    $runtime = Join-Path $packageRoot 'runtime'
    [void](New-Item -ItemType Directory -Path $runtime -Force)
    Copy-Item -Path (Join-Path $expanded 'scrcpy-win64-v5.0.1\*') -Destination $runtime -Recurse -Force
    Write-Host 'Verified official Windows runtime downloaded.'
} finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
