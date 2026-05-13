#!/usr/bin/env bash
# scripts/setup-keys.sh
# 一次性設定：把 Guix 系統的 signing key 複製到 jin 可讀的位置，
# 讓後續 guix publish 不需每次 sudo。
#
# 執行方式：bash scripts/setup-keys.sh
# 只需執行一次（或 signing key 更換後重執行）。

set -euo pipefail

DEST_DIR="$HOME/.config/guix"
DEST_SEC="$DEST_DIR/signing-key.sec"
DEST_PUB="$DEST_DIR/signing-key.pub"
SRC_SEC="/etc/guix/signing-key.sec"
SRC_PUB="/etc/guix/signing-key.pub"

echo "==> 建立目的目錄 $DEST_DIR"
mkdir -p "$DEST_DIR"

echo "==> 複製 signing key（需要 sudo）"
sudo cp "$SRC_SEC" "$DEST_SEC"
sudo cp "$SRC_PUB" "$DEST_PUB"
sudo chown "$(id -un):$(id -gn)" "$DEST_SEC" "$DEST_PUB"
sudo chmod 600 "$DEST_SEC"
sudo chmod 644 "$DEST_PUB"

echo ""
echo "完成。Public key 內容（加入 shared.scm authorized-keys 用）："
echo "---"
cat "$DEST_PUB"
echo "---"
echo ""
echo "之後可用：guix publish --public-key=$DEST_PUB --private-key=$DEST_SEC --port=8765"
