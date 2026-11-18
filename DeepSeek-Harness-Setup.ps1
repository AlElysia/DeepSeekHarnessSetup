#Requires -Version 5.1
<#
.SYNOPSIS
    DeepSeek-Harness 自动部署脚本（Windows PowerShell 版）
.DESCRIPTION
    一键安装与管理 DeepSeek-Harness：
      - Desktop 安装（winget 源）
      - Web 正式版 / 测试版安装（npm + pnpm + npx）
      - Desktop / Web 插件管理（pnpm）
      - Skill 管理（ZIP 解压 / 目录复制）
      - 启动 dsh web
.NOTES
    用法（在 PowerShell 中执行）：
      powershell -ExecutionPolicy Bypass -File .\DeepSeek-Harness-Setup.ps1
    注意：本文件必须保存为 UTF-8 with BOM 编码，否则中文会乱码。
#>

# ============================ 基础配置 ============================

# 脚本作者署名
$Script:ScriptAuthor = "@BLIDK"

# winget 中 DeepSeek Harness Desktop 的包 ID（如需更换安装源可修改）
$Script:WingetDesktopId = "hongfeiyucode.DeepSeekHarnessDesktop"

# npm 包名：Web 正式版 / Web 测试版（next 通道）
$Script:DshPkgName   = "@deepseek-ai/dsh"
$Script:DshPkgStable = "@deepseek-ai/dsh"
$Script:DshPkgBeta   = "@deepseek-ai/dsh@next"

# npm 全局安装目录默认值（自定义安装时使用；靠 npm config set prefix 生效，绝不给 install 传 --prefix）
$Script:DefaultNpmPrefix = "C:\npm-global"

# 安装 / 更新期间临时切换的 npm prefix 原值（结束后据此恢复）
$Script:NpmPrefixBefore  = $null
# 是否真的动过 npm prefix（动过才恢复，避免误删用户原有配置）
$Script:NpmPrefixTouched = $false

# 目录约定：工作目录 %USERPROFILE%，DSH 数据目录 %USERPROFILE%\.dsh
$Script:UserProfileDir = $env:USERPROFILE
$Script:DshHome        = Join-Path $env:USERPROFILE ".dsh"
$Script:SkillsDir      = Join-Path $Script:DshHome "skills"
$Script:DesktopDir     = Join-Path $Script:DshHome "profiles\desktop"
$Script:WebDir         = Join-Path $Script:DshHome "profiles\web"

# 退出标记：skill 子菜单中按 q 时退出整个脚本
$Script:QuitRequested = $false

# ============================ 通用工具函数 ============================

function Clear-Screen {
    try { Clear-Host } catch { Write-Host "" }
}

function Pause-Screen {
    Write-Host ""
    [void](Read-Host "按回车键继续")
}

function Read-MenuInput {
    param([string]$Prompt = "请输入你的选择")
    $v = Read-Host $Prompt
    if ($null -eq $v) { return 'q' }
    return $v.Trim().ToLower()
}

function Read-YesNo {
    param([string]$Prompt)
    while ($true) {
        $v = Read-Host "$Prompt (y/n)"
        if ($null -eq $v) { return $false }
        $a = $v.Trim().ToLower()
        if ($a -eq 'y') { return $true }
        if ($a -eq 'n') { return $false }
        Write-Host "输入无效，请输入 y 或 n。"
    }
}

# 把目录追加到用户 PATH 环境变量（已存在则跳过），并同步当前会话
function Add-UserPath {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return }
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPath) { $userPath = "" }
    $parts = @($userPath -split ';' | Where-Object { $_ -ne "" })
    $exists = @($parts | Where-Object { $_.TrimEnd('\') -ieq $Dir.TrimEnd('\') })
    if ($exists.Count -gt 0) {
        Write-Host "目录已在用户 PATH 中：$Dir"
        return
    }
    $newPath = if ($userPath) { "$userPath;$Dir" } else { $Dir }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    if ($env:Path -notlike "*$Dir*") { $env:Path = "$env:Path;$Dir" }
    Write-Host "已添加用户环境变量 PATH：$Dir（重新打开终端后生效）"
}

# 比较两个路径是否等价（忽略大小写、引号与结尾反斜杠）
function Test-SamePath {
    param([string]$A, [string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -and [string]::IsNullOrWhiteSpace($B)) { return $true }
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return $false }
    $na = $A.Trim().Trim('"').TrimEnd('\')
    $nb = $B.Trim().Trim('"').TrimEnd('\')
    return ($na -ieq $nb)
}

# 读取 npm 配置项（失败或未设置时返回 $null）
function Get-NpmConfigValue {
    param([string]$Key)
    $out = & npm config get $Key 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $v = ([string](@($out) -join "")).Trim()
    if ([string]::IsNullOrWhiteSpace($v) -or $v -eq "undefined" -or $v -eq "null") { return $null }
    return $v
}

# 读取 npm 全局模块目录（npm root -g）
function Get-NpmGlobalRoot {
    $out = & npm root -g 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $v = ([string](@($out) -join "")).Trim()
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v
}

# 读取 @deepseek-ai/dsh 已安装版本（从 <prefix>\node_modules 下的 package.json 读）
function Get-DshInstalledVersion {
    param([string]$PrefixDir)
    if ([string]::IsNullOrWhiteSpace($PrefixDir)) { return $null }
    $pkgJson = Join-Path $PrefixDir "node_modules\@deepseek-ai\dsh\package.json"
    if (-not (Test-Path $pkgJson)) { return $null }
    try {
        $obj = Get-Content $pkgJson -Raw -ErrorAction Stop | ConvertFrom-Json
        return $obj.version
    } catch {
        return $null
    }
}

# 探测 dsh 命令真实位置：Get-Command -> 指定目录 -> 当前 npm prefix -> 默认目录 -> npm root -g 上一级
function Find-DshCommand {
    param([string]$PrefixDir)
    $cmd = Get-Command dsh -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        # 同目录下优先用 .cmd 包装器（比 .ps1 少受执行策略影响）
        $cmdDir  = Split-Path $cmd.Source -Parent
        $cmdFile = Join-Path $cmdDir "dsh.cmd"
        if (Test-Path $cmdFile) { return $cmdFile }
        return $cmd.Source
    }

    $dirs = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PrefixDir)) { $dirs.Add($PrefixDir) }
    $npmPrefix = Get-NpmConfigValue "prefix"
    if ($npmPrefix) { $dirs.Add($npmPrefix) }
    $dirs.Add($Script:DefaultNpmPrefix)
    $npmRoot = Get-NpmGlobalRoot
    if ($npmRoot) { $dirs.Add((Split-Path $npmRoot -Parent)) }

    foreach ($dir in $dirs) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        foreach ($name in @("dsh.cmd", "dsh.exe", "dsh.ps1", "dsh")) {
            $cand = Join-Path $dir $name
            if (Test-Path $cand) { return $cand }
        }
    }
    return $null
}

