# oc-tg-ios

iOS 外殼（WKWebView）打包 `poly39-xoio/tg-oc-skin` 的 OC 皮膚 Telegram 網頁客戶端。

## 為什麼要本機伺服器

`file://` 與自訂 scheme 在 WebKit 屬非 secure context → `crypto.subtle` / OPFS / service worker 全部失效，Telegram 網頁版會登入失敗。
所以 `LocalWebServer.swift` 在 **127.0.0.1** 起一個唯讀靜態 HTTP 伺服器；loopback 是 potentially-trustworthy origin，行為等同 Safari。

## 建置

CI（GitHub Actions，macos-26）：

1. `build`（push 觸發）：Swift 編譯 → build Telegram web（`npm run build:production`）→ 打包 → 模擬器啟動 + 截圖（artifact `smoke`）
2. `archive`（workflow_dispatch）：簽章 → archive → IPA → 上傳 TestFlight

需要的 secrets：`TELEGRAM_API_ID`、`TELEGRAM_API_HASH`、`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`、`DIST_P12_BASE64`、`DIST_P12_PW`、`TEAM_ID`、`PROFILE_BASE64_OC`、`PROFILE_UUID_OC`、`PROFILE_NAME_OC`。

## 授權

Telegram web 客戶端為 GPLv3（`poly39-xoio/tg-oc-skin` 已公開）。本 repo 只含外殼程式碼。
