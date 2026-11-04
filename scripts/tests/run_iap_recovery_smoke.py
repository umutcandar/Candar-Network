"""Test the real StoreKit restore handler with fake transactions and backend."""
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
source = (ROOT / "IAPManager.gd").read_text(encoding="utf-8")

def source_method(name):
    match = re.search(r"^func " + re.escape(name) + r"\(", source, re.M)
    assert match, name
    next_func = re.search(r"^func ", source[match.end():], re.M)
    return source[match.start():match.end() + next_func.start()] if next_func else source[match.start():]

# Static invariant: never print raw receipts or transaction/purchase objects.
for forbidden in (
    r'print\("\[IAP\] on_purchase_updated: ", response\)',
    r'print\("\[IAP\] query_purchases_response: ", response\)',
    r'print\("\[IAP\] consume_purchase_response: ", response\)',
    r'print\("\[IAP\] iOS transaction_updated: ", transaction\)',
    r'"error": "finalize_timeout".*"token": token',
):
    assert re.search(forbidden, source) is None, forbidden

with tempfile.TemporaryDirectory(prefix="candar-iap-restore-") as directory:
    work = Path(directory)
    fixture = """extends Node
signal purchase_applied(payload: Dictionary)
var _ios_recovery_in_flight: Dictionary = {}
var call_count := 0
var allow := true
const BOOST_PRODUCTS := ["candar.boost.basic.30d"]
const PREMIUM_PRODUCTS := ["candar.premium.30d"]
func _app_product_id_from_store_id(store_id: String) -> String:
    return store_id.replace("candar.ios.", "candar.")
func _apply_purchase_via_backend(_platform: String, _product: String, _proof: String, _premium: bool, _id: String = "") -> Dictionary:
    call_count += 1
    await get_tree().create_timer(0.05).timeout
    return {"ok": allow, "alreadyApplied": false}
""".replace("    ", "\t") + "\n" + source_method("_on_ios_transaction_updated") + "\n" + source_method("_ios_extract_tx_id")
    (work / "iap_actual.gd").write_text(fixture, encoding="utf-8")
    test = """extends SceneTree
var checks := 0
var failed := 0
func check(ok: bool, msg: String) -> void:
    checks += 1
    if not ok:
        failed += 1
        push_error(msg)
func _initialize() -> void: run.call_deferred()
func run() -> void:
    var iap = load("res://iap_actual.gd").new()
    root.add_child(iap)
    var recovered := []
    iap.purchase_applied.connect(func(payload): recovered.append(payload))
    await iap._on_ios_transaction_updated({"id": "apple-1", "product_id": "candar.ios.boost.basic.30d"})
    check(iap.call_count == 1 and recovered.size() == 1, "Verified StoreKit update should restore once")
    check(recovered[0].get("restored") == true, "Recovered entitlements must be marked")
    iap.allow = false
    await iap._on_ios_transaction_updated({"id": "apple-2", "product_id": "candar.ios.premium.30d"})
    check(recovered.size() == 1, "Unverified Apple transactions must not grant entitlements")
    await iap._on_ios_transaction_updated({"id": "", "product_id": "candar.ios.premium.30d"})
    check(iap.call_count == 2, "Invalid transaction identifiers must be ignored")
    iap.allow = true
    iap._on_ios_transaction_updated({"id": "apple-3", "product_id": "candar.ios.boost.basic.30d"})
    await iap._on_ios_transaction_updated({"id": "apple-3", "product_id": "candar.ios.boost.basic.30d"})
    await create_timer(0.1).timeout
    check(iap.call_count == 3, "Simultaneous callbacks should coalesce to one backend operation")
    iap.free()
    print("IAP recovery smoke: %d checks, %d failures" % [checks, failed])
    quit(1 if failed else 0)
""".replace("    ", "\t")
    (work / "test.gd").write_text(test, encoding="utf-8")
    (work / "project.godot").write_text("""config_version=5
[application]
config/name="Candar StoreKit Test"
[rendering]
renderer/rendering_method="gl_compatibility"
""", encoding="utf-8")
    for args in [["--editor", "--import", "--quit"], ["--script", "res://test.gd", "--quit-after", "500"]]:
        result = subprocess.run([GODOT, "--headless", "--path", str(work), *args],
                                capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        print(output)
        if result.returncode or "SCRIPT ERROR" in output or "Parse Error" in output or (
            "--script" in args and "IAP recovery smoke:" not in output
        ):
            raise SystemExit(result.returncode or 1)
