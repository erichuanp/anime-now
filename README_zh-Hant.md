<div align="center">

<img src="docs/icon.png" width="96" alt="番時" />

# 番時

只關心正在播出的番劇。

[简体中文](README.md) · **繁體中文** · [English](README_en.md)

<br/>

<img src="docs/screenshots/home.png" width="200" alt="番劇" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/search.png" width="200" alt="查番" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/settings.png" width="200" alt="設定" />

</div>

<br/>

## 關於

輸入一個關鍵字，得到一張卡片：番名、首播日期、每週的播出時間和平台。

首頁按星期排列，今天在最上面。時間換算成你所在的時區，星期也隨之重新歸類。到點可以收到通知。

## 原理

```
關鍵字  →  Bangumi  →  Tavily 搜尋  →  LLM 整理  →  卡片
```

播出時間沒有現成的介面，靠搜尋加大型語言模型整理，所以需要自備兩個 key。

## 準備

| | 用途 | 免費額度 |
|---|---|---|
| Tavily API Key | 網頁搜尋 | 每月 1000 次 |
| LLM API Key | 整理播出表 | 視服務商而定 |

支援 DeepSeek、阿里雲百煉、火山引擎、OpenAI、Anthropic，以及任何 OpenAI 相容介面。設定頁裡有 Tavily 的註冊教學。

## 隱私

沒有帳號，沒有伺服器。請求從本機直接發往 Bangumi、Tavily 和你選擇的服務商。設定留在應用自己的目錄裡，API Key 加密儲存且與裝置綁定。不收集資料。

使用番時鏡像即表示同意：查番時輸入的關鍵字、bangumi 使用者名稱和你的 IP 會經過作者的伺服器，作者可以看到。換回官方或填自己的鏡像即可避免。Tavily 和 LLM 的請求不經過鏡像，它們的隱私問題請詢問對應的服務商。

## 下載

[Releases](https://github.com/erichuanp/anime-now/releases)。Android 6.0 以上，多數手機用 `arm64-v8a`；macOS 12 以上用 `.dmg`。

macOS 版沒有簽章，首次開啟要在圖示上按右鍵選「打開」。

## 狀態

2026.9.3.1 版。原始碼暫未公開。

## 致謝

資料來自 [Bangumi 番組計畫](https://bgm.tv)，搜尋由 [Tavily](https://tavily.com) 提供。

<br/>

<div align="center">
<sub>MIT License · © 2026 erichuanp</sub>
</div>