# 探测 pnpm 是否已安装：Get-Command -> 当前 npm prefix -> npm root -g 上一级 -> 默认目录
# 注意：pnpm 是 Desktop / Web / 插件共用的独立工具，应待在 npm 默认全局目录，不随 dsh 的自定义前缀走
function Find-PnpmCommand {
    $cmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $cmdDir  = Split-Path $cmd.Source -Parent
        $cmdFile = Join-Path $cmdDir "pnpm.cmd"
        if (Test-Path $cmdFile) { return $cmdFile }
        return $cmd.Source
    }

    $dirs = New-Object System.Collections.Generic.List[string]
    $npmPrefix = Get-NpmConfigValue "prefix"
    if ($npmPrefix) { $dirs.Add($npmPrefix) }
    $npmRoot = Get-NpmGlobalRoot
    if ($npmRoot) { $dirs.Add((Split-Path $npmRoot -Parent)) }
    $dirs.Add($Script:DefaultNpmPrefix)

    foreach ($dir in $dirs) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        foreach ($name in @("pnpm.cmd", "pnpm.exe", "pnpm.ps1", "pnpm")) {
            $cand = Join-Path $dir $name
            if (Test-Path $cand) { return $cand }
        }
    }
    return $null
}

# 读取 pnpm 版本（读不到返回 $null）
function Get-PnpmVersion {
    param([string]$PnpmPath)
    if ([string]::IsNullOrWhiteSpace($PnpmPath)) { return $null }
    $out = & $PnpmPath -v 2>$null
    $v = ([string](@($out) -join "")).Trim()
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v
}

# 确保 pnpm 可用：已安装则跳过（不重复安装、不装进自定义目录）；未安装则用 npm 默认全局目录安装
function Ensure-Pnpm {
    $pnpmPath = Find-PnpmCommand
    if ($pnpmPath) {
        $ver = Get-PnpmVersion -PnpmPath $pnpmPath
        Write-Host ("已检测到 pnpm" + $(if ($ver) { "（$ver）" } else { "" }) + "：$pnpmPath，跳过安装。")
        return $pnpmPath
    }

    Write-Host "未检测到 pnpm，正在用 npm 默认全局目录安装（不切换 prefix，避免装进自定义目录）……"
    & npm install -g pnpm
    if ($LASTEXITCODE -ne 0) {
        Write-Host "pnpm 安装失败（退出码 $LASTEXITCODE）。"
        return $null
    }
    $pnpmPath = Find-PnpmCommand
    if ($pnpmPath) {
        $ver = Get-PnpmVersion -PnpmPath $pnpmPath
        Write-Host ("pnpm 安装完成" + $(if ($ver) { "（$ver）" } else { "" }) + "：$pnpmPath")
        return $pnpmPath
    }

    # 刚装完但当前窗口 PATH 尚未刷新：按 npm 全局目录推断位置，返回给上层写 PATH
    $npmPrefix = Get-NpmConfigValue "prefix"
    if (-not $npmPrefix) { $npmPrefix = $Script:DefaultNpmPrefix }
    $expected = Join-Path $npmPrefix "pnpm.cmd"
    Write-Host "pnpm 安装命令已执行，但当前窗口尚未刷新 PATH；预计位置：$expected（重开终端后可用）。"
    return $expected
}

# 临时把 npm prefix 切到指定目录（等于 npm config set prefix），原值存入 $Script:NpmPrefixBefore
function Set-NpmPrefixTemporary {
    param([string]$Prefix)
    if ([string]::IsNullOrWhiteSpace($Prefix)) { return $false }
    $Script:NpmPrefixBefore  = Get-NpmConfigValue "prefix"
    $Script:NpmPrefixTouched = $true
    if (-not (Test-Path $Prefix)) {
        New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
        Write-Host "已创建安装目录：$Prefix"
    }
    Write-Host "正在设置 npm prefix：$Prefix"
    & npm config set prefix "$Prefix" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "警告：npm config set prefix 返回码 $LASTEXITCODE。"
    }
    $now = Get-NpmConfigValue "prefix"
    Write-Host "当前 npm prefix：$now"
    if (-not $now) { return $false }
    return ($now.TrimEnd('\') -ieq $Prefix.TrimEnd('\'))
}

# 恢复安装 / 更新前的 npm 配置：先 npm config delete prefix，再保证结果与安装前完全一致
function Restore-NpmPrefix {
    $before = $Script:NpmPrefixBefore
    $Script:NpmPrefixBefore  = $null
    $Script:NpmPrefixTouched = $false

    $now = Get-NpmConfigValue "prefix"
    if ((Test-SamePath $now $before) -and -not [string]::IsNullOrWhiteSpace($before)) {
        Write-Host "npm prefix 保持安装前配置：$now（未做改动）"
        return
    }

    Write-Host "正在恢复 npm prefix（npm config delete prefix）……"
    & npm config delete prefix 2>$null | Out-Null
    $default = Get-NpmConfigValue "prefix"

    if ($before -and -not (Test-SamePath $before $default)) {
        & npm config set prefix "$before" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "警告：恢复 npm config set prefix 返回码 $LASTEXITCODE。"
        }
        $restored = Get-NpmConfigValue "prefix"
        Write-Host "已恢复安装前的 npm prefix：$before（当前：$restored）"
    } else {
        Write-Host ("npm prefix 已恢复为默认配置：" + $(if ($default) { $default } else { "读取失败" }))
    }
}

