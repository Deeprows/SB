#!/usr/bin/env python3
"""Makes every Flutter plugin compile against Android API 36.

Some plugins (file_picker, photo_manager ...) are still built against an older
Android API, but the AndroidX lifecycle library they all share now requires 36,
and the release build stops with "requires libraries ... to compile against
version 36 or later". This adds a small block to the generated
android/build.gradle(.kts) that raises compileSdk to 36 for the plugin modules
(the app module already uses Flutter's own, newer setting).

Run after `flutter create . --platforms=android` (the GitHub workflow does it):

    python3 tool/patch_compile_sdk.py

Safe to run more than once.
"""
import os
import re
import sys

MARK = "// streambox: plugin compileSdk"

KTS = '''
%s
subprojects {
    afterEvaluate {
        if (name != "app") {
            val ext = extensions.findByName("android")
            if (ext != null) {
                try {
                    ext.withGroovyBuilder { "compileSdkVersion"(36) }
                } catch (e: Exception) {
                    try {
                        ext.withGroovyBuilder { "setCompileSdk"(36) }
                    } catch (e2: Exception) {
                    }
                }
            }
        }
    }
}
''' % MARK

GROOVY = '''
%s
subprojects {
    afterEvaluate { p ->
        if (p.name != "app" && p.hasProperty("android")) {
            try {
                p.android { compileSdkVersion 36 }
            } catch (Exception e) {
            }
        }
    }
}
''' % MARK

for name, block in (("android/build.gradle.kts", KTS), ("android/build.gradle", GROOVY)):
    if not os.path.exists(name):
        continue
    s = open(name, encoding="utf8").read()
    if MARK in s:
        print("already patched", name)
        sys.exit(0)
    # It must be registered BEFORE the template's evaluationDependsOn(":app").
    m = re.search(r"^subprojects\s*\{\s*\n\s*project\.evaluationDependsOn\(", s, re.M)
    if m:
        s = s[:m.start()] + block.lstrip("\n") + "\n" + s[m.start():]
    else:
        s = s + block
    open(name, "w", encoding="utf8").write(s)
    print("patched", name)
    sys.exit(0)

sys.exit("android/build.gradle(.kts) not found - run `flutter create . --platforms=android` first")
