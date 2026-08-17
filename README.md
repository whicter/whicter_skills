# claude_skills

Claude Code 的**跨项目通用 skill**。放在这里的东西对所有项目可见，
且和任何单个项目的代码无关。

## 为什么单独一个 repo

第一个 skill（`xhs-reader`）原本写在 `quantrift_index_future/.claude/skills/` 下，
靠一条 symlink 提到用户级。这样有两个问题：

1. **交易 repo 承载了与交易无关的东西** —— 读小红书跟指数期货没有关系
2. **换机器带不过去** —— `~/.claude/` 不在任何 repo 里，新机器上 skill 直接消失，
   而且**不会报错**，只是安静地不存在

独立 repo 之后，新机器只需 clone + 跑一次 `install.sh`。

## 安装

### 方式一：symlink（维护者自己 / 新机器）

```bash
git clone <this repo> ~/Documents/claude_skills
~/Documents/claude_skills/install.sh
```

`install.sh` 把 `~/.claude/skills` 指向本仓库的 `skills/`。之后**所有项目**
（现有的和以后新建的）都能用，不需要每个项目单独配置。改完 `SKILL.md` 立即生效，
不用重装——适合还在迭代的人。

脚本是幂等的，重复跑没有副作用；如果 `~/.claude/skills` 已经是一个装了东西的
真实目录，它会拒绝覆盖并提示你先自行处理，不会静默删掉任何文件。

### 方式二：plugin marketplace（给别人用）

不用 clone，在 Claude Code 里两条命令：

```
/plugin marketplace add whicter/claude_skills
```

```
/plugin install xhs-reader@whicter-skills
```

装完如果提示 `Run /reload-plugins to activate.`，跑一下 `/reload-plugins`。
更新用 `/plugin marketplace update`。

两种方式**不要同时用**——skill 会被发现两遍。自己开发用方式一，分发给别人用方式二。

## 兼容性

| 环境 | 能不能用 |
|---|---|
| **Claude Code**（CLI / 桌面 / IDE 插件） | ✅ 唯一支持的环境 |
| Claude.ai 网页版 / 手机 App | ❌ 沙箱里没有浏览器工具，也访问不了 xiaohongshu.com |
| **Codex、Cursor、其它 agent** | ❌ 见下 |

`xhs-reader` 依赖 Claude Code 内建的 Browser 工具（`mcp__Claude_Browser__*`）——
小红书正文是 JS 渲染后才存在于 `__INITIAL_STATE__` 里的，**必须有个真浏览器执行
JS 才拿得到**，`curl` 和 WebFetch 都不行。别的 agent 要用，得先自己接一个
Playwright/Puppeteer 类的 MCP，再把 SKILL.md 的第一、二步重写；`AGENTS.md`
格式的差异反而是小事。**这是重做一半，不是移植。**

操作系统方面无限制：macOS / Linux 都可以（2026-08-17 已移除原先唯一的 macOS
专有依赖 `sips`）。Windows 需要 WSL 或自行替换 shell 命令。

## 依赖

| 用途 | 需要 | 装法 |
|---|---|---|
| 读**图文**笔记 | `curl` | 系统自带 |
| 读**视频**笔记 | `ffmpeg`、`ffprobe`、`whisper-cli` | macOS：`brew install ffmpeg whisper-cpp`；Debian/Ubuntu：`apt install ffmpeg` + 自行编译 [whisper.cpp](https://github.com/ggerganov/whisper.cpp)（注意其二进制可能叫 `main` 或 `whisper-cli`，按需改命令） |

只读图文的话装不装 ffmpeg 无所谓。skill 自己会在开工前探测并报缺什么。

whisper 模型（约 1.5GB）由 skill 按需下载到 `~/.cache/whisper-models/`，
**不入库**，也不会重复下载。

## 目录结构

```
claude_skills/
├── README.md
├── LICENSE
├── install.sh
├── .claude-plugin/     ← 方式二用；方式一完全不碰它
│   ├── marketplace.json
│   └── plugin.json
└── skills/             ← 方式一：~/.claude/skills 指向这里
    └── xhs-reader/
        └── SKILL.md
```

仓库根目录同时是一个合法的 plugin 根（plugin 约定就是 `<根>/skills/<名字>/SKILL.md`），
所以 `marketplace.json` 里的 `source` 写 `"./"` 即可，**不需要为了发布重排目录**。

`skills/` 是单独一层，**不要把 README 之类的文件混进去** —— 那一层的每个子目录
都会被当作一个 skill 去发现。

## 加一个新 skill

```bash
mkdir -p skills/<名字> && $EDITOR skills/<名字>/SKILL.md
```

`SKILL.md` 开头必须是 YAML frontmatter：

```markdown
---
name: <名字>            # 与目录名一致
description: <一句话说明做什么，以及**什么时候该用它**>
---
```

`description` 决定 Claude 会不会在该用的时候想起它，所以要写触发条件
（"当用户发来 xxx 链接、要求 yyy 时使用"），而不只是功能描述。

新增之后不用重跑 `install.sh` —— 目录是 symlink，加进来就可见。
但**要把它加进下面的「当前 skill」表**：`./install.sh --check` 会校验
README 清单、`skills/` 下的实际目录、以及每个 `SKILL.md` 的 `name`/`description`
三者是否一致，漏了会报出来。这个校验在每次 `install.sh` 结束时自动跑一遍。

## 当前 skill

| 名字 | 用途 |
|---|---|
| `xhs-reader` | 读小红书笔记全文：图文逐页、视频整片转写。绕过登录墙（不登录账号） |

## 约定

- **不放任何项目专属的东西**。只服务某一个 repo 的 skill 应该留在那个 repo 的
  `.claude/skills/` 下。
- **不放密钥、token、账号**。这个 repo 可能会被 push 到公开位置。
- **大文件（模型、缓存）不入库**，写进 skill 文档里让它按需下载到
  `~/.cache/` 下的固定位置——见 `xhs-reader` 里 whisper 模型的处理方式：
  下到会话临时目录意味着**每开一次新对话就重下一遍**（实测 1.5GB）。
- **写进 SKILL.md 的命令必须真跑过一遍**。这不是洁癖：2026-08-16 那次
  凭经验写的抽帧命令有两条是坏的（`metadata=print` 配 `fps` 输出空文件、
  场景检测必丢封面帧），而且 2026-08-17 才发现「Read 读不了 webp」这个
  沿用已久的前提根本不成立——多出来的转换步骤白白让这份 skill 绑死在 macOS 上。
  **没验证的一句话，会以"实测有效"的语气活很久。**
- **新增 skill 时别忘了同步 `.claude-plugin/marketplace.json`**，
  否则用方式二安装的人看不到它。`install.sh --check` 目前只校验 README 清单和
  frontmatter，**不检查 marketplace.json**。

## 许可

MIT，见 [LICENSE](LICENSE)。