# 读取 npm 的默认全局目录：npm root -g 的上一级（不依赖 install 时临时切换的 prefix）
function Get-DefaultNpmPrefix {
    $root = Get-NpmGlobalRoot
    if ($root) { return (Split-Path $root -Parent) }
    $p = Get-NpmConfigValue "prefix"
    if ($p) { return $p }
    return $Script:DefaultNpmPrefix
}

# 把全局安装目录写进用户环境：只需要 bin 目录进 PATH
# NODE_PATH 是 Node 的旧版模块搜索路径，现代包按自身 node_modules 解析，dsh 也不读它，
# 所以不再写入；旧版本写入过与本目录匹配的 NODE_PATH 时顺手清掉
function Set-NpmEnvVars {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return }
    Add-UserPath -Dir $Dir
    $legacyNodePath = Join-Path $Dir "node_modules"
    $current = [Environment]::GetEnvironmentVariable("NODE_PATH", "User")
    if ($current -and (Test-SamePath $current $legacyNodePath)) {
        [Environment]::SetEnvironmentVariable("NODE_PATH", $null, "User")
        Remove-Item Env:\NODE_PATH -ErrorAction SilentlyContinue
        Write-Host "已移除旧版本写入的用户环境变量 NODE_PATH：$current（dsh 不依赖它）"
    }
    Write-Host "npm 环境已同步：PATH=$Dir"
}

# 定位 dsh 的安装目录（不依赖 PATH）：<dir>\node_modules\@deepseek-ai\dsh 存在即命中
# 用于“更新时 Get-Command 找不到 dsh”的情况——先确认它装在哪，再更新
function Find-DshInstallPrefix {
    param([string]$HintDir)
    $dirs = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($HintDir)) { $dirs.Add($HintDir) }
    $cmd = Get-Command dsh -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { $dirs.Add((Split-Path $cmd.Source -Parent)) }
    $npmPrefix = Get-NpmConfigValue "prefix"
    if ($npmPrefix) { $dirs.Add($npmPrefix) }
    $npmRoot = Get-NpmGlobalRoot
    if ($npmRoot) { $dirs.Add((Split-Path $npmRoot -Parent)) }
    $dirs.Add($Script:DefaultNpmPrefix)
    if ($env:APPDATA) { $dirs.Add((Join-Path $env:APPDATA "npm")) }
    if ($env:ProgramFiles) { $dirs.Add((Join-Path $env:ProgramFiles "nodejs")) }

    foreach ($dir in $dirs) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        if (Get-DshInstalledVersion -PrefixDir $dir) { return $dir }
    }
    return $null
}

# ============================ 菜单显示 ============================

function Show-MainMenu {
    Clear-Screen
    Write-Host "============================================================"
    Write-Host "              DeepSeek-Harness 自动部署脚本"
    Write-Host "           DeepSeek-Harness Auto Deploy Script"
    Write-Host "============================================================"
    Write-Host "描述：一键安装与管理 DeepSeek-Harness（Desktop / Web / Skill），"
    Write-Host "      包含 winget 安装、npm/pnpm 配置、插件管理、Skill 管理。"
    Write-Host "免责声明：本脚本仅供学习交流，按现状提供，不作任何担保；"
    Write-Host "          使用本脚本产生的一切后果由使用者自行承担，与作者无关。"
    Write-Host "作者：$Script:ScriptAuthor"
    Write-Host "工作目录：$Script:UserProfileDir"
    Write-Host "DSH 目录：$Script:DshHome"
    Write-Host "------------------------------------------------------------"
    Write-Host "提示：没有异议请选择第一个安装，更方便。"
    Write-Host ""
    Write-Host "---------------------- [ Main Menu ] -----------------------"
    Write-Host ""
    Write-Host "  1. Install DeepSeek-Harness Desktop     (Recommended, Stable)"
    Write-Host "  2. Install DeepSeek-Harness Web Stable  (Better Performance)"
    Write-Host "  3. Install DeepSeek-Harness Web Beta    (Not Recommended, Unstable)"
    Write-Host
    Write-Host "  4. DeepSeek-Harness Desktop Management  (Plugins)"
    Write-Host "  5. DeepSeek-Harness Web Management      (Plugins)"
    Write-Host "  6. DeepSeek-Harness Skill Management"
    Write-Host "  7. Upgrade DSH Web                      (npm update -g)"
    Write-Host "  8. Start DSH Web"
    Write-Host "  0. Quit"
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "键盘输入提示：输入编号 [1-8 / 0] 选择功能；输入 q 退出脚本。"
}

