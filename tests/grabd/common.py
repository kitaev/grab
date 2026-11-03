"""Helpers for grabd's tests: load grabd as a module with its folders in a
temporary directory, and fake the PipeWire side."""
import asyncio
import importlib.machinery
import importlib.util
import os
import shutil
import tempfile
import unittest

GRABD = os.path.join(os.path.dirname(__file__), "..", "..", "grabd")
FAKEBIN = os.path.join(os.path.dirname(__file__), "fakebin")


def load_grabd(root, path=GRABD):
    """A fresh grabd module whose config and default recordings folder are
    under root (grabd reads them when it is loaded)."""
    os.environ["XDG_CONFIG_HOME"] = os.path.join(root, "cfg")
    os.environ["GRAB_OUTDIR"] = os.path.join(root, "out")
    os.makedirs(os.environ["GRAB_OUTDIR"], exist_ok=True)
    loader = importlib.machinery.SourceFileLoader("grabd_under_test", path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    g = importlib.util.module_from_spec(spec)
    loader.exec_module(g)
    return g


class GrabdTest(unittest.IsolatedAsyncioTestCase):
    """Each test gets its own grabd module, temporary folders, and a fake
    ffmpeg (fakebin) first on PATH."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="grabd-test-")
        self.addCleanup(shutil.rmtree, self.root, True)
        self.saved_env = dict(os.environ)
        self.addCleanup(self._restore_env)
        os.environ["PATH"] = FAKEBIN + os.pathsep + os.environ.get("PATH", "")
        self.g = load_grabd(self.root)
        self.out = os.path.join(self.root, "out")

    def _restore_env(self):
        os.environ.clear()
        os.environ.update(self.saved_env)

    def fake_pipewire(self, rec, streams):
        """No pactl/pw-link: `streams` (a list of sink-input dicts, changed by
        the test) is what pactl lists; sinks and links always work."""
        async def pactl_json(kind):
            return list(streams) if kind == "sink-inputs" else []

        async def run(*cmd):
            return 0, ""

        async def load_sink(*a):
            return "1"

        async def sink_node(name):
            return "60"

        async def link(src, dst, channels):
            return [("1", "2")]

        self.g.pactl_json, self.g.run = pactl_json, run
        rec._load_sink, rec._sink_node, rec._link = load_sink, sink_node, link

    @staticmethod
    def stream(index=7, title="Song", node=50):
        return {"index": index, "corked": False,
                "properties": {"object.id": node, "media.name": title}}

    async def wait_for(self, cond, timeout=5.0):
        for _ in range(int(timeout / 0.05)):
            if cond():
                return
            await asyncio.sleep(0.05)
        self.fail("timed out waiting")
