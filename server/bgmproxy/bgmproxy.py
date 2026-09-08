#!/usr/bin/env python3
"""番时 Bangumi 反代（nginx → 本服务 → api.bgm.tv / lain.bgm.tv）。

规则（全部由用户指定）：
  * 全局排队：每 QUEUE_INTERVAL 秒放行一个请求，最多排 QUEUE_MAX 个，
    再多的请求立即 503 {"error":"mirror_busy"}。API 和图片共用一个队列，缓存命中也排队。
  * 每客户端每日配额：只有真正打到 Bangumi 的请求（缓存未命中）才计数，
    超过 DAILY_QUOTA 次返回 429 {"error":"ip_quota"}。按 TZ 的自然日重置。
    计数的 key 是 IP 加随机盐的 SHA-256 前 16 位，明文 IP 不落盘、不进日志。
  * 图片 LFU 缓存：命中次数最少的先淘汰，次数相同淘汰最早加入的；容量 CACHE_BYTES。
  * API：匿名 GET 结果短缓存 API_TTL 秒（404 缓存 60 秒），POST 不缓存。
"""
import asyncio
import datetime as dt
import hashlib
import json
import logging
import os
import secrets
import signal
import time
from zoneinfo import ZoneInfo

import aiohttp
from aiohttp import web

log = logging.getLogger("bgmproxy")

LISTEN_HOST, LISTEN_PORT = os.environ.get("BGM_LISTEN", "127.0.0.1:8090").rsplit(":", 1)
API_HOST = os.environ.get("BGM_API_HOST", "bgmapi.erichuanp.com")
IMG_HOST = os.environ.get("BGM_IMG_HOST", "bgmimg.erichuanp.com")
API_UPSTREAM = os.environ.get("BGM_API_UPSTREAM", "https://api.bgm.tv")
IMG_UPSTREAM = os.environ.get("BGM_IMG_UPSTREAM", "https://lain.bgm.tv")
QUEUE_INTERVAL = float(os.environ.get("BGM_QUEUE_INTERVAL", "3"))
QUEUE_MAX = int(os.environ.get("BGM_QUEUE_MAX", "20"))
DAILY_QUOTA = int(os.environ.get("BGM_DAILY_QUOTA", "100"))
CACHE_DIR = os.environ.get("BGM_CACHE_DIR", "/var/cache/bgmproxy")
CACHE_BYTES = int(os.environ.get("BGM_CACHE_BYTES", str(500 * 1024 * 1024)))
API_TTL = int(os.environ.get("BGM_API_TTL", "300"))
TZ = ZoneInfo(os.environ.get("BGM_TZ", "Asia/Shanghai"))
UPSTREAM_TIMEOUT = float(os.environ.get("BGM_UPSTREAM_TIMEOUT", "30"))
DEFAULT_UA = "erichuanp/anime-now (https://github.com/erichuanp/anime-now)"

BUSY_BODY = {"error": "mirror_busy", "description": "镜像站暂时不可用，请在几分钟后尝试"}
QUOTA_BODY = {"error": "ip_quota", "description": "当前IP请求次数过多，请明天再试吧"}
UPSTREAM_BODY = {"error": "upstream", "description": "Bangumi 没有响应，请稍后再试"}


class Busy(Exception):
    pass


class Gate:
    """漏桶：每 interval 秒放行一个，排队超过 max_wait 个就拒绝。"""

    def __init__(self, interval, max_wait, clock=time.monotonic, sleep=asyncio.sleep):
        self.interval = interval
        self.max_wait = max_wait
        self._clock = clock
        self._sleep = sleep
        self._next = 0.0

    def depth(self, now=None):
        now = self._clock() if now is None else now
        return max(0.0, self._next - now) / self.interval

    async def acquire(self):
        now = self._clock()
        if self._next - now > self.interval * self.max_wait + 1e-9:
            raise Busy()
        slot = max(now, self._next)
        self._next = slot + self.interval
        if slot > now:
            await self._sleep(slot - now)


