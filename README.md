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
- 自定义脚本：`niri-shortcuts-grid`、`niri-quit`、`wallpaper-random`、`niri-overview-wallpaper`
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

先安装 Git 并克隆仓库：

```bash
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
```

安装软件包：

```bash
./install.sh --packages
```

安装外部包和非 apt 项：

```bash
./install.sh --external
```

从源码构建并安装 niri：

```bash
./install.sh --niri-source
```

需要 screencast/屏幕共享时，可以额外安装 GNOME portal：

```bash
./install.sh --niri-source --with-gnome-portal
```

安装用户配置：

```bash
./install.sh
```

安装 Doom Emacs 配置和包：

```bash
./install.sh --doom
```

安装系统级 greetd/niri-session 模板：

```bash
./install.sh --system
```

`--system` 会写入：

- `/etc/greetd/config.toml`
- `/usr/share/wayland-sessions/niri.desktop`
- `/usr/local/bin/niri-session`

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
- fcitx5 缓存布局
- nvim 内部 `.git`
- Warp 登录状态和本地数据库
- 浏览器、VS Code、Zed 等应用缓存
- 本机代理地址，例如 `HTTP_PROXY=http://192.168...`
- 大型二进制包，例如 Ghostty bundle、Yazi bundle、Codex bundle
- Oh my tmux 上游仓库不直接提交，由 `install.sh` 在新机器 clone 到 `~/.local/share/oh-my-tmux`
- Doom Emacs 上游框架不直接提交，由 `install.sh` clone 到 `~/.config/emacs`

更多需要手动安装的内容见 `packages/manual.md`。