function Show-ProfileMenu {
    param([string]$Name, [string]$Dir)
    Clear-Screen
    Write-Host "============= DeepSeek-Harness $Name Management ============="
    Write-Host "描述：管理 DeepSeek-Harness $Name 的插件（基于 pnpm 包管理器）。"
    Write-Host "插件功能：插件用于扩展 $Name 的能力，例如工具调用、界面增强、"
    Write-Host "          工作流扩展等；插件可来自 npm 仓库或本地目录。"
    Write-Host "工作目录：$Dir"
    Write-Host "------------------------------------------------------------"
    Write-Host ""
    Write-Host "  1. Install           安装插件（包名 / 链接地址 / 本地目录）"
    Write-Host "  2. Remove/Uninstall  卸载插件"
    Write-Host "  3. Upgrade           一键更新全部插件"
    Write-Host "  4. List              查看已安装插件"
    Write-Host "  5. Open Config       打开用户配置 (cordis.patch.yml)"
    Write-Host "  6. Open Package      打开包管理文件 (package.json)"
    Write-Host "  7. Back              返回主菜单 (q)"
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "键盘输入提示：输入编号 [1-7]；输入 m 或 q 返回主菜单。"
}

function Show-SkillMenu {
    Clear-Screen
    Write-Host "============ DeepSeek-Harness Skill Management ============="
    Write-Host "描述：管理 DeepSeek-Harness 的 Skill（技能包）。"
    Write-Host "Skill 功能：技能包为 DeepSeek-Harness 扩展领域技能（提示词模板、"
    Write-Host "            工具流程、任务说明等），以文件夹形式存放。"
    Write-Host "Skill 目录：$Script:SkillsDir"
    Write-Host "------------------------------------------------------------"
    Write-Host ""
    Write-Host "  1. Install           安装 Skill（ZIP 解压 / 目录复制）"
    Write-Host "  2. Remove/Uninstall  删除单个 Skill 文件夹（含子文件及目录）"
    Write-Host "  3. List              查看已安装 Skill（文件夹名）"
    Write-Host "  7. Back              返回主菜单 (q)"
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "键盘输入提示：输入编号 [1-3 / 7 ]；输入 m 或 q 返回主菜单。"
}

# ============================ 安装功能 ============================

# 检查 Node.js；未安装则用 winget 安装，并刷新当前会话 PATH
function Ensure-NodeJs {
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Host "已检测到 Node.js：$(node -v)，跳过安装。"
        return $true
    }
    Write-Host "未检测到 Node.js，正在通过 winget 安装（OpenJS.NodeJS.LTS）……"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "未检测到 winget 命令，无法自动安装 Node.js。"
        Write-Host "请手动安装 Node.js（https://nodejs.org/）后重新运行本脚本。"
        return $false
    }
    & winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
    # 从注册表刷新当前会话 PATH，使刚安装的 node/npm 立即可用
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath     = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($machinePath) { $env:Path = "$machinePath;$userPath" } else { $env:Path = "$userPath" }
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Host "Node.js 安装成功：$(node -v)"
        return $true
    }
    Write-Host "Node.js 已安装，但当前窗口尚未生效。"
    Write-Host "请关闭本窗口，重新打开 PowerShell 后再次运行本脚本。"
    return $false
}

# 允许 @pnpm 与 @deepseek-ai 的包脚本执行（npm 用户级配置）
function Set-NpmAllowScripts {
    Write-Host "正在配置 npm 允许 @pnpm / @deepseek-ai 包脚本执行……"
    & npm config set allow-scripts=pnpm --location=user
    if ($LASTEXITCODE -ne 0) {
        Write-Host "警告：allow-scripts=pnpm 返回码 $LASTEXITCODE（如安装异常请手动执行）。"
    }
    & npm config set allow-scripts=deepseek-ai --location=user
    if ($LASTEXITCODE -ne 0) {
        Write-Host "警告：allow-scripts=deepseek-ai 返回码 $LASTEXITCODE（如安装异常请手动执行）。"
    }
}

# 主菜单 1：安装 DeepSeek-Harness Desktop（winget 源）
function Install-DshDesktop {
    Write-Host ""
    Write-Host "描述：通过 winget 安装 DeepSeek-Harness Desktop 图形客户端。"
    Write-Host "      桌面版内嵌 dsh 引擎，无需终端、无需 Node.js，双击即可运行。"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "未检测到 winget 命令。"
        Write-Host "请先从微软商店安装 App Installer 后重试。"
        Pause-Screen
        return
    }
    Write-Host "正在执行：winget install --id $Script:WingetDesktopId -e"
    & winget install --id $Script:WingetDesktopId -e --accept-source-agreements --accept-package-agreements
    Write-Host ""
    if ($LASTEXITCODE -eq 0) {
        Write-Host "DeepSeek-Harness Desktop 安装完成。"
    } else {
        Write-Host "安装未成功（退出码 $LASTEXITCODE）。"
        Write-Host "可尝试手动执行：winget install --id $Script:WingetDesktopId -e"
    }
    Pause-Screen
}

