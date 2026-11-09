#!/bin/sh
# Project-local Linux builder. Design adapted from Fiximizer's MIT-licensed builder.
set -eu

PROJECT_ROOT=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
TOOLS_ROOT="$PROJECT_ROOT/.tools"
JDK_INSTALL_ROOT="$TOOLS_ROOT/jdk-21-temurin"
WORK_DIR=""

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf -- "$WORK_DIR"
    fi
}
trap cleanup EXIT HUP INT TERM

is_jdk21() {
    HOME_CANDIDATE=$1
    [ -x "$HOME_CANDIDATE/bin/java" ] || return 1
    [ -x "$HOME_CANDIDATE/bin/javac" ] || return 1

    JAVA_OUTPUT=$("$HOME_CANDIDATE/bin/java" -version 2>&1) || return 1
    JAVAC_OUTPUT=$("$HOME_CANDIDATE/bin/javac" -version 2>&1) || return 1

    printf '%s\n' "$JAVA_OUTPUT" | grep -Eq 'version "21([.]|")|openjdk 21([.[:space:]]|$)' || return 1
    printf '%s\n' "$JAVAC_OUTPUT" | grep -Eq '^javac 21([.[:space:]]|$)' || return 1
    return 0
}

try_candidate() {
    CANDIDATE=$1
    [ -n "$CANDIDATE" ] && [ -d "$CANDIDATE" ] || return 1
    if is_jdk21 "$CANDIDATE"; then
        FOUND_JDK_HOME=$(CDPATH= cd -P "$CANDIDATE" && pwd)
        return 0
    fi
    return 1
}

find_jdk21() {
    FOUND_JDK_HOME=""

    if [ -n "${JAVA_HOME:-}" ] && try_candidate "$JAVA_HOME"; then
        return 0
    fi

    if command -v javac >/dev/null 2>&1 && command -v readlink >/dev/null 2>&1; then
        REAL_JAVAC=$(readlink -f "$(command -v javac)" 2>/dev/null || true)
        if [ -n "$REAL_JAVAC" ]; then
            PATH_JDK_HOME=$(dirname "$(dirname "$REAL_JAVAC")")
            if try_candidate "$PATH_JDK_HOME"; then
                return 0
            fi
        fi
    fi

    for CANDIDATE in \
        "$JDK_INSTALL_ROOT" \
        /usr/lib/jvm/* \
        /usr/java/* \
        /opt/jdk* \
        /opt/java/* \
        "${HOME:-/nonexistent}/.local/share/PrismLauncher/java" \
        "${HOME:-/nonexistent}/.local/share/PrismLauncher/java/"* \
        "${HOME:-/nonexistent}/.local/share/PrismLauncher/runtime/"* \
        "${HOME:-/nonexistent}/.local/share/PolyMC/java/"* \
        "${HOME:-/nonexistent}/.local/share/MultiMC/java/"*
    do
        if try_candidate "$CANDIDATE"; then
            return 0
        fi
    done

    return 1
}

install_temurin21() {
    command -v curl >/dev/null 2>&1 || fail "curl is required for the optional JDK download."
    command -v tar >/dev/null 2>&1 || fail "tar is required to extract the JDK archive."

    case "$(uname -m)" in
        x86_64|amd64) ARCHITECTURE="x64" ;;
        aarch64|arm64) ARCHITECTURE="aarch64" ;;
        *) fail "Automatic Temurin installation does not support this CPU architecture. Install JDK 21 and set JAVA_HOME." ;;
    esac

    if command -v sha256sum >/dev/null 2>&1; then
        SHA_TOOL="sha256sum"
    elif command -v shasum >/dev/null 2>&1; then
        SHA_TOOL="shasum"
    else
        fail "sha256sum or shasum is required to verify the JDK download."
    fi

    mkdir -p "$TOOLS_ROOT"
    WORK_DIR=$(mktemp -d "$TOOLS_ROOT/temurin-21.XXXXXX")
    ARCHIVE="$WORK_DIR/temurin-21.tar.gz"
    EXTRACT_DIR="$WORK_DIR/extracted"
    mkdir -p "$EXTRACT_DIR"

    API_URL="https://api.adoptium.net/v3/binary/latest/21/ga/linux/$ARCHITECTURE/jdk/hotspot/normal/eclipse"
    info "No complete JDK 21 found; downloading project-local Eclipse Temurin 21 ($ARCHITECTURE)."

    DOWNLOAD_URL=$(curl --fail --silent --show-error --output /dev/null --write-out '%{redirect_url}' "$API_URL") \
        || fail "Adoptium did not provide a JDK download URL."
    [ -n "$DOWNLOAD_URL" ] || fail "Adoptium returned an empty JDK download URL."

    curl --fail --location --silent --show-error --retry 3 --connect-timeout 20 \
        --output "$ARCHIVE" "$DOWNLOAD_URL" \
        || fail "The JDK archive download failed."

    EXPECTED_HASH=$(curl --fail --location --silent --show-error "$DOWNLOAD_URL.sha256.txt" | awk 'NR == 1 { print $1 }') \
        || fail "Could not retrieve the official JDK SHA-256 checksum."
    printf '%s\n' "$EXPECTED_HASH" | grep -Eq '^[[:xdigit:]]{64}$' \
        || fail "Adoptium returned a malformed SHA-256 checksum."

    if [ "$SHA_TOOL" = "sha256sum" ]; then
        ACTUAL_HASH=$(sha256sum "$ARCHIVE" | awk '{ print $1 }')
    else
        ACTUAL_HASH=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
    fi

    [ "$(printf '%s' "$ACTUAL_HASH" | tr 'A-F' 'a-f')" = "$(printf '%s' "$EXPECTED_HASH" | tr 'A-F' 'a-f')" ] \
        || fail "JDK SHA-256 mismatch. The downloaded archive was rejected."
    ok "JDK archive SHA-256 verified."

    tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR" --no-same-owner \
        || fail "Could not extract the verified JDK archive."

    JAVA_FILE=$(find "$EXTRACT_DIR" -type f -path '*/bin/java' -print -quit)
    [ -n "$JAVA_FILE" ] || fail "The verified archive does not contain bin/java."
    EXTRACTED_HOME=$(dirname "$(dirname "$JAVA_FILE")")
    is_jdk21 "$EXTRACTED_HOME" || fail "The downloaded archive is not a complete JDK 21."

    if [ -e "$JDK_INSTALL_ROOT" ]; then
        BACKUP_PATH="$JDK_INSTALL_ROOT.previous-$(date -u +%Y%m%d%H%M%S)"
        mv "$JDK_INSTALL_ROOT" "$BACKUP_PATH" || fail "Could not preserve the previous project-local JDK."
        warn "Previous project-local JDK preserved at $BACKUP_PATH"
    fi

    mv "$EXTRACTED_HOME" "$JDK_INSTALL_ROOT" || fail "Could not install the JDK under .tools."
    try_candidate "$JDK_INSTALL_ROOT" || fail "Final JDK installation validation failed."
    ok "Installed project-local JDK 21."
}

