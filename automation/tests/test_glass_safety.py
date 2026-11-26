"""Чистые проверки без glass и без tesseract, кроме тоггла на пустом снимке."""
from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from automation.glass_agents import (
    _ocr_name_match,
    agent_on_host,
    archive_menu_click,
    classify,
    discard_menu_click,
    foreign_name_changes,
    format_settings_report,
    inventory_lines,
    settings_target_forbidden,
    composer_click,
    find_anchor,
    handoff_failure,
    load_agents,
    mcp_source_toggle,
    merge_mcp_json,
    palette_is_open,
    palette_text_confirms,
    pick_handoff_agent,
    server_name_from_id,
    sidebar_row_matches,
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

    def test_closed_picker_has_no_result_click(self):
        self.assertIsNone(find_anchor(self._inherited(), "folder-result"))

    def test_open_result_row_is_clicked(self):
        words = self._inherited() + [_w(812, 548, 160, 16, "/tmp/curskill-pass")]
        self.assertEqual(find_anchor(words, "folder-result"), (892, 556))


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


class ArchiveClickTests(unittest.TestCase):
    def test_chat_transcript_is_not_the_menu(self):
        words = [_w(700, 400, 60, 14, "Archive"), _w(180, 640, 50, 14, "Archive")]
        self.assertEqual(archive_menu_click(words), (205, 647))

    def test_archive_all_below_is_not_a_click(self):
        words = [
            _w(180, 640, 50, 14, "Archive"),
            _w(240, 640, 24, 14, "All"),
            _w(270, 642, 40, 14, "Below"),
        ]
        self.assertIsNone(archive_menu_click(words))


class ComposerClickTests(unittest.TestCase):
    def test_idea_in_the_transcript_loses_to_the_footer(self):
        words = [
            _w(800, 600, 40, 16, "Idea"),
            _w(606, 1045, 24, 29, "This"),
            _w(640, 1045, 55, 29, "Computer"),
        ]
        self.assertEqual(composer_click(words, "k-99"), (650, 1021))

    def test_new_chat_still_uses_idea(self):
        words = [_w(800, 600, 40, 16, "Idea")]
        self.assertEqual(composer_click(words, "k-99"), (820, 518))


class PaletteTests(unittest.TestCase):
    def test_chats_and_files_alone_are_not_the_palette(self):
        self.assertFalse(palette_is_open("All Chats Files"))

    def test_search_chats_is_the_palette(self):
        self.assertTrue(palette_is_open("Search chats"))

    def test_five_characters_do_not_confirm(self):
        self.assertFalse(palette_text_confirms("see hello there", "hello", None))

    def test_long_name_confirms(self):
        self.assertTrue(
            palette_text_confirms(
                "Ready response instruction",
                "Ready response instruction",
                None,
            )
        )


class SidebarRowTests(unittest.TestCase):
    def test_name_on_the_row(self):
        words = [_w(40, 330, 70, 14, "full-cycle")]
        self.assertTrue(sidebar_row_matches(words, 337, "full-cycle"))

    def test_truncated_last_word_matches(self):
        # Снимок rename 26.11.2026: instruction прочитано как instruc.
        words = [
            _w(41, 207, 36, 13, "Ready"),
            _w(81, 210, 54, 10, "response"),
            _w(140, 207, 40, 10, "instruc"),
            _w(195, 207, 13, 11, "2"),
        ]
        self.assertTrue(sidebar_row_matches(words, 211, "Ready response instruction"))

    def test_one_word_is_not_the_whole_name(self):
        words = [_w(41, 207, 36, 13, "Ready")]
        self.assertFalse(sidebar_row_matches(words, 211, "Ready response instruction"))

    def test_other_row_does_not_match(self):
        words = [_w(40, 200, 70, 14, "cur-mql")]
        self.assertFalse(sidebar_row_matches(words, 337, "full-cycle"))


class LoadAgentsTests(unittest.TestCase):
    def test_two_keys_are_both_read(self):
        import sqlite3
        import tempfile

        with tempfile.TemporaryDirectory() as td:
            db = Path(td) / "state.vscdb"
            con = sqlite3.connect(db)
            con.execute("create table ItemTable (key text, value text)")
            con.execute(
                "insert into ItemTable values (?, ?)",
                ("cloudAgentRepository.agents", '[{"bcId":"bc-aaa","name":"one"}]'),
            )
            con.execute(
                "insert into ItemTable values (?, ?)",
                ("cloudAgentRepository.agents.2", '[{"bcId":"bc-bbb","name":"two"}]'),
            )
            con.commit()
            con.close()
            got = {a["bcId"] for a in load_agents(db)}
            self.assertEqual(got, {"bc-aaa", "bc-bbb"})


class McpModeTests(unittest.TestCase):
    def test_new_file_is_0600_and_existing_mode_stays(self):
        import os
        import tempfile

        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "mcp.json"
            merge_mcp_json(path, "demo", command="echo")
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            os.chmod(path, 0o640)
            merge_mcp_json(path, "demo", command="echo")
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o640)


class FolderSearchTests(unittest.TestCase):
    def test_truncated_environments_still_finds_the_field(self):
        # Снимок h-picker-103429.png: repos стало «re|», environments — «environmer».
        words = [
            _w(831, 519, 39, 10, "Search"),
            _w(881, 523, 5, 3, "re|"),
            _w(954, 522, 64, 7, "environmer"),
        ]
        self.assertEqual(find_anchor(words, "folder-search"), (986, 525))


