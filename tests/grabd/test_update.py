import asyncio
import os
import shutil

from common import GRABD, GrabdTest, load_grabd


class _Rec:
    busy = True

    def idle(self):
        return not self.busy


class UpdateLoop(GrabdTest):
    async def test_restarts_when_replaced_and_idle(self):
        copy = os.path.join(self.root, "grabd")
        shutil.copy(GRABD, copy)
        g = load_grabd(self.root, copy)
        g.UPDATE_CHECK_INTERVAL = 0.1
        rec, fired = _Rec(), []
        task = asyncio.create_task(g.update_loop(rec, lambda: fired.append(1)))
        await asyncio.sleep(0.3)
        self.assertEqual(fired, [], "fired without an update")
        os.replace(copy, copy + ".old")                     # replaced as pacman does
        shutil.copy(copy + ".old", copy)
        await asyncio.sleep(0.4)
        self.assertEqual(fired, [], "fired while recording")
        rec.busy = False
        await self.wait_for(lambda: fired)
        await asyncio.sleep(0.1)
        self.assertTrue(task.done())
