"""Tests for the devtools hub. Run: python3 -m unittest discover -s tools/devtools -p 'test_*.py'"""
import http.client
import json
import socket
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import registry  # noqa: E402
import runner  # noqa: E402
import server  # noqa: E402

PY = sys.executable


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def fake_command(cid: str, code: str, exclusive: bool = True) -> dict:
    return {"id": cid, "label": cid, "params": [], "argv": lambda p: [PY, "-c", code], "exclusive": exclusive}


def wait(predicate, timeout: float = 10.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


class RegistryTest(unittest.TestCase):
    def test_every_command_has_valid_defaults_and_builds_argv(self) -> None:
        for command in registry.COMMANDS:
            given = {p["name"]: (p["choices"]()[0] if p["type"] == "choice" and p["default"] not in p["choices"]() else p["default"])
                     for p in command["params"]}
            params = registry.validate(command, given)
            argv = command["argv"](params)
            self.assertTrue((registry.REPO_ROOT / argv[0]).is_file() or argv[0] == registry.PYTHON, command["id"])
            if argv[0] == registry.PYTHON:
                self.assertTrue((registry.REPO_ROOT / argv[1]).is_file(), command["id"])

    def test_services_point_at_existing_servers(self) -> None:
        for spec in registry.SERVICES:
            self.assertTrue((registry.REPO_ROOT / spec["argv"][1]).is_file(), spec["id"])
            self.assertIn("--port=%d" % spec["port"], spec["argv"])

    def test_simulate_argv(self) -> None:
        command = registry.find("simulate")
        params = registry.validate(command, {"count": "50", "seed": 7, "max_turns": "", "player0": "russia", "player1": "poland"})
        self.assertEqual(command["argv"](params),
                         ["tools/simulate.sh", "50", "--factions=russia,poland", "--scenario=default_battle", "--seed=7"])

    def test_scenarios_are_the_names_scenario_build_accepts(self) -> None:
        self.assertEqual(registry.scenarios(), ["default_battle", "objective_battle", "command_points_battle"])

    def test_validation_rejects_anything_outside_the_template(self) -> None:
        test = registry.find("test")
        for bad in ({"filter": "x; rm -rf /"}, {"filter": "--help"}, {"verbose": "yes"}, {"extra": 1}):
            with self.assertRaises(registry.ParamError, msg=bad):
                registry.validate(test, bad)
        with self.assertRaises(registry.ParamError):
            registry.validate(registry.find("simulate"), {"count": 0})
        with self.assertRaises(registry.ParamError):
            registry.validate(registry.find("simulate"), {"player0": "../x"})
        with self.assertRaises(registry.ParamError):
            registry.validate(registry.find("render_unit"), {"unit": "not_a_unit"})
        with self.assertRaises(registry.ParamError):
            registry.validate(registry.find("screenshot"), {"shots": "hover;ls"})

    def test_screenshot_states_name_their_images(self) -> None:
        command = registry.find("screenshot")
        params = registry.validate(command, {"shots": "hover:2,toast"})
        self.assertEqual(command["env"](params), {"SCREENSHOT_SHOTS": "hover:2,toast"})
        self.assertEqual(command["images"](params), [".screenshots/battle_hover.png", ".screenshots/battle_toast.png"])

    def test_describe_is_json(self) -> None:
        described = json.loads(json.dumps(registry.describe()))
        self.assertEqual([c["id"] for c in described], [c["id"] for c in registry.COMMANDS])
        self.assertIn("poland", next(p for p in described[4]["params"] if p["name"] == "player0")["choices"])


class JobRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.jobs = runner.JobRunner(self.root)

    def tearDown(self) -> None:
        self.jobs.shutdown()

    def finished(self, job_id: str) -> bool:
        return self.jobs.get(job_id)["finished"] is not None

    def test_output_exit_code_and_ansi_stripped(self) -> None:
        job = self.jobs.submit(fake_command("a", "print('\\x1b[31mred\\x1b[0m'); print('two'); raise SystemExit(3)"), {})
        self.assertTrue(wait(lambda: self.finished(job["id"])))
        info = self.jobs.get(job["id"])
        self.assertEqual((info["state"], info["exit_code"], info["lines"]), ("failed", 3, ["red", "two"]))
        self.assertEqual(self.jobs.get(job["id"], since=1)["lines"], ["two"])

    def test_exclusive_jobs_wait_for_each_other(self) -> None:
        first = self.jobs.submit(fake_command("slow", "import time; time.sleep(0.6)"), {})
        second = self.jobs.submit(fake_command("next", "print('x')"), {})
        free = self.jobs.submit(fake_command("free", "print('y')", exclusive=False), {})
        self.assertTrue(wait(lambda: self.finished(free["id"])))
        self.assertEqual(self.jobs.get(second["id"])["state"], "queued")
        self.assertTrue(wait(lambda: self.finished(second["id"])))
        self.assertGreaterEqual(self.jobs.get(second["id"])["started"], self.jobs.get(first["id"])["finished"])

    def test_cancel_running_and_queued(self) -> None:
        running = self.jobs.submit(fake_command("long", "import time; time.sleep(30)"), {})
        queued = self.jobs.submit(fake_command("after", "print('never')"), {})
        self.assertTrue(wait(lambda: self.jobs.get(running["id"])["state"] == "running"))
        self.assertTrue(self.jobs.cancel(queued["id"]))
        self.assertTrue(self.jobs.cancel(running["id"]))
        self.assertTrue(wait(lambda: self.finished(running["id"]) and self.finished(queued["id"])))
        self.assertEqual(self.jobs.get(running["id"])["state"], "cancelled")
        self.assertEqual(self.jobs.get(queued["id"])["lines"], [])

    def test_images_written_by_the_job(self) -> None:
        (self.root / "old.png").write_bytes(b"x")
        old = time.time() - 60
        import os
        os.utime(self.root / "old.png", (old, old))
        command = fake_command("img", "open('new.png', 'wb').write(b'x')")
        command["images"] = lambda p: ["*.png"]
        job = self.jobs.submit(command, {})
        self.assertTrue(wait(lambda: self.finished(job["id"])))
        self.assertEqual(self.jobs.get(job["id"])["images"], ["new.png"])


class ServiceTest(unittest.TestCase):
    def test_starts_reuses_and_stops(self) -> None:
        port = free_port()
        spec = {"id": "web", "label": "Web", "description": "", "port": port, "probe": "/",
                "argv": [PY, "-m", "http.server", str(port), "--bind", "127.0.0.1"]}
        service = runner.Service(spec, Path(tempfile.mkdtemp()), Path(tempfile.mkdtemp()))
        self.assertFalse(service.status()["up"])
        service.start()
        try:
            self.assertTrue(service.wait_up())
            self.assertEqual((service.status()["up"], service.status()["managed"]), (True, True))
            other = runner.Service(spec, Path(tempfile.mkdtemp()), Path(tempfile.mkdtemp()))
            other.start()  # something already answers on the port: reused, not started twice
            self.assertIsNone(other.proc)
            self.assertEqual(other.status()["managed"], False)
        finally:
            service.stop()
        self.assertFalse(service.alive())


class StaticTest(unittest.TestCase):
    def test_fonts_only_from_assets_fonts(self) -> None:
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "web_ui"))
        import static  # noqa: E402

        self.assertIsNotNone(static.font("ChakraPetch-SemiBold.ttf"))
        for bad in ("../../README.md", "OFL.txt", "x/../JetBrainsMono.ttf", "missing.ttf"):
            self.assertIsNone(static.font(bad), bad)


class ServerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        (self.root / ".screenshots").mkdir()
        (self.root / ".screenshots" / "a.png").write_bytes(b"\x89PNG")
        (self.root / "secret.png").write_bytes(b"\x89PNG")
        self.jobs = runner.JobRunner(self.root)
        handler = server.make_handler(self.root, {}, self.jobs)
        self.httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self) -> None:
        self.jobs.shutdown()
        self.httpd.shutdown()
        self.httpd.server_close()

    def request(self, method: str, path: str, body=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.httpd.server_address[1], timeout=5)
        conn.request(method, path, body=None if body is None else json.dumps(body), headers={"Content-Type": "application/json"})
        res = conn.getresponse()
        data = res.read()
        conn.close()
        return res.status, data

    def test_static_and_commands(self) -> None:
        for path in ("/", "/app.js", "/style.css", "/theme.css", "/fonts/JetBrainsMono.ttf"):
            self.assertEqual(self.request("GET", path)[0], 200, path)
        status, body = self.request("GET", "/api/commands")
        self.assertEqual(status, 200)
        self.assertIn("check", [c["id"] for c in json.loads(body)])

    def test_rejects_unknown_commands_and_bad_params(self) -> None:
        self.assertEqual(self.request("POST", "/api/jobs", {"command": "rm"})[0], 404)
        self.assertEqual(self.request("POST", "/api/jobs", {"command": "test", "params": {"filter": "$(id)"}})[0], 400)
        self.assertEqual(self.request("GET", "/api/jobs")[1], b"[]")

    def test_images_only_from_screenshot_dirs(self) -> None:
        self.assertEqual(self.request("GET", "/files/.screenshots/a.png")[0], 200)
        self.assertEqual(self.request("GET", "/files/secret.png")[0], 404)
        self.assertEqual(self.request("GET", "/files/.screenshots/../secret.png")[0], 404)
        self.assertEqual(self.request("GET", "/files/.screenshots/%2e%2e/secret.png")[0], 404)


if __name__ == "__main__":
    unittest.main()
