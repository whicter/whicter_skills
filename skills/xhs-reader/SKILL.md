---
name: xhs-reader
description: 读取小红书（xiaohongshu / xhslink.cn）笔记的完整内容——图文笔记逐页读图，视频笔记做全片语音转写 + 关键帧逐帧读画面 + 整理带时间轴的完整 script。当用户发来 xhslink.cn 短链或 xiaohongshu.com 链接、要求"看看这个""研究一下这个""总结这篇""把视频内容整理出来"时使用。
---

# 读小红书笔记（图文 + 视频）

**核心事实：小红书正文在登录墙后面，但内容拿得到——不需要登录。**

WebFetch 拿不到（内容是 JS 渲染的），`get_page_text` 只能拿到标题和评论。
**真正的内容在页面的 `__INITIAL_STATE__` 里**：图文笔记的每页图片 URL、
视频笔记的 desc 和视频流地址，全都在那个 script 标签中。

> 不要因为第一次 WebFetch 失败就回复"拿不到"。本文档里的每一步都实测有效。
> 绝不登录用户的小红书账号——不需要，也不允许。

## 前置条件

| 要读的东西 | 需要 | 缺了会怎样 |
|---|---|---|
| **任何笔记**（第一、二步） | Claude Code 的 Browser 工具（`mcp__Claude_Browser__*`）+ `curl` | 没有浏览器就**整个做不了**：正文是 JS 渲染的，`curl`/WebFetch 拿不到 |
| **图文笔记**（第三步） | 无额外依赖 | — |
| **视频笔记**（第四步） | `ffmpeg`、`ffprobe`、`whisper-cli` | 4A/4B 全挂。装：`brew install ffmpeg whisper-cpp`（macOS）/ 见 README |

**开工前先探一次**，别做到一半才发现缺工具：

```bash
for c in curl ffmpeg ffprobe whisper-cli; do printf '%-12s %s\n' "$c" "$(command -v $c || echo '缺')"; done
```

视频笔记而 `ffmpeg`/`whisper-cli` 缺失时：**直说缺什么、给出安装命令**，
不要退回去只读 `desc` 然后当成读过了——那正是本文档反复警告的事。

## 第一步：打开页面

```
mcp__Claude_Browser__preview_start  {url: "<短链或完整链接>"}
```

**然后直接跳第二步跑 JS**——内容本来就在 DOM 里，登录弹窗只是遮住画面，
不挡 JS 读取。2026-08-16 实测：一次 `preview_start` + 一次 JS 就拿全了 7 页，
截图和点 ✕ 都没做。**别默认要关弹窗，那是白花两轮往返。**

只有第二步返回 `{err: 'state 未加载'}` 且等 2 秒重试仍失败时，才截图关弹窗：
登录弹窗右上角有个 ✕。**坐标陷阱**：截图返回的坐标空间是 **800×450**，
但你看到的图像按 1600×900 渲染——**点击坐标要把目测值除以 2**。
✕ 通常在目测 (1249, 200) 处 ⇒ 传 `coordinate: [625, 100]`。

```
mcp__Claude_Browser__computer  {action: "left_click", coordinate: [625, 100]}
```

## 第二步：从 __INITIAL_STATE__ 提取

```
mcp__Claude_Browser__javascript_tool  {action: "javascript_exec", text: "<下面这段>"}
```

```js
(() => {
  const s = [...document.querySelectorAll('script')]
    .find(x => x.textContent.includes('imageList'));
  if (!s) return {err: 'state 未加载，等 2 秒重试'};
  let t = s.textContent.replace(/\\u002F/g, '/');
  const urls = [...new Set([...t.matchAll(/"urlDefault":"(http:[^"]+)"/g)].map(m => m[1]))];
  const desc = (t.match(/"desc":"([^"]{0,4000})"/) || [])[1] || null;
  const vid  = (t.match(/"masterUrl":"(http:[^"]+\.mp4[^"]*)"/) || [])[1] || null;
  const dur  = (t.match(/"duration":(\d+)/) || [])[1] || null;
  return {title: document.title, isVideo: !!vid, imageCount: urls.length,
          durationSec: dur ? +dur/1000 : null, desc, urls, videoUrl: vid};
})()
```

- `desc` = 作者自己写的正文/摘要，**任何笔记都要读它**
- `isVideo` 为 false ⇒ 图文笔记，走第三步
- `isVideo` 为 true ⇒ 视频笔记，走第四步

**⚠️ `desc` 是作者对自己内容的转述，不等于内容本身。**
实测遇到过 desc 把视频里的 k=1 单阶信号写成"跌久必涨"多根连跌、
并省略了标的是加密货币这一关键前提。**拿到正文/转写后必须与 desc 对账，
不一致时以正文为准并明确指出差异。**

## 第三步（图文）：下载 → 逐张读

**Read 工具直接能读 webp，不需要转格式**（2026-08-17 用小红书真实图片实测）。
这一步只要 `curl`，没有任何其它依赖。

