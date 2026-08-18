#!/usr/bin/env python3
import json
import pathlib
import re
import stat
import unittest


ROOT = pathlib.Path(__file__).parents[1]


class PluginSourceTests(unittest.TestCase):
    def test_manifest_declares_a_single_native_bar_widget(self):
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["id"], "cd.digitalocean")
        self.assertEqual(manifest["kinds"], ["bar-widget"])
        self.assertEqual(manifest["entryPoints"]["barWidget"], "Panel.qml")
        self.assertFalse(manifest["barWidget"]["allowMultiple"])
        keys = {item["key"] for item in manifest["barWidget"]["schema"]}
        self.assertEqual(keys, {"refreshIntervalSec", "idleRefreshIntervalSec", "notificationsEnabled", "lowBalanceThreshold"})

    def test_required_plugin_files_exist_and_helper_is_executable(self):
        for name in ["Panel.qml", "Service.qml", "ResourceRow.qml", "Model.js", "README.md", "LICENSE"]:
            self.assertTrue((ROOT / name).is_file(), name)
        mode = (ROOT / "omarchy-digitalocean-fetch").stat().st_mode
        self.assertTrue(mode & stat.S_IXUSR)

    def test_every_offered_row_action_is_handled_by_the_panel(self):
        panel = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        body = panel.split("function executeRowAction", 1)[1].split("\n  function ", 1)[0]
        handled = set(re.findall(r'action === "([a-z-]+)"', body))
        for array in re.findall(r'\[([^\]]*)\]\.indexOf\(action\)', body):
            handled.update(re.findall(r'"([a-z-]+)"', array))
        rows = panel.split("function dropletActions", 1)[1].split("function contextNames", 1)[0]
        offered = set(re.findall(r'\{\s*id:\s*"([a-z-]+)",\s*label:', rows))

        self.assertTrue(offered)
        self.assertEqual(offered - handled, set(), "row actions offered but never executed")

    def test_panel_uses_the_omarchy_kit_and_not_platform_controls(self):
        panel = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        self.assertNotIn("ComboBox {", panel)
        self.assertIn("Dropdown {", panel)
        self.assertIn("root.switchPanel(direction)", panel)

    def test_sources_never_embed_or_request_api_tokens(self):
        production = [
            ROOT / "Panel.qml",
            ROOT / "Service.qml",
            ROOT / "ResourceRow.qml",
            ROOT / "digitalocean_backend.py",
            ROOT / "omarchy-digitalocean-fetch",
        ]
        forbidden = ["DIGITALOCEAN_ACCESS_TOKEN", "api-token", "access-token", "password"]
        combined = "\n".join(path.read_text(encoding="utf-8") for path in production).lower()
        for term in forbidden:
            self.assertNotIn(term.lower(), combined)


if __name__ == "__main__":
    unittest.main()
