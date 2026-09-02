$ErrorActionPreference = 'Stop'

Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found in PATH.'
}

$platforms = @()
if (-not (Test-Path 'windows')) { $platforms += 'windows' }
if (-not (Test-Path 'web')) { $platforms += 'web' }

if ($platforms.Count -gt 0) {
    flutter create --platforms ($platforms -join ',') .
} else {
    Write-Host 'Windows and web platform folders already exist.'
}
