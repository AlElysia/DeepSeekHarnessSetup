# DeepSeek-Harness-Setup

**中文** | [English](README.md)

Windows 上一键安装与管理 [DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh) 的 PowerShell 脚本：桌面版、Web 版、插件、技能包，全部在一个交互式菜单里完成。

## 功能

- **安装 Desktop**：通过 winget 安装桌面客户端（稳定、推荐，无需 Node.js）
- **安装 Web 正式版 / 测试版**：自动检查并安装 Node.js，配置 npm `allow-scripts`；先检测 pnpm——已安装就跳过，未安装则在**切换 prefix 之前**用 npm 默认全局目录安装，绝不装进 dsh 的自定义目录；自定义目录走 `npm config set prefix`（绝不传 `--prefix`，实测会损坏文件），PATH / NODE_PATH 随安装自动写入（不再单独设置 npm 环境），并探测 `dsh` 实际位置
- **更新 DSH Web**：PATH 里找不到 `dsh` 时先去各全局目录扫 `node_modules\@deepseek-ai\dsh` 确认它装在哪（都找不到再让用户输入目录），再把 `npm config set prefix` 指向其目录并执行 `npm update -g`，结束后把 npm prefix 精确恢复成更新前的配置（原来没设 → `npm config delete prefix`；原来有自定义值 → `npm config set prefix <原值>`）。直接在包目录里更新只会 remove 文件，不会更新
- **插件管理**：管理 Desktop / Web 的 profile（`%USERPROFILE%\.dsh\profiles\desktop|web`），支持安装 / 卸载 / 一键更新 / 查看列表，可直接用记事本打开 `cordis.patch.yml` 和 `package.json`
- **Skill 管理**：从 ZIP（自动解压、识别单顶层文件夹）或文件夹安装到 `%USERPROFILE%\.dsh\skills`，支持删除 / 列表
- **启动 Web**：优先 `dsh web`（通过 `Get-Command dsh` 与常见 prefix 目录探测），未检测到时自动回退 `npx`
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

## 免责声明

本脚本按“原样”提供，仅供学习交流，不附带任何形式的保证；第三方插件与 Skill 的使用风险由用户自行承担，与作者无关。

## 许可证

[MIT](./LICENSE)
