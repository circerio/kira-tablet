# Kira Tablet

**Kira Tablet** 是以 [Kira](https://github.com/caolib/kira) 為基礎的 Windows-first fork，重點放在 **Windows 11 平板、二合一裝置、橫屏與純觸控操作**。

> Preview 軟體。這不是拷貝漫畫官方客戶端，也不是 Kira 官方 Windows 發行版。

## 主要差異

- Windows 11 x64、橫屏優先，預設 1280×720。
- 觸控優先：主要功能不依賴鍵盤、右鍵或 hover。
- Win32 真正無邊框全螢幕，閱讀器可直接觸控退出。
- 不靠 Esc / F11 才能離開全螢幕。
- 首頁依 Windows 平板重新排版，小視窗與高 DPI 自適應。
- 首頁使用官網高解析輪播圖並保持原始比例。
- Copy 首頁採固定桌面區塊：推薦、熱門更新、全新上架、專題、排行榜。
- Copy 登入不直接提交帳號密碼；使用官方網頁登入或既有 Token。
## v0.1.0 Preview

這是第一個公開預覽版本。主要驗證目標：

- 1280×800 / 1920×1200 等常見 Windows 平板解析度。
- Windows 100% / 125% / 150% DPI。
- 觸控翻頁、捲動、全螢幕進出與無鍵盤操作。
- 官網輪播與第三方 API 變動時的 fallback。

若網站或 API 結構改動，部分功能可能暫時失效。

## 安裝

建議使用 kira-tablet-*-windows-x64-setup.exe。

也提供 portable ZIP；解壓後必須保留 EXE、DLL 與 data/ 在同一資料夾，不能只複製單一 EXE。

## 專案關係

Kira Tablet 基於 Kira 修改。Kira 原始碼採 MIT License：

- Upstream: https://github.com/caolib/kira
- Original copyright: Copyright (c) 2026 孤独的Lonely
- License: LICENSE
本 fork 不是拷貝漫畫、熱辣漫畫或 Kira upstream 的官方產品；相關名稱、內容與服務由其各自權利人所有。

## 內容與帳號

本應用本身不託管漫畫內容，畫面中的資料來自第三方服務。

Copy 帳號登入刻意不提供直接帳密提交。請使用官方網頁登入或已有的 Token。Kira Tablet 不提供規避第三方反濫用、反修改或存取控制的功能。

## 開發

目前主要目標平台為 Windows 11 x64。

需要：

- Flutter
- Visual Studio 2022 Desktop development with C++
- Windows 10/11 SDK
- Inno Setup 6（建立 installer）

Build：

    flutter pub get
    flutter build windows --release

詳細第三方資訊見 THIRD_PARTY_NOTICES.md。
