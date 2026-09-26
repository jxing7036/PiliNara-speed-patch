# PiliPlus Z/X/C 倍速快捷键补丁包

给 PiliNara（PiliPlus）添加 **Windows 端 Z/X/C 快捷键快速调节播放倍速** 的独立补丁。

> 构建源码默认用 **你自己的 fork：`https://github.com/jxing7036/PiliNara.git` @ `main`**（Actions 里可用 `source_repo` / `source_ref` 覆盖成官方仓库或别的分支）。
> 补丁基线 = fork main `aa993b3c0`（含上游 PiliPlus 2.1.5 合并）；上游作者未接受相关 PR，故用独立补丁包一键构建。

## 功能

| 按键 | 行为 |
|------|------|
| **Z** | 恢复 1.0x 倍速 |
| **X** | 倍速 -0.1x（长按持续减速） |
| **C** | 倍速 +0.1x（长按持续加速，300ms 防误触后每 100ms 步进） |

- 倍速范围 0.1x ~ 6.0x，整数运算避免浮点精度累积误差
- 直播不生效；播放器内显示当前倍速 toast
- 仅桌面端（Windows）快捷键生效

## 一键构建（推荐）

### GitHub Actions（无需本地环境）

把本仓库推到 GitHub 后，内置的 `.github/workflows/build.yml` 会自动完成全部流程：

手动触发：**Actions** 页 → **Build PiliNara (Z/X/C hotkey)** → **Run workflow**
（每次跑都会重新拉取源码再构建；`source_repo` 默认 `https://github.com/jxing7036/PiliNara.git`，`source_ref` 默认 `main`）

产物在运行页的 **Artifacts**（`pilinara_zxc_windows_x64.zip`，便携版，解压即用）。
勾选 `create_release` 后还会发布到 GitHub Release 的 `nightly` 预发布。


## 涉及文件（3 个）

```
lib/pages/video/widgets/player_focus.dart   # 按键分发 + 步进逻辑
lib/plugin/pl_player/controller.dart        # keyboardSpeedToast 状态 + 定时器
lib/plugin/pl_player/view/view.dart         # 倍速 toast UI
```
## 注意事项

- 构建源码改过这 3 个文件时，`git apply` 会失败。此时构建脚本会自动做 **3 路合并**：
  `patch-base/`（基线 `aa993b3c0`）+ `files/`（我们的改动）+ 新源码，自动把快捷键改动并到新版上。
  → 合并干净则直接继续；有冲突则**中止构建并报错**，避免盲覆盖丢失官方改动，需人工更新 `patch-base/` 与 `files/` 后重试。
- 调速走 `setManualPlaybackSpeed()`（不是 `setPlaybackSpeed()`）：新版有「倍速锁定」，前者会先解锁再调速，锁定态下按 Z/X/C 也能生效。
- 更新补丁方式：源码改过这 3 个文件后，需人工把改动合并到新代码，再更新 `files/` 和 `patch-base/`（见下方）

## 如何重新生成补丁（源码改动冲突时需要）

在改好代码的仓库里，把 3 个文件更新到新基线并合入快捷键改动：

```bash
git diff <新基线commit> <当前HEAD> -- <这3个文件> > pilinara_zxc_speed_hotkey.patch
# 同时更新:
#   files/lib/.../*.dart       —— 合并后的完整文件（改动侧）
#   patch-base/lib/.../*.dart  —— 新基线文件（合并基线）
```


## 文件清单

```
run.bat                               # 一键构建入口（双击运行）
run.ps1                               # 一键构建脚本（自动更新源码+打补丁+编译+输出 exe）
apply.ps1                             # 仅打补丁脚本（给已有源码用）
pilinara_zxc_speed_hotkey.patch       # git 补丁
patch-base\lib\...\*.dart            # 官方基线（3 路合并用）
files\lib\...\*.dart                  # 修改后的完整文件（改动侧）
README.md
```
