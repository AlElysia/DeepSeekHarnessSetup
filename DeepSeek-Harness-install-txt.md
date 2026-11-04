
```text
DeepSeek-Harness-安装与启动教程.md
```

---

# DeepSeek Harness（dsh）安装与启动教程

> 适用环境：Windows / macOS / Linux  
> 目标：把 `@deepseek-ai/dsh` 安装到合适的位置，并能正常启动 `dsh web`。  
> 推荐顺序：**优先项目内安装**；确实需要全局命令时，再配置全局安装和 PATH。

---

## 0. 先选安装方式

| 方式 | 适合场景 | 优点 | 注意点 |
|---|---|---|---|
| **项目内安装（推荐）** | 只想在一个项目里使用 dsh | 包永久保存在项目里，不污染全局，不怕 npx 缓存被清理 | 启动时要进入项目目录，或使用 `npm start` |
| **全局安装** | 希望任意目录都能直接运行 `dsh` | 命令全局可用 | 必须正确配置 npm `prefix` 和系统 `PATH` |
| **npx 临时运行** | 临时试用 | 不用手动安装 | 缓存可能被清理，不便于管理 |

---

## 1. 准备工作

先确认 Node.js 和 npm 已安装：

```bash
node -v
npm -v
```

如果两条命令都能输出版本号，说明环境正常。

> 修改环境变量后，必须**关闭终端并重新打开**，否则新配置不会生效。

---

## 2. 推荐方案：安装到项目目录

这种方式最稳，不会出现“全局命令找不到”的问题。

### 2.1 创建项目并安装

#### Windows PowerShell

```powershell
New-Item -ItemType Directory -Force D:\my-project
Set-Location D:\my-project
npm init -y
npm install @deepseek-ai/dsh
```

#### macOS / Linux

```bash
mkdir -p ~/my-project
cd ~/my-project
npm init -y
npm install @deepseek-ai/dsh
```

安装完成后，目录大致如下：

```text
my-project/
├── node_modules/          # dsh 及其依赖都在这里
├── package.json
└── package-lock.json
```

### 2.2 启动 dsh

在项目目录下运行：

```bash
npx dsh web
```

也可以把启动命令写进 `package.json`：

```json
{
  "scripts": {
    "start": "dsh web"
  }
}
```

以后在项目目录下直接运行：

```bash
npm start
```

### 2.3 如果安装时提示“是否允许执行安装脚本”

npm 可能会要求确认部分依赖的安装脚本。与 dsh 相关的常见包如下：

| 包名 | 脚本作用 | 建议 |
|---|---|---|
| `@deepseek-ai/dsh-subprocess-local` | dsh 子进程辅助工具 | 允许 |
| `@google/genai` | 基本为空操作 | 允许 |
| `koffi` | FFI 原生模块编译 | 允许 |
| `node-pty` | 终端模拟库，需要编译 C++ | 允许 |
| `protobufjs` | Protocol Buffers 相关后处理 | 允许 |

> 注意：不同 npm 版本对“安装脚本审批”的命令不同。下面命令如果你的 npm 支持可直接用；如果不支持，请以终端实际提示为准。

如果 npm 支持 `install-scripts`：

```bash
npm install-scripts approve @deepseek-ai/dsh-subprocess-local
npm install-scripts approve @google/genai
npm install-scripts approve koffi
npm install-scripts approve node-pty
npm install-scripts approve protobufjs
```

或一次性批准：

```bash
npm install-scripts approve --all
```

批准后重新安装：

```bash
npm install
```

如果安装时使用了 `--allow-scripts` 参数，也可以按实际提示保留对应包名。若不确定，重新运行 `npm install`，按终端提示选择允许即可。

---

## 3. 可选方案：全局安装 dsh

只有你确实需要“在任意目录直接运行 `dsh`”时，才建议使用全局安装。

### 3.1 方法一：临时指定安装目录（单次安装）

#### Windows

```powershell
npm install -g @deepseek-ai/dsh --prefix "C:\DeepSeek Harness"
```

如果安装时提示需要允许脚本，并且你的 npm 支持 `--allow-scripts`，可使用类似命令：

```powershell
npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh --prefix "C:\DeepSeek Harness"
```

#### macOS / Linux

```bash
npm install -g @deepseek-ai/dsh --prefix "$HOME/my-npm-global"
```

> 临时 `--prefix` 只影响本次安装，不改变 npm 全局配置。  
> 安装后如果要在终端直接输入 `dsh`，仍然需要把对应目录加入 `PATH`，或者使用完整路径运行。

