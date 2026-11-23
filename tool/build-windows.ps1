$ErrorActionPreference = 'Stop'

Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found in PATH. Install Flutter and enable Windows desktop support.'
}

if (-not (Test-Path 'windows')) {
    flutter create --platforms=windows,web .
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

flutter pub get
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

flutter build windows --release @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host 'Windows build output: build\windows\x64\runner\Release'