```bash
D=<scratchpad>/xhs && rm -rf "$D" && mkdir -p "$D" && cd "$D"
i=1; while read -r u; do curl -sS -o "$(printf 'p%02d.webp' $i)" "$u"; i=$((i+1)); done < urls.txt
ls -la p*.webp     # 逐个确认非空——签名过期时 curl 会静默产出 0 字节文件
```

> **本文档 2026-08-16 版曾写「Read 读不了 webp，必须先转 PNG」，那是错的**
> （或者早已过期）。多出来的 `sips` 转换步骤既浪费一轮命令，又是这份 skill
> 当时唯一的 macOS 专有依赖，白白挡住了 Linux 用户。
> 万一将来遇到 Read 读不了的 webp 变体（例如动图），再按需转：
> `sips -s format png in.webp --out out.png`（macOS）/ `dwebp in.webp -o out.png`
> / `ffmpeg -i in.webp out.png` —— **三条都实测可解码**，按 `command -v` 探测取其一。

> zsh 坑：目录里没有 `.webp` 时 `rm -f p*.webp` 会报 `no matches found` 并
> **中止那一行**——这是 **shell 自己报的**，`2>/dev/null` 和 `|| true` 都挡不住。
> 所以上面用全新目录，不用 `rm -f` 通配。

然后用 Read 工具**逐张**读 `p01.webp` … `pNN.webp`。
长图文常有 20+ 页，**每一页都要读**——正文经常拆在图片里，跳读会漏掉数字。
**边读边记**：正文往往横跨多页（一句话在 p04 结尾、p05 开头接上），
读完一次性重组比读到哪写到哪准确。

## 第四步（视频）：音轨 + 画面两条腿

视频笔记要走完 4A/4B/4C 三步。**只做 4A 是不够的**——小红书的口播视频
大量信息只在画面上：图表、数字、代码、参数表、"重点"贴纸。
只听音轨会漏掉全部数字，而数字恰恰是最要紧的部分。

先确认 URL 可达（视频 URL 带签名，几小时后过期，过期回第二步重取）：

```bash
curl -sI "<videoUrl>" | head -3
```

### 4A 音轨 → 带时间轴的转写

```bash
# 只抽音轨，16kHz 单声道（whisper 要求）。41 分钟视频约 1-2 分钟
ffmpeg -y -loglevel error -i "<videoUrl>" -vn -ac 1 -ar 16000 -c:a pcm_s16le v.wav

# 模型：whisper-cli 自带的是 575KB 测试桩，不能用，要真模型（约 1.5GB）。
# **固定放共享缓存，不要下到项目里或 scratchpad**——否则每个项目重下一遍。
MODEL=~/.cache/whisper-models/ggml-large-v3-turbo.bin
[ -f "$MODEL" ] || { mkdir -p ~/.cache/whisper-models && curl -sL -o "$MODEL" \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin; }

# 转写。**必须出 srt 不是 txt**——没有时间轴就没法和画面对齐，
# 也整理不出 script。-l 用内容语言，不确定就 auto
whisper-cli -m "$MODEL" -f v.wav -l auto -osrt -otxt -of transcript -pp
```

### 4B 关键帧 → 逐帧读画面

**先量体裁衣**：`ffprobe` 拿时长，按内容形态选抽帧策略。

```bash
ffprobe -v error -show_entries format=duration -of csv=p=0 "<videoUrl>"
```

**下面两条命令 2026-08-16 实测通过**（合成测试片：4 个纯色段各 3 秒）。
草稿里想当然写的版本两条都是坏的，坑写在后面。

```bash
# 策略 B（默认，推荐）：固定间隔。**时间戳由序号推算，不需要 metadata**：
#   第 i 张（1-indexed）= (i-1) × N 秒
# N = 时长秒数 / 目标帧数，例如 40 分钟(2400s)要 60 帧 ⇒ N=40
ffmpeg -y -loglevel error -i "<videoUrl>" -vf "fps=1/40" -q:v 3 f_%03d.jpg
```

```bash
# 策略 A：场景切换检测。只在"幻灯片式换页、且要精确抓到每次换页时刻"时用。
# eq(n,0) 那一项不能省——否则**封面帧一定丢**（第 0 帧没有前帧可比）
ffmpeg -y -loglevel error -i "<videoUrl>" \
  -vf "select='eq(n,0)+gt(scene,0.2)',metadata=print:file=frames.txt" \
  -vsync vfr -q:v 3 f_%03d.jpg
grep -o 'pts_time:[0-9.]*' frames.txt   # 与 4A 的 srt 对齐用
```

**为什么默认是 B 而不是 A**——实测 A 在 4 段纯色片上只抽到 2/3 次切换：
红→绿那次**连 `gt(scene,0)` 都没触发**，score 根本没产生。
不是阈值调低就能救的，它就是会漏。小红书视频的信息大量是画面上的数字，
**漏一次换页就漏一整屏数字**，而 B 只是冗余几帧、不会漏内容。
A 只在"必须知道换页发生在第几秒"时才值得用，且用完要对帧数。

**帧数控制在 30–80 张**：每帧都要过一次视觉，100+ 帧是几万 token 且大半重复。
太多就调大 N 重抽，别硬读。

```bash
ls f_*.jpg | wc -l
```

