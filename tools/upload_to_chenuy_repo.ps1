$ErrorActionPreference = 'Stop'
$repo = 'https://github.com/chenyu9512/GameLingoAI.git'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
  Write-Host '请先安装 Git for Windows: https://git-scm.com/downloads/win' -ForegroundColor Yellow
  exit 1
}

$workDir = Join-Path ([IO.Path]::GetTempPath()) ('GameLingoAI_upload_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir | Out-Null
try {
  Write-Host ('正在通过 GitHub 安全登录并克隆：' + $repo)
  & git.exe clone $repo (Join-Path $workDir 'repo')
  if ($LASTEXITCODE -ne 0) { throw '克隆失败。请确认仓库存在、GitHub 登录成功且你拥有写入权限。' }
  $clone = Join-Path $workDir 'repo'
  $gitMeta = Join-Path $clone '.git'
  if (-not (Test-Path $gitMeta)) { throw 'Git 克隆目录无效。' }

  $items = Get-ChildItem -LiteralPath $projectRoot -Force
  foreach ($item in $items) {
    if ($item.Name -in @('.git', '上传到GitHub.cmd')) { continue }
    $target = Join-Path $clone $item.Name
    if (Test-Path $target) {
      if ($item.Name -eq 'README.md') {
        $target = Join-Path $clone 'README_GameLingoAI.md'
        Write-Host '仓库已有 README.md，保留原文件；新项目说明写到 README_GameLingoAI.md。'
      } elseif ($item.Name -eq '.gitignore') {
        Write-Host '仓库已有 .gitignore：保留原文件，请后续检查是否需要合并忽略规则。'
        continue
      } else {
        throw ('远端仓库已有同名项目文件/目录 ' + $item.Name + '。为了保护原有内容，已停止；请先备份或处理冲突。')
      }
    }
    Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
  }
  Push-Location $clone
  try {
    & git.exe add .
    if ($LASTEXITCODE -ne 0) { throw 'Git add 失败。' }
    & git.exe diff --cached --quiet
    $hasChanges = $LASTEXITCODE -eq 1
    if (-not $hasChanges) { Write-Host '没有需要上传的新文件。'; exit 0 }
    & git.exe -c 'user.name=GameLingoAI' -c 'user.email=gamelingo@users.noreply.github.com' commit -m 'Add GameLingoAI offline iPhone source and Codemagic workflow'
    if ($LASTEXITCODE -ne 0) { throw 'Git 提交失败。' }
    & git.exe push origin HEAD
    if ($LASTEXITCODE -ne 0) { throw '上传失败；请检查仓库权限、网络与 GitHub 登录。' }
    Write-Host '上传成功！仓库地址：https://github.com/chenyu9512/GameLingoAI' -ForegroundColor Green
  } finally { Pop-Location }
} catch {
  Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
  exit 1
} finally {
  # 临时克隆中不保存任何仓库文件到用户项目；遇到占用则稍后手动清理即可。
  Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
