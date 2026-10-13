#!/usr/bin/env python3
"""Replaces the generated MainActivity with one that exposes picture-in-picture.

Run after `flutter create . --platforms=android` (the GitHub workflow does it):

    python3 tool/patch_main_activity.py

Provides the `footbolive/pip` MethodChannel used by lib/services/pip_service.dart
for the movie player's floating window.
"""
import glob
import re
import sys

matches = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not matches:
    sys.exit("MainActivity.kt not found - run `flutter create . --platforms=android` first")
path = matches[0]
pkg = re.search(r"^package\s+([\w.]+)", open(path, encoding="utf8").read(), re.M).group(1)

code = f'''package {pkg}

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "footbolive/pip")
            .setMethodCallHandler {{ call, result ->
                when (call.method) {{
                    "isAvailable" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    )
                    "enter" -> {{
                        var ok = false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {{
                            try {{
                                val params = PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(16, 9))
                                    .build()
                                ok = enterPictureInPictureMode(params)
                            }} catch (e: Exception) {{
                                ok = false
                            }}
                        }}
                        result.success(ok)
                    }}
                    else -> result.notImplemented()
                }}
            }}
    }}
}}
'''
open(path, "w", encoding="utf8").write(code)
print("patched", path)