# 主菜单 2 / 3：安装 DeepSeek-Harness Web（正式版 / 测试版）
# 流程约定（见 docs/12.md）：
#   1) 一开始就问清楚装到哪：自定义目录（默认 C:\npm-global）或 npm 默认位置
#   2) 绝不给 npm install 传 --prefix 参数（实测会损坏文件）
#   3) 只有自定义目录才 npm config set prefix，装完恢复成安装前的 npm config
#   4) 安装目录写入用户 PATH（全局 bin）；不写 NODE_PATH——dsh 只用自身 node_modules
#   5) 安装不做 dsh 路径探测：装到哪个目录是已知的，直接按该目录给出运行命令
#   6) pnpm 是共用工具，必须装在 npm 默认全局目录（切换 prefix 之前装）；已安装则直接跳过，
#      既不重复安装，也不会跟着 dsh 的自定义目录跑掉
function Install-DshWeb {
    param([ValidateSet("stable", "beta")][string]$Channel = "stable")

    $label   = if ($Channel -eq "beta") { "测试版（next 通道，不稳定）" } else { "正式版" }
    $pkgSpec = if ($Channel -eq "beta") { $Script:DshPkgBeta } else { $Script:DshPkgStable }

    Write-Host ""
    Write-Host "描述：安装 DeepSeek-Harness Web $label。"
    Write-Host "流程：检查 Node.js -> 询问是否自定义安装目录 -> 允许包脚本 -> 检查 pnpm（默认目录，已装则跳过）->"
    Write-Host "      自定义才 npm config set prefix -> 安装 dsh -> 恢复 npm config 原配置 -> 安装目录写入用户 PATH。"
    if (-not (Ensure-NodeJs)) { Pause-Screen; return }

    # 先问清楚装到哪：自定义目录（默认 C:\npm-global）或 npm 默认位置
    $prefixDir = $null
    if (Read-YesNo "是否使用自定义安装目录（默认 $Script:DefaultNpmPrefix，n 表示使用 npm 默认位置）？") {
        $inputDir = (Read-Host "请输入安装目录（直接回车使用 $Script:DefaultNpmPrefix）").Trim().Trim('"').Trim()
        $prefixDir = if ([string]::IsNullOrWhiteSpace($inputDir)) { $Script:DefaultNpmPrefix } else { $inputDir }
    }

    if (-not (Read-YesNo "是否允许执行 @pnpm 和 @deepseek-ai/dsh 两个包的安装脚本？")) {
        Write-Host "已拒绝执行包脚本，返回主菜单（不安装）。"
        Pause-Screen
        return
    }
    Set-NpmAllowScripts

    # 先把 pnpm 落实好：此时 npm prefix 还是用户原来的（默认）配置，
    # pnpm 因此装在默认全局目录，不会被后面的自定义 prefix 带跑；
    # 已经装了 pnpm 就直接跳过，避免出现两套 pnpm 互相打架。
    $pnpmPath = Ensure-Pnpm
    if (-not $pnpmPath) {
        Write-Host "pnpm 不可用，已中止安装（dsh 的插件管理依赖 pnpm）。"
        Pause-Screen
        return
    }
    Add-UserPath -Dir (Split-Path $pnpmPath -Parent)

    # 只有选了自定义目录才动 npm prefix；否则直接装进 npm 默认位置
    $switched = $false
    if ($prefixDir) {
        # 关键：只用 npm config set prefix，绝不给 install 加 --prefix
        $switched = Set-NpmPrefixTemporary -Prefix $prefixDir
        if (-not $switched) {
            Write-Host "警告：npm prefix 可能未切到 $prefixDir，仍按当前 prefix 继续安装。"
        }
    }
    $targetPrefix = if ($prefixDir) { $prefixDir } else { Get-DefaultNpmPrefix }
    Write-Host "安装目标目录：$targetPrefix"

    $ok = $true
    try {
        Write-Host "正在安装 DeepSeek-Harness Web $label（npm install -g $pkgSpec）……"
        & npm install -g $pkgSpec
        if ($LASTEXITCODE -ne 0) {
            Write-Host "安装失败（退出码 $LASTEXITCODE）。"
            $ok = $false
        }
    } finally {
        # 只要动过 npm prefix 就恢复成安装前配置（含异常中断的情况）
        if ($Script:NpmPrefixTouched) { Restore-NpmPrefix }
    }

    if (-not $ok) {
        Pause-Screen
        return
    }

    # 安装完成后把全局 bin 目录写进用户 PATH（不再单独提供设置项）
    Set-NpmEnvVars -Dir $targetPrefix

    # 安装不做路径探测：装到哪个目录是已知的，直接按该目录给出结果
    $ver = Get-DshInstalledVersion -PrefixDir $targetPrefix
    Write-Host ""
    Write-Host "安装完成，安装目录：$targetPrefix"
    if ($ver) { Write-Host "已安装版本：$ver" }
    Write-Host "可直接运行：$targetPrefix\dsh.cmd web"
    Write-Host "提示：重新打开终端后 PATH 才会完整生效。"
    Pause-Screen
}

