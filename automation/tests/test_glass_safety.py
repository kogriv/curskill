"""Чистые проверки без glass и без tesseract, кроме тоггла на пустом снимке."""
from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from automation.glass_agents import (
    _ocr_name_match,
    agent_on_host,
    classify,
    find_anchor,
    handoff_failure,
    mcp_source_toggle,
    merge_mcp_json,
    pick_handoff_agent,
    server_name_from_id,
    turn_still_planning,
)


def _agent(**kw):
    base = {
        "bcId": "bc-aaa",
        "name": "a",
        "usePrivateWorker": True,
        "privateWorkerDisplayName": "/data/proj @ this-host",
        "workspaceRootPath": "/data/proj",
        "createdAt": 10,
    }
    base.update(kw)
    return base


class ClassifyTests(unittest.TestCase):
    def test_environment_workspace(self):
        self.assertEqual(classify(_agent(workspaceRootPath="/workspace")), "environment")

    def test_logical_environment(self):
        a = _agent(cloudTargetKey="logicalEnvironment:abc", workspaceRootPath="/data/proj")
        self.assertEqual(classify(a), "environment")

    def test_local_rc(self):
        self.assertEqual(classify(_agent()), "local-rc")


class NameMatchTests(unittest.TestCase):
    def test_one_letter_is_not_a_match(self):
        self.assertFalse(_ocr_name_match("-", "ai-agent-bridge"))
        self.assertFalse(_ocr_name_match("e", "n8n"))

    def test_n8n_and_bridge(self):
        self.assertTrue(_ocr_name_match("nan", "n8n"))
        self.assertFalse(_ocr_name_match("gn", "n8n"))
        self.assertTrue(_ocr_name_match("ai-agent-bridge", "ai-agent-bridge"))
        self.assertFalse(_ocr_name_match("bridge", "ai-agent-bridge"))


class ServerIdTests(unittest.TestCase):
    def test_user_keeps_hyphens(self):
        self.assertEqual(server_name_from_id("user-ai-agent-bridge", []), "ai-agent-bridge")
        self.assertEqual(server_name_from_id("user-mt5", []), "mt5")

    def test_project_pair(self):
        self.assertEqual(server_name_from_id("project-0-app-tool", []), "tool")

    def test_project_hyphenated_without_json_is_not_guessed(self):
        self.assertIsNone(server_name_from_id("project-0-app-long-name", []))

    def test_project_hyphenated_uses_json_name(self):
        got = server_name_from_id(
            "project-0-app-long-name", ["tool", "long-name"]
        )
        self.assertEqual(got, "long-name")


class MergeMcpTests(unittest.TestCase):
    def test_keeps_env_and_mode(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "mcp.json"
            path.write_text(
                '{"mcpServers":{"mt5":{"type":"stdio","command":"/old",'
                '"args":["a"],"env":{"TOKEN":"secret"}}}}\n',
                encoding="utf-8",
            )
            os.chmod(path, 0o600)
            merge_mcp_json(path, "mt5", command="/new", args=["b"])
            text = path.read_text(encoding="utf-8")
            self.assertIn('"TOKEN": "secret"', text)
            self.assertIn('"/new"', text)
            self.assertNotIn('"/old"', text)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertFalse(list(Path(td).glob(".mcp.json.tmp-*")))


class HandoffOkTests(unittest.TestCase):
    def test_uuid_not_the_newest(self):
        older = _agent(bcId="bc-old", createdAt=5)
        newer = _agent(
            bcId="bc-new",
            createdAt=50,
            workspaceRootPath="/workspace",
            cloudTargetKey="logicalEnvironment:x",
            privateWorkerDisplayName="",
        )
        picked = pick_handoff_agent([older, newer], 1, "old")
        self.assertEqual(picked["bcId"], "bc-old")
        self.assertIsNone(handoff_failure(picked, "/data/proj"))
        newest = pick_handoff_agent([older, newer], 1, None)
        self.assertEqual(newest["bcId"], "bc-new")
        self.assertIn("Environment", handoff_failure(newest, "/data/proj") or "")


class OtherHostTests(unittest.TestCase):
    def test_drops_other_machine(self):
        here = _agent()
        there = _agent(bcId="bc-hp", privateWorkerDisplayName="/data/proj @ other-host")
        self.assertTrue(agent_on_host(here, "this-host"))
        self.assertFalse(agent_on_host(there, "this-host"))
        self.assertTrue(agent_on_host(there, "other-host"))


class ToggleTests(unittest.TestCase):
    def test_no_label_is_not_a_click(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("нет Pillow")
        with tempfile.TemporaryDirectory() as td:
            shot = Path(td) / "blank.png"
            im = Image.new("RGB", (1200, 800), (30, 30, 30))
            for x in range(1080, 1160):
                for y in range(500, 540):
                    im.putpixel((x, y), (240, 240, 240))
            im.save(shot)
            self.assertIsNone(mcp_source_toggle(shot))


def _w(x, y, w, h, text):
    return (x, y, w, h, 90.0, text)


class FolderChipTests(unittest.TestCase):
    def _inherited(self):
        # handoff-fail-155702: имя папки вместо ветки main.
        return [
            _w(800, 482, 137, 13, "curskill-cycle-20261125"),
            _w(984, 473, 24, 29, "This"),
            _w(1017, 473, 55, 29, "Computer"),
        ]

    def test_folder_name_left_of_this_computer(self):
        self.assertEqual(find_anchor(self._inherited(), "folder-chip"), (868, 488))

    def test_main_keeps_the_old_click(self):
        words = self._inherited() + [_w(900, 480, 30, 12, "main")]
        # центр main (915, 486) + (-55, 3)
        self.assertEqual(find_anchor(words, "folder-chip"), (860, 489))

    def test_footer_this_computer_is_not_the_chip(self):
        words = [
            _w(606, 1045, 24, 29, "This"),
            _w(640, 1045, 55, 29, "Computer"),
            _w(800, 1045, 80, 13, "curskill-cycle-20261125"),
        ]
        self.assertIsNone(find_anchor(words, "folder-chip"))

    def test_result_row_is_below_the_name(self):
        self.assertEqual(find_anchor(self._inherited(), "folder-result"), (840, 556))


class PlanningTests(unittest.TestCase):
    def test_planning_next_moves(self):
        words = [
            _w(592, 138, 60, 15, "Planning"),
            _w(659, 139, 28, 10, "next"),
            _w(693, 141, 44, 8, "moves"),
            _w(658, 1014, 65, 15, "follow-up"),
            _w(606, 1045, 24, 29, "This"),
        ]
        self.assertTrue(turn_still_planning(words))

    def test_planning_without_next_is_not_the_status(self):
        self.assertFalse(turn_still_planning([_w(592, 138, 60, 15, "Planning")]))


if __name__ == "__main__":
    unittest.main()
