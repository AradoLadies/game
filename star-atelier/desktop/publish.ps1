param()
$ErrorActionPreference='Stop'
$root=(Get-Item -LiteralPath $PSScriptRoot).Parent.Parent.FullName
$expected='https://github.com/AradoLadies/game.git'
$api='https://api.github.com/repos/AradoLadies/game'
$headers=@{'User-Agent'='AradoLadies-Publisher';'Cache-Control'='no-cache'}
Push-Location -LiteralPath $root
try {
    if ((git branch --show-current) -ne 'main' -or (git remote get-url --push origin) -ne $expected) {
        throw '배포 대상이 AradoLadies/game의 main 브랜치인지 확인하세요.'
    }
    $paths=@('star-atelier/art','star-atelier/index.html','star-atelier/game.js','star-atelier/game.css',
        'star-atelier/models.js','star-atelier/silhouettes.js','star-atelier/desktop/Launcher.cs','star-atelier/desktop/star.ico',
        'star-atelier/desktop/build.ps1','star-atelier/desktop/install-game.ps1','star-atelier/desktop/publish.ps1',
        'star-atelier/desktop/org-auth.cjs','.github/workflows/release.yml','README.md','.gitignore')
    git add -A -- @paths
    if ($LASTEXITCODE) { throw '배포할 소스를 준비하지 못했습니다.' }
    git diff --cached --quiet -- @paths
    if ($LASTEXITCODE -eq 1) {
        git -c 'user.name=Arado Ladies' -c 'user.email=release@arado-ladies.invalid' commit --only -m 'Update game' -- @paths
        if ($LASTEXITCODE) { throw '배포 커밋을 만들지 못했습니다.' }
    } elseif ($LASTEXITCODE -ne 0) { throw '소스 변경 확인에 실패했습니다.' }
    $env:GIT_TERMINAL_PROMPT='0'
    git -c credential.helper= -c credential.https://github.com.helper= -c 'credential.https://github.com.helper=!node ./star-atelier/desktop/org-auth.cjs' -c credential.useHttpPath=true -c credential.interactive=false push origin HEAD:refs/heads/main
    if ($LASTEXITCODE) { throw '조직 배포 앱으로 소스를 올리지 못했습니다.' }
    $tag='game-'+(git rev-parse HEAD)
    $until=(Get-Date).AddMinutes(15)
    Write-Host 'GitHub Actions에서 Windows 실행 파일을 준비하고 있습니다.'
    $release=$null
    do {
        try {
            $candidate=Invoke-RestMethod -Uri "$api/releases/latest" -Headers $headers
            if ($candidate.tag_name -eq $tag) { $release=$candidate; break }
        } catch {
            if (!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 404) { throw }
        }
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $until)
    if (!$release) { throw 'GitHub Actions에서 배포 상태를 확인하세요: https://github.com/AradoLadies/game/actions' }
    $asset=@($release.assets | Where-Object name -ceq 'AradoLadies.exe')
    if ($asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:[a-f0-9]{64}$') { throw '공개 실행 파일의 SHA-256을 확인할 수 없습니다.' }
    $tmp=Join-Path ([IO.Path]::GetTempPath()) ('AradoVerified-'+[guid]::NewGuid().ToString('N')+'.exe')
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $asset[0].browser_download_url -Headers $headers -OutFile $tmp
        if (('sha256:'+(Get-FileHash -LiteralPath $tmp).Hash) -ne $asset[0].digest) { throw '다운로드한 파일의 SHA-256이 일치하지 않습니다.' }
        & (Join-Path $PSScriptRoot 'install-game.ps1') -SourceExe $tmp | Out-Null
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
    Write-Output 'https://github.com/AradoLadies/game/releases/latest/download/AradoLadies.exe'
} finally { Pop-Location }