然后用 Read 工具**逐帧**读。**边读边写帧级摘要**，一帧一行，格式见 4C。

### 4B 的四个坑（都是实测踩出来的，不是推测）

1. **`metadata=print` 配 `fps` 滤镜输出的是空文件**——`fps` 生成的帧不带
   metadata。策略 B 别指望它给时间戳，按序号算。
2. **`showinfo` 的输出在 stderr 的 info 级**，`-loglevel error` 会把它整个压掉，
   看起来像"没输出"。要用它就别压 loglevel。
3. **zsh 的 `no matches found`**：`rm -f f_*.jpg` 在没有匹配文件时
   zsh 会**报错并中止那一行**，`2>/dev/null` 挡不住（是 shell 报的不是 rm 报的）。
   可靠做法是每次用全新目录：`rm -rf "$D" && mkdir -p "$D" && cd "$D"`。
4. **变量后面紧跟 `:s=` 会被 zsh 当参数替换修饰符吃掉**
   （`"color=c=$c:s=640x360"` 里的 `$c:s=...` 被解析成替换，报
   `Cannot find color 'red10'`）。ffmpeg 滤镜串里凡是 `$var` 后面跟冒号，
   一律写成 `${var}`。

### 4C 合成：帧级摘要 + 完整 script

两份产出，都写进 scratchpad 落盘，别只留在上下文里：

**① `frames_summary.md` — 逐帧摘要**（每帧一行，读一帧写一行）

```
| # | 时间 | 画面 | 画面上的文字/数字（照抄，不要转述） |
|---|------|------|--------------------------------|
| 01 | 00:00 | 封面 | 「2026 中期选举预测」 |
| 02 | 01:23 | 折线图 | 标普 7610 → 7406，标注 −2.7% |
```

画面文字**照抄原样**，不要顺手改写或换算——这是后面能和音轨对账的前提。

**② `script.md` — 完整 script**

把 srt 的碎句合并成自然段（whisper 断句按停顿，一句常被切三段），
在对应的时间点插入画面信息：

```
## 00:00–01:20  开场
（口播）今天讲一下中期选举年的回撤规律……
> 🖼 01:23 画面：折线图，标普 7610 → 7406，标注 −2.7%

## 01:20–04:05  历史数据
……
```

**这一步的价值全在对账**，不是排版：
- 音轨说"跌了大概三个点"，画面写 `−2.68%` ⇒ **以画面为准**，口播是约数
- 画面有、音轨完全没提的数字/图表 ⇒ 单独列一节「只在画面上出现」
- 音轨有、画面无从印证的断言 ⇒ 标为作者口述主张

### 视频部分的实测要点

- **用 `run_in_background: true` 跑 ffmpeg / 模型下载 / whisper**——都是分钟级。
  4A 和 4B 互不依赖，**同时发出去并行跑**，别串行等。
- **标题语言 ≠ 内容语言**。标题中文的笔记，视频可能全英文（实测遇到过）。
  用 `-l auto`，或转写后看结果再决定要不要重跑。
- whisper 会把专业词转错：`mean reversion` → `meme reversion`、
  `Sharpe` → `shop`。**读的时候按上下文还原，别当成作者原话引用。**
  画面上的英文术语通常是对的，可以拿来校正音轨。
- 转写文本约 1KB/分钟，41 分钟约 36KB ≈ 9k token，可以整篇 Read。
- **纯静音视频**（配乐 + 字幕卡）不是失败：4A 会转出空的或全是拟声词的结果，
  这时 4B 就是全部内容。**别因为转写为空就说"读不到"。**

## 汇报纪律

这类内容会被拿去做交易决策，**准确性优先于完整性**：

1. **拿不到的部分明确说拿不到**，不要用 desc 脑补正文。附件（.docx 等）
   需要登录下载，通常拿不到——直说。
2. **数字要精确**，不要约等于。图上被遮挡的数字如果是倒推出来的，
   必须标明"倒推"并给出验算依据。
3. **区分作者主张与已验证事实**。笔记里的回测数字几乎都不含成本、
   样本量常常极小（实测见过 n=9 报 PF 10.71）——照搬前先看样本量和成本口径。
4. **评论区常有最要害的质疑**，一并读（`get_page_text` 可拿到）。
   评论区空的（显示"这是一片荒地"）也要说一句——**"没人质疑"本身是信息**，
   和"我没去看"是两回事。顺带记下赞/藏数：个位数互动的笔记，
   不存在"经过市场检验"这回事。
5. **音轨与画面冲突时以画面为准**，并明确写出两者分别说了什么。
   口播讲约数（"跌了大概三个点"）、画面是精确值（`−2.68%`），这不算冲突；
   **数量级或方向不一致才是**，那种必须单独指出来。
6. **图文笔记同样要做内部对账**。实测这条：同一篇里 P4 写高点 7609、
   P6 按 7610 算档位；P3 声称"五次里四次"，但 P2 的表格只撑得起三次
   （另一次要靠后文另一段补，且那段没给数字）。
   **笔记内部不自洽的地方，是最该在汇报里点名的地方**——
   照抄结论等于把作者的错误一起搬进决策。
