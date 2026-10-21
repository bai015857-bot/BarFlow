#!/usr/bin/env python3
"""Run every deterministic test and persist exact command outcomes."""
import datetime
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
logs = root / ".build/verification"
logs.mkdir(parents=True, exist_ok=True)
scripts = ["test-settings.sh", "test-launch.sh", "test-ui.sh", "test-menu.sh", "test-scroll.sh", "test-side-buttons.sh", "test-integration.sh"]
rows = []
for name in scripts:
    result = subprocess.run(["bash", str(root / "scripts" / name)], cwd=root, capture_output=True, text=True)
    output = result.stdout + result.stderr
    (logs / (name + ".log")).write_text(output)
    rows.append({"command": "bash scripts/" + name, "exit_code": result.returncode, "log": str(logs / (name + ".log"))})
    print(f"=== {name}: exit {result.returncode} ===\n{output}", flush=True)
report = {"checked_at": datetime.datetime.now().astimezone().isoformat(), "results": rows,
          "all_passed": all(row["exit_code"] == 0 for row in rows),
          "hardware_acceptance": False, "notes": "Policy tests, in-process CGEvent fixtures, native settings UI, safe packaged smoke; no granted TCC or live physical scroll/real folding acceptance."}
(logs / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
if not report["all_passed"]:
    sys.exit(1)
