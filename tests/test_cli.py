#!/usr/bin/env python3
import json
import os
import pathlib
import stat
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).parents[1]
EXECUTABLE = ROOT / "omarchy-digitalocean-fetch"


class CommandLineTests(unittest.TestCase):
    def test_droplet_action_outputs_json_and_passes_literal_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = pathlib.Path(directory) / "doctl"
            fake.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$@\" >> \"$DOCTL_ARGUMENT_LOG\"\n"
                "case \" $* \" in\n"
                "  *\" droplet get \"*) printf '[{\"id\":42,\"name\":\"web\",\"status\":\"active\"}]\\n' ;;\n"
                "  *) printf '[{\"id\":99,\"status\":\"in-progress\"}]\\n' ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
            log = pathlib.Path(directory) / "arguments"
            environment = os.environ.copy()
            environment["PATH"] = f"{directory}:{environment['PATH']}"
            environment["DOCTL_ARGUMENT_LOG"] = str(log)

            completed = subprocess.run(
                [str(EXECUTABLE), "droplet-action", "--context", "prod", "--action", "shutdown", "--target", "42"],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(json.loads(completed.stdout)["success"])
            self.assertEqual(log.read_text(encoding="utf-8").splitlines(), [
                "--context", "prod", "--interactive=false", "compute", "droplet", "get", "42", "--output", "json",
                "--context", "prod", "--interactive=false", "compute", "droplet-action", "shutdown", "42", "--http-retry-max", "0", "--output", "json",
            ])


if __name__ == "__main__":
    unittest.main()
