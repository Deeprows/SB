#!/usr/bin/env python3
"""Sets the app's minSdk to 24 (Android 7.0).

Run after `flutter create . --platforms=android` (the GitHub workflow does it).
The WebView player, background downloader and picture-in-picture all behave
best from Android 7 up.
"""
import glob
import re
import sys

gradles = glob.glob("android/app/build.gradle*")
if not gradles:
    sys.exit("android/app/build.gradle(.kts) not found")
g = gradles[0]
t = open(g, encoding="utf8").read()
t2 = re.sub(r"(minSdk(?:Version)?\s*=?\s*)flutter\.minSdkVersion", r"\g<1>24", t)
if t2 != t:
    open(g, "w", encoding="utf8").write(t2)
    print("minSdk set to 24 in", g)
else:
    print("minSdk left unchanged in", g)
