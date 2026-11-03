import asyncio
import os

from common import GrabdTest

DEAD_PID = 999999999                       # above pid_max: never a running process


class _Windows:
    """Stands in for grabd's Windows: window titles by process id."""

    def __init__(self, titles):
        self.titles = titles

    def title_for(self, pid):
        return self.titles.get(pid, "")


class ZoomTest(GrabdTest):
    def zoom(self, index=7, node=50):
        return self.stream(index=index, node=node, title="playStream", app="ZOOM VoiceEngine",
                           pid=os.getpid())


class Titles(ZoomTest):
    """Zoom's stream is called "playStream" and Zoom has no MPRIS player:
    the title comes from its window, else the app's name."""

    def test_generic(self):
        self.assertFalse(self.g.real_title("playStream"))
        self.assertTrue(self.g.real_title("Play Stream Radio"))

    def test_sources(self):
        s = self.g.Stream(self.zoom(), window_title="Zoom Meeting")
        self.assertEqual((s.title, s.title_source), ("Zoom Meeting", "window"))
        s = self.g.Stream(self.zoom(), player_title="Song", window_title="Zoom Meeting")
        self.assertEqual((s.title, s.title_source), ("Song", "player"))
        s = self.g.Stream(self.zoom())
        self.assertEqual((s.title, s.title_source), ("ZOOM VoiceEngine", "app"))
        self.assertFalse(s.has_title)
        s = self.g.Stream(self.stream(title="Song"), window_title="Zoom Meeting")
        self.assertEqual((s.title, s.title_source), ("Song", "media"))

    def test_window_title_of_parent(self):
        w = self.g.Windows(None, lambda: None)
        w.set('[["%d", "Main window"], ["%d", "Other"], ["%d", "Behind"]]'
              % (os.getppid(), 1, os.getppid()))
        self.assertEqual(w.title_for(str(os.getppid())), "Main window", "topmost first")
        self.assertEqual(w.title_for(str(os.getpid())), "Main window", "via the parent")
        self.assertEqual(w.title_for(str(DEAD_PID)), "")
        w.set("not json")
        self.assertEqual(w.title_for(str(os.getppid())), "Main window", "bad reports ignored")


class CallRecording(ZoomTest):
    """A call: titled from the window, stamped with the start time, followed
    through stream replacements while the app runs (Zoom replaces its
    stream during a call)."""

    async def asyncSetUp(self):
        self.g.STREAM_GRACE = 0.2
        self.g.CALL_GRACE = 1.0
        self.rec = self.g.Recorder()
        self.rec.windows = _Windows({str(os.getpid()): "Zoom Meeting"})
        self.worker = asyncio.create_task(self.rec.queue.worker())
        self.streams = [self.zoom()]
        self.fake_pipewire(self.rec, self.streams)

        async def no_input(item):
            pass
        self.rec._link_input = no_input
        await self.rec.refresh_streams()
        (self.item,) = self.rec.items.values()
        self.assertEqual(self.item.title, "Zoom Meeting")
        self.rec.request_toggle(self.item)
        await self.wait_for(lambda: self.item.state == "recording" and not self.item.pending)

    async def asyncTearDown(self):
        await self.rec.shutdown()
        if self.item.proc and self.item.proc.returncode is None:
            self.item.proc.kill()
        self.worker.cancel()

    async def test_stamped(self):
        self.assertRegex(self.item.title, r"^Zoom Meeting, \d{1,2} \w+ \d\d:\d\d$")
        self.assertNotRegex(os.path.basename(self.item.flac), r", \d", "file name: no time twice")
        self.rec.windows.titles[str(os.getpid())] = "Zoom Meeting - Screen sharing"
        await self.rec.refresh_streams()
        self.assertTrue(self.item.title.startswith("Zoom Meeting, "), "stays while recording")

    async def test_unstamped_when_discarded(self):
        await self.rec.remove_record(self.item, permanently=True)
        self.assertEqual((self.item.state, self.item.title), ("available", "Zoom Meeting"))

    async def test_follows_late_replacement(self):
        self.streams.clear()
        await self.rec.refresh_streams()
        await asyncio.sleep(0.6)                       # 3 short grace periods
        self.assertEqual(self.item.state, "recording", "a call waits longer")
        self.rec.windows.titles[str(os.getpid())] = "Zoom Meeting - Screen sharing"
        self.streams[:] = [self.zoom(index=8, node=51)]
        await self.rec.refresh_streams()
        self.assertEqual(self.item.stream.idx, 8, "followed despite the new window title")
        self.assertEqual(list(self.rec.items.values()), [self.item])

    async def test_ends_after_call_grace(self):
        self.streams.clear()
        await self.rec.refresh_streams()
        await asyncio.sleep(0.6)
        self.assertEqual(self.item.state, "recording")
        await self.wait_for(lambda: self.item.state in self.g.FINISHED, timeout=3)

    async def test_ends_when_app_gone(self):
        self.item.process = str(DEAD_PID)              # the app quit
        self.streams.clear()
        await self.rec.refresh_streams()
        await self.wait_for(lambda: self.item.state in self.g.FINISHED, timeout=0.6)
