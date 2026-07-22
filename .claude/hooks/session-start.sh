#!/bin/bash
# SessionStart hook: install the Flutter SDK (which bundles the Dart SDK) so
# Claude Code on the web (desktop + mobile apps, default cloud environment) can
# run `flutter analyze`, `flutter test`, and `flutter build` to check for errors
# and verify a passing build.
#
# Runs synchronously so the SDK is guaranteed to be on PATH before the agent
# starts working. Idempotent: re-running with the SDK already present is a no-op
# aside from `flutter pub get`.
set -euo pipefail

# Only bother in the remote (Claude Code on the web) environment. Local machines
# are expected to already have Flutter installed.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Pinned to match the Dart SDK constraint in pubspec.yaml (sdk: ^3.9.2).
# Flutter 3.44.7 bundles Dart 3.12.2. Bump this when the project needs a newer
# Dart/Flutter; keep it pinned for reproducible cloud sessions.
FLUTTER_VERSION="3.44.7"
FLUTTER_HOME="${HOME}/flutter"
FLUTTER_BIN="${FLUTTER_HOME}/bin"
DART_BIN="${FLUTTER_HOME}/bin/cache/dart-sdk/bin"
PUB_CACHE_BIN="${HOME}/.pub-cache/bin"
ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
ARCHIVE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${ARCHIVE}"

log() { echo "[session-start] $*"; }

# --- Install Flutter (skip if the pinned version is already present) ----------
installed_version=""
if [ -x "${FLUTTER_BIN}/flutter" ]; then
  installed_version="$(cat "${FLUTTER_HOME}/version" 2>/dev/null || true)"
fi

if [ "${installed_version}" != "${FLUTTER_VERSION}" ]; then
  log "Installing Flutter ${FLUTTER_VERSION} to ${FLUTTER_HOME} ..."
  rm -rf "${FLUTTER_HOME}"
  tmp_archive="$(mktemp -d)/${ARCHIVE}"
  # Retry the download a few times to tolerate transient network hiccups.
  for attempt in 1 2 3; do
    if curl -fsSL "${ARCHIVE_URL}" -o "${tmp_archive}"; then
      break
    fi
    log "Download attempt ${attempt} failed; retrying ..."
    sleep $((attempt * 2))
  done
  mkdir -p "${HOME}"
  tar -xf "${tmp_archive}" -C "${HOME}"
  rm -rf "$(dirname "${tmp_archive}")"
  log "Flutter extracted."
else
  log "Flutter ${FLUTTER_VERSION} already present; skipping download."
fi

export PATH="${FLUTTER_BIN}:${DART_BIN}:${PUB_CACHE_BIN}:${PATH}"

# Flutter uses git internally for version checks; the extracted SDK carries its
# own .git, which git refuses to touch under a different owner without this.
git config --global --add safe.directory "${FLUTTER_HOME}" 2>/dev/null || true

# Disable analytics/telemetry so first-run prompts never block automation.
flutter --disable-analytics >/dev/null 2>&1 || true
dart --disable-analytics >/dev/null 2>&1 || true

# --- Warm the toolchain & fetch project dependencies -------------------------
# First `flutter` invocation unpacks the bundled Dart SDK into bin/cache.
log "Flutter version:"
flutter --version || true

log "Fetching project dependencies (flutter pub get) ..."
(cd "${CLAUDE_PROJECT_DIR}" && flutter pub get)

# Precache the artifacts `flutter test` needs (the flutter_tester binary) so the
# first test run doesn't stall on a download mid-session.
log "Precaching universal + linux artifacts ..."
flutter precache --universal --linux >/dev/null 2>&1 || true

# --- Persist PATH for the rest of the session --------------------------------
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"${FLUTTER_BIN}:${DART_BIN}:${PUB_CACHE_BIN}:\${PATH}\""
    echo "export PUB_CACHE=\"${HOME}/.pub-cache\""
  } >> "${CLAUDE_ENV_FILE}"
  log "PATH persisted to CLAUDE_ENV_FILE."
fi

log "Flutter toolchain ready."
