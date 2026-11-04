# DeepSeek-Harness-Setup

**English** | [中文](#中文)

One-click installer and manager for [DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh) on Windows — Desktop client, Web edition, plugins, and skills, all from a single interactive PowerShell menu.

## Features

- 🖥️ **Install Desktop** — via winget (stable, recommended; no Node.js needed)
- 🌐 **Install Web Stable / Beta** — via npm + pnpm (auto-checks Node.js, configures npm `allow-scripts`, installs pnpm, supports global or custom-directory install with user PATH setup)
- 🧩 **Plugin Management** — for Desktop & Web profiles (`%USERPROFILE%\.dsh\profiles\desktop|web`): install / remove / upgrade / list, open `cordis.patch.yml` and `package.json` in Notepad
- 🎯 **Skill Management** — install from ZIP (auto-extract, single-top-folder aware) or folder copy; remove / list skills in `%USERPROFILE%\.dsh\skills`
- 🚀 **Start DSH Web** — `dsh web` with automatic `npx` fallback
- 中文 descriptions with English menu options; every action pauses so you can read the output

## Menu

```
1. Install DeepSeek-Harness Desktop     (Recommended, Stable)
2. Install DeepSeek-Harness Web Stable  (Better Performance)
3. Install DeepSeek-Harness Web Beta    (Not Recommended, Unstable)
4. DeepSeek-Harness Desktop Management  (Plugins)
5. DeepSeek-Harness Web Management      (Plugins)
6. DeepSeek-Harness Skill Management
7. Start DSH Web
8. Quit
```

## Requirements

- Windows 10 / 11 with Windows PowerShell 5.1 or later (built in)
- [winget](https://aka.ms/getwinget) (App Installer) — for Desktop / Node.js install
- Node.js — for Web install; option 2/3 auto-installs it via winget if missing

## Quick Start

```powershell
powershell -ExecutionPolicy Bypass -File .\DeepSeek-Harness-Setup.ps1
```

> Tip: right-click the script folder → "Open in Terminal", or `cd` into the folder first.

## Notes

- The script file **must stay UTF-8 with BOM**, or Chinese text garbles in PowerShell 5.1.
- Third-party plugins/skills are run at your own risk — the author is not responsible for their content.
- Workspace layout follows DeepSeek Harness conventions: working directory `%USERPROFILE%`, data under `%USERPROFILE%\.dsh`.

## 免责声明 / Disclaimer

This script is provided "AS IS", for learning purposes, without warranty of any kind. Use of third-party plugins and skills is at your own risk.

## License

[MIT](./LICENSE)
---

# 中文

Windows 上一键安装与管理 [DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh) 的 PowerShell 脚本：桌面版、Web 版、插件、技能包，全部在一个交互式菜单里完成。

## 功能

- **安装 Desktop**：通过 winget 安装桌面客户端（稳定、推荐，无需 Node.js）
- **安装 Web 正式版 / 测试版**：自动检查并安装 Node.js，配置 npm `allow-scripts`，安装 pnpm，支持全局或自定义目录安装（自动添加用户 PATH）
- **插件管理**：管理 Desktop / Web 的 profile（`%USERPROFILE%\.dsh\profiles\desktop|web`），支持安装 / 卸载 / 一键更新 / 查看列表，可直接用记事本打开 `cordis.patch.yml` 和 `package.json`
- **Skill 管理**：从 ZIP（自动解压、识别单顶层文件夹）或文件夹安装到 `%USERPROFILE%\.dsh\skills`，支持删除 / 列表
- **启动 Web**：优先 `dsh web`，未检测到时自动回退 `npx`
- 中文描述 + 英文选项；每个操作结束后停顿显示结果，按回车返回菜单

## 环境要求

- Windows 10 / 11，自带 Windows PowerShell 5.1 即可
- winget（安装 Desktop / Node.js 用）；Web 安装需要 Node.js，缺了会自动装

## 快速开始

```powershell
powershell -ExecutionPolicy Bypass -File .\DeepSeek-Harness-Setup.ps1
```

## 注意事项

- 脚本文件必须保持 **UTF-8 with BOM** 编码，否则 PowerShell 5.1 下中文会乱码
- 第三方插件 / Skill 风险自负，与作者无关
- 工作目录为 `%USERPROFILE%`，数据目录为 `%USERPROFILE%\.dsh`

## 许可证

[MIT](./LICENSE)
