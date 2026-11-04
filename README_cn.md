## DeepSeek-Harness 自动部署脚本与配置
要求：
（1）`主菜单`开头添加 描述说明与免责声明，还有作者
（2）描述使用中文，选项使用英文（English）
（3）`主菜单`添加 没有异议请选择第一个安装，更方便
（4）`主菜单`'m';退出'q'
（5）`主菜单`和`子菜单`，添加键盘输入提示
（6）进入工作目录当前"%USERPROFILE%", '%USERPROFILE%/.dsh'

`主菜单`选项
1.安装 DeepSeek-Harness Deaktop(推荐使用，稳定)
2.安装 DeepSeek-Harness web 正式版(性能较好，可用)
3.安装 DeepSeek-Harness web 测试版(不推荐，不稳定)
4.DeepSeek-Harness Deaktop 管理
5.DeepSeek-Harness web 管理
6.DeepSeek-Harness skill 管理
7.start dsh web
8.退出'q'

### `主菜单`操作
1.安装 DeepSeek-Harness Deaktop
使用 winget install 源安装，完成后返回`主菜单`

2.安装 DeepSeek-Harness web
 - 先检查node.js命令是否安装，是就`跳过`,不是就`winget install`  node.js
 - 安装后，询问是否允许执行脚本@pnpm 和 @deepseek-ai/dsh两个包脚本 输入 y or n，n--> `主菜单`不安装
 - npm config set allow-scripts=pnpm --location=user and npm config set allow-scripts=deepseek-ai --location=user
 - (npm install -g pnpm) and (npx @deepseek-ai/dsh web)

3.安装 DeepSeek-Harness web
 - 先检查node.js命令是否安装，是就`跳过`,不是就`winget install`  node.js
 - 1.安装后，询问是否允许执行脚本@pnpm 和 @deepseek-ai/dsh两个包脚本 输入 y or n，n--> `主菜单`不安装
 - 2.@deepseek-ai是否要全局安装，输入 y or n，n-->自定义目录添加参数--prefix "<你的目录>"
 - npm config set allow-scripts=pnpm --location=user and npm config set allow-scripts=deepseek-ai --location=user
 - (npm install -g pnpm) and (npm install -g @deepseek-ai/dsh or npm install -g @deepseek-ai/dsh --prefix "")
 - `自定义目录`添加用户环境变量;`全局`不管

6.DeepSeek-Harness skill 管理
 - `.ssh/`目录下添加文件夹名'skill'，如有则不
 - 新`子菜单`,选项1.install 2.remove/uninstall 3.查看list-->文件夹名 7.`主菜单` 8.退出'q'
 - 1.install，添加描述，选择zip或者目录拖入窗口，zip-->解压skill下；目录-->复制skill下
 - 2.remove/uninstall，删除单个skill文件夹，包含子文件及目录


### `子菜单`
4.DeepSeek-Harness Deaktop 管理
(1)`/.dsh/profiles/desktop`进入目录
(2)`子菜单`添加描述`插件`功能、用途
选项
1.install--> pnpm install
2.remove/uninstall--> pnpm remove
3.一键更新upgrade--> pnpm upgrade
4.插件list--> pnpm list
5.open 用户配置-->notepad cordis.patch.yml
6.open 包管理--> notepad package.json
7.返回上一个菜单'q'

5.DeepSeek-Harness web 管理
(1)`/.dsh/profiles/web`进入目录
(2)添加描述同理
(3)选项菜单desktop同理

### `子菜单`操作
1.install
 - pnpm install
 - 添加描述，填入插件链接地址或者名称，免责声明与作者无关，自行承担风险
 - 或者本地安装，填入目录地址
 - 返回上一个菜单'q'
2.remove/uninstall
 - pnpm remove
 - 添加描述，填入插件名称
 - 返回上一个菜单'q'

4.插件list
 - 显示已安装插件数量：'x'
 - 返回上一个菜单'q'