# Windows PowerShell 5.1 and PowerShell 7 compatible (ASCII-only script).
# Upload GameLingoAI v2 files into the existing private GitHub repository.
$ErrorActionPreference = 'Stop'
$repoUrl = 'https://github.com/chenyu9512/GameLingoAI.git'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    Write-Host 'Git for Windows is missing. Install: https://git-scm.com/downloads/win' -ForegroundColor Yellow
    exit 1
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ('GameLingoAI_upload_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$locationPushed = $false
try {
    $clone = Join-Path $workDir 'repo'
    Write-Host 'Step 1/4: Clone repository...' -ForegroundColor Cyan
    & git.exe clone --branch main $repoUrl $clone
    if ($LASTEXITCODE -ne 0) { throw 'Git clone failed. Check your GitHub login and network.' }

    Write-Host 'Step 2/4: Copy project files...' -ForegroundColor Cyan
    $paths = @('.gitignore', 'README.md', 'codemagic.yaml', 'ios', 'tools', 'GameLingoAI.xcodeproj', 'project.yml')
    foreach ($path in $paths) {
        $source = Join-Path $projectRoot $path
        if (-not (Test-Path -LiteralPath $source)) { continue }
        $target = Join-Path $clone $path
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }

    Push-Location -LiteralPath $clone
    $locationPushed = $true
    Write-Host 'Step 3/4: Commit changes...' -ForegroundColor Cyan
    & git.exe add -A -- .gitignore README.md codemagic.yaml ios tools GameLingoAI.xcodeproj project.yml
    if ($LASTEXITCODE -ne 0) { throw 'Git add failed.' }

    & git.exe diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'No changes to upload. Repository is already up to date.' -ForegroundColor Green
    } elseif ($LASTEXITCODE -eq 1) {
        & git.exe -c user.name='GameLingoAI' -c user.email='gamelingo@users.noreply.github.com' commit -m 'GameLingoAI v2 offline: UI, PiP, OCR diagnostics and icon'
        if ($LASTEXITCODE -ne 0) { throw 'Git commit failed.' }
        Write-Host 'Step 4/4: Push to GitHub...' -ForegroundColor Cyan
        & git.exe push origin HEAD:main
        if ($LASTEXITCODE -ne 0) {
            throw 'Git push failed. Do not force push. Confirm permission and retry.'
        }
        Write-Host 'Upload completed successfully.' -ForegroundColor Green
    } else {
        throw 'Git diff failed.'
    }
    Write-Host 'Repo: https://github.com/chenyu9512/GameLingoAI'
} catch {
    Write-Host ('Upload failed: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($locationPushed) { Pop-Location }
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
