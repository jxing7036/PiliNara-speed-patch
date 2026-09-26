# 一键构建：拉源码 -> 打补丁 -> 打官方 SDK 补丁 -> 编译 Windows exe -> 输出便携 zip
#
# 用法：  powershell -ExecutionPolicy Bypass -File .\run.ps1
# 可选：  -Source <git url> -Ref <branch> -Out <zip 名>
param(
    [string]$Source = 'https://github.com/jxing7036/PiliNara.git',
    [string]$Ref = 'main',
    [string]$Out = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dir = Join-Path $root 'PiliNara-source'

& (Join-Path $root 'apply.ps1') -Source $Source -Ref $Ref -Dir $dir
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) { throw '打补丁失败' }

Push-Location $dir
try {
    $env:FLUTTER_ROOT = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)

    # 上次构建可能已经把官方 SDK 补丁打进这个 Flutter SDK 了，先还原成干净工作区，
    # 否则 patch.ps1 会 "patch does not apply"。
    if (Test-Path (Join-Path $env:FLUTTER_ROOT '.git')) {
        git -C $env:FLUTTER_ROOT checkout -- .
        if ($LASTEXITCODE -ne 0) { throw "还原 Flutter SDK 失败: $env:FLUTTER_ROOT" }
        Write-Host "  已还原 Flutter SDK 工作区: $env:FLUTTER_ROOT"
    }

    # 官方 SDK 补丁是 CRLF，而 flutter SDK 的 .dart 被 .gitattributes 强制为 LF，先统一
    Get-ChildItem -Path 'lib/scripts' -Filter '*.patch' -ErrorAction SilentlyContinue | ForEach-Object {
        $t = [System.IO.File]::ReadAllText($_.FullName)
        $t = $t.Replace([string][char]13 + [string][char]10, [string][char]10)
        [System.IO.File]::WriteAllText($_.FullName, $t, (New-Object System.Text.UTF8Encoding($false)))
    }
    $env:GITHUB_WORKSPACE = (Get-Location).Path
    & powershell -NoProfile -ExecutionPolicy Bypass -File 'lib\scripts\patch.ps1' windows
    if ($LASTEXITCODE -ne 0) { throw '官方 SDK 补丁应用失败' }

    & powershell -NoProfile -ExecutionPolicy Bypass -File 'lib\scripts\build.ps1'
    if ($LASTEXITCODE -ne 0) { throw '生成 release 配置失败' }

    $cmakeFile = 'windows\CMakeLists.txt'
    if (Test-Path -LiteralPath $cmakeFile) {
        $c = [System.IO.File]::ReadAllText($cmakeFile)
        if ($c -match '/WX') {
            [System.IO.File]::WriteAllText($cmakeFile, ($c -replace '/WX', ''), (New-Object System.Text.UTF8Encoding($false)))
            Write-Host '  已移除 /WX'
        }
    }

    flutter build windows --release --dart-define-from-file=pili_release.json
    if ($LASTEXITCODE -ne 0) { throw '编译失败' }

    $releaseDir = 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'pilinara.exe'))) { throw "未找到产物: $releaseDir\pilinara.exe" }
    if (-not $Out) { $Out = "pilinara_zxc_$env:version.zip" }
    $stage = Join-Path $root 'release'
    if (Test-Path -LiteralPath $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Copy-Item -Path (Join-Path $releaseDir '*') -Destination $stage -Recurse -Force
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath (Join-Path $root $Out) -Force
    Write-Host "[OK] 已生成: $(Join-Path $root $Out)"
} finally {
    Pop-Location
}
