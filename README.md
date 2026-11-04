# DeepSeek-Harness-Setup

**English** | [中文](README.zh-CN.md)

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
