#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

recipe="$ROOT/packaging/omartix/PKGBUILD"
guide="$ROOT/packaging/README.md"

[[ -f $recipe && -f $guide ]] || fail "Omartix keeps its core package recipe and delivery contract in this repository"
grep -Fx 'pkgname=omartix' "$recipe" >/dev/null || fail "single-repository core package is named omartix"
grep -Fx "provides=('omarchy')" "$recipe" >/dev/null || fail "core package preserves Omarchy's package capability"
grep -Fx "conflicts=('omarchy' 'omarchy-dev' 'omarchy-settings' 'omarchy-settings-dev')" "$recipe" >/dev/null ||
  fail "core package cannot coexist with upstream systemd-owned core files"
grep -Fx 'depends=('\''bash'\'' '\''dinit'\'' '\''elogind'\'' '\''uwsm'\'')' "$recipe" >/dev/null ||
  fail "core package declares its dinit session prerequisites"
grep -F '"${OMARTIX_SRC:?set OMARTIX_SRC to the checked-out Omartix source tree}"' "$recipe" >/dev/null ||
  fail "package build is pinned to the release job checkout"
grep -F 'rm -rf "$pkgdir/usr/share/omarchy/default/systemd" "$pkgdir/etc/systemd"' "$recipe" >/dev/null ||
  fail "core package rejects systemd payload"
grep -F 'No application-specific Omartix' "$guide" >/dev/null ||
  fail "delivery contract keeps application packages external"
grep -F 'provider selected later' "$guide" >/dev/null ||
  fail "delivery contract does not lock Omartix to a remote hosting provider"

require_command bsdtar
require_command makepkg

build_dir=$(mktemp -d)
trap 'find "$build_dir" -depth -delete' EXIT
package_dir="$build_dir/packages"

(
  cd "$ROOT/packaging/omartix"
  OMARTIX_SRC="$ROOT" \
    OMARTIX_PACKAGE_VERSION=0.0.0test \
    PKGDEST="$package_dir" \
    SRCDEST="$build_dir/sources" \
    BUILDDIR="$build_dir/build" \
    makepkg --nodeps --cleanbuild --force >/dev/null
)

packages=("$package_dir"/omartix-0.0.0test-1-x86_64.pkg.tar.*)
[[ ${#packages[@]} == 1 && -f ${packages[0]} ]] ||
  fail "package recipe produces exactly one Omartix archive"
package_archive=${packages[0]}

package_entries=$(bsdtar -tf "$package_archive")
grep -qx 'usr/bin/omarchy-apply-system' <<<"$package_entries" ||
  fail "package ships the Omartix system finalizer"
grep -qx 'usr/share/omarchy/install/dinit/config/all.sh' <<<"$package_entries" ||
  fail "package ships the dinit system finalizer configuration"
grep -qx 'usr/share/omarchy/install/artix/dinit/user/omarchy-sleep-lock' <<<"$package_entries" ||
  fail "package ships dinit user service definitions"
grep -qx 'etc/elogind/logind.conf.d/20-inhibit-delay.conf' <<<"$package_entries" ||
  fail "package ships elogind configuration"
! grep -Eq '(^|/)systemd(/|$)' <<<"$package_entries" ||
  fail "published package archive contains no systemd payload"

package_info=$(bsdtar -xOf "$package_archive" .PKGINFO)
grep -qx 'pkgname = omartix' <<<"$package_info" ||
  fail "package archive metadata identifies Omartix"
pass "Omartix owns one provider-neutral dinit core package in the source repository"
