#!/usr/bin/env bash
set -euo pipefail

user_home=""
if [[ -n "${USER:-}" ]]; then
  user_home="$(eval echo "~${USER}" 2>/dev/null || true)"
fi

if [[ -n "${FLUTTER_BIN:-}" && -x "${FLUTTER_BIN}" ]]; then
  exec "${FLUTTER_BIN}" "$@"
fi

if command -v flutter >/dev/null 2>&1; then
  exec flutter "$@"
fi

for candidate in \
  "${user_home}/flutter/bin/flutter" \
  "${user_home}/fvm/default/bin/flutter" \
  "$HOME/flutter/bin/flutter" \
  "$HOME/fvm/default/bin/flutter" \
  "/opt/homebrew/bin/flutter"
do
  if [[ -x "$candidate" ]]; then
    exec "$candidate" "$@"
  fi
done

cat <<'EOF' >&2
Unable to locate a Flutter SDK.

Set FLUTTER_BIN=/absolute/path/to/flutter, or install Flutter in one of:
  - $HOME/flutter/bin/flutter
  - $HOME/fvm/default/bin/flutter
  - /opt/homebrew/bin/flutter
EOF

exit 1
