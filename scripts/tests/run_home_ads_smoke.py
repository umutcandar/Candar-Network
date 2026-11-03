"""Run real home ad entrypoints with an isolated backend/SDK double."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
source = (ROOT / "home.gd").read_text()
method_names = [
    "_init_admob", "_set_rewarded_button_idle", "_set_rewarded_button_blocked",
    "_refresh_rewarded_button_state", "_on_rewarded_button_pressed",
    "_run_rewarded_boost_flow", "_show_rewarded_and_wait",
    "_format_rewarded_wait_time", "_rewarded_boost_error_message",
]
methods = []
for name in method_names:
    match = re.search(r"^func " + re.escape(name) + r"\(", source, re.M)
    assert match, name
    end = re.search(r"^func ", source[match.end():], re.M)
    methods.append(source[match.start():match.end() + end.start()] if end else source[match.start():])
constants = "\n".join(re.findall(r"^const (?:IOS_\w+_ID|AND_\w+_ID|REWARDED_BOOST_\w+).*", source, re.M))
with tempfile.TemporaryDirectory(prefix="candar-home-ads-") as directory:
    work = Path(directory)
    for src, dest in [("home_ads_fixture.gd", "global.gd"), ("home_ads_smoke.gd", "test.gd")]:
        shutil.copy2(ROOT / "scripts/tests" / src, work / dest)
    (work / "home_actual.gd").write_text('''extends Control
var rewarded_button: Button
var current_user_id := "test-user"
var user_data: Dictionary = {}
var _rewarded_flow_in_progress := false
var mobile := true
var modals: Array = []
func _is_mobile() -> bool: return mobile
func _ui_text(_tr_text: String, en_text: String) -> String: return en_text
func _show_app_modal(title: String, body: String) -> void: modals.append([title, body])
func update_kazim_orani_ve_ui() -> void: pass
''' + constants + "\n" + "\n".join(methods))
    (work / "project.godot").write_text('''config_version=5
[application]
config/name="Candar Home Ad Entrypoint Test"
[autoload]
Global="*res://global.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
''')
    result = subprocess.run(
        [GODOT, "--headless", "--path", str(work), "--script", "res://test.gd", "--quit-after", "600"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
    )
    print(result.stdout)
    if result.returncode or "ERROR:" in result.stdout or "Home ads smoke:" not in result.stdout:
        raise SystemExit(result.returncode or 1)
