#!/usr/bin/env sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR="$PROJECT_DIR/.tooling/core-check"
mkdir -p "$CHECK_DIR"
# The java invocation also works on JDK installations without a javac launcher.
java com.sun.tools.javac.Main -source 17 -target 17 -Xlint:-options -d "$CHECK_DIR" \
    "$PROJECT_DIR/app/src/main/java/org/tabletalk/core/Language.java" \
    "$PROJECT_DIR/app/src/main/java/org/tabletalk/core/AudioSamples.java" \
    "$PROJECT_DIR/app/src/main/java/org/tabletalk/core/ConversationLedger.java" \
    "$PROJECT_DIR/app/src/main/java/org/tabletalk/core/TranslationReveal.java" \
    "$PROJECT_DIR/app/src/main/java/org/tabletalk/inference/WhisperEngine.java" \
    "$PROJECT_DIR/app/src/main/java/org/tabletalk/core/VerifiedModelCopy.java" \
    "$PROJECT_DIR/tests/CoreTests.java"
java -cp "$CHECK_DIR" CoreTests