class Quota:
    """每客户端每自然日配额，只统计打到上游的请求。key 是 IP 的盐化哈希。"""

    def __init__(self, limit, tz=TZ, today=None):
        self.limit = limit
        self._tz = tz
        self._today = today or (lambda: dt.datetime.now(self._tz).date().isoformat())
        self.day = self._today()
        self.counts = {}

    def _roll(self):
        d = self._today()
        if d != self.day:
            self.day = d
            self.counts = {}

    def exhausted(self, ip):
        self._roll()
        return self.counts.get(ip, 0) >= self.limit

    def hit(self, ip):
        self._roll()
        self.counts[ip] = self.counts.get(ip, 0) + 1

    def to_json(self):
        return {"day": self.day, "counts": self.counts}

    def load(self, j):
        if j and j.get("day") == self._today():
            self.day = j["day"]
            self.counts = dict(j.get("counts", {}))


class LfuCache:
    """磁盘 LFU：淘汰 (次数最少, 最早加入) 的条目。"""

    def __init__(self, directory, capacity, clock=time.time):
        self.dir = directory
        self.capacity = capacity
        self._clock = clock
        self.entries = {}  # key -> {"count","added","size","ctype","file"}
        self.total = 0
        os.makedirs(self.dir, exist_ok=True)

    def _path(self, key):
        h = hashlib.sha1(key.encode()).hexdigest()
        d = os.path.join(self.dir, h[:2])
        os.makedirs(d, exist_ok=True)
        return os.path.join(d, h)

    def peek(self, key):
        return self.entries.get(key)

    def get(self, key):
        e = self.entries.get(key)
        if e is None:
            return None
        e["count"] += 1
        try:
            with open(e["file"], "rb") as f:
                return e, f.read()
        except OSError:
            self.remove(key)
            return None

    def put(self, key, data, ctype):
        size = len(data)
        if size > self.capacity:
            return None
        if key in self.entries:
            self.remove(key)
        while self.entries and self.total + size > self.capacity:
            self.evict()
        path = self._path(key)
        with open(path, "wb") as f:
            f.write(data)
        e = {"count": 1, "added": self._clock(), "size": size, "ctype": ctype, "file": path}
        self.entries[key] = e
        self.total += size
        return e

    def evict(self):
        key, e = min(self.entries.items(), key=lambda kv: (kv[1]["count"], kv[1]["added"]))
        log.info("evict %s (count=%d size=%d)", key, e["count"], e["size"])
        self.remove(key)
        return key

    def remove(self, key):
        e = self.entries.pop(key, None)
        if e is None:
            return
        self.total -= e["size"]
        try:
            os.remove(e["file"])
        except OSError:
            pass

    def to_json(self):
        return {"entries": self.entries}

    def load(self, j):
        for key, e in (j or {}).get("entries", {}).items():
            if os.path.isfile(e.get("file", "")):
                self.entries[key] = e
                self.total += e["size"]
        while self.entries and self.total > self.capacity:
            self.evict()


class ApiCache:
    def __init__(self, ttl, clock=time.time):
        self.ttl = ttl
        self._clock = clock
        self.items = {}  # key -> (expires, status, ctype, body)

    def peek(self, key):
        v = self.items.get(key)
        if v is None:
            return None
        if v[0] < self._clock():
            del self.items[key]
            return None
        return v

    def put(self, key, status, ctype, body):
        if status == 200:
            ttl = self.ttl
        elif status == 404:
            ttl = min(60, self.ttl)
        else:
            return
        if len(self.items) > 5000:
            now = self._clock()
            for k in [k for k, v in self.items.items() if v[0] < now]:
                del self.items[k]
        self.items[key] = (self._clock() + ttl, status, ctype, body)


# ---------------------------------------------------------------- server

