param([Parameter(Mandatory=$true)][string]$RepositoryUrl)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw '请先安装 Git for Windows: https://git-scm.com/downloads/win'
}
if (-not (Test-Path '.git')) { git init }
git add .
if ((git status --porcelain).Length -eq 0) { Write-Host '无新改动需要提交' }
else {
  git -c user.name='GameLingo user' -c user.email='gamelingo@users.noreply.github.com' commit -m 'Offline iPhone GameLingo v1.3'
}
git branch -M main
$exists = git remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0 -and $exists) { git remote set-url origin $RepositoryUrl }
else { git remote add origin $RepositoryUrl }
git push -u origin main
Write-Host '已提交。前往 Codemagic 刷新仓库。'
