"""Offline regression tests for local emulator setup and UI smoke helpers."""
import hashlib
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from xml.dom import minidom
from xml.etree import ElementTree as ET
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import android_emulator_smoke as smoke
import install_android_sdk as sdk
import prepare_android_emulator as prepare


class FakeAdb:
    """Small in-process adb emulator for network snapshot tests."""

    def __init__(self, fail=None, preexisting=False):
        self.settings = {"airplane_mode_on": "0", "wifi_on": "1", "mobile_data": "0"}
        self.services = {"wifi": "enable", "data": "disable"}
        self.chains = {
            "iptables": [f"-A {smoke.CHAIN} -j FOREIGN"]
            if preexisting
            else None,
            "ip6tables": None,
        }
        self.output_jumps = {"iptables": [], "ip6tables": []}
        self.calls = []
        self.fail = fail
        self.avd_name = smoke.AVD
        self.boot_id = "boot-fixture"

    def __call__(self, command, **_kwargs):
        command = list(map(str, command))
        self.calls.append(command)
        tail = command[5:]
        if self.fail:
            failure = self.fail(tail)
            if failure == "timeout":
                raise subprocess.TimeoutExpired(command, 10)
            if failure:
                return subprocess.CompletedProcess(command, 1, b"", b"synthetic failure")
        if tail == ["root"] or tail == ["wait-for-device"]:
            return subprocess.CompletedProcess(command, 0, b"", b"")
        if tail == ["emu", "avd", "name"]:
            return subprocess.CompletedProcess(command, 0, (self.avd_name + "\n").encode(), b"")
        if tail == ["shell", "cat", "/proc/sys/kernel/random/boot_id"]:
            return subprocess.CompletedProcess(command, 0, (self.boot_id + "\n").encode(), b"")
        if tail == ["shell", "id", "-u"]:
            return subprocess.CompletedProcess(command, 0, b"0\n", b"")
        if tail[:3] == ["shell", "settings", "get"]:
            key = tail[4]
            return subprocess.CompletedProcess(
                command, 0, (self.settings.get(key, "null") + "\n").encode(), b""
            )
        if tail[:3] == ["shell", "settings", "put"]:
            self.settings[tail[4]] = tail[5]
            return subprocess.CompletedProcess(command, 0, b"", b"")
        if tail[:2] == ["shell", "svc"]:
            service, mode = tail[2], tail[3]
            self.services[service] = mode
            self.settings["wifi_on" if service == "wifi" else "mobile_data"] = (
                "1" if mode == "enable" else "0"
            )
            return subprocess.CompletedProcess(command, 0, b"", b"")
        if tail[:2] == ["shell", "am"] and "broadcast" in tail:
            return subprocess.CompletedProcess(command, 0, b"", b"")
        if tail[:2] == ["shell", "iptables"] or tail[:2] == ["shell", "ip6tables"]:
            firewall = tail[1]
            args = tail[2:]
            op = args[0]
            chain = args[1] if len(args) > 1 else ""
            if op == "-S":
                if chain == "OUTPUT":
                    return subprocess.CompletedProcess(
                        command, 0, ("\n".join(self.output_jumps[firewall]) + "\n").encode(), b""
                    )
                if self.chains[firewall] is None:
                    return subprocess.CompletedProcess(command, 1, b"", b"No chain")
                lines = [f"-N {smoke.CHAIN}", *self.chains[firewall]]
                return subprocess.CompletedProcess(
                    command, 0, ("\n".join(lines) + "\n").encode(), b""
                )
            if op == "-N":
                if self.chains[firewall] is not None:
                    return subprocess.CompletedProcess(command, 1, b"", b"chain exists")
                self.chains[firewall] = []
                return subprocess.CompletedProcess(command, 0, b"", b"")
            if op == "-F":
                if self.chains[firewall] is None:
                    return subprocess.CompletedProcess(command, 1, b"", b"No chain")
                self.chains[firewall] = []
                return subprocess.CompletedProcess(command, 0, b"", b"")
            if op == "-X":
                if self.chains[firewall] is None:
                    return subprocess.CompletedProcess(command, 1, b"", b"No chain")
                if self.chains[firewall]:
                    return subprocess.CompletedProcess(command, 1, b"", b"chain not empty")
                self.chains[firewall] = None
                return subprocess.CompletedProcess(command, 0, b"", b"")
            if op == "-A" and chain == "OUTPUT":
                self.output_jumps[firewall].append("-A OUTPUT -j JASMINE_SMOKE_OFFLINE")
                return subprocess.CompletedProcess(command, 0, b"", b"")
            if op == "-A" and chain == "JASMINE_SMOKE_OFFLINE":
                suffix = " ".join(args[2:])
                if "REJECT" in args:
                    reject_type = "icmp-port-unreachable" if firewall == "iptables" else "icmp6-port-unreachable"
                    suffix += f" --reject-with {reject_type}"
                self.chains[firewall].append(f"-A {chain} {suffix}")
                return subprocess.CompletedProcess(command, 0, b"", b"")
            if op == "-I" and chain == "OUTPUT":
                self.output_jumps[firewall].insert(0, "-A OUTPUT -j JASMINE_SMOKE_OFFLINE")
                return subprocess.CompletedProcess(command, 0, b"", b"")
            if op == "-D" and chain == "OUTPUT":
                if self.output_jumps[firewall]:
                    self.output_jumps[firewall].pop(0)
                    return subprocess.CompletedProcess(command, 0, b"", b"")
                return subprocess.CompletedProcess(command, 1, b"", b"No chain")
        return subprocess.CompletedProcess(command, 0, b"", b"")


