#!/usr/bin/env python3
"""Package an already-verified BarFlow build, with source manifest."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
dist = root / "dist"
app = dist / "BarFlow.app"
version = plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
results_path = root / ".build/verification/results.json"
results = json.loads(results_path.read_text())
assert results["all_passed"], "Run verify-all.py successfully before packaging"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
files = [p for folder in ["Sources", "Tests", "Resources", "scripts", "docs", "vendor-notices"]
         for p in (root / folder).rglob("*") if p.is_file()]
files += [root / name for name in ["README.md", "使用说明.md", "LICENSE", "CHANGELOG.md", "THIRD_PARTY_NOTICES.md", ".gitignore", "TEST_RESULTS.md"]]
files += [p for p in (root / ".github").rglob("*") if p.is_file()]
files = [p for p in files if "__pycache__" not in p.parts and p.suffix != ".pyc"]
manifest = {str(p.relative_to(root)): hashlib.file_digest(p.open("rb"), "sha256").hexdigest()
            for p in sorted(set(files))}
(root / "SOURCE_MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
staging = root / f".build/BarFlow-{version}"
assert not staging.exists(), "Packaging staging directory already exists; inspect before replacing"
staging.mkdir()
subprocess.run(["ditto", str(app), str(staging / "BarFlow.app")], check=True)
for name in ["使用说明.md", "TEST_RESULTS.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "SOURCE_MANIFEST.json"]:
    shutil.copy2(root / name, staging / name)
installer_zip = dist / f"BarFlow-{version}-macOS-arm64.zip"
subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(staging), str(installer_zip)], check=True)
source_zip = dist / f"BarFlow-{version}-source.zip"
with zipfile.ZipFile(source_zip, "w", zipfile.ZIP_DEFLATED) as z:
    for p in sorted(set(files + [root / "SOURCE_MANIFEST.json"])):
        z.write(p, "BarFlow/" + str(p.relative_to(root)))
for p in [installer_zip, source_zip]:
    with zipfile.ZipFile(p) as z:
        assert z.testzip() is None
dmg_staging = root / f".build/BarFlow-{version}-dmg"
assert not dmg_staging.exists(), "DMG staging directory already exists; inspect before replacing"
dmg_staging.mkdir()
subprocess.run(["ditto", str(app), str(dmg_staging / "BarFlow.app")], check=True)
(dmg_staging / "Applications").symlink_to("/Applications")
for name in ["使用说明.md", "LICENSE", "THIRD_PARTY_NOTICES.md"]:
    shutil.copy2(root / name, dmg_staging / name)
dmg = dist / f"BarFlow-{version}-macOS-arm64.dmg"
assert not dmg.exists(), "Release DMG already exists; inspect before replacing"
subprocess.run(["hdiutil", "create", "-volname", f"轻栏 {version}", "-srcfolder", str(dmg_staging),
                "-format", "UDZO", str(dmg)], check=True)
subprocess.run(["hdiutil", "verify", str(dmg)], check=True)
manifest_path = dist / "SHA256SUMS.json"
manifest_path.write_text(json.dumps({p.name: {"bytes": p.stat().st_size,
        "sha256": hashlib.file_digest(p.open("rb"), "sha256").hexdigest()}
        for p in [installer_zip, source_zip, dmg]}, indent=2))
checksums = dist / "SHA256SUMS.txt"
checksums.write_text("".join(f"{hashlib.file_digest(p.open('rb'), 'sha256').hexdigest()}  {p.name}\n"
                              for p in [installer_zip, source_zip, dmg]))
print(manifest_path.read_text())
