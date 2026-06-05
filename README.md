# Sakura Niri Dotfiles

这个仓库用于迁移当前 Ubuntu + niri 桌面环境。重点覆盖：

- niri 桌面配置、快捷键、窗口规则
- greetd + tuigreet 登录配置模板
- Waybar/Owlphin 主题和电源菜单入口
- wlogout 电源菜单主题
- fcitx5 拼音 + 五笔输入法配置
- fuzzel、mako、ghostty、NvChad 配置
- tmux + Oh my tmux 本地覆盖配置
- Emacs pgtk + Doom Emacs 私人配置
- 自定义脚本：`niri-layout`、`niri-fullscreen`、`niri-shortcuts-grid`、`niri-settings-menu`、
  `power-menu`、`screen-lock`、`niri-quit`、`wallpaper-random`、`niri-overview-wallpaper`
- niri overview 专用背景图

## 目录

```text
home/       # 对应 $HOME 下的配置，安装时会软链接到真实位置
system/     # 需要 sudo 安装的系统级模板
packages/   # apt 软件清单和手动安装说明
scripts/    # 外部包安装脚本
install.sh  # 新机器安装/软链接
sync.sh     # 从当前机器刷新仓库内容
check.sh    # 提交前校验
```

## 新机器安装

推荐从 Ubuntu Desktop 的默认安装开始。Server 版也能用，但需要补齐更多桌面组件，出现缺
portal、keyring、polkit、XWayland 集成等问题的概率更高。

先安装 Git 并克隆仓库：

```bash
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
```

### 推荐顺序

一键自动配置可以直接执行：

```bash
./bootstrap.sh
```

`bootstrap.sh` 会检测当前 Ubuntu 环境、已安装的 apt 包、命令行工具、niri、外部工具、用户配置
软链接和系统登录模板，只运行缺失的阶段。先查看将要执行的步骤：

```bash
./bootstrap.sh --dry-run
```

Doom Emacs 的完整安装默认会执行，以免首次启动 Emacs 时 Doom 包和 env 尚未初始化。
只想先跳过 Emacs 时：

```bash
./bootstrap.sh --skip-doom
```

下面是等价的手动顺序。这些脚本有依赖关系，排查问题时建议按下面顺序执行。

1. 安装 apt 包、构建工具和基础桌面组件：

```bash
./install.sh --packages
```

这一步是后续所有步骤的基础。它会安装 niri/Wayland 运行时依赖、开发工具、fcitx5、Waybar、
portal 后端、Rust/cargo、Doom/Emacs 支持包，并从源码安装 `xwayland-satellite`，用于 niri
下运行 Warp Terminal 等仍依赖 X11 后端的程序。

2. 安装外部包和非 apt 项：

```bash
./install.sh --external
```

这一步依赖 `--packages` 里的 `curl`、`jq`、`git`、`cargo` 等工具。它会安装 Chrome、Yazi、
swww/swww-daemon、Nerd Font Symbols、壁纸集合，以及 apt 中可用的 Ghostty。

3. 从源码构建并安装 niri：

```bash
./install.sh --niri-source
```

这一步依赖 `--packages` 里的 Rust 和 niri 构建依赖。需要指定版本时可以追加 ref，例如：

```bash
./install.sh --niri-source --ref v26.04
```

4. 安装用户配置和系统登录模板：

```bash
./install.sh --system
```

`--system` 会先执行默认的用户配置安装，再写入系统级模板：

- `/etc/greetd/config.toml`
- `/usr/share/wayland-sessions/niri.desktop`
- `/usr/local/bin/niri-session`

它还会把默认显示管理器设回 `greetd`，并禁用 `gdm/gdm3`。这一步应放在 niri 已经安装之后，
否则重启进入 niri 会话时可能找不到 `/usr/local/bin/niri`。

5. 安装 Doom Emacs 配置和包：

```bash
./install.sh --doom
```

这一步依赖 `--packages` 里的 Emacs、git、Python/Node 工具。它会再次确保用户配置已链接，然后
运行 Doom 的安装和环境同步。

执行完后重启，选择 niri 会话登录。

### 单独维护命令

只更新用户配置，不写系统模板：

```bash
./install.sh
```

只安装/更新自动壁纸集合：

```bash
./install.sh --wallpapers
```

默认会把 Catppuccin 壁纸集合浅克隆到
`~/Pictures/Wallpapers/catppuccin-wallpapers`，`wallpaper-random` 会递归扫描
`~/Pictures/Wallpapers`。

只补齐 niri 的 X11 兼容层：

```bash
./install.sh --xwayland-satellite
```

这通常不需要单独执行，因为 `--packages` 已经会调用它。

### 关于 `--all`

也可以在 niri 已经准备好的机器上使用：

```bash
./install.sh --all
```

它会依次执行 packages、external、用户配置、系统模板和 Doom 配置。niri 源码构建仍然单独使用
`./install.sh --niri-source`，因为它可能需要按机器选择 ref。新机器首次安装时不要直接用 `--all`
替代完整顺序，除非已经先安装好了 niri。

现有文件会先移动到 `~/.dotfiles-backup/<timestamp>/`。

## 上传到 GitHub

```bash
cd ~/dotfiles
git init
git add .
git commit -m "Initial niri desktop dotfiles"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```

如果还没配置 Git 身份：

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

## 日常更新

以后在系统里继续调整配置后，运行：

```bash
cd ~/dotfiles
./sync.sh
./check.sh
git status
```

确认没有敏感内容后再提交。

## 不纳入仓库的内容

- `*.backup-*` 历史备份
- fcitx5 缓存布局；Wayland 会话下不跟踪 `GTK_IM_MODULE`，避免和 fcitx5 的 Wayland frontend 冲突
- nvim 内部 `.git`
- Warp 登录状态和本地数据库
- 浏览器、VS Code、Zed 等应用缓存
- 私有网络代理地址，例如 `HTTP_PROXY=http://192.168...`；如需本机代理，可手动创建被忽略的 `home/.config/environment.d/proxy.conf`
- 大型二进制包，例如 Ghostty bundle、Yazi bundle、Codex bundle
- Oh my tmux 上游仓库不直接提交，由 `install.sh` 在新机器 clone 到 `~/.local/share/oh-my-tmux`
- Doom Emacs 上游框架不直接提交，由 `install.sh` clone 到 `~/.config/emacs`

更多需要手动安装的内容见 `packages/manual.md`。