class Proxy:
    def __init__(self):
        self.gate = Gate(QUEUE_INTERVAL, QUEUE_MAX)
        self.quota = Quota(DAILY_QUOTA)
        self.img = LfuCache(os.path.join(CACHE_DIR, "img"), CACHE_BYTES)
        self.api = ApiCache(API_TTL)
        self.state_file = os.path.join(CACHE_DIR, "state.json")
        self.ip_salt = secrets.token_hex(16)
        self._dirty = False
        self.session = None
        self._load()

    def _load(self):
        try:
            with open(self.state_file) as f:
                j = json.load(f)
            self.img.load(j.get("img"))
            self.quota.load(j.get("quota"))
            # Reusing the stored salt is what makes the counters survive a
            # restart; a fresh salt would silently reset everyone's quota.
            self.ip_salt = j.get("ip_salt") or self.ip_salt
            log.info("state loaded: %d cached images (%.1f MB), quota day %s (%d clients)",
                     len(self.img.entries), self.img.total / 1048576, self.quota.day, len(self.quota.counts))
        except FileNotFoundError:
            pass
        except Exception as e:  # noqa: BLE001
            log.warning("state load failed: %s", e)

    def save(self):
        tmp = self.state_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"img": self.img.to_json(), "quota": self.quota.to_json(),
                       "ip_salt": self.ip_salt}, f)
        os.replace(tmp, self.state_file)
        self._dirty = False

    async def saver(self):
        while True:
            await asyncio.sleep(5)
            if self._dirty:
                try:
                    self.save()
                except Exception as e:  # noqa: BLE001
                    log.warning("state save failed: %s", e)

    @staticmethod
    def client_key(req, salt):
        """Per-client quota key: a salted hash, never the address itself.

        The salt is random per deployment and lives only in state.json, so the
        stored counters cannot be walked back to an IP even with the whole
        address space to try.
        """
        ip = req.headers.get("CF-Connecting-IP")
        if not ip:
            xff = req.headers.get("X-Forwarded-For", "")
            ip = xff.split(",")[0].strip() if xff else None
        ip = ip or (req.remote or "?")
        return hashlib.sha256(f"{salt}:{ip}".encode()).hexdigest()[:16]

    @staticmethod
    def cors(kind):
        return {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, HEAD, POST, OPTIONS" if kind == "api" else "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization, User-Agent",
            "Access-Control-Max-Age": "86400",
            "X-Robots-Tag": "noindex, nofollow, noarchive",
        }

    def err(self, status, body, kind, extra=None):
        h = self.cors(kind)
        if extra:
            h.update(extra)
        return web.json_response(body, status=status, headers=h, dumps=lambda o: json.dumps(o, ensure_ascii=False))

    async def handle(self, req):
        host = req.headers.get("Host", "").split(":")[0].lower()
        if req.path == "/healthz":
            return web.Response(text="ok\n")
        if host == API_HOST:
            kind = "api"
        elif host == IMG_HOST:
            kind = "img"
        else:
            raise web.HTTPNotFound()

        allowed = ("GET", "HEAD", "POST", "OPTIONS") if kind == "api" else ("GET", "HEAD", "OPTIONS")
        if req.method not in allowed:
            return self.err(405, {"error": "method_not_allowed"}, kind)
        if req.method == "OPTIONS":
            return web.Response(status=204, headers=self.cors(kind))

        ip = self.client_key(req, self.ip_salt)
        has_auth = "Authorization" in req.headers
        if kind == "img":
            key = req.path
            hit = self.img.peek(key)
        else:
            key = f"{req.method} {req.path_qs}"
            hit = None if (has_auth or req.method != "GET") else self.api.peek(key)

        # 未命中且配额已用完：不排队，直接拒
        if hit is None and self.quota.exhausted(ip):
            return self.err(429, QUOTA_BODY, kind, {"Retry-After": "3600"})
        try:
            await self.gate.acquire()
        except Busy:
            return self.err(503, BUSY_BODY, kind, {"Retry-After": "120"})

        if kind == "img":
            return await self.serve_img(req, key, ip)
        return await self.serve_api(req, key, ip, has_auth)

    async def serve_img(self, req, key, ip):
        got = self.img.get(key)
        if got is not None:
            e, data = got
            self._dirty = True
            return self.reply("img", 200, e["ctype"], data, "HIT", req)
        if self.quota.exhausted(ip):
            return self.err(429, QUOTA_BODY, "img", {"Retry-After": "3600"})
        self.quota.hit(ip)
        self._dirty = True
        try:
            async with self.session.get(IMG_UPSTREAM + key, headers={"User-Agent": DEFAULT_UA}, allow_redirects=True) as r:
                data = await r.read()
                status, ctype = r.status, r.headers.get("Content-Type", "application/octet-stream")
        except Exception as e:  # noqa: BLE001
            log.warning("img upstream %s failed: %s", key, e)
            return self.err(502, UPSTREAM_BODY, "img")
        if status == 200 and ctype.startswith("image/"):
            self.img.put(key, data, ctype)
        return self.reply("img", status, ctype, data, "MISS", req)

    async def serve_api(self, req, key, ip, has_auth):
        cached = None if (has_auth or req.method != "GET") else self.api.peek(key)
        if cached is not None:
            _, status, ctype, body = cached
            return self.reply("api", status, ctype, body, "HIT", req)
        if self.quota.exhausted(ip):
            return self.err(429, QUOTA_BODY, "api", {"Retry-After": "3600"})
        self.quota.hit(ip)
        self._dirty = True
        headers = {
            "User-Agent": req.headers.get("User-Agent") or DEFAULT_UA,
            "Accept": req.headers.get("Accept", "application/json"),
        }
        for h in ("Authorization", "Content-Type"):
            if h in req.headers:
                headers[h] = req.headers[h]
        body = await req.read() if req.method == "POST" else None
        try:
            async with self.session.request(req.method, API_UPSTREAM + req.path_qs, headers=headers, data=body,
                                            allow_redirects=False) as r:
                data = await r.read()
                status, ctype = r.status, r.headers.get("Content-Type", "application/json")
                location = r.headers.get("Location")
        except Exception as e:  # noqa: BLE001
            log.warning("api upstream %s failed: %s", key, e)
            return self.err(502, UPSTREAM_BODY, "api")
        if req.method == "GET" and not has_auth:
            self.api.put(key, status, ctype, data)
        extra = {"Location": location} if location else None
        return self.reply("api", status, ctype, data, "MISS", req, extra)

    def reply(self, kind, status, ctype, data, xcache, req, extra=None):
        h = self.cors(kind)
        h["X-Cache"] = xcache
        if kind == "img":
            h["Cache-Control"] = "public, max-age=2592000, immutable"
        else:
            h["Cache-Control"] = "no-store"
        if extra:
            h.update(extra)
        if req.method == "HEAD":
            data = b""
        return web.Response(status=status, body=data, content_type=ctype.split(";")[0].strip(),
                            charset="utf-8" if ctype.startswith(("application/json", "text/")) else None, headers=h)


async def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    p = Proxy()
    p.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=UPSTREAM_TIMEOUT))
    app = web.Application(client_max_size=64 * 1024)
    app.router.add_route("*", "/{tail:.*}", p.handle)
    # No client address in the access log: the request path alone already says
    # which anime was looked up, and pairing that with an IP is exactly what
    # this mirror promises not to keep.
    runner = web.AppRunner(app, access_log_format='"%r" %s %b %Tf "%{X-Cache}o"')
    await runner.setup()
    await web.TCPSite(runner, LISTEN_HOST, int(LISTEN_PORT)).start()
    log.info("listening on %s:%s  queue=1/%.0fs max %d  quota=%d/day  cache=%d MB",
             LISTEN_HOST, LISTEN_PORT, QUEUE_INTERVAL, QUEUE_MAX, DAILY_QUOTA, CACHE_BYTES // 1048576)
    saver = asyncio.create_task(p.saver())
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for s in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(s, stop.set)
    await stop.wait()
    saver.cancel()
    p.save()
    await p.session.close()
    await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
