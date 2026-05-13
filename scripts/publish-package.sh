#!/usr/bin/env bash
# scripts/publish-package.sh
# 把 Guix store 裡的一個套件發布到 guix-cache GitHub repository。
#
# 用法：
#   bash scripts/publish-package.sh <store-path>
#
# 例如：
#   bash scripts/publish-package.sh /gnu/store/xxxx...-linux-6.12.0
#
# 前置條件：
#   1. 已執行過 scripts/setup-keys.sh（signing key 在 ~/.config/guix/）
#   2. 已安裝 gh CLI 並完成 gh auth login
#   3. 已在 guix-cache repo 根目錄下執行本腳本（或提供正確路徑）
#   4. 目標套件已在本機 Guix store 中

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$REPO_DIR/scripts"
NARINFO_DIR="$REPO_DIR/narinfo"
PUB_KEY="$HOME/.config/guix/signing-key.pub"
SEC_KEY="$HOME/.config/guix/signing-key.sec"
GH_REPO="jcguu95/guix-cache"
PUBLISH_PORT=8765

# ── 參數檢查 ────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "用法：$0 <store-path>" >&2
    echo "例：$0 /gnu/store/abc123...-linux-6.12.0" >&2
    exit 1
fi

STORE_PATH="$1"
if [[ ! -d "$STORE_PATH" && ! -f "$STORE_PATH" ]]; then
    echo "錯誤：store path 不存在：$STORE_PATH" >&2
    exit 1
fi

# ── 從 store path 取得 hash ─────────────────────────────────────────────────
BASENAME="$(basename "$STORE_PATH")"
HASH="${BASENAME%%-*}"   # 取第一個 - 前的部分（32字元 hash）
PACKAGE_NAME="${BASENAME#*-}"  # hash 後面的名稱

if [[ ${#HASH} -ne 32 ]]; then
    echo "錯誤：無法從 $BASENAME 取得 32 字元 hash" >&2
    exit 1
fi

echo "==> 套件：$PACKAGE_NAME"
echo "==> Hash：$HASH"

# ── 建立 nar 檔名 ────────────────────────────────────────────────────────────
NAR_NAME="${HASH}.nar.gz"
NAR_FILE="/tmp/${NAR_NAME}"
RELEASE_TAG="$(echo "$PACKAGE_NAME" | tr '/' '-')"

# ── 啟動 guix publish（若尚未啟動）─────────────────────────────────────────
echo "==> 啟動 guix publish 於 port $PUBLISH_PORT..."
guix publish \
    --public-key="$PUB_KEY" \
    --private-key="$SEC_KEY" \
    --port="$PUBLISH_PORT" \
    --compression=gzip \
    --listen=127.0.0.1 \
    &
PUBLISH_PID=$!
trap "kill $PUBLISH_PID 2>/dev/null || true" EXIT

# 等待 publish server 就緒
echo "==> 等待 publish server 就緒..."
for i in $(seq 1 10); do
    sleep 1
    if curl -sf "http://127.0.0.1:${PUBLISH_PORT}/nix-cache-info" >/dev/null 2>&1; then
        echo "    Server 就緒。"
        break
    fi
    if [[ $i -eq 10 ]]; then
        echo "錯誤：guix publish server 10 秒內未就緒" >&2
        exit 1
    fi
done

# ── 下載 narinfo ─────────────────────────────────────────────────────────────
echo "==> 下載 narinfo..."
NARINFO_FILE="$NARINFO_DIR/${HASH}.narinfo"
mkdir -p "$NARINFO_DIR"
curl -sf "http://127.0.0.1:${PUBLISH_PORT}/${HASH}.narinfo" -o "$NARINFO_FILE"
echo "    narinfo 已儲存至 $NARINFO_FILE"

# ── 下載 nar.gz ──────────────────────────────────────────────────────────────
echo "==> 下載 nar.gz..."
NAR_URL="$(grep '^URL:' "$NARINFO_FILE" | awk '{print $2}')"
curl -sf "http://127.0.0.1:${PUBLISH_PORT}/${NAR_URL}" -o "$NAR_FILE"
echo "    nar.gz 已儲存至 $NAR_FILE"

# ── 建立 GitHub Release 並上傳 nar.gz ───────────────────────────────────────
echo "==> 建立 GitHub Release tag: $RELEASE_TAG"
gh release create "$RELEASE_TAG" \
    --repo "$GH_REPO" \
    --title "$PACKAGE_NAME" \
    --notes "Guix store NAR for $STORE_PATH" \
    "$NAR_FILE" \
    || echo "    (Release 可能已存在，嘗試上傳檔案...)"

# 若 release 已存在，只上傳檔案
gh release upload "$RELEASE_TAG" "$NAR_FILE" \
    --repo "$GH_REPO" \
    --clobber \
    2>/dev/null || true

# ── 修改 narinfo 的 URL 欄位為 GitHub Releases 絕對 URL ─────────────────────
echo "==> 修改 narinfo URL 欄位..."
ABSOLUTE_URL="https://github.com/$GH_REPO/releases/download/$RELEASE_TAG/$NAR_NAME"
# URL 欄位不在簽章範圍內，可安全修改
sed -i "s|^URL:.*|URL: $ABSOLUTE_URL|" "$NARINFO_FILE"
echo "    新 URL: $ABSOLUTE_URL"

# ── 停止 publish server ──────────────────────────────────────────────────────
kill $PUBLISH_PID 2>/dev/null || true
trap - EXIT

# ── 提交並推送 narinfo ───────────────────────────────────────────────────────
echo "==> 提交 narinfo 到 GitHub Pages..."
cd "$REPO_DIR"
cp "$NARINFO_FILE" "./${HASH}.narinfo"   # narinfo 要在 repo 根目錄才能被 Pages 提供
git add "${HASH}.narinfo" "narinfo/${HASH}.narinfo"
git commit -m "add narinfo for $PACKAGE_NAME ($HASH)"
git push origin master

echo ""
echo "完成！"
echo "  narinfo URL: https://jcguu95.github.io/guix-cache/${HASH}.narinfo"
echo "  nar URL:     $ABSOLUTE_URL"
echo ""
echo "驗證方式："
echo "  curl https://jcguu95.github.io/guix-cache/${HASH}.narinfo"
