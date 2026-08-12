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

## 安装（新机器 / 新环境）

```bash
git clone <this repo> ~/Documents/claude_skills
~/Documents/claude_skills/install.sh
```

`install.sh` 做的事：把 `~/.claude/skills` 指向本仓库的 `skills/`。
之后**所有项目**（现有的和以后新建的）都能用，不需要每个项目单独配置。

脚本是幂等的，重复跑没有副作用；如果 `~/.claude/skills` 已经是一个装了东西的
真实目录，它会拒绝覆盖并提示你先自行处理，不会静默删掉任何文件。

## 目录结构

```
claude_skills/
├── README.md
├── install.sh
└── skills/            ← ~/.claude/skills 指向这里
    └── xhs-reader/
        └── SKILL.md
```

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
