# 读小红书笔记（Codex / 其它 agent 版）

用户发来 `xiaohongshu.com` 或 `xhslink.cn` 链接、要求"看看这个""总结这篇"时，
按本文件操作。

**完整流程见 [`skills/xhs-reader/SKILL.md`](skills/xhs-reader/SKILL.md)——先把它读一遍。**
那份是唯一权威，本文件只写 Codex 与 Claude Code 的**差异**，不重复正文，
免得两边各说各话。

## 能做到哪一步

| | Codex |
|---|---|
| 抓页面 + 提取（第一、二步） | ✅ 纯 `curl` + `python3`，与 Claude Code 完全一样 |
| 视频语音转写（4A） | ✅ 纯 shell，一样 |
| 视频关键帧抽取（4B 抽帧） | ✅ 抽得出来 |
| **读图**（图文正文 / 视频帧画面） | ⚠️ **要走 OCR**，见下 |

## 差异一：跳过浏览器兜底

SKILL.md 里"兜底：浏览器路径"那一节用的是 Claude Code 内建工具，**Codex 没有，跳过**。
`curl` 那条路是主路径，本来就不需要浏览器。

真遇到 `curl` 拿不到的情况（小红书改了渲染或加了反爬），Codex 侧的等价物是自己接一个
Playwright/Puppeteer 类 MCP（`codex mcp` 可加）。**在那之前不要假装读到了内容**——
按 SKILL.md 的汇报纪律，拿不到就说拿不到。

## 差异二：读图改成 OCR

Codex 的图片输入是**用户上传**（`--image` 或粘贴到输入框），
agent **不能自己打开刚下载到磁盘的图**。而图文笔记的正文几乎全在图里，
所以这一步要换成 OCR。

```bash
# 需要 tesseract 及中文语言包：
#   macOS        brew install tesseract tesseract-lang
#   Debian/Ubuntu apt install tesseract-ocr tesseract-ocr-chi-sim
for f in p*.webp; do
  ffmpeg -y -loglevel error -i "$f" "${f%.*}.png"      # CDN 混着 webp/JPEG，统一转一道
  echo "===== $f ====="
  tesseract "${f%.*}.png" - -l chi_sim 2>/dev/null | grep -v '^[[:space:]]*$'
done
```

视频帧（4B 抽出来的 `f_*.jpg`）同理，把上面的 glob 换掉即可。

### OCR 的实测质量（2026-08-17，真实笔记三页）

**数字非常可靠，中文偶有单字错。**

- 表格页：`1325.76` `5/23` `168天` `-7.70%` `-15.99%` —— **每一个数字都正确**
- 点位页：`7610` `7230` `7000` `6850` `7406` —— **全对**
- 装饰字体封面：`Be Bpave to The World`（应为 `Brave`）
- 中文错字：`8月下旬` → `8月王旬`、`见顶` → `见项`、`选举前` → `和洗举前`
- **漏行**：第一张表的表头 `年份 主要高点 跌至≥5% 距选举` 整行没识别出来
  （`≥` 这类符号容易让整行丢掉）

因此：

1. **数字可以直接用**，这是最要紧的部分，OCR 在这上面表现很好。
2. **中文按上下文纠错**，别把 `王旬`/`见项` 当作者原文引用。
   拿不准的字**标出来**，不要默默改成你以为的样子。
3. **警惕整行漏识别**。OCR 出来的表格行数要和肉眼预期对一下；
   表头和带特殊符号（`≥` `≈` `→`）的行最容易整行消失。
   **漏掉的行不会报错，它只是不在了**——这是 OCR 路径最危险的失败模式。
4. 汇报时**注明内容来自 OCR**。SKILL.md 的汇报纪律要求区分"读到的"和"推断的"，
   OCR 属于前者但有误差，读者有权知道。

如果用户能自己把图发进来（Codex 支持上传），那比 OCR 准得多——
**值得主动提一句**，尤其是笔记里有关键数字、而 OCR 结果看起来可疑的时候。

## 安装

Codex 只在**工作目录**（及其父目录）和 `~/.codex/AGENTS.md` 找这个文件。

```bash
git clone https://github.com/whicter/whicter_skills.git ~/whicter_skills
# 全局生效（会覆盖已有的 ~/.codex/AGENTS.md，先看一眼）
cat ~/whicter_skills/AGENTS.md >> ~/.codex/AGENTS.md
```

注意本文件用相对路径引用 `skills/xhs-reader/SKILL.md`。放到 `~/.codex/` 之后
那个相对路径就不成立了——**把它改成 clone 后的绝对路径**，否则 Codex 找不到正文。

## ⚠️ 未在 Codex 上实测

本文件的 Codex 部分是**按能力推导写的，没有在真实 Codex 会话里跑过**
（写它的机器上没装 Codex）。已经实测过的只有那些与 agent 无关的部分：
`curl` 取数、`python3` 提取、`ffmpeg` 抽帧、`tesseract` OCR——这些在任何 shell 里
行为都一样。**没验证的是 Codex 会不会按本文件行事、以及它的沙箱允不允许外网访问。**
第一次用请人工核对结果。
