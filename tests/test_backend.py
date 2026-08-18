#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).parents[1] / "digitalocean_backend.py"


def load_backend():
    spec = importlib.util.spec_from_file_location("digitalocean_backend", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load backend module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RecordingRunner:
    def __init__(self, responses=None):
        self.responses = responses or {}
        self.commands = []

    def __call__(self, command, timeout):
        self.commands.append((command, timeout))
        key = tuple(command)
        if key not in self.responses:
            raise AssertionError(f"Unexpected command: {command}")
        return self.responses[key]


class DigitalOceanClientTests(unittest.TestCase):
    def test_json_request_uses_selected_context_without_shell(self):
        backend = load_backend()
        runner = RecordingRunner({
            ("doctl", "--context", "production", "--interactive=false", "account", "get", "--output", "json"): (0, '[{"email":"owner@example.com"}]', "")
        })
        client = backend.DigitalOceanClient(context="production", runner=runner)

        result = client.json_request(["account", "get"])

        self.assertEqual(result, [{"email": "owner@example.com"}])
        self.assertEqual(runner.commands[0][1], 20)

    def test_dashboard_normalizes_resources_and_preserves_partial_failures(self):
        backend = load_backend()
        responses = {
            ("doctl", "--interactive=false", "account", "get", "--output", "json"): (0, '[{"email":"owner@example.com","droplet_limit":25}]', ""),
            ("doctl", "--interactive=false", "compute", "droplet", "list", "--output", "json"): (0, '[{"id":12,"name":"web-1","status":"active","region":{"slug":"nyc3"},"networks":{"v4":[{"type":"public","ip_address":"203.0.113.10"}]},"vcpus":2,"memory":4096,"disk":80}]', ""),
            ("doctl", "--interactive=false", "kubernetes", "cluster", "list", "--output", "json"): (0, '[{"id":"k1","name":"prod-k8s","region":"nyc3","status":{"state":"running"},"version":"1.33.1-do.0"}]', ""),
            ("doctl", "--interactive=false", "databases", "list", "--output", "json"): (1, "", "permission denied\nextra detail"),
            ("doctl", "--interactive=false", "apps", "list", "--output", "json"): (0, '{"apps":[{"id":"a1","spec":{"name":"portal","region":"nyc"},"tier_slug":"professional","active_deployment":{"phase":"ACTIVE"},"default_ingress":"https://portal.example.com"}]}', ""),
            ("doctl", "--interactive=false", "compute", "load-balancer", "list", "--output", "json"): (0, '[]', ""),
            ("doctl", "--interactive=false", "compute", "volume", "list", "--output", "json"): (0, '[]', ""),
            ("doctl", "--interactive=false", "compute", "snapshot", "list", "--output", "json"): (0, '[]', ""),
            ("doctl", "--interactive=false", "compute", "domain", "list", "--output", "json"): (0, '[{"name":"example.com","ttl":1800}]', ""),
            ("doctl", "--interactive=false", "projects", "list", "--output", "json"): (0, '[{"id":"p1","name":"Production","is_default":true}]', ""),
            ("doctl", "--interactive=false", "balance", "get", "--output", "json"): (0, '[{"month_to_date_balance":"12.34","account_balance":"45.67","month_to_date_usage":"8.90","generated_at":"2026-08-18T12:00:00Z"}]', ""),
        }
        client = backend.DigitalOceanClient(runner=RecordingRunner(responses))

        result = backend.build_dashboard(client)

        self.assertEqual(result["state"], "ready")
        self.assertEqual(result["account"]["email"], "owner@example.com")
        self.assertEqual(result["droplets"][0]["publicIpv4"], "203.0.113.10")
        self.assertEqual(result["kubernetes"][0]["status"], "running")
        self.assertEqual(result["apps"][0]["name"], "portal")
        self.assertEqual(result["apps"][0]["tier"], "professional")
        self.assertEqual(result["billing"]["accountBalance"], 45.67)
        self.assertEqual(result["summary"]["runningDroplets"], 1)
        self.assertEqual(result["summary"]["healthyKubernetes"], 1)
        self.assertEqual(result["summary"]["activeApps"], 1)
        self.assertEqual(result["errors"], {"databases": "permission denied"})

    def test_droplet_actions_are_allowlisted_and_target_ids_are_strict(self):
        backend = load_backend()
        responses = {
            ("doctl", "--context", "prod", "--interactive=false", "compute", "droplet", "get", "42", "--output", "json"): (0, '[{"id":42,"name":"web","status":"active"}]', ""),
            ("doctl", "--context", "prod", "--interactive=false", "compute", "droplet-action", "reboot", "42", "--http-retry-max", "0", "--output", "json"): (0, '[{"id":99,"status":"in-progress"}]', "")
        }
        client = backend.DigitalOceanClient(context="prod", runner=RecordingRunner(responses))

        result = backend.run_droplet_action(client, "reboot", "42")

        self.assertTrue(result["success"])
        self.assertEqual(result["action"], "reboot")
        with self.assertRaisesRegex(backend.DigitalOceanError, "Unsupported"):
            backend.run_droplet_action(client, "destroy", "42")
        with self.assertRaisesRegex(backend.DigitalOceanError, "invalid"):
            backend.run_droplet_action(client, "reboot", "--help")

    def test_droplet_action_refuses_a_stale_or_incompatible_state(self):
        backend = load_backend()
        runner = RecordingRunner({
            ("doctl", "--interactive=false", "compute", "droplet", "get", "42", "--output", "json"): (0, '[{"id":42,"name":"web","status":"off"}]', "")
        })
        client = backend.DigitalOceanClient(runner=runner)

        with self.assertRaisesRegex(backend.DigitalOceanError, "requires state active"):
            backend.run_droplet_action(client, "shutdown", "42")
        self.assertEqual(len(runner.commands), 1)

    def test_nonzero_json_error_is_summarized_without_dumping_raw_stdout(self):
        backend = load_backend()
        runner = RecordingRunner({
            ("doctl", "--interactive=false", "databases", "list", "--output", "json"): (1, '{"errors":[{"detail":"permission denied"}],"connection":{"password":"do-not-leak"}}', "")
        })
        client = backend.DigitalOceanClient(runner=runner)

        with self.assertRaisesRegex(backend.DigitalOceanError, "^permission denied$"):
            client.json_request(["databases", "list"])

    def test_context_list_uses_doctl_json_without_exposing_tokens(self):
        backend = load_backend()
        runner = RecordingRunner({
            ("doctl", "--interactive=false", "auth", "list", "--output", "json"): (0, '[{"name":"production","current":true},{"name":"staging","current":false}]', "")
        })
        client = backend.DigitalOceanClient(runner=runner)

        contexts = backend.list_contexts(client)

        self.assertEqual(contexts, [{"name": "production", "current": True}, {"name": "staging", "current": False}])


if __name__ == "__main__":
    unittest.main()
