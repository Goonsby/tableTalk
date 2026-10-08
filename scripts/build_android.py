#!/usr/bin/env python3
"""Prepare an isolated Android build toolchain and produce signed setup/offline debug APKs and the POCO release APK."""
import hashlib
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

from bootstrap import ROOT, download

TOOLS = ROOT / ".tooling"
SDK = TOOLS / "android-sdk"
JDK = TOOLS / "jdk-17"
ENV = os.environ.copy()


def announce(message):
    print(message, flush=True)


def get(url):
    with urllib.request.urlopen(url, timeout=60) as source:
        return source.read()


def verified_download(url, path, expected, algorithm):
    if path.is_file():
        with path.open("rb") as stream:
            if hashlib.file_digest(stream, algorithm).hexdigest() == expected:
                return
    announce(f"Downloading {path.name}…")
    download(url, path)
    with path.open("rb") as stream:
        actual = hashlib.file_digest(stream, algorithm).hexdigest()
    if actual != expected:
        path.unlink()
        raise RuntimeError(f"Checksum mismatch for {path.name}")


def prepare_jdk():
    if (JDK / "bin/javac").is_file():
        return
    announce("Finding the current Temurin JDK 17 release…")
    metadata = json.loads(get("https://api.github.com/repos/adoptium/temurin17-binaries/releases/latest"))
    package = next(asset for asset in metadata["assets"]
                   if asset["name"].startswith("OpenJDK17U-jdk_x64_linux_hotspot_")
                   and asset["name"].endswith(".tar.gz"))
    checksum_asset = next(asset for asset in metadata["assets"]
                          if asset["name"] == package["name"] + ".sha256.txt")
    checksum = get(checksum_asset["browser_download_url"]).decode("ascii").split()[0]
    archive = TOOLS / "downloads" / package["name"]
    verified_download(package["browser_download_url"], archive, checksum, "sha256")
    staging = TOOLS / "jdk-extract"
    staging.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as bundle:
        bundle.extractall(staging, filter="data")
    candidates = [p for p in staging.iterdir() if (p / "bin/javac").is_file()]
    if len(candidates) != 1:
        raise RuntimeError("Unexpected JDK archive layout")
    candidates[0].rename(JDK)
    shutil.rmtree(staging)
    announce("JDK 17 installed in the workspace.")


