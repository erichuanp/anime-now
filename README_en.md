<div align="center">

<img src="docs/icon.png" width="96" alt="Anime Now" />

# Anime Now

**What's airing this week, and when. At a glance.**

Only the anime that are airing right now. Type one keyword; the app does the rest.

[简体中文](README.md) · [繁體中文](README_zh-Hant.md) · **English**

<br/>

<img src="docs/screenshots/home.png" width="200" alt="Schedule" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/search.png" width="200" alt="Search" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/detail.png" width="200" alt="Broadcast times" />&nbsp;&nbsp;&nbsp;
<img src="docs/screenshots/settings.png" width="200" alt="Settings" />

</div>

<br/>

## What it does

**One card, three lines.** Cover, title, premiere date and weekly slot, plus the platform. Tap the card to see every platform, earliest first.

**Sorted by weekday.** The home screen is an endless loop of weekdays with today always on top. Scroll down forever; a button brings you back to today.

**Your time, not Tokyo's.** A Japanese "Friday 23:00" shows as Friday 22:00 in Beijing and Friday 10:00 in New York. The weekday is regrouped for your timezone too.

**Only what's airing.** Finished shows are flagged and can be cleared in one tap. Upcoming shows can be added early, marked "Upcoming".

**One at a time, or ten at once.** Advanced search takes one title per line, or pulls the watching and wish lists of any bangumi user.

**Three languages.** Simplified Chinese, Traditional Chinese and English, with titles in each language.

## How it works

```
keyword  →  Bangumi  →  Tavily search  →  LLM  →  card
```

1. [Bangumi](https://bgm.tv) turns a fuzzy keyword into a definite show, its cover and aliases.
2. The Japanese title is searched for broadcast times; English and Chinese are tried if that fails.
3. A large language model turns the search results into a structured schedule.
4. Times are converted to your timezone and drawn as a card.

A typical lookup: 3 Bangumi calls, 1 Tavily call, 1 LLM call, about 4 seconds.

## What you need

| | Used for | Free tier |
|---|---|---|
| **Tavily API key** | Web search | 1000 searches / month |
| **LLM API key** | Structuring the schedule | Depends on the provider |

Supports Volcengine (Doubao), DeepSeek, Alibaba Model Studio (Qwen), OpenAI, Anthropic and any OpenAI-compatible endpoint. Settings include a step-by-step Tavily sign-up guide.

## Privacy

- No account, no server. Requests go straight from your phone to Bangumi, Tavily and the LLM provider you chose.
- Settings stay in the app's own folder with no storage permission; the anime list can be backed up to Download in one tap.
- API keys are stored AES-256-GCM encrypted with a device-bound key; they cannot be decrypted on another phone.
- Nothing is collected.

## Download

Android 6.0 or later. Android 11 or later is recommended so settings survive a reinstall.

APKs for every architecture are on the [Releases](https://github.com/erichuanp/anime-now/releases) page. Most phones want the `arm64-v8a` build.

## Status

Version 2026.9.3.0. The source is not public yet.

## Credits

Broadcast data from [Bangumi](https://bgm.tv). Search by [Tavily](https://tavily.com).

<br/>

<div align="center">
<sub>MIT License · © 2026 erichuanp</sub>
</div>
