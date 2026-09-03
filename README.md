<div align="center">

<img src="docs/icon.png" width="96" alt="番时" />

# 番时

只关心正在放送的番剧。

**简体中文** · [繁體中文](README_zh-Hant.md) · [English](README_en.md)

<br/>

<img src="docs/screenshots/home.png" width="200" alt="番剧" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/search.png" width="200" alt="查番" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/settings.png" width="200" alt="设置" />

</div>

<br/>

## 关于

输入一个关键词，得到一张卡片：番名、首播日期、每周的放送时间和平台。

首页按星期排列，今天在最上面。时间换算成你所在的时区，星期也随之重新归类。到点可以收到通知。

## 原理

```
关键词  →  Bangumi  →  Tavily 搜索  →  LLM 整理  →  卡片
```

放送时间没有现成的接口，靠搜索加大语言模型整理，所以需要自备两个 key。

## 准备

| | 用途 | 免费额度 |
|---|---|---|
| Tavily API Key | 网页搜索 | 每月 1000 次 |
| LLM API Key | 整理放送表 | 视服务商而定 |

支持 DeepSeek、阿里云百炼、火山引擎、OpenAI、Anthropic，以及任何 OpenAI 兼容接口。设置页里有 Tavily 的注册教程。

bgm.tv 在中国大陆访问不畅，可以在设置里切换到镜像。

## 隐私

没有账号，没有服务器。请求从手机直接发往 Bangumi、Tavily 和你选择的服务商。配置留在应用自己的目录里，API Key 加密存储且与设备绑定。不收集数据。

## 下载

[Releases](https://github.com/erichuanp/anime-now/releases)。Android 6.0 以上，多数手机用 `arm64-v8a`。

## 状态

2026.9.3.0 版。源码暂未公开。

## 致谢

数据来自 [Bangumi 番组计划](https://bgm.tv)，搜索由 [Tavily](https://tavily.com) 提供。

<br/>

<div align="center">
<sub>MIT License · © 2026 erichuanp</sub>
</div>
