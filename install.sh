#!/bin/bash
# 把 ~/.claude/skills 指向本仓库的 skills/，让所有项目都能用这里的 skill。
#
# 幂等：重复跑没有副作用。
# 安全：如果 ~/.claude/skills 是一个装了东西的真实目录，拒绝动它并提示人工处理——
#       静默删掉别处的 skill 是不可接受的。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/skills"
DST="$HOME/.claude/skills"

[ -d "$SRC" ] || { echo "❌ 找不到 $SRC"; exit 1; }
mkdir -p "$HOME/.claude"

if [ -L "$DST" ]; then
    cur="$(readlink "$DST")"
    if [ "$cur" = "$SRC" ]; then
        echo "✅ 已就位：$DST → $SRC"
        exit 0
    fi
    echo "⚠️  $DST 目前指向别处：$cur"
    read -rp "    改指向本仓库？[y/N] " a
    [ "$a" = "y" ] || { echo "已取消"; exit 0; }
    rm "$DST"
elif [ -e "$DST" ]; then
    # 真实目录：只有空目录才敢删
    if [ -n "$(ls -A "$DST" 2>/dev/null)" ]; then
        echo "❌ $DST 是一个非空的真实目录，里面是："
        ls -1 "$DST" | sed 's/^/     /'
        echo
        echo "   不会自动删除。请先把要保留的 skill 移进本仓库的 skills/ 再重跑："
        echo "     mv $DST/<名字> $SRC/ && rmdir $DST && $0"
        exit 1
    fi
    rmdir "$DST"
fi

ln -s "$SRC" "$DST"
echo "✅ $DST → $SRC"
echo
echo "可用 skill："
find "$SRC" -maxdepth 2 -name SKILL.md -exec dirname {} \; | xargs -n1 basename | sed 's/^/  · /'
