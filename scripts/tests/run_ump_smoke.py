"""Exercise the real AdMob wrappers with native-signal doubles, without network/ads."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"

with tempfile.TemporaryDirectory(prefix="candar-ump-test-") as directory:
    work = Path(directory)
    shutil.copytree(ROOT / "addons/admob/src", work / "addons/admob/src")
    shutil.copy2(ROOT / "addons/admob/version_helper.gd", work / "addons/admob/version_helper.gd")
    shutil.copy2(ROOT / "addons/admob/plugin.cfg", work / "addons/admob/plugin.cfg")
    shutil.copy2(ROOT / "scripts/tests/ump_smoke.gd", work / "test.gd")
    (work / "project.godot").write_text('''config_version=5
[application]
config/name="Candar Isolated AdMob Test"
[rendering]
renderer/rendering_method="gl_compatibility"
''')
    for args in [["--editor", "--import", "--quit"], ["--script", "res://test.gd", "--quit-after", "300", "--verbose"]]:
        result = subprocess.run(
            [GODOT, "--headless", "--path", str(work), *args],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
        )
        failures = [line for line in result.stdout.splitlines() if "ERROR:" in line or "Parse Error" in line]
        incomplete = "--script" in args and "UMP smoke:" not in result.stdout
        if result.returncode or failures or incomplete:
            print(result.stdout)
            raise SystemExit(result.returncode or 1)
        print("\n".join(line for line in result.stdout.splitlines() if "UMP smoke" in line) or "Godot AdMob import passed.")
