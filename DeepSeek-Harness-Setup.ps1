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
$Script:DshPkgStable = "@deepseek-ai/dsh"
$Script:DshPkgBeta   = "@deepseek-ai/dsh@next"

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
    Write-Host "  7. Start DSH Web"
    Write-Host "  8. Quit"
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "键盘输入提示：输入编号 [1-8] 选择功能；输入 q 退出脚本。"
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

# 主菜单 2：安装 DeepSeek-Harness Web 正式版
function Install-DshWebStable {
    Write-Host ""
    Write-Host "描述：安装 DeepSeek-Harness Web 正式版（性能较好，可用）。"
    Write-Host "流程：检查 Node.js -> 允许包脚本 -> 安装 pnpm -> npx 启动。"
    if (-not (Ensure-NodeJs)) { Pause-Screen; return }

    if (-not (Read-YesNo "是否允许执行 @pnpm 和 @deepseek-ai/dsh 两个包的安装脚本？")) {
        Write-Host "已拒绝执行包脚本，返回主菜单（不安装）。"
        return
    }
    Set-NpmAllowScripts

    Write-Host "正在安装 pnpm（npm install -g pnpm）……"
    & npm install -g pnpm
    if ($LASTEXITCODE -ne 0) {
        Write-Host "pnpm 安装失败（退出码 $LASTEXITCODE）。"
        Pause-Screen
        return
    }

    Write-Host ""
    Write-Host "正在启动 DeepSeek-Harness Web 正式版（npx @deepseek-ai/dsh web）……"
    Write-Host "提示：在浏览器打开脚本提示的地址即可使用；按 Ctrl+C 可停止并返回本脚本。"
    & npx -y "@deepseek-ai/dsh" web
    Pause-Screen
}

# 主菜单 3：安装 DeepSeek-Harness Web 测试版
function Install-DshWebBeta {
    Write-Host ""
    Write-Host "描述：安装 DeepSeek-Harness Web 测试版（不推荐，不稳定，next 通道）。"
    Write-Host "流程：检查 Node.js -> 允许包脚本 -> 选择全局/自定义目录 -> 安装。"
    if (-not (Ensure-NodeJs)) { Pause-Screen; return }

    if (-not (Read-YesNo "是否允许执行 @pnpm 和 @deepseek-ai/dsh 两个包的安装脚本？")) {
        Write-Host "已拒绝执行包脚本，返回主菜单（不安装）。"
        return
    }

    # 全局安装 或 自定义目录（--prefix）
    $useGlobal = Read-YesNo "@deepseek-ai/dsh 是否全局安装？(y=全局安装 / n=自定义目录)"
    $customDir = $null
    if (-not $useGlobal) {
        $customDir = (Read-Host "请输入自定义安装目录（例如 D:\dsh-global）").Trim().Trim('"').Trim()
        if ([string]::IsNullOrWhiteSpace($customDir)) {
            Write-Host "目录为空，已取消，返回主菜单。"
            return
        }
    }

    Set-NpmAllowScripts

    Write-Host "正在安装 pnpm（npm install -g pnpm）……"
    & npm install -g pnpm
    if ($LASTEXITCODE -ne 0) {
        Write-Host "pnpm 安装失败（退出码 $LASTEXITCODE）。"
        Pause-Screen
        return
    }

    Write-Host "正在安装 DeepSeek-Harness Web 测试版（npm install -g $Script:DshPkgBeta）……"
    if ($useGlobal) {
        & npm install -g @deepseek-ai/dsh@next
        if ($LASTEXITCODE -ne 0) {
            Write-Host "安装失败（退出码 $LASTEXITCODE）。"
            Pause-Screen
            return
        }
        Write-Host "全局安装完成。重新打开终端后可直接运行：dsh web"
    } else {
        New-Item -ItemType Directory -Path $customDir -Force | Out-Null
        & npm install -g @deepseek-ai/dsh@next --prefix "$customDir"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "安装失败（退出码 $LASTEXITCODE）。"
            Pause-Screen
            return
        }
        Write-Host "自定义目录安装完成：$customDir"
        # 自定义目录需要添加用户环境变量；全局安装不需要
        Add-UserPath -Dir $customDir
        Write-Host "提示：重新打开终端后可运行 dsh 命令；也可直接运行：$customDir\dsh web"
    }
    Pause-Screen
}

# 主菜单 7：启动 dsh web
function Start-DshWeb {
    Write-Host ""
    $dshCmd = Get-Command dsh -ErrorAction SilentlyContinue
    if ($dshCmd) {
        Write-Host "正在启动 DeepSeek-Harness Web（dsh web）……"
        Write-Host "提示：按 Ctrl+C 可停止并返回本脚本。"
        & dsh web
    } else {
        Write-Host "未检测到全局 dsh 命令，改用 npx 临时运行（首次可能需要下载）……"
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
        '2' { Install-DshWebStable }
        '3' { Install-DshWebBeta }
        '4' { Manage-Profile -Name "Desktop" -Dir $Script:DesktopDir }
        '5' { Manage-Profile -Name "Web" -Dir $Script:WebDir }
        '6' { Manage-Skills }
        '7' { Start-DshWeb }
        '8' { $exitLoop = $true }
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
