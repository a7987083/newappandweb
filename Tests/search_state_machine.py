#!/usr/bin/env python3
"""Execute search lifecycle transition regression tests using the macOS Swift toolchain."""
from pathlib import Path
import subprocess
import tempfile

source = Path("GameStore/UI/ShellSearchSession.swift").read_text()
start = source.index("final class ShellSearchPhaseMachine {")
end = source.index("final class ShellSearchSession {")
machine = source[start:end]
tests = r'''
func check(_ result: Bool, _ message: String) {
    if !result { fatalError(message) }
}
let phase = ShellSearchPhaseMachine()
check(phase.phase == .idle, "initial phase")
check(phase.begin(), "begin search")
check(!phase.begin(), "reject repeated begin")
check(phase.isSearching, "active during activation")
check(phase.startRestoring(), "cancel during entering animation")
check(!phase.activate(), "stale entry completion must not reactivate")
check(!phase.begin(), "reject begin during restore")
phase.finishRestoring()
check(phase.phase == .idle, "finish restores idle")
check(phase.begin(), "reopen after cancel")
check(phase.activate(), "complete entry")
check(!phase.activate(), "reject repeated activation")
check(phase.startRestoring(), "close active search")
check(!phase.startRestoring(), "reject repeated cancel")
phase.finishRestoring()
check(!phase.isSearching, "not searching after exit")
check(!phase.startRestoring(), "reject cancel while idle")
print("Search phase transitions passed")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "search_phase_tests.swift"
    path.write_text(machine + "\n" + tests)
    subprocess.run(["swift", str(path)], check=True)
