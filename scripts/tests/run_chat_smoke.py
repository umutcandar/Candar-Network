"""Exercise real chat UI with isolated services; no production requests."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "test-artifacts/candar-ai-20260909"
GODOT = shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
OUT.mkdir(parents=True, exist_ok=True)
(OUT / ".gdignore").touch()
with tempfile.TemporaryDirectory(prefix="candar-chat-test-") as folder:
    work = Path(folder)
    for name in ["chat.gd", "localized_label.gd", "localized_button.gd", "localized_line_edit.gd", "candar_translations.csv"]:
        shutil.copy2(ROOT / name, work / name)
    for source in ROOT.glob("candar_translations.*.translation"):
        shutil.copy2(source, work / source.name)
    shutil.copy2(ROOT / "scripts/CandarUI.gd", work / "ui.gd")
    shutil.copy2(ROOT / "scripts/tests/profile_fixture.gd", work / "global.gd")
    shutil.copy2(ROOT / "scripts/tests/chat_smoke.gd", work / "test.gd")
    (work / "chat.tscn").write_text(re.sub(r' uid="[^"]+"', "", (ROOT / "chat.tscn").read_text()))
    (work / "firebase.gd").write_text('''extends Node
var calls := 0
var payload: Dictionary = {}
var fail := false
func chat_send(data: Dictionary) -> Dictionary:
 calls += 1
 payload = data
 await get_tree().create_timer(0.1).timeout
 if fail: return {"status":429,"error":"Ücretsiz kapasite dolu. Hakkın kullanılmadı."}
 return {"answer":"Günlük ödül butonuna dokun.","premium":false,"remaining":4}
''')
    (work / "project.godot").write_text('''config_version=5
[application]
config/name="Candar Ai Isolated Test"
[autoload]
Global="*res://global.gd"
Firebase="*res://firebase.gd"
CandarUI="*res://ui.gd"
[display]
window/size/viewport_width=720
window/size/viewport_height=1560
window/size/window_width_override=360
window/size/window_height_override=780
window/stretch/mode="canvas_items"
window/subwindows/embed_subwindows=true
[internationalization]
locale/translations=PackedStringArray("res://candar_translations.tr.translation", "res://candar_translations.en.translation")
[rendering]
renderer/rendering_method="gl_compatibility"
''')
    for args in [["--headless", "--editor", "--import", "--quit"], ["--script", "res://test.gd", "--quit-after", "600", "--", str(OUT)]]:
        result = subprocess.run([GODOT, "--path", str(work), *args], capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        if result.returncode or "ERROR:" in output or "SCRIPT ERROR" in output:
            print(output)
            raise SystemExit(result.returncode or 1)
        print("\n".join(line for line in output.splitlines() if "checks passed" in line) or "Chat import passed.")