---

### 3.2 方法二：永久修改 npm 全局安装目录

#### Windows

```powershell
npm config set prefix "D:\npm-global"
npm config get prefix
```

#### macOS / Linux

```bash
npm config set prefix "$HOME/.npm-global"
npm config get prefix
```

然后安装：

```bash
npm install -g @deepseek-ai/dsh
```

如果提示需要批准安装脚本，按第 2.3 节处理。

---

### 3.3 关键步骤：把全局目录加入 PATH

#### Windows

1. 按 `Win + R`，输入 `sysdm.cpl`，回车。
2. 打开“高级” → “环境变量”。
3. 在“用户变量”中找到 `Path`，点击“编辑”。
4. 点击“新建”，填入 `npm config get prefix` 输出的目录本身。
   - 例如：`D:\npm-global`
   - 或：`C:\DeepSeek Harness`
5. 一路点击“确定”保存。
6. **关闭所有终端，重新打开一个新终端。**

> Windows 下可执行文件通常直接位于 `{prefix}` 目录下，**没有 `bin` 子目录**。  
> 不要把 `node_modules\.bin` 当作全局 PATH 目录。

#### macOS / Linux

在 shell 配置文件中追加 PATH，例如 `~/.zshrc`、`~/.bashrc` 或 `~/.profile`：

```bash
export PATH="$HOME/.npm-global/bin:$PATH"
```

保存后执行：

```bash
source ~/.zshrc
```

或者直接关闭并重新打开终端。

> macOS / Linux 下可执行文件位于 `{prefix}/bin`，所以 PATH 要指向 `bin` 子目录。

---

### 3.4 验证全局安装

重新打开终端后运行：

```bash
# 查看 npm 全局目录
npm root -g
npm prefix -g

# 查找 dsh 命令位置
# Windows PowerShell
Get-Command dsh -All
# Windows CMD
where dsh
# macOS / Linux
which dsh

# 查看版本
dsh --version

# 启动 Web UI
dsh web
```

如果 `where dsh` 或 `which dsh` 能指向你配置的目录，并且 `dsh --version` 正常输出版本号，就说明 PATH 配置成功。

---

## 4. 常见问题排查

### 问题 1：提示 `dsh` 不是内部或外部命令 / command not found

常见原因：

1. 自定义全局目录没有加入 `PATH`；
2. 修改 PATH 后没有重新打开终端；
3. 系统里有多份 dsh，PATH 顺序不对；
4. 安装失败，目录下根本没有生成 `dsh` 可执行文件。

处理顺序：

```bash
npm prefix -g
npm root -g
where dsh
```

确认 `dsh` 实际安装位置，再检查该位置是否在 PATH 中。

---

### 问题 2：`dsh` 命令存在，但启动失败

可能是原生依赖没有正确编译，或安装脚本没有被允许。

可以尝试：

```bash
npm rebuild
```

然后重新运行：

```bash
dsh web
```

如果仍然失败，回到安装步骤，确认 `koffi`、`node-pty` 等包的安装脚本已允许执行。

---

### 问题 3：不想折腾 PATH，怎么办？

可以直接在项目里运行：

```bash
npx dsh web
```

或者临时使用：

```bash
npx --yes @deepseek-ai/dsh web
```

项目内安装方式不需要配置全局 PATH，最适合新手。

---

### 问题 4：清理旧的 npx 缓存（可选）

项目安装完成后，旧 npx 缓存可以清理。先确认路径，再执行：

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\npm-cache\_npx" -ErrorAction SilentlyContinue
```

如果你的缓存路径不同，请替换为实际路径。清理缓存不是必需步骤。

---

## 5. 最短流程总结

### 推荐：项目内安装

```bash
mkdir my-project
cd my-project
npm init -y
npm install @deepseek-ai/dsh
npx dsh web
```

或者在 `package.json` 中配置：

```json
{
  "scripts": {
    "start": "dsh web"
  }
}
```

然后运行：

```bash
npm start
```

### 全局安装

```bash
npm config set prefix "你的全局目录"
npm install -g @deepseek-ai/dsh
# 把“你的全局目录”加入 PATH
# Windows 加入目录本身；macOS/Linux 加入该目录下的 bin
# 重新打开终端
dsh --version
dsh web
```

---

## 6. 一句话建议

**新手优先用“项目内安装 + `npx dsh web` / `npm start`”。**  
只有确实需要全局命令时，再配置 `npm prefix` 和 `PATH`；配置完一定重新打开终端。


---
