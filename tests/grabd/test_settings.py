import asyncio
import json
import os

from common import GrabdTest


class Settings(GrabdTest):
    def test_folder(self):
        S = self.g.SETTINGS
        self.assertEqual(S.outdir, self.out)
        S.update({"folder": self.root + "/rec/"})
        self.assertEqual(S.outdir, self.root + "/rec")
        self.assertTrue(os.path.isdir(self.root + "/rec"))
        with open(self.root + "/cfg/grabd/settings.json") as f:
            self.assertEqual(json.load(f), {"folder": self.root + "/rec"})
        self.assertEqual(self.g.Settings().outdir, self.root + "/rec")    # read back
        S.update({"folder": self.out})                                     # the default
        self.assertEqual(S.values["folder"], "")

    def test_rejected(self):
        S = self.g.SETTINGS
        for bad in ({"folder": "rel/path"}, {"folder": 1}, {"trash": True},
                    {"folder": "/proc/nope"}):
            with self.subTest(bad=bad), self.assertRaises(self.g.SettingsError):
                S.update(bad)
        self.assertEqual(S.outdir, self.out)


class Discard(GrabdTest):
    async def test_delete_permanently(self):
        path = os.path.join(self.root, "a.mp3")
        open(path, "w").close()
        self.assertEqual(await self.g.discard([path], permanently=True), "")
        self.assertFalse(os.path.exists(path))

    async def test_error(self):
        err = await self.g.discard([self.root + "/missing.mp3"], permanently=True)
        self.assertIn("could not delete", err)
