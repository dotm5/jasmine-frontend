"""Offline smoke test of the unchanged ARM64 APK on the owned local AVD.

No accounts, real credentials, content browsing, host settings, or extra packages.
Uses only the already-installed adb and Python standard library.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import time
import traceback
from xml.etree import ElementTree as ET


PACKAGE = "opensource.jasmine.local"
ACTIVITY = f"{PACKAGE}/opensource.jmtt2mic.MainActivity"
AVD = "jasmine_api30_smoke"
CHAIN = "JASMINE_SMOKE_OFFLINE"


def labels(tree):
    return [value for node in tree.iter("node") for key in ("text", "content-desc") if (value := node.get(key))]


def center(bounds):
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
    if not match:
        raise ValueError(f"Invalid UI bounds: {bounds}")
    x1, y1, x2, y2 = map(int, match.groups())
    if x2 <= x1 or y2 <= y1:
        raise ValueError("Empty UI bounds")
    return (x1 + x2) // 2, (y1 + y2) // 2


class Smoke:
    def __init__(self, adb, port, serial, output):
        if not re.fullmatch(r"emulator-\d+", serial):
            raise ValueError("Only an explicitly addressed local emulator may be tested")
        self.prefix = [str(adb), "-P", str(port), "-s", serial]
        self.output = output
        self.pids = set()
        self.report = {"started_at": datetime.now(timezone.utc).isoformat(), "status": "running", "serial": serial,
                       "package": PACKAGE, "checks": [], "scope": "Offline emulator smoke only; not physical-device or live API validation"}

    def adb(self, *args, timeout=30, check=True, binary=False):
        started = time.monotonic()
        cmd = self.prefix + list(map(str, args))
        result = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        output = result.stdout.decode("utf-8", errors="replace") if not binary else result.stdout
        error = result.stderr.decode("utf-8", errors="replace")
        entry = {"args": cmd, "exit_code": result.returncode, "seconds": round(time.monotonic() - started, 3),
                 "stdout": f"{len(output)} binary bytes" if binary else output[:5000], "stderr": error[:2000]}
        with (self.output / "commands.jsonl").open("a", encoding="utf-8") as file:
            file.write(json.dumps(entry, ensure_ascii=False) + "\n")
        if check and result.returncode:
            raise RuntimeError(f"adb command failed ({result.returncode}): {args!r}\n{error}\n{output if not binary else ''}")
        return output

    def passed(self, name, **details):
        self.report["checks"].append({"name": name, "status": "passed", **details})
        print(f"PASS {name}", flush=True)

    def save_text(self, name, content):
        (self.output / name).write_text(content, encoding="utf-8")

    def tree(self):
        self.adb("shell", "uiautomator", "dump", "/data/local/tmp/jasmine-smoke.xml", timeout=25)
        raw = self.adb("exec-out", "cat", "/data/local/tmp/jasmine-smoke.xml", binary=True)
        return ET.fromstring(raw)

    def wait_ui(self, *required, timeout=75):
        deadline = time.monotonic() + timeout
        current = []
        while time.monotonic() < deadline:
            tree = self.tree()
            current = labels(tree)
            if any("初始化失败" in value for value in current):
                raise RuntimeError(f"Native/startup failure screen: {current}")
            if all(any(value in label for label in current) for value in required):
                return tree
            time.sleep(1)
        raise TimeoutError(f"UI missing {required}; last labels={current}")

    def capture(self, name, tree=None):
        if tree is None:
            tree = self.tree()
        ET.ElementTree(tree).write(self.output / f"{name}.xml", encoding="utf-8", xml_declaration=True)
        png = self.adb("exec-out", "screencap", "-p", binary=True)
        if not png.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError("Screenshot is not a PNG")
        (self.output / f"{name}.png").write_bytes(png)
        return struct.unpack(">II", png[16:24])

    def tap(self, label, exact=True, x_fraction=None):
        tree = self.tree()
        candidates = [node for node in tree.iter("node")
                      if node.get("package") == PACKAGE and node.get("enabled") == "true"
                      and any(label == node.get(key) if exact else label in node.get(key, "") for key in ("text", "content-desc"))]
        if not candidates:
            raise ValueError(f"UI target not found: {label}; labels={labels(tree)}")
        node = next((n for n in candidates if n.get("clickable") == "true"), candidates[0])
        x, y = center(node.get("bounds", ""))
        if x_fraction is not None:
            x1, _, x2, _ = map(int, re.findall(r"\d+", node.get("bounds")))
            x = round(x1 + (x2 - x1) * x_fraction)
        self.adb("shell", "input", "tap", x, y)
        time.sleep(0.35)

    def app_pid(self):
        pid = self.adb("shell", "pidof", PACKAGE).strip()
        if not re.fullmatch(r"\d+", pid):
            raise RuntimeError(f"Expected one running app process; received {pid!r}")
        self.pids.add(pid)
        return pid

    def offline(self):
        # Restrict only this owned Android guest. Root comes from the unmodified
        # official Google APIs debug image, not an exploit or a host change.
        self.adb("root")
        self.adb("wait-for-device", timeout=45)
        if self.adb("shell", "id", "-u").strip() != "0":
            raise RuntimeError("The owned Google APIs image did not provide adb root")
        for service in ("wifi", "data"):
            self.adb("shell", "svc", service, "disable")
        self.adb("shell", "settings", "put", "global", "airplane_mode_on", "1")
        self.adb("shell", "am", "broadcast", "-a", "android.intent.action.AIRPLANE_MODE", "--ez", "state", "true")
        for command in ("iptables", "ip6tables"):
            self.adb("shell", command, "-N", CHAIN, check=False)
            self.adb("shell", command, "-F", CHAIN)
            self.adb("shell", command, "-A", CHAIN, "-o", "lo", "-j", "RETURN")
            self.adb("shell", command, "-A", CHAIN, "-j", "REJECT")
            output_rules = self.adb("shell", command, "-S", "OUTPUT")
            if f"-A OUTPUT -j {CHAIN}" not in output_rules:
                self.adb("shell", command, "-I", "OUTPUT", "1", "-j", CHAIN)
            rules = self.adb("shell", command, "-S", CHAIN)
            self.save_text(f"guest-{command}.txt", rules)
            if f"-A {CHAIN} -j REJECT" not in rules:
                raise RuntimeError("Guest offline rule verification failed")
        self.passed("guest_ipv4_ipv6_offline", host_firewall_changed=False)

    def run(self, root):
        started = time.monotonic()
        deadline = started + 240
        while time.monotonic() < deadline:
            if self.adb("shell", "getprop", "sys.boot_completed", timeout=10, check=False).strip() == "1":
                break
            time.sleep(2)
        else:
            raise TimeoutError("Android boot timed out after 240 seconds")
        if self.adb("emu", "avd", "name").splitlines()[0].strip() != AVD:
            raise ValueError("Connected emulator is not the project's owned AVD")
        if self.adb("shell", "getprop", "ro.kernel.qemu").strip() != "1":
            raise ValueError("Target is not an Android emulator")
        props = self.adb("shell", "getprop")
        self.save_text("getprop.txt", props)
        abis = self.adb("shell", "getprop", "ro.product.cpu.abilist").strip().split(",")
        bridge = self.adb("shell", "getprop", "ro.dalvik.vm.native.bridge").strip()
        if "arm64-v8a" not in abis or bridge != "libndk_translation.so":
            raise RuntimeError(f"ARM64 native bridge not available: {abis}, {bridge}")
        self.report["guest"] = {"api": self.adb("shell", "getprop", "ro.build.version.sdk").strip(), "abis": abis, "native_bridge": bridge}
        self.passed("boot_and_arm64_bridge", boot_wait_seconds=round(time.monotonic() - started, 2))
        self.offline()
        self.adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        self.adb("shell", "wm", "dismiss-keyguard")
        manifest = json.loads((root / "dist" / "build-manifest.json").read_text(encoding="utf-8-sig"))
        apk = root / "dist" / "jasmine-local-1.7.21-arm64.apk"
        sha256 = hashlib.sha256(apk.read_bytes()).hexdigest()
        if sha256 != manifest["sha256"] or manifest["packageId"] != PACKAGE:
            raise ValueError("APK differs from the verified build manifest")
        self.report["apk"] = {"path": str(apk), "sha256": sha256, "size": apk.stat().st_size, "unchanged_from_build": True}
        package_paths = self.adb("shell", "pm", "path", PACKAGE, check=False).splitlines()
        base_apk = next((line.removeprefix("package:") for line in package_paths if line.endswith("/base.apk")), None)
        reused = base_apk is not None and self.adb("shell", "sha256sum", base_apk).split()[0] == sha256
        installed = "Success: reusing identical installed APK (SHA256 checked)\n" if reused else self.adb("install", "--no-streaming", "-r", apk, timeout=120)
        self.save_text("apk-install.txt", installed)
        if "Success" not in installed:
            raise RuntimeError(f"Package installation failed: {installed}")
        package_info = self.adb("shell", "dumpsys", "package", PACKAGE)
        self.save_text("package.txt", package_info)
        if "primaryCpuAbi=arm64-v8a" not in package_info or "versionName=1.7.21-local" not in package_info:
            raise RuntimeError("Installed ABI/version mismatch")
        self.passed("install_original_arm64_apk", reused_identical_install=reused)
        self.adb("shell", "am", "force-stop", PACKAGE)
        self.adb("logcat", "-b", "all", "-c")
        launch = self.adb("shell", "am", "start", "-W", "-n", ACTIVITY, timeout=90)
        self.save_text("launch.txt", launch)
        tree = self.wait_ui("登录", "账号", "密码", "使用协议")
        size = self.capture("01-login", tree)
        self.passed("login_ui", screenshot_size=size)
        first_pid = self.app_pid()
        maps = self.adb("exec-out", "cat", f"/proc/{first_pid}/maps")
        self.save_text("native-maps.txt", maps)
        required_libraries = ("libflutter.so", "libapp.so", "librust.so", "libndk_translation.so")
        if not all(library in maps for library in required_libraries):
            raise RuntimeError("Expected runtime native libraries not mapped")
        self.save_text("app-files.txt", self.adb("shell", "find", f"/data/user/0/{PACKAGE}/files", "-type", "f"))
        self.passed("native_flutter_dart_rust_loaded", libraries=required_libraries)
        # Flutter merges the linked text into a full-width semantics row. Its
        # center is blank; the observed 720px screenshot places the link at 37%.
        # Keep the reference AVD resolution fixed, and still locate the row by text.
        if size != (720, 1280):
            raise RuntimeError("Merged agreement link requires the reference 720x1280 layout")
        self.tap("使用协议", exact=False, x_fraction=0.37)
        self.capture("02-agreement", self.wait_ui("我知道了"))
        self.tap("我知道了")
        self.wait_ui("账号", "密码")
        self.passed("agreement_open_close")
        self.tap("账号")
        dialog = self.wait_ui("账号", "取消", "确认")
        if not any(n.get("class") == "android.widget.EditText" and n.get("password") == "false" for n in dialog.iter("node")):
            raise RuntimeError("Account input field is missing")
        self.capture("03-account-dialog", dialog)
        self.tap("取消")
        self.wait_ui("账号", "密码")
        self.tap("密码")
        dialog = self.wait_ui("密码", "取消", "确认")
        if not any(n.get("class") == "android.widget.EditText" and n.get("password") == "true" for n in dialog.iter("node")):
            raise RuntimeError("Password input is not marked as obscured")
        self.capture("04-password-dialog", dialog)
        self.tap("取消")
        self.wait_ui("账号", "密码")
        self.passed("account_password_dialogs_cancel", credentials_entered=False, login_attempted=False)
        self.adb("shell", "input", "keyevent", "KEYCODE_HOME")
        time.sleep(1)
        self.adb("shell", "am", "start", "-W", "-n", ACTIVITY)
        self.capture("05-resume", self.wait_ui("账号", "密码"))
        if self.app_pid() != first_pid:
            raise RuntimeError("Process changed during simple background/resume")
        self.passed("background_resume")
        self.adb("shell", "am", "force-stop", PACKAGE)
        self.save_text("relaunch.txt", self.adb("shell", "am", "start", "-W", "-n", ACTIVITY))
        self.capture("06-cold-relaunch", self.wait_ui("登录", "账号", "密码"))
        if self.app_pid() == first_pid:
            raise RuntimeError("Cold relaunch did not create a new app process")
        self.passed("cold_relaunch")
        crash = self.adb("logcat", "-b", "crash", "-d", "-v", "threadtime")
        self.save_text("crash-buffer.txt", crash)
        log = self.adb("logcat", "-b", "all", "-d", "-v", "threadtime")
        self.save_text("logcat.txt", log)
        app_lines = [line for line in log.splitlines() if any(re.search(rf"\s{pid}\s+\d+\s", line) for pid in self.pids)]
        app_log = "\n".join(app_lines)
        self.save_text("app-logcat.txt", app_log)
        fatal = r"FATAL EXCEPTION|Fatal signal|JNI DETECTED ERROR|Unhandled Exception|panicked at|UnsatisfiedLinkError|NoSuchMethodError"
        if (PACKAGE in crash) or re.search(fatal, app_log, re.I):
            raise RuntimeError("App crash/runtime failure found in logs")
        warnings = [line for line in app_lines if re.search(r"\s[EW]\s+flutter\s*:", line)]
        self.report["renderer_warnings"] = warnings
        self.passed("no_app_crash_or_unhandled_exception", app_pids=sorted(self.pids))
        if hashlib.sha256(apk.read_bytes()).hexdigest() != sha256:
            raise RuntimeError("APK changed during testing")
        self.report["status"] = "passed_with_renderer_warnings" if warnings else "passed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", type=Path, required=True)
    parser.add_argument("--adb-port", type=int, default=5038)
    parser.add_argument("--serial", default="emulator-5554")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    if not output.is_relative_to(root / ".tmp" / "emulator-runs"):
        raise ValueError("Test evidence must remain under this workspace's .tmp/emulator-runs")
    output.mkdir(parents=True, exist_ok=True)
    if (output / "smoke-report.json").exists():
        raise FileExistsError("Previous report preserved; select a new output directory")
    smoke = Smoke(args.adb, args.adb_port, args.serial, output)
    try:
        smoke.run(root)
    except Exception as error:
        smoke.report.update(status="failed", error=str(error), traceback=traceback.format_exc())
        try:
            smoke.save_text("failure-logcat.txt", smoke.adb("logcat", "-d", "-b", "all", "-v", "threadtime", timeout=15))
            smoke.capture("failure")
        except Exception as capture_error:
            smoke.report["failure_capture_error"] = str(capture_error)
    finally:
        smoke.report["finished_at"] = datetime.now(timezone.utc).isoformat()
        (output / "smoke-report.json").write_text(json.dumps(smoke.report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": smoke.report["status"], "checks": len(smoke.report["checks"]), "report": str(output / "smoke-report.json")}), flush=True)
    return 1 if smoke.report["status"] == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
