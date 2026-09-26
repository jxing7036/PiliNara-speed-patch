# 仅打补丁：把 Z/X/C 倍速快捷键补丁应用到已有的 PiliNara 源码上
#
# 用法：
#   .\apply.ps1                                   # 克隆 jxing7036/PiliNara@main 到 .\PiliNara-source 并打补丁
#   .\apply.ps1 -Dir ..\PiliNara -SkipClone       # 对已有源码目录打补丁
#   .\apply.ps1 -Source https://github.com/Starfallan/PiliNara.git -Ref develop
param(
    [string]$Source = 'https://github.com/jxing7036/PiliNara.git',
    [string]$Ref = 'main',
    [string]$Dir = 'PiliNara-source',
    [switch]$SkipClone
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$patch = Join-Path $root 'pilinara_zxc_speed_hotkey.patch'
if (-not (Test-Path -LiteralPath $patch)) { throw "找不到补丁文件: $patch" }

if (-not $SkipClone) {
    if (Test-Path -LiteralPath (Join-Path $Dir '.git')) {
        Write-Host "更新已有源码: $Dir"
        git -C $Dir fetch -q --depth 1 origin $Ref
        if ($LASTEXITCODE -ne 0) { throw "拉取失败: $Dir / $Ref" }
        git -C $Dir checkout -q FETCH_HEAD
    } else {
        Write-Host "克隆源码: $Source @ $Ref"
        git -c core.autocrlf=false clone -q --depth 1 --branch $Ref $Source $Dir
        if ($LASTEXITCODE -ne 0) { throw "克隆失败: $Source @ $Ref" }
    }
}

$repo = (Resolve-Path -LiteralPath $Dir).Path
Write-Host "源码 HEAD: $(git -C $repo log -1 --format='%h %ad %s' --date=short)"

Push-Location $repo
try {
    $applied = $false
    git apply --check $patch 2>$null
    if ($LASTEXITCODE -eq 0) {
        git apply $patch
        if ($LASTEXITCODE -eq 0) { $applied = $true }
    }

    if (-not $applied) {
        Write-Host 'git apply 未成功（源码改过这 3 个文件），尝试 3 路合并...'
        $targets = @(
            'lib/pages/video/widgets/player_focus.dart',
            'lib/plugin/pl_player/controller.dart',
            'lib/plugin/pl_player/view/view.dart'
        )
        $conflict = $false
        foreach ($f in $targets) {
            $base = Join-Path $root "patch-base/$f"
            $ours = Join-Path $root "files/$f"
            if (-not (Test-Path -LiteralPath $base)) { throw "缺少合并基线: $base" }
            if (-not (Test-Path -LiteralPath $ours)) { throw "缺少改动文件: $ours" }
            if (-not (Test-Path -LiteralPath $f)) { throw "源码文件路径已变化: $f" }
            git merge-file $f $base $ours 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Host "  已合并: $f" } else { Write-Host "  冲突: $f"; $conflict = $true }
        }
        if ($conflict) { throw '3 路合并存在冲突，需人工更新 files/ 与 patch-base/' }
    }

    Write-Host '[OK] 补丁已应用'
    git --no-pager diff --stat
} finally {
    Pop-Location
}