def build_environment():
    ENV["JAVA_HOME"] = str(JDK)
    ENV["ANDROID_HOME"] = str(SDK)
    ENV["ANDROID_SDK_ROOT"] = str(SDK)
    ENV["ANDROID_USER_HOME"] = str(TOOLS / "android-user")
    ENV["GRADLE_USER_HOME"] = str(TOOLS / "gradle-user")
    ENV["PATH"] = str(JDK / "bin") + os.pathsep + ENV.get("PATH", "")
    Path(ENV["ANDROID_USER_HOME"]).mkdir(parents=True, exist_ok=True)
    Path(ENV["GRADLE_USER_HOME"]).mkdir(parents=True, exist_ok=True)
    trust = TOOLS / "java-truststore"
    if not trust.exists():
        shutil.copyfile(JDK / "lib/security/cacerts", trust)
        # Public managed-environment CA certificates; no credential files are read.
        for cert in sorted(Path("/usr/local/share/ca-certificates").glob("*.crt")):
            subprocess.run([str(JDK / "bin/keytool"), "-importcert", "-noprompt",
                            "-keystore", str(trust), "-storepass", "changeit",
                            "-alias", "tabletalk-" + cert.stem, "-file", str(cert)],
                           env=ENV, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    properties = {"javax.net.ssl.trustStore": str(trust)}
    for protocol, variable in [("https", "HTTPS_PROXY"), ("http", "HTTP_PROXY")]:
        configured = ENV.get(variable) or ENV.get(variable.lower())
        if configured:
            proxy = urllib.parse.urlparse(configured)
            if proxy.username or proxy.password:
                raise RuntimeError("This helper requires the managed proxy without URL credentials")
            if proxy.hostname:
                properties[protocol + ".proxyHost"] = proxy.hostname
                properties[protocol + ".proxyPort"] = str(proxy.port or 80)
    opts = " ".join(f"-D{key}={value}" for key, value in properties.items())
    ENV["JAVA_OPTS"] = ENV.get("JAVA_OPTS", "") + " " + opts
    ENV["GRADLE_OPTS"] = ENV.get("GRADLE_OPTS", "") + " " + opts
    settings = [f"systemProp.{key}={value}" for key, value in properties.items()]
    settings.append("org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8 " + opts)
    (Path(ENV["GRADLE_USER_HOME"]) / "gradle.properties").write_text("\n".join(settings) + "\n")


def prepare_sdk():
    manager = SDK / "cmdline-tools/latest/bin/sdkmanager"
    if not manager.is_file():
        announce("Reading Google's Android toolchain metadata…")
        repository = ET.fromstring(get("https://dl.google.com/android/repository/repository2-1.xml"))
        for item in repository.iter():
            item.tag = item.tag.rsplit("}", 1)[-1]
        # Pin the SDK manager: newer launchers bootstrap an additional CLI.
        package = next(p for p in repository.iter("remotePackage") if p.get("path") == "cmdline-tools;19.0")
        archive = next(a.find("complete") for a in package.findall("./archives/archive")
                       if a.findtext("host-os") == "linux")
        relative = archive.findtext("url")
        checksum = archive.find("checksum")
        algorithm = checksum.get("type", "sha1").lower().replace("-", "")
        path = TOOLS / "downloads" / relative
        verified_download("https://dl.google.com/android/repository/" + relative,
                          path, checksum.text.strip(), algorithm)
        staging = TOOLS / "sdk-command-extract"
        staging.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path) as bundle:
            for entry in bundle.infolist():
                member = Path(entry.filename)
                if member.is_absolute() or ".." in member.parts:
                    raise RuntimeError("Invalid SDK archive path")
            bundle.extractall(staging)
            for entry in bundle.infolist():
                mode = entry.external_attr >> 16
                target = staging / entry.filename
                if mode and target.exists():
                    target.chmod(mode & 0o777)
        manager.parent.parent.parent.mkdir(parents=True, exist_ok=True)
        (staging / "cmdline-tools").rename(manager.parent.parent)
        shutil.rmtree(staging)
    announce("Preparing SDK licenses and Android 35 / NDK 27.2 / CMake 3.22.1…")
    with (TOOLS / "sdk-licenses.log").open("w") as log:
        subprocess.run(["sh", str(manager), "--sdk_root=" + str(SDK), "--licenses"],
                       input="y\n" * 100, text=True, env=ENV, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    with (TOOLS / "sdk-install.log").open("w") as log:
        subprocess.run(["sh", str(manager), "--sdk_root=" + str(SDK),
                        "platforms;android-35", "build-tools;35.0.0", "ndk;27.2.12479018", "cmake;3.22.1"],
                       env=ENV, stdout=log, stderr=subprocess.STDOUT, check=True)
    # Some SDK-manager installations leave the archive root nested one level
    # below the package directory. Gradle requires these files at package root.
    for relative, archive_root in [("platforms/android-35", "android-35"),
                                   ("build-tools/35.0.0", "android-15")]:
        package_dir = SDK / relative
        nested = package_dir / archive_root
        if not (package_dir / "source.properties").is_file() and (nested / "source.properties").is_file():
            for entry in nested.iterdir():
                destination = package_dir / entry.name
                if destination.exists():
                    raise RuntimeError(f"Conflicting SDK package entry: {destination}")
                shutil.move(str(entry), str(destination))
        if not (package_dir / "source.properties").is_file():
            raise RuntimeError(f"Incomplete SDK package: {package_dir}")
    announce("Android SDK and native toolchain prepared.")


def debug_key():
    path = TOOLS / "android-user/debug.keystore"
    if not path.is_file():
        subprocess.run([str(JDK / "bin/keytool"), "-genkeypair", "-noprompt", "-keystore", str(path),
                        "-storepass", "android", "-keypass", "android", "-alias", "androiddebugkey",
                        "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
                        "-dname", "CN=Android Debug,O=Android,C=US"], env=ENV, check=True)
    path.chmod(0o600)
    ENV["TABLETALK_DEBUG_KEYSTORE"] = str(path)


def artifacts():
    output = ROOT / "artifacts"
    output.mkdir(exist_ok=True)
    aapt = SDK / "build-tools/35.0.0/aapt"
    signer = SDK / "build-tools/35.0.0/apksigner"
    certs = []
    summary = {}
    for flavor in ["setup", "offline", "poco"]:
        build_type = "release" if flavor == "poco" else "debug"
        apk = ROOT / f"app/build/outputs/apk/{flavor}/{build_type}/app-{flavor}-{build_type}.apk"
        if flavor == "offline":
            subprocess.run([sys.executable, str(ROOT / "scripts/check_apk_permissions.py"),
                            "--aapt", str(aapt), str(apk)], env=ENV, check=True)
        result = subprocess.check_output(["sh", str(signer), "verify", "--verbose", "--print-certs", str(apk)],
                                         env=ENV, text=True)
        cert = next(line.split(":", 1)[1].strip() for line in result.splitlines()
                    if "certificate SHA-256 digest:" in line)
        certs.append(cert)
        name = f"tabletalk-{flavor}.apk"
        destination = output / name
        shutil.copyfile(apk, destination)
        summary[name] = {"bytes": destination.stat().st_size,
                         "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
                         "signing_certificate_sha256": cert}
    if len(set(certs)) != 1:
        raise RuntimeError("Setup and offline APKs do not share a signing certificate")
    (output / "build-info.json").write_text(json.dumps(summary, indent=2) + "\n")
    announce("All APK signatures verified; offline APK has no INTERNET permission.")
    for name, info in summary.items():
        announce(f"Ready: {output / name} ({info['bytes'] / 1024 / 1024:.1f} MiB)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rebuild-only", action="store_true", help="Reuse the installed SDK and dependencies")
    parser.add_argument("--offline", action="store_true", help="Tell Gradle to use only cached dependencies")
    options = parser.parse_args()
    TOOLS.mkdir(parents=True, exist_ok=True)
    if not options.rebuild_only:
        prepare_jdk()
    build_environment()
    if not options.rebuild_only:
        prepare_sdk()
        subprocess.run([sys.executable, str(ROOT / "scripts/bootstrap.py")], cwd=ROOT, env=ENV, check=True)
    debug_key()
    announce("Building Android APKs and running lint…")
    subprocess.run(["sh", str(ROOT / "gradlew"), "--no-daemon", "--console=plain", "--max-workers=2",
                    *(["--offline"] if options.offline else []),
                    ":app:assembleSetupDebug", ":app:assembleOfflineDebug",
                    ":app:lintSetupDebug", ":app:lintOfflineDebug",
                    ":app:assemblePocoRelease", ":app:lintPocoRelease"], cwd=ROOT, env=ENV, check=True)
    artifacts()
    announce("Build complete.")
