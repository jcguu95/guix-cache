# HOWTO：把新套件發布到 guix-cache

## 這個 repo 的用途

`jcguu95/guix-cache` 是一個個人 Guix substitute server：

- **narinfo 檔案**（`<hash>.narinfo`，~1KB）放在 repo 根目錄，由 GitHub Pages 提供。
- **NAR 二進位檔**（`<hash>.nar.gz`，可能數百 MB）存在 GitHub Releases。
- narinfo 裡的 `URL:` 欄位指向對應 Release 的絕對 URL。
- narinfo 有 Guix signing key 的簽章，Guix 客戶端會驗證。

客戶端設定（已寫在 `guix/common/shared.scm`）：
```scheme
(substitute-urls
 (cons* "https://jcguu95.github.io/guix-cache"
        "https://substitutes.nonguix.org"
        %default-substitute-urls))
```

---

## 一次性設定（新機器或 signing key 更換後）

```bash
# 1. clone 此 repo
git clone git@github.com:jcguu95/guix-cache.git
cd guix-cache

# 2. 把系統 signing key 複製到 jin 可讀的位置
bash scripts/setup-keys.sh
# 會顯示 public key 內容，確認與 shared.scm 裡的一致
```

---

## 發布新套件的流程

### 1. 確認套件已在本機 store

```bash
# 確認有這個套件（以 linux 為例）
guix build --no-grafts linux    # 若已有 substitute 會很快完成
# 找到 store path
guix build --no-grafts linux --dry-run 2>&1 | grep '/gnu/store'
# 或直接查
ls /gnu/store/ | grep linux-[0-9]
```

### 2. 取得完整 store path

```bash
STORE_PATH=$(guix build --no-grafts linux)
echo $STORE_PATH
# 例：/gnu/store/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-linux-6.18.28
```

### 3. 執行發布腳本

```bash
cd guix-cache
bash scripts/publish-package.sh "$STORE_PATH"
```

腳本會自動：
1. 啟動 `guix publish`（用 jin 的 signing key）
2. 取得 narinfo 和 nar.gz
3. 把 nar.gz 上傳到 GitHub Releases
4. 修改 narinfo 裡的 URL 為絕對 GitHub URL
5. 把 narinfo 推到 GitHub Pages（repo 根目錄）

### 4. 驗證

```bash
HASH="$(echo $STORE_PATH | grep -oP '[a-z0-9]{32}(?=-)')"
curl "https://jcguu95.github.io/guix-cache/${HASH}.narinfo"
```

等 GitHub Pages 部署完成（約 1~2 分鐘）後，
在任何有設定此 substitute server 的機器上執行：
```bash
guix build --no-grafts linux
# 應該會顯示 substitute 下載，不會重新編譯
```

---

## 手動流程（腳本出問題時）

若腳本執行失敗，可手動執行以下步驟：

```bash
# 1. 取得 store path
STORE_PATH=/gnu/store/xxxx...-linux-6.18.28
HASH=$(basename $STORE_PATH | cut -d- -f1)

# 2. 啟動 guix publish
guix publish \
    --public-key=$HOME/.config/guix/signing-key.pub \
    --private-key=$HOME/.config/guix/signing-key.sec \
    --port=8765 --compression=gzip --listen=127.0.0.1 &

# 3. 下載 narinfo 和 nar
curl http://127.0.0.1:8765/${HASH}.narinfo > ${HASH}.narinfo
NAR_URL=$(grep '^URL:' ${HASH}.narinfo | awk '{print $2}')
curl "http://127.0.0.1:8765/${NAR_URL}" > ${HASH}.nar.gz

# 4. 上傳 nar 到 GitHub Releases
RELEASE_TAG="linux-6.18.28"   # 依套件名稱調整
gh release create "$RELEASE_TAG" \
    --repo jcguu95/guix-cache \
    --title "linux-6.18.28" \
    ${HASH}.nar.gz

# 5. 修改 narinfo 的 URL（URL 欄位不在簽章範圍，可修改）
ABSOLUTE_URL="https://github.com/jcguu95/guix-cache/releases/download/${RELEASE_TAG}/${HASH}.nar.gz"
sed -i "s|^URL:.*|URL: $ABSOLUTE_URL|" ${HASH}.narinfo

# 6. 把 narinfo 放到 repo 根目錄並推送
cp ${HASH}.narinfo guix-cache/${HASH}.narinfo
cd guix-cache
git add ${HASH}.narinfo
git commit -m "add narinfo for linux-6.18.28"
git push origin master
```

---

## 關於 narinfo 格式

```
StorePath: /gnu/store/<hash>-<name>
URL: <nar 的下載 URL>         ← 不在簽章範圍，可替換為絕對 URL
Compression: gzip
FileHash: sha256:<hash>
FileSize: <bytes>
NarHash: sha256:<hash>
NarSize: <bytes>
References: <store path hashes...>
Deriver: <drv path>
Sig: <substitute-server-name>:<base64-signature>
```

**重要**：`Sig:` 欄位的簽章範圍只涵蓋
`1;<StorePath>;<NarHash>;<NarSize>;<References>`，
**不**包含 `URL:`，所以替換 URL 不會破壞簽章。

---

## 目前已發布的套件

| 套件 | store hash 前綴 | Release tag |
|------|----------------|-------------|
| linux-6.18.28 (nonguix, x86_64) | 見 .narinfo 檔名 | `linux-6.18.28-nonguix-x86_64` |

---

## 授權 key 設定（shared.scm 用）

把 `~/.config/guix/signing-key.pub` 的內容加入 `guix/common/shared.scm`：

```scheme
(authorized-keys
 (cons* (plain-file
         "guix-cache.pub"
         "<signing-key.pub 的完整內容>")
        %default-authorized-guix-keys))
```
