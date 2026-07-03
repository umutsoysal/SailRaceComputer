#!/usr/bin/env bash
set -euo pipefail

user_home=""
if [[ -n "${USER:-}" ]]; then
  user_home="$(eval echo "~${USER}" 2>/dev/null || true)"
fi

if [[ -n "${DART_BIN:-}" && -x "${DART_BIN}" ]]; then
  exec "${DART_BIN}" "$@"
fi

if [[ -n "${FLUTTER_BIN:-}" && -x "${FLUTTER_BIN}" ]]; then
  flutter_dir="$(cd "$(dirname "${FLUTTER_BIN}")" && pwd)"
  if [[ -x "${flutter_dir}/dart" ]]; then
    exec "${flutter_dir}/dart" "$@"
  fi
fi

if command -v flutter >/dev/null 2>&1; then
  flutter_bin="$(command -v flutter)"
  flutter_dir="$(cd "$(dirname "${flutter_bin}")" && pwd)"
  if [[ -x "${flutter_dir}/dart" ]]; then
    exec "${flutter_dir}/dart" "$@"
  fi
fi

if [[ -x "$HOME/flutter/bin/dart" ]]; then
  exec "$HOME/flutter/bin/dart" "$@"
fi

if [[ -x "$HOME/fvm/default/bin/dart" ]]; then
  exec "$HOME/fvm/default/bin/dart" "$@"
fi

if [[ -n "${user_home}" && -x "${user_home}/flutter/bin/dart" ]]; then
  exec "${user_home}/flutter/bin/dart" "$@"
fi

if [[ -n "${user_home}" && -x "${user_home}/fvm/default/bin/dart" ]]; then
  exec "${user_home}/fvm/default/bin/dart" "$@"
fi

if command -v dart >/dev/null 2>&1; then
  exec dart "$@"
fi

cat <<'EOF' >&2
Unable to locate a Dart SDK.

Set DART_BIN=/absolute/path/to/dart, or install Flutter/Dart in one of:
  - $HOME/flutter/bin/dart
  - $HOME/fvm/default/bin/dart
EOF

exit 1