# 主菜单 7：更新 DeepSeek-Harness Web
# 流程约定（见 docs/12.md）：
#   1) dsh 在 npm 默认全局目录时不需要探测，直接更新；只有装在自定义（非默认）目录，
#      才去 Get-Command / 各全局目录的 node_modules\@deepseek-ai\dsh 里找，仍找不到再让用户输入目录
#   2) 必须先把 npm prefix 切到该目录再 npm update -g；直接在 dsh 目录里更新只会 remove 掉文件，不会更新
#   3) 更新完恢复 npm config 为更新前的配置，并把安装目录同步进用户 PATH
#   4) pnpm 属共用工具，更新 dsh 时不动它
function Upgrade-DshWeb {
    Write-Host ""
    Write-Host "描述：更新已安装的 DeepSeek-Harness Web（升级包流程，不清空配置）。"
    Write-Host "注意：直接进包目录执行 npm update 只会 remove 文件、不会更新；"
    Write-Host "      所以先 npm config set prefix 指向 dsh 所在目录，再 npm update -g，"
    Write-Host "      更新完把 npm config 恢复成更新前的配置。"
    Write-Host ""

    # dsh 在 npm 默认全局目录时不需要探测，直接更新；
    # 只有装在自定义（非默认）目录时，才去找它到底在哪
    $defaultPrefix = Get-DefaultNpmPrefix
    $prefix = $null
    if (Get-DshInstalledVersion -PrefixDir $defaultPrefix) {
        $prefix = $defaultPrefix
        Write-Host "dsh 位于 npm 默认全局目录：$prefix"
    } else {
        Write-Host "dsh 不在 npm 默认全局目录（$defaultPrefix），开始查找自定义安装路径……"
        $prefix = Find-DshInstallPrefix
        if ($prefix) {
            Write-Host "已定位到自定义安装路径：$prefix"
        } else {
            Write-Host "未在 PATH 与常见全局目录里找到已安装的 dsh。"
            $manual = (Read-Host "请输入 dsh 安装目录（含 node_modules 的全局目录；也可直接给 dsh.cmd 路径，回车取消）").Trim().Trim('"').Trim()
            if ([string]::IsNullOrWhiteSpace($manual)) {
                Write-Host "已取消。"
                Pause-Screen
                return
            }
            if ((Test-Path $manual) -and -not (Test-Path $manual -PathType Container)) {
                $manual = Split-Path $manual -Parent
            }
            $prefix = $manual
            if (-not (Get-DshInstalledVersion -PrefixDir $prefix)) {
                Write-Host "警告：$prefix 下没有 node_modules\@deepseek-ai\dsh，仍按该目录继续。"
            }
        }
    }

    $dshPath = $null
    $cand = Join-Path $prefix "dsh.cmd"
    if (Test-Path $cand) { $dshPath = $cand }
    if (-not $dshPath) { $dshPath = Find-DshCommand -PrefixDir $prefix }

    $verBefore = Get-DshInstalledVersion -PrefixDir $prefix
    Write-Host ("dsh 位置：" + $(if ($dshPath) { $dshPath } else { "未找到命令文件，按安装目录继续" }))
    Write-Host "安装目录（prefix）：$prefix"
    Write-Host ("当前版本：" + $(if ($verBefore) { $verBefore } else { "未知" }))

    $pkgSpec = $Script:DshPkgStable
    if (Read-YesNo "是否更新到测试版 next 通道？") { $pkgSpec = $Script:DshPkgBeta }

    $switched = Set-NpmPrefixTemporary -Prefix $prefix
    if (-not $switched) {
        Write-Host "警告：npm prefix 可能未切到 $prefix，更新结果可能不符合预期。"
    }

    $ok = $false
    try {
        Write-Host "正在执行：npm update -g $pkgSpec"
        & npm update -g $pkgSpec
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host "npm update 返回码 $code。" }

        $verAfter = Get-DshInstalledVersion -PrefixDir $prefix
        if ((-not $verAfter) -or ($verAfter -eq $verBefore)) {
            Write-Host "npm update 没有带来新版本（当前 $verAfter），改用 npm upgrade -g $pkgSpec……"
            & npm upgrade -g $pkgSpec
            if ($LASTEXITCODE -ne 0) { Write-Host "npm upgrade 返回码 $LASTEXITCODE。" }
            $verAfter = Get-DshInstalledVersion -PrefixDir $prefix
        }
        if ((-not $verAfter) -or ($verAfter -eq $verBefore)) {
            Write-Host "npm upgrade 仍未带来新版本（当前 $verAfter），改用 npm install -g $pkgSpec 强制拉取……"
            & npm install -g $pkgSpec
            if ($LASTEXITCODE -ne 0) {
                Write-Host "强制更新失败（退出码 $LASTEXITCODE）。"
            } else {
                $verAfter = Get-DshInstalledVersion -PrefixDir $prefix
            }
        }

        if ($verAfter -and $verAfter -ne $verBefore) {
            Write-Host "更新完成：$verBefore -> $verAfter"
            $ok = $true
        } elseif ($verAfter -and $verAfter -eq $verBefore) {
            Write-Host "已是最新版本：$verAfter"
            $ok = $true
        }
    } finally {
        # 更新完把 npm prefix 恢复成更新前配置
        if ($Script:NpmPrefixTouched) { Restore-NpmPrefix }
    }

    # 更新后把真实安装目录同步进用户 PATH
    Set-NpmEnvVars -Dir $prefix

    if (-not $ok) { Write-Host "更新未成功，请查看上方 npm 输出。" }
    if ($dshPath) {
        Write-Host "更新后建议重新打开终端，或直接执行：$dshPath web"
    } else {
        Write-Host "更新后建议重新打开终端，或直接执行：$prefix\dsh.cmd web"
    }
    Pause-Screen
}

# 主菜单 8：启动 dsh web
function Start-DshWeb {
    Write-Host ""
    $dshPath = Find-DshCommand
    if ($dshPath) {
        Write-Host "正在启动 DeepSeek-Harness Web（dsh web）……"
        Write-Host "命令位置：$dshPath"
        Write-Host "提示：按 Ctrl+C 可停止并返回本脚本。"
        & $dshPath web
    } else {
        Write-Host "未检测到 dsh 命令，改用 npx 临时运行（首次可能需要下载，不会写入全局目录）。"
        Write-Host "提示：按 Ctrl+C 可停止并返回本脚本。"
        & npx -y "@deepseek-ai/dsh" web
    }
    Write-Host ""
    Write-Host "dsh web 已退出。"
    Pause-Screen
}

# ============================ 插件管理（Desktop / Web 共用） ============================

