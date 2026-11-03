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


class StreamReplaced(GrabdTest):
    """Firefox replaces a stream paused for a few seconds when it resumes:
    the recording follows the new stream instead of ending."""

    async def asyncSetUp(self):
        self.g.STREAM_GRACE = 0.5
        self.rec = self.g.Recorder()
        self.worker = asyncio.create_task(self.rec.queue.worker())
        self.streams = [self.stream()]
        self.fake_pipewire(self.rec, self.streams)
        self.links = []

        async def link(src, dst, channels):
            self.links.append(src)
            return [("1", "2")]
        self.rec._link = link

        async def no_input(item):
            pass
        self.rec._link_input = no_input
        await self.rec.refresh_streams()
        (self.item,) = self.rec.items.values()
        self.rec.request_toggle(self.item)
        await self.wait_for(lambda: self.item.state == "recording" and not self.item.pending)

    async def asyncTearDown(self):
        await self.rec.shutdown()
        if self.item.proc and self.item.proc.returncode is None:
            self.item.proc.kill()
        self.worker.cancel()

    async def replace(self, **new):
        self.streams[:] = [self.stream(**new)]
        await self.rec.refresh_streams()

    async def test_follows(self):
        await self.replace(index=8, node=51)
        await asyncio.sleep(0.1)
        self.assertEqual(list(self.rec.items.values()), [self.item], "no second entry")
        self.assertEqual(self.item.stream.idx, 8)
        self.assertEqual(self.links[-1], "51", "linked the new stream")
        await asyncio.sleep(0.7)                       # past the grace period
        self.assertEqual(self.item.state, "recording")

    async def test_follows_while_paused(self):
        self.rec.request_toggle(self.item)
        await self.wait_for(lambda: self.item.state == "paused" and not self.item.pending)
        await self.replace(index=8, node=51)
        await asyncio.sleep(0.7)
        self.assertEqual(self.item.state, "paused")
        self.rec.request_toggle(self.item)             # resume: the new stream
        await self.wait_for(lambda: self.item.state == "recording" and not self.item.pending)
        self.assertEqual(self.links[-1], "51")

    async def test_ends_without_replacement(self):
        self.streams.clear()
        await self.rec.refresh_streams()
        await asyncio.sleep(0.2)
        self.assertEqual(self.item.state, "recording", "waits for a replacement first")
        await self.wait_for(lambda: self.item.state in self.g.FINISHED)

    async def test_other_title_not_followed(self):
        await self.replace(index=8, node=51, title="Another video")
        await self.wait_for(lambda: self.item.state in self.g.FINISHED)
        self.assertEqual(len(self.rec.items), 2)

    async def test_other_process_not_followed(self):
        await self.replace(index=8, node=51, pid=999)
        await self.wait_for(lambda: self.item.state in self.g.FINISHED)
        self.assertEqual(len(self.rec.items), 2)


class _Players:
    """Stands in for grabd's MPRIS Players: whether the app still has the title."""
    loaded = True

    def has_media(self, pid, title):
        return self.loaded

    def title_for(self, pid):
        return ""


class StreamReplacedLate(StreamReplaced):
    """After a long pause the new stream comes only once the player has
    re-buffered: wait while the player still has the title loaded."""

    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.rec.players = _Players()

    async def test_late_replacement(self):
        self.streams.clear()
        await self.rec.refresh_streams()
        await asyncio.sleep(1.5)                       # 3 grace periods, the player has it
        self.assertEqual(self.item.state, "recording")
        await self.replace(index=8, node=51)
        await asyncio.sleep(0.1)
        self.assertEqual(self.item.stream.idx, 8)
        self.assertEqual(list(self.rec.items.values()), [self.item])

    async def test_player_closed(self):
        self.streams.clear()
        await self.rec.refresh_streams()
        await asyncio.sleep(0.7)
        self.assertEqual(self.item.state, "recording")
        self.rec.players.loaded = False                # tab closed / other video
        await self.wait_for(lambda: self.item.state in self.g.FINISHED)

    async def test_ends_without_replacement(self):     # (inherited: no player here)
        self.rec.players = None
        await super().test_ends_without_replacement()

    async def test_other_title_not_followed(self):
        self.rec.players.loaded = False
        await super().test_other_title_not_followed()

    async def test_other_process_not_followed(self):
        self.rec.players.loaded = False
        await super().test_other_process_not_followed()


class HasMedia(GrabdTest):
    def test_match(self):
        p = self.g.Players(None, lambda: None)
        p.players["a"] = {"owner": ":1", "pid": "7731", "status": "Paused", "title": "x",
                          "media": "КАК СВЯЩЕННАЯ ГОРА 1991"}
        self.assertTrue(p.has_media("7731", "КАК СВЯЩЕННАЯ ГОРА 1991 - YouTube"))
        self.assertFalse(p.has_media("7731", "Другое видео - YouTube"))
        self.assertFalse(p.has_media("1", "КАК СВЯЩЕННАЯ ГОРА 1991 - YouTube"))
        p.players["a"]["status"] = "Stopped"
        self.assertFalse(p.has_media("7731", "КАК СВЯЩЕННАЯ ГОРА 1991 - YouTube"))
