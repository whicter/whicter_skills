# claude_skills

Claude Code 的**跨项目通用 skill**。放在这里的东西对所有项目可见，
且和任何单个项目的代码无关。

## `xhs-reader` 做什么

**给它一个小红书链接，它把里面的内容全部变成文字。**

小红书的正文不是文本——图文帖的正文印在图片里，视频帖的正文是人在说话。
两种都读不了 Ctrl-F。这个 skill 做的就是把它们**统一还原成可读、可搜、可引用的文字**。

| 笔记类型 | 怎么读 | 你拿到什么 |
|---|---|---|
| **图文帖** | 按页下载图片，逐页读 | 每页正文（数字照抄原样）+ 作者写的 desc |
| **视频帖** | ① 抽音轨 → 语音转文字<br>② 抽关键帧 → 逐帧读画面 | **带时间轴的完整 script** + 逐帧画面摘要，两者对账后合并 |

视频为什么要两条腿一起走：口播视频里的图表、数字、参数表**只存在于画面上**，
只做语音转写会把数字全部漏掉——而数字往往正是你要的那部分。

它还有一条**汇报纪律**：数字必须精确、区分"作者主张"和"已验证事实"、
笔记内部前后不一致的地方要点名。这类内容常被拿去做决策，照抄结论
等于把作者的错误一起搬进来。

不登录任何账号，也不需要——内容本来就拿得到。

## 用到的库

| 环节 | 用什么 | 撰写时实测版本 |
|---|---|---|
| 抓页面、解析 | `curl` + `python3`（标准库正则，无第三方包） | 系统自带 |
| **视频解码 / 抽音轨 / 抽帧** | **FFmpeg**（`ffmpeg` + `ffprobe`） | 8.1.1 |
| **语音转文字** | **whisper.cpp**（`whisper-cli`），模型 `ggml-large-v3-turbo`（约 1.5 GB） | whisper-cpp 1.8.4 |
| 画面转文字（仅不能直接看图的 agent） | **Tesseract OCR** + `chi_sim` 中文包 | tesseract 5.5.2 |

几点说明：

- **没有 Python 第三方依赖**，不需要 venv、不需要 pip install。解析就是标准库 `re`。
- **FFmpeg 只做解复用和转码**，不重编码视频：抽音轨是 `-vn -ac 1 -ar 16000`
  （whisper 要求 16 kHz 单声道 PCM），抽帧是 `fps=1/N` 直接出 JPEG。所以很快。
- **whisper.cpp 是本地推理，不调任何云 API**，音频不出本机。模型按需下载到
  `~/.cache/whisper-models/`，只下一次。
- **Tesseract 只有 Codex 这类"不能自己打开磁盘图片"的 agent 才需要**。
  Claude Code 直接读图，不经过 OCR。

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

> **marketplace 是什么**：Claude Code 装扩展（plugin）的官方渠道。它**不是应用商店，
> 也不是任何在线服务**——就是一个 git 仓库，根目录放一个
> `.claude-plugin/marketplace.json` 当目录清单，列出"我这儿有哪些 plugin、各自在哪"。
> 别人 `add` 你的仓库地址，Claude Code 读那份清单，就知道能装什么。
> 没有审核、没有上架、不用注册，**推到 GitHub 就算发布了**。
>
> 三个名字别混：**marketplace**（仓库/货架，本仓库叫 `whicter-skills`）→
> 里面的 **plugin**（一个可安装单元，这里叫 `xhs-reader`）→ plugin 里的
> **skill**（真正干活的 `SKILL.md`，这里也叫 `xhs-reader`）。
> 所以安装命令读作「从 `whicter-skills` 这个货架上装 `xhs-reader`」。

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

| 环境 | 图文笔记 | 视频笔记 | 入口 |
|---|---|---|---|
| **Claude Code**（CLI / 桌面 / IDE） | ✅ | ✅ | `SKILL.md`，自动触发 |
| **Codex / Cursor / 其它带 shell 的 agent** | ⚠️ 走 OCR | ✅ 语音<br>⚠️ 画面走 OCR | [`AGENTS.md`](AGENTS.md)（**未在真实 Codex 上实测**） |
| Claude.ai 网页版 / 手机 App | ❌ | ❌ | 沙箱访问不了 xiaohongshu.com |

取数这一层是**纯 `curl` + `python3`，任何有 shell 的 agent 都一样**——
`__INITIAL_STATE__` 是服务端渲染在 HTML 里的，不需要浏览器执行 JS。

> 本 README 2026-08-17 上午还写着"必须有真浏览器，别的 agent 要重做一半"。
> 当天下午一条 `curl` 就推翻了它：875KB HTML 里数据齐全，抽出的图片 URL
> 与浏览器路径逐条一致。**那个错误前提让这份 skill 白白独占了 Claude Code。**

真正划分能力边界的不是取数，是**读图**：图文笔记的正文几乎全在图片里。
能直接看图的 agent（Claude Code）逐页读；不能的（Codex 只接受用户上传的图，
agent 不能自己打开磁盘上的图）走 `tesseract` OCR——实测**数字很准、中文偶有单字错、
带 `≥` 的行可能整行漏掉**，细节和注意事项写在 `AGENTS.md`。

操作系统方面无限制：macOS / Linux 都可以（2026-08-17 已移除原先唯一的 macOS
专有依赖 `sips`）。Windows 需要 WSL 或自行替换 shell 命令。

## 依赖

| 用途 | 需要 | 装法 |
|---|---|---|
| 抓取 + 解析（一切的前提） | `curl`、`python3` | 系统自带 |
| 读**视频**笔记 | `ffmpeg`、`ffprobe`、`whisper-cli` | macOS：`brew install ffmpeg whisper-cpp`；Debian/Ubuntu：`apt install ffmpeg` + 自行编译 [whisper.cpp](https://github.com/ggerganov/whisper.cpp)（注意其二进制可能叫 `main` 或 `whisper-cli`，按需改命令） |
| **OCR**（只有不能直接看图的 agent 需要） | `tesseract` + 中文包 | macOS：`brew install tesseract tesseract-lang`；Debian/Ubuntu：`apt install tesseract-ocr tesseract-ocr-chi-sim` |

只读图文、且 agent 能看图的话，`curl` + `python3` 就够了。
skill 自己会在开工前探测并报缺什么。

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
| `xhs-reader` | **把小红书笔记全部转成文字**：图文帖逐页读图，视频帖做语音转写 + 关键帧读画面，合成带时间轴的完整 script。不登录账号 |

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
