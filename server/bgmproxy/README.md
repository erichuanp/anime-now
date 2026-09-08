# 番时镜像

`bgmapi.erichuanp.com` / `bgmimg.erichuanp.com` 的服务端：

```
cloudflared tunnel "bgm"  →  nginx 127.0.0.1:8080  →  bgmproxy.py 127.0.0.1:8090  →  api.bgm.tv / lain.bgm.tv
```

| 文件 | 服务器上的位置 |
|---|---|
| `bgmproxy.py` / `test_bgmproxy.py` | `/opt/bgmproxy/` |
| `bgmproxy.service` | `/etc/systemd/system/bgmproxy.service` |
| `bgmproxy.env.example` | `/etc/default/bgmproxy`（改完 `systemctl restart bgmproxy`） |
| `nginx-bangumi-proxy.conf` | `/etc/nginx/sites-available/bangumi-proxy.conf` |
| `cloudflared-config.yml.example` | `/etc/cloudflared/config.yml`（真实文件多 `tunnel:` / `credentials-file:` 两行） |

规则都在 `bgmproxy.py`：

- 全局排队：每 3 秒放行一个请求，最多排 20 个，超出立即 `503 {"error":"mirror_busy"}`。API 和图片共用，缓存命中也排队。
- 每客户端每自然日（北京时间）100 次，只统计真正打到 Bangumi 的请求；超出 `429 {"error":"ip_quota"}`。
  计数的 key 不是 IP 本身，而是 `CF-Connecting-IP` 加随机盐后的 SHA-256 前 16 位；盐随机生成、只存在
  `state.json` 里。明文 IP 既不落盘也不进日志（access log 也不记录客户端地址）。
- 图片 LFU 缓存 500 MB（`/var/cache/bgmproxy/img`）：满了淘汰「命中次数最少、相同则最早加入」的；索引、配额计数和哈希盐都在 `state.json`，重启不丢（盐丢了配额会重置）。
- API 匿名 GET 结果缓存 5 分钟（404 一分钟），POST 不缓存。

单元测试（策略部分，不联网）：`cd /opt/bgmproxy && BGM_CACHE_DIR=/tmp/t python3 -m unittest -q test_bgmproxy`。
日志：`journalctl -u bgmproxy -f`。隧道是纯出站的，服务器不需要开放任何入站端口。
