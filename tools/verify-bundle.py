#!/usr/bin/env python3
import pathlib
import plistlib
import subprocess

app = pathlib.Path("dist/Mac Fan Controller.app")
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["LSUIElement"] is True, "Dock icon must be hidden"
assert info["CFBundleShortVersionString"] == pathlib.Path("VERSION").read_text().strip()
helper = plistlib.loads((app / "Contents/Library/LaunchDaemons/com.tasnimzotder.mac-fan-controller.helper.plist").read_bytes())
assert helper["BundleProgram"] == "Contents/MacOS/mfc-helper"
assert helper["KeepAlive"] is True
assert helper["MachServices"][helper["Label"]] is True
for executable in [info["CFBundleExecutable"], "mfc-helper"]:
    path = app / "Contents/MacOS" / executable
    assert path.is_file()
    subprocess.run(["codesign", "--verify", "--strict", str(path)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print("Bundle verified: accessory app, launch daemon, versions, peer signatures")
