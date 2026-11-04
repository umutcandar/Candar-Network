"""Exercise real Firebase session store methods offline in Godot 4.6."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
original = (ROOT / "global.gd").read_text(encoding="utf-8")
android = (ROOT / "android/build/src/main/java/com/godot/game/CandarSecureStorePlugin.java").read_text()
activity = (ROOT / "android/build/src/main/java/com/godot/game/GodotApp.java").read_text()
swift = (ROOT / "ios/s.swift").read_text()
assert "FileAccess.open(_REFRESH_PATH, FileAccess.WRITE)" not in original
assert 'await _save_refresh_token(str(token_dict["refresh_token"]))' not in original
for source, checks in [
    (android, ["AES/GCM/NoPadding", "AndroidKeyStore", "@UsedByGodot", "clearRefreshToken", "loadRefreshToken", "saveRefreshToken"]),
    (activity, ["getHostPlugins(Godot godot)", "new CandarSecureStorePlugin(godot)"]),
    (swift, ["import Security", "SecItemAdd", "SecItemCopyMatching", "SecItemDelete", "kSecAttrAccessibleWhenUnlockedThisDeviceOnly", "startSecureSessionRequestWatcher"]),
]:
    for check in checks:
        assert check in source, f"Missing native session implementation: {check}"

def method(name):
    match = re.search(r"^func " + re.escape(name) + r"\(", original, re.M)
    assert match, f"Missing {name}"
    end = re.search(r"^func ", original[match.end():], re.M)
    return original[match.start():match.end() + end.start()] if end else original[match.start():]

names = ["_remove_legacy_refresh_file", "_ios_secure_session_exchange",
         "_save_refresh_token", "_load_refresh_token", "_clear_refresh_token", "logout"]
methods = "\n".join(method(name) for name in names)
# Godot headless CI is Linux, so isolate the real iOS branch with the native
# protocol responder below; this replacement is only in the test harness.
methods = methods.replace('OS.get_name() == "iOS"', 'OS.get_name() == "Linux"')
with tempfile.TemporaryDirectory(prefix="candar-native-session-") as directory:
    work = Path(directory)
    prelude = """extends Node
const _REFRESH_PATH = "user://refresh_token.txt"
const _SECURE_REQUEST_PATH = "user://secure_session_request.json"
const _SECURE_RESPONSE_PATH = "user://secure_session_response.json"
var _secure_session_in_flight = false
var _firebase_refresh_token = ""
var _firebase_id_token = ""
var _current_uid = ""
var _is_signed_in = false
"""
    (work / "global_actual.gd").write_text(prelude + "\n" + methods, encoding="utf-8")
    (work / "responder.gd").write_text("""extends Node
var saved := ""
var operations: Array = []
var enabled := true
func _process(_delta: float) -> void:
    var path = "user://secure_session_request.json"
    if not enabled or not FileAccess.file_exists(path):
        return
    var raw := FileAccess.get_file_as_string(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    var data = JSON.parse_string(raw)
    if typeof(data) != TYPE_DICTIONARY:
        return
    var operation = str(data.get("operation", ""))
    operations.append(operation)
    var reply = {"request_id": data.get("request_id", ""), "ok": true}
    if operation == "save":
        saved = str(data.get("token", ""))
    elif operation == "load":
        reply["token"] = saved
        reply["ok"] = saved != ""
    elif operation == "clear":
        saved = ""
    else:
        reply["ok"] = false
    var result = FileAccess.open("user://secure_session_response.json", FileAccess.WRITE)
    result.store_string(JSON.stringify(reply))
    result.close()
""".replace("    ", "\t"), encoding="utf-8")
    (work / "firebase.gd").write_text("""extends Node
var last_tokens := []
func set_tokens(_id: String, _refresh: String, _uid: String) -> void:
    last_tokens = [_id, _refresh, _uid]
""".replace("    ", "\t"), encoding="utf-8")
    test = """extends SceneTree
var checks := 0
var failures := 0
func check(condition: bool, label: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error(label)
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var session = root.get_node("Session")
    var responder = load("res://responder.gd").new()
    root.add_child(responder)
    var secret := "firebase-refresh-token-1234567890"
    check(await session._save_refresh_token(secret), "Native save should confirm")
    check(responder.saved == secret, "Native storage should receive the correct token")
    check(not FileAccess.file_exists("user://refresh_token.txt"), "No plaintext legacy file")
    session._firebase_refresh_token = ""
    check(await session._load_refresh_token() == secret, "Cold restore should recover native token")
    check(not FileAccess.file_exists("user://secure_session_response.json"), "Response should be deleted")
    await session._clear_refresh_token()
    check(responder.saved == "", "Clear should erase native secret")
    # Simulate upgrade of one old mobile install.
    var legacy = FileAccess.open("user://refresh_token.txt", FileAccess.WRITE)
    legacy.store_string("legacy-firebase-refresh-1234567")
    legacy.close()
    session._firebase_refresh_token = ""
    check(await session._load_refresh_token() == "legacy-firebase-refresh-1234567", "Legacy migration should restore the session")
    check(not FileAccess.file_exists("user://refresh_token.txt"), "Legacy token should be deleted after migration")
    check(responder.saved == "legacy-firebase-refresh-1234567", "Legacy token should be persisted natively")
    session._firebase_id_token = "id-123"
    session._current_uid = "uid-test"
    session._is_signed_in = true
    var uid = FileAccess.open("user://uid.txt", FileAccess.WRITE)
    uid.store_string("uid-test")
    uid.close()
    await session.logout()
    check(responder.saved == "" and session._firebase_refresh_token == "", "Logout removes secure and memory token")
    check(session._firebase_id_token == "" and not session._is_signed_in, "Logout clears id token and signed-in state")
    check(root.get_node("Firebase").last_tokens == ["", "", ""], "Logout clears FirebaseClient credentials")
    check(not FileAccess.file_exists("user://uid.txt"), "Logout removes saved user identity")
    print("Secure session smoke: %d checks; %d failures" % [checks, failures])
    quit(1 if failures else 0)
""".replace("    ", "\t")
    (work / "test.gd").write_text(test, encoding="utf-8")
    (work / "project.godot").write_text("""config_version=5
[application]
config/name="Candar Secure Session"
[autoload]
Session="*res://global_actual.gd"
Firebase="*res://firebase.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
""", encoding="utf-8")
    for args in [["--editor", "--import", "--quit"], ["--script", "res://test.gd", "--quit-after", "500"]]:
        result = subprocess.run([GODOT, "--headless", "--path", str(work), *args],
                                capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        print(output)
        if result.returncode or "SCRIPT ERROR" in output or "Parse Error" in output or (
            "--script" in args and "Secure session smoke:" not in output
        ):
            raise SystemExit(result.returncode or 1)
