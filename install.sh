#!/bin/bash
# 把 ~/.claude/skills 指向本仓库的 skills/，让所有项目都能用这里的 skill。
#
# 幂等：重复跑没有副作用。
# 安全：如果 ~/.claude/skills 是一个装了东西的真实目录，拒绝动它并提示人工处理——
#       静默删掉别处的 skill 是不可接受的。
#
# 用法：
#   ./install.sh          安装（或确认已安装）+ 一致性自检
#   ./install.sh --check  只做自检，不碰任何 symlink
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/skills"
DST="$HOME/.claude/skills"
README="$REPO/README.md"

# ── 自检 ───────────────────────────────────────────────────────────────
# 清单不自动校验就必然会漂移。README 的「当前 skill」表和 SKILL.md 里的
# name 字段都是手写的，加/删 skill 时最容易忘记同步——让它成为显式动作。
check() {
    local actual listed drift=0
    actual="$(mktemp)"; listed="$(mktemp)"

    find "$SRC" -maxdepth 2 -name SKILL.md 2>/dev/null \
        | while read -r f; do basename "$(dirname "$f")"; done | sort > "$actual"
    # 表格行形如：| `xhs-reader` | 说明 |　（表头无反引号，自然被排除）
    grep -oE '^\| *`[^`]+`' "$README" 2>/dev/null | tr -d '|` ' | sort > "$listed"

    local missing extra
    missing="$(comm -23 "$actual" "$listed")"
    extra="$(comm -13 "$actual" "$listed")"

    if [ -n "$missing" ]; then
        drift=1
        echo "⚠️  这些 skill 存在，但 README 的「当前 skill」表里没有："
        echo "$missing" | sed 's/^/     · /'
    fi
    if [ -n "$extra" ]; then
        drift=1
        echo "⚠️  README 列了这些，但 skills/ 下找不到（改名或删了没同步？）："
        echo "$extra" | sed 's/^/     · /'
    fi

    # frontmatter 的 name 必须与目录名一致，否则调用名和目录名对不上
    while read -r d; do
        local dir n
        dir="$(basename "$d")"
        n="$(awk -F': *' '/^name:/{print $2; exit}' "$d/SKILL.md" 2>/dev/null || true)"
        if [ -z "$n" ]; then
            drift=1; echo "⚠️  $dir/SKILL.md 缺 frontmatter 的 name 字段"
        elif [ "$n" != "$dir" ]; then
            drift=1; echo "⚠️  $dir/SKILL.md 的 name 是「$n」，与目录名不一致"
        fi
        if ! grep -q '^description:' "$d/SKILL.md" 2>/dev/null; then
            drift=1; echo "⚠️  $dir/SKILL.md 缺 description——没有它 Claude 不知道何时该用"
        fi
    done < <(find "$SRC" -maxdepth 2 -name SKILL.md -exec dirname {} \; 2>/dev/null | sort)

    rm -f "$actual" "$listed"
    if [ "$drift" -eq 0 ]; then
        echo "✅ 自检通过：README 清单、目录、frontmatter 三者一致"
    else
        echo
        echo "   以上是文档漂移，不影响 skill 能否使用，但请顺手修掉。"
    fi
    return 0
}

if [ "${1:-}" = "--check" ]; then
    check
    exit 0
fi

# ── 安装 ───────────────────────────────────────────────────────────────
[ -d "$SRC" ] || { echo "❌ 找不到 $SRC"; exit 1; }
mkdir -p "$HOME/.claude"

linked=0
if [ -L "$DST" ]; then
    cur="$(readlink "$DST")"
    if [ "$cur" = "$SRC" ]; then
        echo "✅ 已就位：$DST → $SRC"
        linked=1
    else
        echo "⚠️  $DST 目前指向别处：$cur"
        read -rp "    改指向本仓库？[y/N] " a
        [ "$a" = "y" ] || { echo "已取消"; exit 0; }
        rm "$DST"
    fi
elif [ -e "$DST" ]; then
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

if [ "$linked" -eq 0 ]; then
    ln -s "$SRC" "$DST"
    echo "✅ $DST → $SRC"
fi

echo
echo "可用 skill："
find "$SRC" -maxdepth 2 -name SKILL.md -exec dirname {} \; 2>/dev/null \
    | while read -r d; do basename "$d"; done | sort | sed 's/^/  · /'
echo
check
