# pc_setup

交互式新电脑初始化脚本（macOS / Linux 最小可用版）。

## 功能

- 按分段交互（每段 `y/n`）执行初始化。
- 启动时自动检测 GitHub 连通性；不可达时优先引导 FlClash + 代理配置。
- 可选安装：`git`、`nodejs`、`cmake`、`vscode`、`claude cli`。
- 可选安装：`Claude settings`（`git clone https://github.com/feiskyer/claude-code-settings.git ~/.claude`）。
- 可选安装：`copilot-api`（`npm install -g copilot-api`）。
- 可选配置：`zsh`、`oh-my-zsh`、主题与常用插件。
- 可选执行：尝试把默认登录 shell 切换到 `zsh`（失败仅提示，不中断）。

## 支持范围

- macOS：通过 Homebrew 安装。
- Linux：当前最小版本仅保证 apt 系（如 Ubuntu/Debian）可用。

> Linux 其他发行版（dnf/pacman）可在后续版本扩展。

## 使用方式

```bash
chmod +x ./bootstrap.sh
./bootstrap.sh
```

## 发布到 GitHub / GitHub Pages

```bash
chmod +x ./publish.sh
./publish.sh
```

脚本会：

- 初始化本地 git 仓库并提交。
- 设置 `origin` 为你的 `owner/repo`。
- 推送到 `main` 分支。
- 若检测到已登录的 `gh`，会自动创建仓库（若不存在）并尝试启用 Pages（`main` + `/docs`）。

发布后可用一行命令执行：

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/bootstrap.sh | bash
```

## 交互分段

脚本会依次询问你是否执行以下段落：

1. 网络预检（GitHub 可达性）与代理引导（不可达时优先 FlClash + 代理 URL）
2. 基础开发工具（git/nodejs/cmake）
3. VS Code
4. Claude CLI
5. Claude settings（`~/.claude`）
6. copilot-api（`npm -g`）
7. zsh
8. oh-my-zsh
9. oh-my-zsh 主题与插件（默认 `robbyrussell` + `git zsh-autosuggestions zsh-syntax-highlighting`）
10. 默认 shell 切换为 zsh

## 幂等行为

- 已安装的软件会自动跳过。
- `~/.zshrc` 中主题和插件配置会更新，不会无限重复追加。
- 插件目录已存在时不会重复克隆。

## 说明

- Claude CLI 使用官方命令安装：`curl -fsSL https://claude.ai/install.sh | bash`。
- Claude settings 使用仓库安装到 `~/.claude`；若目录已是该仓库会自动 `git pull --ff-only` 更新。
- copilot-api 使用 npm 全局安装：`npm install -g copilot-api`。
- GitHub 不可达时，脚本会优先尝试安装 FlClash（macOS 会先尝试 `brew install --cask flclash`，失败则引导你输入安装包 URL）。
- 代理 URL 需要输入为 `http://`、`https://` 或 `socks5://` 开头，并可选择写入 `~/.zshrc` 持久化。
- 若某步骤失败，脚本会记录失败项并继续执行后续步骤。
- 执行结束会输出成功 / 失败 / 跳过汇总。