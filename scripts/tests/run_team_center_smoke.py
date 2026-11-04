"""Load actual team center GDScript in an isolated, offline Godot harness."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
source = (ROOT / "home.gd").read_text(encoding="utf-8")
method_names = [
    "_open_real_team_center", "_create_real_team_pressed",
    "_join_real_team_pressed", "_leave_real_team_pressed",
    "_show_real_team_result", "_open_real_team_leaderboard",
]
methods = []
for name in method_names:
    match = re.search(r"^func " + re.escape(name) + r"\(", source, re.M)
    assert match, f"Missing method: {name}"
    end = re.search(r"^func ", source[match.end():], re.M)
    methods.append(source[match.start():match.end() + end.start()] if end else source[match.start():])
with tempfile.TemporaryDirectory(prefix="candar-team-center-") as directory:
    work = Path(directory)
    (work / "home_actual.gd").write_text("""extends Control
var real_team_label: Label
var modals: Array = []
func _ui_text(_tr: String, en: String) -> String: return en
func _show_app_modal(title: String, body: String) -> void:
    modals.append([title, body])
""".replace("    ", "\t") + "\n".join(methods), encoding="utf-8")
    (work / "global.gd").write_text("""extends Node
var state := {"ok": true, "inTeam": false}
var create_calls := 0
var join_calls := 0
var leave_calls := 0
var score_calls := 0
func get_my_team() -> Dictionary:
    return state
func create_team(_name: String, _code: String = "") -> Array:
    create_calls += 1
    return [true, {"ok": true, "team": {"name": _name}}]
func join_team(_code: String) -> Array:
    join_calls += 1
    return [true, {"ok": true}]
func leave_team() -> Array:
    leave_calls += 1
    return [true, {"ok": true}]
func get_team_leaderboard(_limit: int = 10) -> Array:
    score_calls += 1
    return [{"name": "Alpha", "memberCount": 9}]
""".replace("    ", "\t"), encoding="utf-8")
    (work / "test.gd").write_text("""extends SceneTree
var checks := 0
var failed := 0
func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failed += 1
        push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
    var global = root.get_node("Global")
    var home = load("res://home_actual.gd").new()
    root.add_child(home)
    home.real_team_label = Label.new()
    home.add_child(home.real_team_label)
    await home._open_real_team_center()
    check(home.get_children().any(func(n): return n is AcceptDialog), "Team dialog must be available")
    var name_field := LineEdit.new()
    name_field.text = "Candar Birliği"
    var dialog := AcceptDialog.new()
    home.add_child(dialog)
    await home._create_real_team_pressed(name_field, dialog)
    check(global.create_calls == 1, "Create team must call backend")
    var code_field := LineEdit.new()
    code_field.text = "t0a1b2c3d4e5f"
    await home._join_real_team_pressed(code_field, dialog)
    check(global.join_calls == 1, "Join team must call backend")
    await home._leave_real_team_pressed(dialog)
    check(global.leave_calls == 1, "Leave team must call backend")
    global.state = {"ok": true, "inTeam": true, "team": {
      "name": "Candar", "code": "T0A1B2C3D4E5F", "memberCount": 4, "maxMembers": 30
    }}
    await home._open_real_team_center()
    check(home.real_team_label.text == "Candar", "Team name should be shown")
    await home._open_real_team_leaderboard()
    check(global.score_calls == 1 and home.modals.size() >= 4, "Leaderboard and success modals must open")
    home.free()
    print("Team center smoke: %d checks, %d failures" % [checks, failed])
    quit(1 if failed else 0)
""".replace("    ", "\t"), encoding="utf-8")
    (work / "project.godot").write_text("""config_version=5
[application]
config/name="Candar Teams UI"
[autoload]
Global="*res://global.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
""", encoding="utf-8")
    for arguments in [["--editor", "--import", "--quit"], ["--script", "res://test.gd", "--quit-after", "500"]]:
        result = subprocess.run([GODOT, "--headless", "--path", str(work), *arguments],
                                capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        print(output)
        if result.returncode or "SCRIPT ERROR" in output or "Parse Error" in output or (
            "--script" in arguments and "Team center smoke:" not in output
        ):
            raise SystemExit(result.returncode or 1)
