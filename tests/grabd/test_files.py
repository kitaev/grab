import asyncio
import os
import time

from common import GrabdTest


class Names(GrabdTest):
    def test_fname(self):
        f = self.g.fname
        self.assertEqual(f('a/b:c\\d"e\'f\x01g'), "a_b_c_d_e_f_g")
        self.assertEqual(f("   "), "audio")
        long = f("Ж" * 300)                          # 2 bytes a letter
        self.assertLessEqual(len(long.encode()), self.g.FNAME_BYTES)
        self.assertEqual(long, "Ж" * 100)            # at most 120 chars, 200 bytes

    def test_unique_paths(self):
        rec = self.g.Recorder()
        f1, m1 = rec._new_paths("2026_x")
        self.assertEqual((os.path.basename(f1), os.path.basename(m1)), (".2026_x.flac", "2026_x.mp3"))
        open(f1, "w").close()                        # taken on disk
        f2, m2 = rec._new_paths("2026_x")
        self.assertTrue(f2.endswith(".2026_x (2).flac") and m2.endswith("2026_x (2).mp3"))
        item = self.g.Item(title="t")                # taken by an item
        item.flac, item.mp3 = f2, m2
        rec.items[item.id] = item
        self.assertTrue(rec._new_paths("2026_x")[0].endswith("(3).flac"))


class RemoveFailed(GrabdTest):
    async def test_keeps_flac_visible(self):
        """Removing a failed entry (not its files) keeps its FLAC as a visible
        file, not found again as a crashed recording at the next start."""
        rec = self.g.Recorder()
        item = self.g.Item(title="f")
        item.state = "failed"
        item.flac = os.path.join(self.out, ".2026-11-03_10-00-00_f.flac")
        item.mp3 = os.path.join(self.out, "2026-11-03_10-00-00_f.mp3")
        open(item.flac, "w").close()
        open(os.path.join(self.out, "2026-11-03_10-00-00_f.flac"), "w").close()   # name taken
        rec.items[item.id] = item
        await rec.remove(item, False)
        self.assertNotIn(item.id, rec.items)
        self.assertEqual(sorted(os.listdir(self.out)),
                         ["2026-11-03_10-00-00_f (2).flac", "2026-11-03_10-00-00_f.flac"])
        await rec.recover_orphans()
        self.assertEqual(rec.items, {})


class Tags(GrabdTest):
    async def test_read_in_a_thread(self):
        """A slow tag read (big folders) doesn't stall grabd's loop."""
        if not self.g.mutagen:
            self.skipTest("python-mutagen not installed")
        self.g.probe_mutagen = lambda path: (time.sleep(0.5), None)[1]
        ticks = 0

        async def tick():
            nonlocal ticks
            while True:
                await asyncio.sleep(0.05)
                ticks += 1
        t = asyncio.create_task(tick())
        await self.g.tag_info(os.path.join(self.out, "x.mp3"))
        t.cancel()
        self.assertGreaterEqual(ticks, 5)
