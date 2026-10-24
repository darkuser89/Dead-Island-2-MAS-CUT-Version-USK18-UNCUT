#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Exercise the real launcher and runtime module in movable synthetic bundles."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unicodedata


def run_tests(app, test_root):
    with tempfile.TemporaryDirectory(prefix="location-tests-", dir=app.parent) as scratch:
        scratch = Path(scratch)
        pair = scratch / "Spiele mit Leerzeichen – Übung"
        pair.mkdir()
        moved_app = pair / app.name
        app.rename(moved_app)
        try:
            game = pair / "DeadIsland2.app"
            executable = game / "Contents/MacOS/DeadIsland2"
            executable.parent.mkdir(parents=True)
            os.link(test_root / "RuntimeProbe.app/Contents/MacOS/RuntimeProbe", executable)
            observer = test_root / "libBoundaryObserver.dylib"
            os.link(observer, pair / observer.name)
            info = {
                "CFBundleIdentifier": "com.plaion.DeadIsland2Usk",
                "CFBundleExecutable": "DeadIsland2",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1",
            }
            info_path = game / "Contents/Info.plist"
            info_path.write_bytes(plistlib.dumps(info))
            original_info = info_path.read_bytes()

            def check_location():
                expected = pair / "DeadIsland2.app"
                located = subprocess.check_output(
                    [str(moved_app / "Contents/MacOS/Launcher"), "--game-path"],
                    cwd="/", text=True,
                ).rstrip("\n")
                assert unicodedata.normalize("NFD", located) == unicodedata.normalize(
                    "NFD", str(expected)
                ), (located, expected)

            def check_runtime(bundle, active):
                environment = os.environ.copy()
                environment["DYLD_INSERT_LIBRARIES"] = str(
                    moved_app / "Contents/Resources/RuntimeIdentity.dylib"
                )
                environment.pop("DI2_LAUNCHER_CLOUD_CHECK", None)
                command = [str(bundle / "Contents/MacOS/DeadIsland2")]
                if not active:
                    command.append("--expect-inactive")
                subprocess.run(command, env=environment, cwd="/", check=True)

            check_location()
            check_runtime(game, active=True)
            assert info_path.read_bytes() == original_info

            relocated = scratch / "Anderer gemeinsamer Ordner"
            pair.rename(relocated)
            pair = relocated
            moved_app = pair / app.name
            game = pair / game.name
            info_path = game / "Contents/Info.plist"
            check_location()
            check_runtime(game, active=True)
            assert info_path.read_bytes() == original_info

            # A non-adjacent game must not get patched even with the module loaded.
            separated = scratch / "Getrennt"
            separated.mkdir()
            os.link(observer, separated / observer.name)
            detached_game = separated / game.name
            game.rename(detached_game)
            check_location()  # no fallback to another installed game
            check_runtime(detached_game, active=False)
            assert (detached_game / "Contents/Info.plist").read_bytes() == original_info

            detached_game.rename(game)
            info["CFBundleIdentifier"] = "local.deadisland2.unsupported"
            info_path.write_bytes(plistlib.dumps(info))
            check_runtime(game, active=False)
            print("PASS: adjacent lookup, relocation, Unicode/spaces, independent working directory; separated/wrong-ID processes refused")
        finally:
            # Keep the single release candidate; temporary fixtures are discarded.
            moved_app.rename(app)


if __name__ == "__main__":
    run_tests(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
