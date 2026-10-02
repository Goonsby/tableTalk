#!/usr/bin/env sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Lightweight launcher: bootstrap the pinned Gradle distribution on first use.
# No Gradle wrapper binary is bundled with this starter.
if [ ! -f "$PROJECT_DIR/.tooling/gradle-8.11.1/bin/gradle" ]; then
    python3 "$PROJECT_DIR/scripts/bootstrap.py" --gradle-only
fi
exec sh "$PROJECT_DIR/.tooling/gradle-8.11.1/bin/gradle" -p "$PROJECT_DIR" "$@"
