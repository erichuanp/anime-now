"""bgmproxy 策略单元测试（不联网）。"""
import asyncio
import os
import tempfile
import unittest

os.environ.setdefault("BGM_CACHE_DIR", tempfile.mkdtemp())
import bgmproxy as bp  # noqa: E402


class GateTest(unittest.TestCase):
    def test_21_pass_9_rejected_and_3s_spacing(self):
        now = [1000.0]
        sleeps = []

        async def fake_sleep(d):
            sleeps.append(d)

        g = bp.Gate(3, 20, clock=lambda: now[0], sleep=fake_sleep)

        async def run():
            ok = busy = 0
            for _ in range(30):
                try:
                    await g.acquire()
                    ok += 1
                except bp.Busy:
                    busy += 1
            return ok, busy

        ok, busy = asyncio.run(run())
        self.assertEqual((ok, busy), (21, 9))
        self.assertEqual(sleeps, [3.0 * i for i in range(1, 21)])
        now[0] += 63
        self.assertEqual(g.depth(), 0)
        asyncio.run(g.acquire())  # 60 秒后队列空了，又能进


class QuotaTest(unittest.TestCase):
    def test_limit_and_day_rollover(self):
        day = ["2026-09-03"]
        q = bp.Quota(3, today=lambda: day[0])
        for _ in range(3):
            self.assertFalse(q.exhausted("1.2.3.4"))
            q.hit("1.2.3.4")
        self.assertTrue(q.exhausted("1.2.3.4"))
        self.assertFalse(q.exhausted("5.6.7.8"))
        day[0] = "2026-09-04"
        self.assertFalse(q.exhausted("1.2.3.4"))

    def test_persist_only_same_day(self):
        day = ["2026-09-03"]
        q = bp.Quota(3, today=lambda: day[0])
        q.hit("a")
        j = q.to_json()
        q2 = bp.Quota(3, today=lambda: day[0])
        q2.load(j)
        self.assertEqual(q2.counts, {"a": 1})
        day[0] = "2026-09-04"
        q3 = bp.Quota(3, today=lambda: day[0])
        q3.load(j)
        self.assertEqual(q3.counts, {})


class LfuTest(unittest.TestCase):
    def test_user_scenario_abc_abde_adf(self):
        """用户给的例子：容量 5 张，请求 ABC / ABDE / ADF → 淘汰 C。"""
        t = [0.0]

        def clock():
            t[0] += 1
            return t[0]

        d = tempfile.mkdtemp()
        c = bp.LfuCache(d, capacity=50, clock=clock)  # 每张 10 字节 → 满 5 张
        blob = b"0123456789"

        def request(keys):
            for k in keys:
                if c.get(k) is None:
                    c.put(k, blob, "image/jpeg")

        def counts():
            return {k: e["count"] for k, e in sorted(c.entries.items())}

        request("ABC")
        self.assertEqual(counts(), {"A": 1, "B": 1, "C": 1})
        request("ABDE")
        self.assertEqual(counts(), {"A": 2, "B": 2, "C": 1, "D": 1, "E": 1})
        request("ADF")
        self.assertEqual(counts(), {"A": 3, "B": 2, "D": 2, "E": 1, "F": 1})
        self.assertNotIn("C", c.entries)
        self.assertEqual(c.total, 50)
        # 磁盘上也只剩 5 个文件
        files = sum(len(fs) for _, _, fs in os.walk(d))
        self.assertEqual(files, 5)

    def test_tie_breaks_on_oldest(self):
        t = [0.0]

        def clock():
            t[0] += 1
            return t[0]

        c = bp.LfuCache(tempfile.mkdtemp(), capacity=20, clock=clock)
        c.put("X", b"0123456789", "image/jpeg")
        c.put("Y", b"0123456789", "image/jpeg")
        c.put("Z", b"0123456789", "image/jpeg")  # X、Y 都是 1 次，X 更老 → 淘汰 X
        self.assertEqual(sorted(c.entries), ["Y", "Z"])

    def test_reload_from_index(self):
        d = tempfile.mkdtemp()
        c = bp.LfuCache(d, capacity=100)
        c.put("A", b"aa", "image/png")
        c.get("A")
        j = c.to_json()
        c2 = bp.LfuCache(d, capacity=100)
        c2.load(j)
        self.assertEqual(c2.entries["A"]["count"], 2)
        self.assertEqual(c2.get("A")[1], b"aa")


class ApiCacheTest(unittest.TestCase):
    def test_ttl(self):
        t = [0.0]
        a = bp.ApiCache(300, clock=lambda: t[0])
        a.put("GET /x", 200, "application/json", b"{}")
        a.put("GET /y", 500, "application/json", b"{}")
        self.assertIsNotNone(a.peek("GET /x"))
        self.assertIsNone(a.peek("GET /y"))
        t[0] = 301
        self.assertIsNone(a.peek("GET /x"))


if __name__ == "__main__":
    unittest.main()
