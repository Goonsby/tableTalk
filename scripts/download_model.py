#!/usr/bin/env python3
"""Download an upstream, checksum-verified multilingual Whisper model for import."""
import argparse
import hashlib
import pathlib
from bootstrap import download, ROOT

MODELS = {
    "tiny": "bd577a113a864445d4c299885e0cb97d4ba92b5f",
    "base": "465707469ff3a37a2b9b8d8f89f2f99de7299dac",
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", choices=MODELS, nargs="?", default="tiny")
options = parser.parse_args()
destination = ROOT / "models" / f"ggml-{options.model}.bin"
download(f"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{destination.name}", destination)
with destination.open("rb") as stream:
    actual = hashlib.file_digest(stream, "sha1").hexdigest()
if actual != MODELS[options.model]:
    destination.unlink()
    raise SystemExit("Model checksum mismatch; file removed")
print(f"Verified {destination}. Copy it to the phone's Downloads folder and import it.")
