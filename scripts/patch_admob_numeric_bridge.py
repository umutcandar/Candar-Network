"""Reproduce the scoped Godot 4.6 banner fix from the untouched vendor 1.0.1 AAR.

Requires Java and ASM 9.7.1 (already cached by the Android Gradle build), or ASM_JAR.
Preserves all vendor entries except Banner.<init> and convertToAdSize numeric casts.
The input digest and exact instruction counts protect against patching another SDK.
"""
import argparse
import hashlib
import io
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SHA256 = '3045a09d0f7592e8fc667d93b60cbc1fd86a8e6e900e51151abb3aba4f1accfa'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', type=Path, default=ROOT / 'android/plugins/poing-godot-admob-libs/poing-godot-admob-ads-v1.0.1-release.aar')
parser.add_argument('--output', type=Path, default=ROOT / 'android/plugins/poing-godot-admob-libs/poing-godot-admob-ads-v1.0.1-godot46-release.aar')
args = parser.parse_args()
assert args.input.resolve() != args.output.resolve(), 'Never overwrite the original vendor binary'
assert hashlib.sha256(args.input.read_bytes()).hexdigest() == EXPECTED_SHA256, 'Unexpected vendor AAR'
cache = Path.home() / '.gradle/caches/modules-2/files-2.1/org.ow2.asm/asm/9.7.1'
asm = Path(os.environ['ASM_JAR']) if 'ASM_JAR' in os.environ else next(cache.rglob('asm-9.7.1.jar'), None)
if asm is None or not asm.is_file():
    raise SystemExit('ASM 9.7.1 is required; run the Android Gradle build or set ASM_JAR.')
targets = {
    'com/poingstudios/godot/admob/ads/adformats/Banner.class': ('<init>', 1),
    'com/poingstudios/godot/admob/ads/converters/GodotDictionaryToJavaObjectKt.class': ('convertToAdSize', 2),
}
with tempfile.TemporaryDirectory(prefix='candar-admob-numeric-') as directory:
    work = Path(directory)
    subprocess.run(['javac', '-cp', str(asm), '-d', str(work), str(ROOT / 'scripts/android/AdMobNumericBridgePatch.java')], check=True)
    with zipfile.ZipFile(args.input) as aar, zipfile.ZipFile(io.BytesIO(aar.read('classes.jar'))) as jar:
        replacements = {}
        for name, (method, count) in targets.items():
            (work / 'input.class').write_bytes(jar.read(name))
            subprocess.run(['java', '-cp', str(work) + os.pathsep + str(asm), 'AdMobNumericBridgePatch',
                            str(work / 'input.class'), str(work / 'output.class'), method, str(count)], check=True)
            replacements[name] = (work / 'output.class').read_bytes()
        modified_jar = io.BytesIO()
        with zipfile.ZipFile(modified_jar, 'w', zipfile.ZIP_DEFLATED) as output:
            for entry in jar.infolist():
                output.writestr(entry, replacements.get(entry.filename, jar.read(entry.filename)))
        output_aar = io.BytesIO()
        with zipfile.ZipFile(output_aar, 'w', zipfile.ZIP_DEFLATED) as output:
            for entry in aar.infolist():
                output.writestr(entry, modified_jar.getvalue() if entry.filename == 'classes.jar' else aar.read(entry.filename))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(output_aar.getvalue())
print('Patched AAR:', args.output)
print('SHA256:', hashlib.sha256(args.output.read_bytes()).hexdigest())
