#!/usr/bin/env python3
"""Inspect the built visit APK; source manifests alone cannot prove its permissions."""
import argparse
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("apk")
parser.add_argument("--aapt", default="aapt", help="Path to Android build-tools aapt")
options = parser.parse_args()
result = subprocess.run([options.aapt, "dump", "permissions", options.apk],
                        check=True, capture_output=True, text=True)
if "android.permission.INTERNET" in result.stdout:
    raise SystemExit("FAIL: offline APK still declares INTERNET")
if "android.permission.RECORD_AUDIO" not in result.stdout:
    raise SystemExit("FAIL: offline APK is missing RECORD_AUDIO")
print("PASS: built APK has microphone permission and no INTERNET permission.")