function Install-Plugin {
    param([string]$Dir)
    Write-Host ""
    Write-Host "安装插件：填入插件的 npm 包名、链接地址，或本地目录地址。"
    Write-Host "免责声明：第三方插件与脚本作者无关，请自行甄别来源，风险自行承担。"
    $pkg = (Read-Host "请输入插件包名 / 链接地址 / 本地目录").Trim().Trim('"').Trim()
    if ([string]::IsNullOrWhiteSpace($pkg)) {
        Write-Host "输入为空，已取消。"
        return
    }
    Push-Location $Dir
    try {
        & pnpm add $pkg
        if ($LASTEXITCODE -eq 0) { Write-Host "插件安装完成：$pkg" }
        else { Write-Host "插件安装失败（退出码 $LASTEXITCODE）。" }
    } finally {
        Pop-Location
    }
}

function Remove-Plugin {
    param([string]$Dir)
    Write-Host ""
    $pkg = (Read-Host "请输入要卸载的插件名称").Trim()
    if ([string]::IsNullOrWhiteSpace($pkg)) {
        Write-Host "输入为空，已取消。"
        return
    }
    Push-Location $Dir
    try {
        & pnpm remove $pkg
        if ($LASTEXITCODE -eq 0) { Write-Host "插件已卸载：$pkg" }
        else { Write-Host "插件卸载失败（退出码 $LASTEXITCODE）。" }
    } finally {
        Pop-Location
    }
}

function Upgrade-Plugins {
    param([string]$Dir)
    Write-Host ""
    Write-Host "正在一键更新全部插件（pnpm upgrade）……"
    Push-Location $Dir
    try {
        & pnpm upgrade
        if ($LASTEXITCODE -eq 0) { Write-Host "插件更新完成。" }
        else { Write-Host "插件更新失败（退出码 $LASTEXITCODE）。" }
    } finally {
        Pop-Location
    }
}

function List-Plugins {
    param([string]$Dir)
    Write-Host ""
    Push-Location $Dir
    try {
        & pnpm list
    } finally {
        Pop-Location
    }
    # 统计已安装插件数量
    $pkgJsonPath = Join-Path $Dir "package.json"
    if (Test-Path $pkgJsonPath) {
        try {
            $pkgJson = Get-Content $pkgJsonPath -Raw | ConvertFrom-Json
            $count = 0
            if ($pkgJson.dependencies) {
                $count += @($pkgJson.dependencies.PSObject.Properties).Count
            }
            if ($pkgJson.devDependencies) {
                $count += @($pkgJson.devDependencies.PSObject.Properties).Count
            }
            Write-Host ""
            Write-Host "已安装插件数量：$count"
        } catch {
            Write-Host "（无法解析 package.json，跳过数量统计。）"
        }
    }
}

function Open-ProfileFile {
    param([string]$Dir, [string]$File)
    $path = Join-Path $Dir $File
    if (-not (Test-Path $path)) {
        Write-Host "未找到文件：$path"
        return
    }
    Write-Host "正在用记事本打开：$path"
    & notepad $path
}

# 主菜单 4 / 5：Desktop / Web 插件管理子菜单
function Manage-Profile {
    param([string]$Name, [string]$Dir)
    if (-not (Test-Path $Dir)) {
        Write-Host ""
        Write-Host "未检测到目录：$Dir"
        Write-Host "请先安装并至少运行一次 DeepSeek-Harness $Name 以生成该目录。"
        Pause-Screen
        return
    }
    $redraw = $true
    while ($true) {
        if ($redraw) { Show-ProfileMenu -Name $Name -Dir $Dir }
        $redraw = $true
        $choice = Read-MenuInput "请输入你的选择"
        switch ($choice) {
            '1' { Install-Plugin -Dir $Dir; Pause-Screen }
            '2' { Remove-Plugin -Dir $Dir; Pause-Screen }
            '3' { Upgrade-Plugins -Dir $Dir; Pause-Screen }
            '4' { List-Plugins -Dir $Dir; $redraw = $false }
            '5' { Open-ProfileFile -Dir $Dir -File "cordis.patch.yml" }
            '6' { Open-ProfileFile -Dir $Dir -File "package.json" }
            '7' { return }
            'm' { return }
            'q' { return }
            default {
                Write-Host "无效选项：$choice，请重新输入。"
                Start-Sleep -Milliseconds 900
            }
        }
    }
}

# ============================ Skill 管理 ============================