class EmulatorToolsTest(unittest.TestCase):
    def test_system_image_url_uses_its_own_repository(self):
        doc = minidom.parseString('''<repository><remotePackage path="fixture">
          <revision><major>1</major></revision><display-name>Fixture</display-name>
          <archives><archive><complete><size>10</size><checksum type="sha1">0000000000000000000000000000000000000000</checksum>
          <url>x86_64-fixture.zip</url></complete></archive></archives></remotePackage></repository>''')
        info = sdk.package_info(doc, "fixture", prepare.SOURCES[1][1])
        self.assertEqual(info["url"], "https://dl.google.com/android/repository/sys-img/google_apis/x86_64-fixture.zip")
        with self.assertRaisesRegex(ValueError, "origin"):
            sdk.package_info(doc, "fixture", "https://fixture.invalid/repository.xml")

    def test_license_normalization_preserves_paragraphs(self):
        value = "  Heading\n\nAn indented\n    line.  \n\nLast paragraph.\n"
        normalized = "Heading\n\nAn indented line. \n\nLast paragraph."
        self.assertEqual(prepare.license_hash(value), hashlib.sha1(normalized.encode()).hexdigest())

    def test_installed_components_are_reused_only_when_complete(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            info = {"path": "emulator", "url": "https://dl.google.com/fixture.zip", "size": 10,
                    "algorithm": "sha1", "checksum": "0" * 40}
            target = root / "emulator"
            target.mkdir()
            (target / ".jasmine-toolchain-receipt.json").write_text(json.dumps({**info, "archive_sha256": "1" * 64}))
            for name in ("source.properties", "package.xml", "emulator.exe"):
                (target / name).write_text("fixture")
            self.assertTrue(prepare.installed(info, root, ("emulator.exe",)))
            self.assertFalse(prepare.installed(info, root, ("missing.exe",)))
            self.assertFalse(prepare.installed({**info, "size": 11}, root, ("emulator.exe",)))

    def test_ui_bounds_and_merged_flutter_semantics(self):
        tree = ET.fromstring('<hierarchy><node text="" content-desc="登录即为同意 &#10;使用协议"/><node text="取消"/></hierarchy>')
        self.assertEqual(smoke.labels(tree), ["登录即为同意 \n使用协议", "取消"])
        self.assertEqual(smoke.center("[0,736][720,838]"), (360, 787))
        for invalid in ("", "[0,0][0,10]", "[-1,0][20,20]"):
            with self.assertRaises(ValueError):
                smoke.center(invalid)

    def test_real_device_serials_are_rejected_before_any_command(self):
        with self.assertRaisesRegex(ValueError, "local emulator"):
            smoke.Smoke(Path("adb.exe"), 5038, "physical-device", Path("unused"))

    def test_guest_network_snapshot_restore_is_idempotent_and_scoped(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            fake = FakeAdb()
            instance = smoke.Smoke(Path("fake-adb"), 5038, "emulator-5554", output)
            with mock.patch.object(smoke.subprocess, "run", side_effect=fake):
                instance.offline()
                snapshot = json.loads((output / smoke.NETWORK_SNAPSHOT).read_text())
                self.assertEqual(snapshot["settings"], {
                    "airplane_mode_on": "0", "wifi_on": "1", "mobile_data": "0"
                })
                self.assertEqual(snapshot["avd"], smoke.AVD)
                self.assertEqual(snapshot["boot_id"], "boot-fixture")
                self.assertEqual(snapshot["firewalls"]["iptables"]["chain_rules"], [])
                self.assertFalse(any("-F" in call and "OUTPUT" in call for call in fake.calls))
                self.assertEqual(fake.settings["airplane_mode_on"], "1")
                self.assertIsNotNone(fake.chains["iptables"])
                self.assertEqual(len(fake.output_jumps["iptables"]), 1)
                instance.restore_network()
                first_restore_call_count = len(fake.calls)
                instance.restore_network()
                self.assertEqual(instance.network_restore_attempts, 2)
                self.assertEqual(len(fake.calls), first_restore_call_count)
                self.assertEqual(fake.settings, {
                    "airplane_mode_on": "0", "wifi_on": "1", "mobile_data": "0"
                })
                self.assertEqual(fake.services, {"wifi": "enable", "data": "disable"})
                self.assertIsNone(fake.chains["iptables"])
                self.assertIsNone(fake.chains["ip6tables"])
                self.assertEqual(fake.output_jumps, {"iptables": [], "ip6tables": []})
                self.assertTrue(instance.report["network"]["restored"])

    def test_partial_offline_failure_is_restored_in_finally_style(self):
        def fail_reject(tail):
            return tail[:2] == ["shell", "iptables"] and tail[2:4] == ["-A", smoke.CHAIN] and "REJECT" in tail

        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            fake = FakeAdb(fail=fail_reject)
            instance = smoke.Smoke(Path("fake-adb"), 5038, "emulator-5554", output)
            with mock.patch.object(smoke.subprocess, "run", side_effect=fake):
                with self.assertRaisesRegex(RuntimeError, "adb command failed"):
                    instance.offline()
                instance.restore_network()
                instance.restore_network()
                self.assertEqual(fake.settings, {
                    "airplane_mode_on": "0", "wifi_on": "1", "mobile_data": "0"
                })
                self.assertIsNone(fake.chains["iptables"])
                self.assertIsNone(fake.chains["ip6tables"])
                self.assertEqual(fake.output_jumps, {"iptables": [], "ip6tables": []})

    def test_restore_timeout_is_recorded_and_later_steps_continue(self):
        timed_out = False

        def fail_once(tail):
            nonlocal timed_out
            if not timed_out and tail[:4] == ["shell", "iptables", "-F", smoke.CHAIN]:
                timed_out = True
                return "timeout"
            return False

        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            fake = FakeAdb()
            instance = smoke.Smoke(Path("fake-adb"), 5038, "emulator-5554", output)
            with mock.patch.object(smoke.subprocess, "run", side_effect=fake):
                instance.offline()
                fake.fail = fail_once
                with self.assertRaisesRegex(RuntimeError, "did not complete"):
                    instance.restore_network()
                self.assertIsNotNone(fake.chains["iptables"])
                self.assertIsNone(fake.chains["ip6tables"])
                self.assertEqual(fake.settings["airplane_mode_on"], "0")
                self.assertTrue(any(call[5:8] == ["shell", "settings", "put"] for call in fake.calls))
                instance.restore_network()
                self.assertIsNone(fake.chains["iptables"])
                self.assertIsNone(fake.chains["ip6tables"])
                self.assertTrue(instance.report["network"]["restored"])

    def test_restore_identity_mismatch_stops_before_guest_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            fake = FakeAdb()
            instance = smoke.Smoke(Path("fake-adb"), 5038, "emulator-5554", output)
            with mock.patch.object(smoke.subprocess, "run", side_effect=fake):
                instance.offline()
                restore_start = len(fake.calls)
                fake.boot_id = "different-boot"
                with self.assertRaisesRegex(RuntimeError, "differs"):
                    instance.restore_network()
                restore_calls = [call[5:] for call in fake.calls[restore_start:]]
                self.assertEqual(restore_calls, [
                    ["emu", "avd", "name"],
                    ["shell", "cat", "/proc/sys/kernel/random/boot_id"],
                ])
                self.assertIsNotNone(fake.chains["iptables"])
                self.assertEqual(fake.settings["airplane_mode_on"], "1")

    def test_restore_network_cli_uses_persisted_snapshot(self):
        root = Path(__file__).resolve().parents[2]
        runs = root / ".tmp" / "emulator-runs"
        runs.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=runs) as folder:
            output = Path(folder)
            fake = FakeAdb()
            instance = smoke.Smoke(Path("fake-adb"), 5038, "emulator-5554", output)
            with mock.patch.object(smoke.subprocess, "run", side_effect=fake):
                instance.offline()
                argv = [
                    "android_emulator_smoke.py",
                    "--adb", "fake-adb",
                    "--adb-port", "5038",
                    "--serial", "emulator-5554",
                    "--output", str(output),
                    "--restore-network",
                    "--network-snapshot", str(output / smoke.NETWORK_SNAPSHOT),
                ]
                with mock.patch.object(sys, "argv", argv):
                    self.assertEqual(smoke.main(), 0)
            report = json.loads((output / "network-restore-report.json").read_text())
            self.assertEqual(report["status"], "restored")
            self.assertIsNone(fake.chains["iptables"])
            self.assertIsNone(fake.chains["ip6tables"])

    def test_preexisting_same_named_chain_is_rejected_without_guest_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            fake = FakeAdb(preexisting=True)
            instance = smoke.Smoke(Path("fake-adb"), 5038, "emulator-5554", output)
            with mock.patch.object(smoke.subprocess, "run", side_effect=fake):
                with self.assertRaisesRegex(RuntimeError, "pre-existing"):
                    instance.offline()
                self.assertEqual(fake.settings, {
                    "airplane_mode_on": "0", "wifi_on": "1", "mobile_data": "0"
                })
                self.assertEqual(fake.services, {"wifi": "enable", "data": "disable"})
                self.assertEqual(fake.chains["iptables"], ["-A JASMINE_SMOKE_OFFLINE -j FOREIGN"])
                instance.restore_network()
                self.assertEqual(fake.chains["iptables"], ["-A JASMINE_SMOKE_OFFLINE -j FOREIGN"])

    def test_powershell_fallback_is_scoped_to_owned_chain(self):
        source = (Path(__file__).resolve().parents[1] / "run-android-emulator.ps1").read_text(encoding="utf-8")
        self.assertIn("network-state-before.json", source)
        self.assertIn("--restore-network", source)
        self.assertIn("--network-snapshot", source)
        self.assertIn("already-restored", source)
        self.assertNotIn("Restore-GuestNetwork", source)
        self.assertNotIn("Invoke-GuestAdb", source)
        self.assertNotIn("'-F', $chain", source)
        self.assertNotIn("'-F', 'OUTPUT'", source)
        self.assertNotIn('"-F", "OUTPUT"', source)
        self.assertNotIn("iptables -F OUTPUT", source)


if __name__ == "__main__":
    unittest.main()
