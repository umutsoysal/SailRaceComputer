#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${DART_BIN:-}" && -x "${DART_BIN}" ]]; then
  exec "${DART_BIN}" "$@"
fi

if command -v dart >/dev/null 2>&1; then
  exec dart "$@"
fi

if [[ -x "$HOME/flutter/bin/dart" ]]; then
  exec "$HOME/flutter/bin/dart" "$@"
fi

if [[ -x "$HOME/fvm/default/bin/dart" ]]; then
  exec "$HOME/fvm/default/bin/dart" "$@"
fi

cat <<'EOF' >&2
Unable to locate a Dart SDK.

Set DART_BIN=/absolute/path/to/dart, or install Flutter/Dart in one of:
  - $HOME/flutter/bin/dart
  - $HOME/fvm/default/bin/dart
EOF

exit 1