class InventoryTests(unittest.TestCase):
    def test_four_kinds_and_a_draft(self):
        agents = [
            _agent(bcId="bc-rc", name="rc", status=1),
            _agent(
                bcId="bc-env",
                name="env",
                workspaceRootPath="/workspace",
                cloudTargetKey="logicalEnvironment:x",
                usePrivateWorker=False,
                privateWorkerDisplayName="",
                status=0,
            ),
            _agent(
                bcId="bc-inc",
                name="inc",
                usePrivateWorker=True,
                privateWorkerDisplayName="",
                workspaceRootPath="",
                status=0,
            ),
            {"bcId": "bc-old", "name": "old", "isArchived": True},
        ]
        lines = inventory_lines(agents, "11111111-1111-4111-8111-111111111111")
        text = "\n".join(lines)
        self.assertIn("bc-rc\trc\t/data/proj\tlocal-rc\t1\t", text)
        self.assertIn("\tenvironment\t", text)
        self.assertIn("\tprivate-incomplete\t", text)
        self.assertIn("11111111-1111-4111-8111-111111111111\t\t\tlocal-draft\t?\t", text)
        self.assertNotIn("bc-old", text)

    def test_selected_row_is_not_a_second_draft(self):
        agents = [_agent()]
        lines = inventory_lines(agents, "bc-aaa")
        self.assertEqual(len(lines), 1)

    def test_foreign_rename_ignores_the_new_id(self):
        before = "bc-keep\told\t/data/a\tlocal-rc\t0\t/data/a @ h\nbc-new\tready\t/tmp/x\tlocal-rc\t0\t"
        after = "bc-keep\told\t/data/a\tlocal-rc\t0\t/data/a @ h\nbc-new\trenamed\t/tmp/x\tlocal-rc\t0\t"
        self.assertEqual(foreign_name_changes(before, after, "bc-new"), [])
        after_bad = "bc-keep\tother\t/data/a\tlocal-rc\t0\t/data/a @ h\n"
        self.assertEqual(
            foreign_name_changes(before, after_bad, "bc-new"),
            ["bc-keep\told\tother"],
        )


class DiscardClickTests(unittest.TestCase):
    def test_discard_in_the_menu(self):
        words = [_w(120, 400, 60, 14, "Discard")]
        self.assertEqual(discard_menu_click(words), (150, 407))

    def test_archive_is_not_discard(self):
        words = [_w(120, 400, 60, 14, "Archive"), _w(120, 430, 40, 14, "All"), _w(170, 430, 50, 14, "Below")]
        self.assertIsNone(discard_menu_click(words))

    def test_discard_in_the_transcript_is_ignored(self):
        words = [_w(800, 400, 60, 14, "Discard")]
        self.assertIsNone(discard_menu_click(words))


class SettingsReportTests(unittest.TestCase):
    def test_labels_for_the_required_rows(self):
        merged = {
            "remote_control": ("on", "Connected"),
            "self_hosted_workers": ("on", ""),
            "new_messages": ("queue", ""),
            "run_mode": ("auto", ""),
            "read_access": ("on", ""),
            "file_deletion_protection": ("on", ""),
            "external_file_protection": ("on", ""),
            "web_search": ("on", ""),
            "wait_mcp_auth": ("off", ""),
            "computer_use_apps": ("none", "No always-allowed apps"),
            "legacy_terminal": ("off", ""),
        }
        text = "\n".join(format_settings_report(merged))
        for label in (
            "Remote Control\ton\tConnected",
            "self-hosted workers\ton\t",
            "New Messages\tqueue\t",
            "Run Mode\tauto\t",
            "Read Access\ton\t",
            "File-Deletion Protection\ton\t",
            "External-File Protection\ton\t",
            "Web Search\ton\t",
            "Wait for MCP Authentication\toff\t",
            "Computer Use\tnone\tNo always-allowed apps",
            "Legacy Terminal\toff\t",
        ):
            self.assertIn(label, text)

    def test_unregister_and_cloud_are_forbidden_targets(self):
        self.assertTrue(
            settings_target_forbidden([_w(80, 240, 80, 14, "Unregister")], 120, 247, "settings-item")
        )
        self.assertTrue(
            settings_target_forbidden([_w(80, 200, 40, 14, "Cloud")], 100, 207, "agents-nav")
        )
        self.assertFalse(
            settings_target_forbidden([_w(40, 200, 50, 14, "Agents")], 65, 207, "agents-nav")
        )


class ProbeServerTests(unittest.TestCase):
    def test_tool_call_writes_the_token(self):
        import json
        import subprocess

        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "token"
            proc = subprocess.Popen(
                ["python3", "automation/mcp_probe.py", str(out)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
            )
            assert proc.stdin and proc.stdout

            def send(payload: dict) -> dict:
                body = json.dumps(payload).encode()
                proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
                proc.stdin.flush()
                header = proc.stdout.readline()
                self.assertTrue(header.lower().startswith(b"content-length:"))
                length = int(header.split(b":", 1)[1].strip())
                self.assertEqual(proc.stdout.readline(), b"\r\n")
                return json.loads(proc.stdout.read(length))

            try:
                init = send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
                self.assertEqual(init["result"]["serverInfo"]["name"], "curskill-probe")
                listed = send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
                self.assertEqual(listed["result"]["tools"][0]["name"], "curskill_probe_ping")
                called = send(
                    {
                        "jsonrpc": "2.0",
                        "id": 3,
                        "method": "tools/call",
                        "params": {"name": "curskill_probe_ping", "arguments": {}},
                    }
                )
                token = called["result"]["content"][0]["text"]
                self.assertRegex(token, r"^probe-ok-[0-9a-f]{16}$")
                self.assertEqual(out.read_text(encoding="utf-8").strip(), token)
            finally:
                if proc.stdin:
                    proc.stdin.close()
                proc.kill()
                proc.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
