<div align="center">

<img src="docs/icon.png" width="96" alt="番時" />

# 番時

**這週有什麼番，幾點播，一眼看完。**

只關心正在播出的番劇。輸入一個關鍵字，剩下的交給它。

[简体中文](README.md) · **繁體中文** · [English](README_en.md)

<br/>

<img src="docs/screenshots/home.png" width="200" alt="番劇" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/search.png" width="200" alt="查番" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/detail.png" width="200" alt="各平台播出時間" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/settings.png" width="200" alt="設定" />

</div>

<br/>

## 它做什麼

**一張卡片，三行資訊。** 封面、番名、首播日期和每週播出時間，再加一行平台。點開卡片，看到所有平台的播出時間，從最早到最晚。

**按星期排好。** 首頁是一條循環的星期流，今天永遠在最上面。往下滑，滑不到底；一個按鈕隨時回到今天。

**時間是你的時間。** 日本的「金曜 23:00」，在台北顯示為週五 22:00，在紐約顯示為週五 10:00。星期也按你所在的時區重新歸類。

**只留正在播的。** 完結的番會被標出來，一鍵清掉。還沒開播的可以先加進來，標著「即將開播」。

**一次查一部，或者一次查十部。** 進階搜尋一行一個番名，也可以直接匯入任何 bangumi 使用者的在看／想看清單。

**三種語言。** 簡體中文、繁體中文、English，番名也各有對應語言的版本。

## 它怎麼運作

```
關鍵字  →  Bangumi 番組計畫  →  Tavily 搜尋  →  LLM 整理  →  卡片
```

1. 用 [Bangumi](https://bgm.tv) 把模糊的關鍵字變成確定的番劇、封面和別名。
2. 用番劇的日文原名搜尋播出時間。日文找不到，換英文、繁中、簡中。
3. 讓大型語言模型把搜尋結果整理成結構化的播出表。
4. 換算時區，畫成卡片。

典型的一次查詢：Bangumi 3 次、Tavily 1 次、LLM 1 次，約 4 秒。

## 你需要準備

| | 用途 | 免費額度 |
|---|---|---|
| **Tavily API Key** | 網頁搜尋 | 每月 1000 次 |
| **LLM API Key** | 整理播出表 | 視服務商而定 |

支援火山引擎（豆包）、DeepSeek、阿里雲百煉（通義千問）、OpenAI、Anthropic，以及任何 OpenAI 相容介面。設定頁裡有 Tavily 的手把手註冊教學。

## 隱私

- 沒有帳號，沒有伺服器。所有請求從你的手機直接發往 Bangumi、Tavily 和你選擇的 LLM 服務商。
- 設定儲存在手機的 `Documents/AnimeNow/`，解除安裝後重裝不會遺失。
- API Key 以 AES-256-GCM 加密儲存，金鑰與你的裝置綁定，換手機無法解密。
- 不收集任何資料。

## 下載

Android 6.0 及以上。建議 Android 11 及以上，以獲得「重裝不丟設定」的完整體驗。

各架構的 APK 在 [Releases](https://github.com/erichuanp/anime-now/releases) 頁面。大多數手機用 `arm64-v8a` 版本。

## 狀態

1.0.0 版。原始碼暫未公開。

## 致謝

播出資料來自 [Bangumi 番組計畫](https://bgm.tv)。搜尋由 [Tavily](https://tavily.com) 提供。

<br/>

<div align="center">
<sub>MIT License · © 2026 erichuanp</sub>
</div>
