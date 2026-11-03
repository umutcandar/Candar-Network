"""Exercise production Global ad state with fake native ads and no network."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
source = (ROOT / "global.gd").read_text()
manager = source[source.index("var ads_initialized :="):source.index("func start_apple_login()")]
manager = manager.replace('return OS.has_feature("android") or OS.has_feature("ios")', 'return mobile')
for kind in ["banner", "interstitial", "rewarded"]:
    manager = re.sub(r'func _ads_get_' + kind + r'_unit_id\(\) -> String:.*?(?=\nfunc |\n#)',
                     'func _ads_get_' + kind + '_unit_id() -> String:\n\treturn "test-unit"\n', manager, flags=re.S)
with tempfile.TemporaryDirectory(prefix="candar-ad-manager-") as directory:
    work = Path(directory)
    shutil.copytree(ROOT / "addons/admob/src", work / "addons/admob/src")
    for name in ["version_helper.gd", "plugin.cfg"]:
        shutil.copy2(ROOT / "addons/admob" / name, work / "addons/admob" / name)
    (work / "manager.gd").write_text('''extends Node
signal rewarded_boost_applied(payload: Dictionary)
var mobile := true
var premium := false
var ad_free := false
var mining_rate := 1.0
var apply_count := 0
var events: Array = []
func is_ad_free_user() -> bool: return ad_free
func is_user_premium() -> bool: return premium
func analytics_event(name: String, data: Dictionary) -> void: events.append([name, data])
func activate_rewarded_boost(_uid: String, _attempt: int) -> Array:
	apply_count += 1
	return [true, {"total_rate": 1.05}]
''' + manager)
    shutil.copy2(ROOT / "scripts/tests/ad_manager_smoke.gd", work / "test.gd")
    (work / "project.godot").write_text('''config_version=5
[application]
config/name="Candar Ad Manager Test"
[rendering]
renderer/rendering_method="gl_compatibility"
''')
    for args in [["--editor", "--import", "--quit"], ["--script", "res://test.gd", "--quit-after", "1200"]]:
        result = subprocess.run([GODOT, "--headless", "--path", str(work), *args],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        print(result.stdout)
        if result.returncode or "ERROR:" in result.stdout or ("--script" in args and "Ad manager smoke:" not in result.stdout):
            raise SystemExit(result.returncode or 1)
