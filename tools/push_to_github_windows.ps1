# Alternative uploader. ASCII-only for Windows PowerShell 5.1.
param([Parameter(Mandatory=$true)][string]$RepositoryUrl)
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'upload_to_chenuy_repo.ps1'
if ($RepositoryUrl -ne 'https://github.com/chenyu9512/GameLingoAI.git' -and $RepositoryUrl -ne 'https://github.com/chenyu9512/GameLingoAI') {
    throw 'This package uploader is restricted to chenyu9512/GameLingoAI. Use git manually for other repositories.'
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script
exit $LASTEXITCODE