function Install-Skill {
    Write-Host ""
    Write-Host "安装 Skill：输入 ZIP 压缩包路径或 Skill 文件夹路径（可直接拖入本窗口）。"
    Write-Host "  - ZIP 压缩包：解压到 Skill 目录下"
    Write-Host "  - 文件夹：复制到 Skill 目录下"
    $src = (Read-Host "请输入路径").Trim().Trim('"').Trim()
    if ([string]::IsNullOrWhiteSpace($src)) {
        Write-Host "输入为空，已取消。"
        return
    }
    if (-not (Test-Path $src)) {
        Write-Host "路径不存在：$src"
        return
    }

    if (Test-Path $src -PathType Container) {
        # 文件夹 -> 复制到 Skill 目录下
        $name = Split-Path $src -Leaf
        $dest = Join-Path $Script:SkillsDir $name
        if (Test-Path $dest) {
            if (-not (Read-YesNo "目标已存在：$dest，是否覆盖？")) {
                Write-Host "已取消。"
                return
            }
            Remove-Item $dest -Recurse -Force
        }
        try { Copy-Item -Path $src -Destination $dest -Recurse -Force -ErrorAction Stop }
        catch { Write-Host "Skill 安装失败：$($_.Exception.Message)"; return }
        Write-Host "Skill 已复制到：$dest"
    }
    elseif ($src -like "*.zip") {
        # ZIP -> 解压到 Skill 目录下（先解压到临时目录再归位）
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("dsh-skill-" + [guid]::NewGuid().ToString("N"))
        try {
            Expand-Archive -Path $src -DestinationPath $tempDir -Force -ErrorAction Stop
            $entries = @(Get-ChildItem $tempDir -Force)
            if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {
                # 压缩包内含单一顶层文件夹：以该文件夹名安装
                $name = $entries[0].Name
                $dest = Join-Path $Script:SkillsDir $name
                if (Test-Path $dest) {
                    if (-not (Read-YesNo "目标已存在：$dest，是否覆盖？")) {
                        Write-Host "已取消。"
                        return
                    }
                    Remove-Item $dest -Recurse -Force -ErrorAction Stop
                }
                Copy-Item -Path $entries[0].FullName -Destination $dest -Recurse -Force -ErrorAction Stop
            }
            else {
                # 压缩包内容无统一顶层文件夹：以 ZIP 文件名建立文件夹
                $name = [IO.Path]::GetFileNameWithoutExtension($src)
                $dest = Join-Path $Script:SkillsDir $name
                if (Test-Path $dest) {
                    if (-not (Read-YesNo "目标已存在：$dest，是否覆盖？")) {
                        Write-Host "已取消。"
                        return
                    }
                    Remove-Item $dest -Recurse -Force -ErrorAction Stop
                }
                New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null
                Get-ChildItem $tempDir -Force | Copy-Item -Destination $dest -Recurse -Force -ErrorAction Stop
            }
            Write-Host "Skill 已解压到：$dest"
        }
        catch {
            Write-Host "Skill 安装失败：$($_.Exception.Message)"
        }
        finally {
            if (Test-Path $tempDir) {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-Host "不支持的路径类型（仅支持 .zip 文件或文件夹）：$src"
    }
}

function Remove-Skill {
    Write-Host ""
    $dirs = @(Get-ChildItem $Script:SkillsDir -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) {
        Write-Host "Skill 目录为空，没有可删除的 Skill。"
        return
    }
    Write-Host "已安装的 Skill："
    for ($i = 0; $i -lt $dirs.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $dirs[$i].Name)
    }
    $sel = (Read-Host "请输入要删除的编号或文件夹名").Trim()
    if ([string]::IsNullOrWhiteSpace($sel)) {
        Write-Host "输入为空，已取消。"
        return
    }
    $target = $null
    if ($sel -match '^\d+$') {
        $idx = [int]$sel
        if ($idx -ge 1 -and $idx -le $dirs.Count) {
            $target = $dirs[$idx - 1]
        } else {
            Write-Host "编号超出范围。"
            return
        }
    }
    else {
        if ($sel -match '[\\/]' -or $sel -eq '.' -or $sel -eq '..') {
            Write-Host "名称不合法（不允许包含路径分隔符）。"
            return
        }
        $target = $dirs | Where-Object { $_.Name -eq $sel } | Select-Object -First 1
        if (-not $target) {
            Write-Host "未找到该 Skill：$sel"
            return
        }
    }
    if (Read-YesNo ("确认删除（含所有子文件及目录，不可恢复）：" + $target.FullName + " ？")) {
        Remove-Item -Path $target.FullName -Recurse -Force
        Write-Host "已删除：$($target.FullName)"
    } else {
        Write-Host "已取消。"
    }
}

function List-Skills {
    Write-Host ""
    $dirs = @(Get-ChildItem $Script:SkillsDir -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) {
        Write-Host "当前没有已安装的 Skill（目录：$Script:SkillsDir）。"
        return
    }
    Write-Host "已安装的 Skill（共 $($dirs.Count) 个）："
    foreach ($d in $dirs) {
        Write-Host "  - $($d.Name)"
    }
}

# 主菜单 6：Skill 管理子菜单
function Manage-Skills {
    # 确保 Skill 目录存在（已有则不创建）
    if (-not (Test-Path $Script:SkillsDir)) {
        New-Item -ItemType Directory -Path $Script:SkillsDir -Force | Out-Null
        Write-Host "已创建 Skill 目录：$Script:SkillsDir"
        Start-Sleep -Milliseconds 900
    }
    $redraw = $true
    while ($true) {
        if ($redraw) { Show-SkillMenu }
        $redraw = $true
        $choice = Read-MenuInput "请输入你的选择"
        switch ($choice) {
            '1' { Install-Skill; Pause-Screen }
            '2' { Remove-Skill; Pause-Screen }
            '3' { List-Skills; $redraw = $false }
            '7' { return }
            'm' { return }
            'q' { return }
            default {
                Write-Host "无效选项：$choice，请重新输入。"
                Start-Sleep -Milliseconds 900
            }
        }
    }
}

# ============================ 主流程 ============================

# README 约定：工作目录为 %USERPROFILE%
Set-Location $Script:UserProfileDir

$exitLoop = $false
while (-not $exitLoop) {
    Show-MainMenu
    $choice = Read-MenuInput "请输入你的选择"
    switch ($choice) {
        '1' { Install-DshDesktop }
        '2' { Install-DshWeb -Channel "stable" }
        '3' { Install-DshWeb -Channel "beta" }
        '4' { Manage-Profile -Name "Desktop" -Dir $Script:DesktopDir }
        '5' { Manage-Profile -Name "Web" -Dir $Script:WebDir }
        '6' { Manage-Skills }
        '7' { Upgrade-DshWeb }
        '8' { Start-DshWeb }
        '0' { $exitLoop = $true }
        'q' { $exitLoop = $true }
        default {
            Write-Host "无效选项：$choice，请重新输入。"
            Start-Sleep -Milliseconds 900
        }
    }
    if ($Script:QuitRequested) { $exitLoop = $true }
}

Write-Host ""
Write-Host "感谢使用 DeepSeek-Harness 自动部署脚本，再见！"
