#!/usr/bin/env python3
"""Fetch build dependencies; internet is needed on the development computer only."""
import argparse
import hashlib
import pathlib
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
WHISPER_COMMIT = "a8d002cfd879315632a579e73f0148d06959de36"
GRADLE_VERSION = "8.11.1"


def download(url, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".part")
    try:
        with urllib.request.urlopen(url, timeout=120) as source, temporary.open("wb") as output:
            shutil.copyfileobj(source, output)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def gradle():
    tooling = ROOT / ".tooling"
    name = f"gradle-{GRADLE_VERSION}"
    if (tooling / name / "bin" / "gradle").is_file():
        return
    url = f"https://services.gradle.org/distributions/{name}-bin.zip"
    with urllib.request.urlopen(url + ".sha256", timeout=60) as response:
        expected = response.read().decode("ascii").strip().split()[0]
    if len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected.lower()):
        raise RuntimeError("Invalid Gradle checksum response")
    archive = tooling / f"{name}-bin.zip"
    download(url, archive)
    with archive.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    if actual != expected.lower():
        archive.unlink()
        raise RuntimeError("Gradle archive checksum mismatch")
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            path = pathlib.PurePosixPath(member.filename)
            if path.is_absolute() or ".." in path.parts or path.parts[0] != name:
                raise RuntimeError("Unexpected archive entry")
        bundle.extractall(tooling)
    archive.unlink()
    print(f"Gradle {GRADLE_VERSION} prepared.")


def whisper():
    destination = ROOT / "third_party" / "whisper.cpp"
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "--depth", "1", "--branch", "v1.7.6",
                        "https://github.com/ggml-org/whisper.cpp.git", str(destination)], check=True)
    actual = subprocess.check_output(["git", "-C", str(destination), "rev-parse", "HEAD"], text=True).strip()
    dirty = subprocess.check_output(["git", "-C", str(destination), "status", "--porcelain"], text=True).strip()
    if actual != WHISPER_COMMIT or dirty:
        raise RuntimeError("whisper.cpp checkout does not match the clean pinned commit; inspect it before continuing")
    print(f"whisper.cpp v1.7.6 verified at {actual}.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gradle-only", action="store_true")
    parser.add_argument("--whisper-only", action="store_true")
    options = parser.parse_args()
    if options.gradle_only and options.whisper_only:
        parser.error("Choose at most one dependency restriction")
    if not options.gradle_only:
        whisper()
    if not options.whisper_only:
        gradle()
