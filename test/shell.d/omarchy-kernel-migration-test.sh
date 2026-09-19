#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1789325478.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"

export PATH="$scratch/bin:$ROOT/bin:$PATH"
export CALL_LOG="$scratch/calls"
export INSTALLED_PACKAGES="$scratch/packages"
printf '%s\n' linux linux-headers > "$INSTALLED_PACKAGES"
: > "$CALL_LOG"

cat > "$scratch/bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman %s\n' "$*" >> "$CALL_LOG"
case "$1" in
  -Q) grep -Fxq "$2" "$INSTALLED_PACKAGES" ;;
  -S) exit 1 ;;
  *) exit 99 ;;
esac
SH
cat > "$scratch/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$CALL_LOG"
exit 1
SH
chmod +x "$scratch/bin/"*

bash -euo pipefail "$migration" >/dev/null

[[ ! -s $CALL_LOG ]] || fail "the Artix kernel migration does not install packages" "$(cat "$CALL_LOG")"
grep -Fxq linux "$INSTALLED_PACKAGES" || fail "the Artix kernel remains installed"
! grep -Fxq linux-omarchy "$INSTALLED_PACKAGES" || fail "linux-omarchy must not be installed"
! grep -Fxq linux-ptl "$INSTALLED_PACKAGES" || fail "linux-ptl must not be installed"
pass "the Artix kernel migration leaves the stock kernel in place"
