import asyncio
import os

from common import GrabdTest


class Ids(GrabdTest):
    def test_unique_per_run(self):
        a, b = self.g.Item(title="a"), self.g.Item(title="b")
        self.assertNotEqual(a.id, b.id)
        other_run = self.g.Item.run
        g2 = __import__("common").load_grabd(self.root)       # grabd restarted
        self.assertNotEqual(g2.Item(title="a").id, a.id)
        self.assertNotEqual(g2.Item.run, other_run)


class EncodeQueue(GrabdTest):
    async def test_worker_survives_errors(self):
        calls = []

        async def bad_encode(*a):
            raise OSError(36, "File name too long")

        async def done(item, final, ok, saved, sec):
            calls.append((item.title, ok))
            if item.title == "boom":
                raise RuntimeError("on_done broke")
        self.g.encode_snapshot = bad_encode
        q = self.g.EncodeQueue(done, lambda item: {})
        worker = asyncio.create_task(q.worker())
        for t in ("a", "boom", "c"):
            q.request(self.g.Item(title=t), final=True)
        await asyncio.wait_for(q.drain(), 2)
        self.assertEqual(calls, [("a", False), ("boom", False), ("c", False)])
        self.assertFalse(worker.done())
        worker.cancel()

    async def test_final_states(self):
        rec = self.g.Recorder()
        died = self.g.Item(title="d")
        died.ffmpeg_died, died.error = True, "recording stopped: ffmpeg exited (1)"
        await rec.encoded(died, True, True, False, 0.0)
        self.assertEqual(died.state, "failed")
        quiet = self.g.Item(title="e")
        await rec.encoded(quiet, True, True, False, 0.0)
        self.assertEqual(quiet.state, "empty")


class FfmpegWatch(GrabdTest):
    async def test_exits_by_itself(self):
        rec = self.g.Recorder()
        finalized = []

        async def finalize(item):
            finalized.append(item.title)
        rec.finalize = finalize
        x = self.g.Item(title="x")
        x.state, x.flac = "recording", os.path.join(self.out, ".x.flac")
        x.proc = await asyncio.create_subprocess_exec("sh", "-c", "sleep 0.2; exit 3")
        await rec._watch_ffmpeg(x, x.proc)
        self.assertEqual(finalized, ["x"])
        self.assertTrue(x.ffmpeg_died)
        self.assertIn("exited (3)", x.error)

    async def test_stopped_by_grabd(self):
        rec = self.g.Recorder()
        finalized = []

        async def finalize(item):
            finalized.append(item.title)
        rec.finalize = finalize
        y = self.g.Item(title="y")
        y.state = "recording"
        y.proc = await asyncio.create_subprocess_exec("sh", "-c", "sleep 0.2")
        t = asyncio.create_task(rec._watch_ffmpeg(y, y.proc))
        y.proc_stopping = True
        await t
        self.assertEqual(finalized, [])
        self.assertFalse(y.ffmpeg_died)


class StreamGoneWhileStarting(GrabdTest):
    """The stream ends while its recording starts (e.g. while the echo
    canceller comes up): nothing may be left recording unseen."""

    async def asyncSetUp(self):
        self.rec = self.g.Recorder()
        self.worker = asyncio.create_task(self.rec.queue.worker())
        self.streams = [self.stream()]
        self.fake_pipewire(self.rec, self.streams)

        async def slow_input(item):
            await asyncio.sleep(0.3)
        self.rec._link_input = slow_input
        await self.rec.refresh_streams()
        (self.item,) = self.rec.items.values()

    async def asyncTearDown(self):
        await self.rec.shutdown()
        if self.item.proc and self.item.proc.returncode is None:
            self.item.proc.kill()
        self.worker.cancel()

    async def test_started(self):
        self.rec.request_toggle(self.item)
        await asyncio.sleep(0.1)
        self.streams.clear()
        await self.rec.refresh_streams()
        await self.wait_for(lambda: self.item.state in self.g.FINISHED)
        self.assertIn(self.item.id, self.rec.items)
        self.assertEqual(self.item.state, "empty")
        self.assertIsNotNone(self.item.proc.returncode, "ffmpeg still running")

    async def test_start_failed(self):
        async def no_link(src, dst, channels):
            await asyncio.sleep(0.3)
            return []
        self.rec._link = no_link
        self.rec.request_toggle(self.item)
        await asyncio.sleep(0.1)
        self.streams.clear()
        await self.rec.refresh_streams()
        await self.wait_for(lambda: not self.item.pending)
        self.assertNotIn(self.item.id, self.rec.items)
