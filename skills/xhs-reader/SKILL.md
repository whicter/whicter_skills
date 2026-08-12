---
name: xhs-reader
description: 读取小红书（xiaohongshu / xhslink.cn）笔记的完整内容，包括图文笔记的每一页图片和视频笔记的全片语音转写。当用户发来 xhslink.cn 短链或 xiaohongshu.com 链接、要求"看看这个""研究一下这个""总结这篇"时使用。
---

# 读小红书笔记（图文 + 视频）

**核心事实：小红书正文在登录墙后面，但内容拿得到——不需要登录。**

WebFetch 拿不到（内容是 JS 渲染的），`get_page_text` 只能拿到标题和评论。
**真正的内容在页面的 `__INITIAL_STATE__` 里**：图文笔记的每页图片 URL、
视频笔记的 desc 和视频流地址，全都在那个 script 标签中。

> 不要因为第一次 WebFetch 失败就回复"拿不到"。本文档里的每一步都实测有效。
> 绝不登录用户的小红书账号——不需要，也不允许。

## 第一步：打开页面并关掉登录弹窗

```
mcp__Claude_Browser__preview_start  {url: "<短链或完整链接>"}
mcp__Claude_Browser__computer       {action: "screenshot"}
```

登录弹窗右上角有个 ✕。**坐标陷阱**：截图返回的坐标空间是 **800×450**，
但你看到的图像按 1600×900 渲染——**点击坐标要把目测值除以 2**。
✕ 通常在目测 (1249, 200) 处 ⇒ 传 `coordinate: [625, 100]`。

```
mcp__Claude_Browser__computer  {action: "left_click", coordinate: [625, 100]}
```

弹窗关掉后页面就完整了（内容本来就在 DOM 里，只是被遮住）。

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

## 第三步（图文）：下载 → 转 PNG → 逐张读

图片是 webp，**Read 工具读不了 webp，必须先转 PNG**。

```bash
cd <scratchpad>/xhs && i=1
while read -r u; do curl -sS -o "$(printf 'p%02d.webp' $i)" "$u"; i=$((i+1)); done < urls.txt
for f in p*.webp; do sips -s format png "$f" --out "${f%.webp}.png" >/dev/null 2>&1; done
```

然后用 Read 工具**逐张**读 `p01.png` … `pNN.png`。
长图文常有 20+ 页，**每一页都要读**——正文经常拆在图片里，跳读会漏掉数字。

## 第四步（视频）：抽音轨 → whisper 转写

**这是最容易被误判为"做不到"的一步，但本机工具齐全。**

```bash
# 1) 确认音轨可达（视频 URL 带签名，几小时后过期，过期就回第二步重取）
curl -sI "<videoUrl>" | head -3

# 2) 只抽音轨，16kHz 单声道（whisper 要求）。41 分钟视频约 1-2 分钟
ffmpeg -y -loglevel error -i "<videoUrl>" -vn -ac 1 -ar 16000 -c:a pcm_s16le v.wav

# 3) 模型：whisper-cli 自带的是 575KB 测试桩，不能用，要真模型（约 1.5GB）。
#    **固定放共享缓存，不要下到项目里或 scratchpad**——否则每个项目重下一遍。
MODEL=~/.cache/whisper-models/ggml-large-v3-turbo.bin
[ -f "$MODEL" ] || { mkdir -p ~/.cache/whisper-models && curl -sL -o "$MODEL" \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin; }

# 4) 转写。-l 用内容语言；不确定就用 auto
whisper-cli -m "$MODEL" -f v.wav -l auto -otxt -of transcript -pp
```

**用 `run_in_background: true` 跑第 2、3、4 步**——都是分钟级，别阻塞。

实测要点：
- **标题语言 ≠ 内容语言**。标题是中文的笔记，视频本身可能全英文
  （实测遇到过）。用 `-l auto`，或转写后看结果再决定要不要重跑。
- whisper 会把专业词转错：`mean reversion` → `meme reversion`、
  `Sharpe` → `shop`。**读的时候按上下文还原，别当成作者原话引用。**
- 转写文本约 1KB/分钟，41 分钟约 36KB ≈ 9k token，可以整篇 Read。

## 汇报纪律

这类内容会被拿去做交易决策，**准确性优先于完整性**：

1. **拿不到的部分明确说拿不到**，不要用 desc 脑补正文。附件（.docx 等）
   需要登录下载，通常拿不到——直说。
2. **数字要精确**，不要约等于。图上被遮挡的数字如果是倒推出来的，
   必须标明"倒推"并给出验算依据。
3. **区分作者主张与已验证事实**。笔记里的回测数字几乎都不含成本、
   样本量常常极小（实测见过 n=9 报 PF 10.71）——照搬前先看样本量和成本口径。
4. **评论区常有最要害的质疑**，一并读（`get_page_text` 可拿到）。