printf '\nCruor Sable Compat automatic builder\nMinecraft 1.21.1 | NeoForge 21.1.x | Java 21\n\n'

[ -f "$PROJECT_ROOT/gradlew" ] || fail "gradlew is missing."
[ -f "$PROJECT_ROOT/gradle/wrapper/gradle-wrapper.jar" ] || fail "Gradle Wrapper JAR is missing."

if ! find_jdk21; then
    install_temurin21
fi

export JAVA_HOME="$FOUND_JDK_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
ok "Using JDK 21: $JAVA_HOME"
java -version

if [ "$#" -eq 0 ]; then
    set -- build --build-cache --parallel
else
    case " $* " in
        *" --build-cache "*) ;;
        *) set -- "$@" --build-cache ;;
    esac
fi

info "Starting the pinned Gradle Wrapper..."
"$PROJECT_ROOT/gradlew" "$@" || fail "Gradle build failed."

MOD_ID=$(sed -n 's/^mod_id=//p' "$PROJECT_ROOT/gradle.properties" | sed -n '1p')
MOD_VERSION=$(sed -n 's/^mod_version=//p' "$PROJECT_ROOT/gradle.properties" | sed -n '1p')
[ -n "$MOD_ID" ] && [ -n "$MOD_VERSION" ] || fail "Could not read mod_id and mod_version."

JAR_PATH="$PROJECT_ROOT/build/libs/$MOD_ID-$MOD_VERSION.jar"
[ -f "$JAR_PATH" ] || fail "The expected distributable JAR was not found: $JAR_PATH"

printf '\n==========================================\nBUILD SUCCESSFUL\n==========================================\n'
ok "Mod: $JAR_PATH"
if command -v du >/dev/null 2>&1; then
    ok "Size: $(du -h "$JAR_PATH" | awk '{ print $1 }')"
fi
printf '\nCopy this JAR into your Minecraft instance mods/ folder.\n\n'
