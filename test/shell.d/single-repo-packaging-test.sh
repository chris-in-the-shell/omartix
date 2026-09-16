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
grep -Fx 'depends=('\''bash'\'' '\''dinit'\'' '\''elogind'\'')' "$recipe" >/dev/null ||
  fail "core package declares its dinit session prerequisites"
grep -F '"${OMARTIX_SRC:?set OMARTIX_SRC to the checked-out Omartix source tree}"' "$recipe" >/dev/null ||
  fail "package build is pinned to the release job checkout"
grep -F '"$pkgdir/usr/share/omarchy/default/uwsm"' "$recipe" >/dev/null ||
  fail "core package rejects UWSM payload"
grep -F '"$pkgdir/usr/share/omarchy/default/systemd"' "$recipe" >/dev/null ||
  fail "core package rejects systemd payload"
grep -F 'No application-specific Omartix' "$guide" >/dev/null ||
  fail "delivery contract keeps application packages external"
grep -F 'provider selected later' "$guide" >/dev/null ||
  fail "delivery contract does not lock Omartix to a remote hosting provider"
grep -F 'default/systemd' "$guide" >/dev/null ||
  fail "delivery contract documents the systemd payload boundary"
grep -F 'default/uwsm' "$guide" >/dev/null ||
  fail "delivery contract documents the UWSM payload boundary"
grep -F 'allowlist' "$guide" >/dev/null ||
  fail "delivery contract documents review of legacy init-specific migrations"
! grep -Fxq 'usage' "$ROOT/install/omarchy-base.packages" ||
  fail "dinit runtime manifest does not retain an unavailable usage helper"
! grep -Fxq 'uwsm' "$ROOT/install/omarchy-base.packages" ||
  fail "dinit runtime manifest does not retain the systemd UWSM session manager"
! grep -Fxq 'power-profiles-daemon' "$ROOT/install/omarchy-base.packages" ||
  fail "dinit runtime manifest does not retain the conflicting power-profiles daemon"
for package in tlp tlp-pd; do
  grep -Fxq "$package" "$ROOT/install/omarchy-base.packages" ||
    fail "dinit runtime manifest supplies $package"
done
grep -Fxq 'tlp-dinit' "$ROOT/install/omarchy-other.packages" ||
  fail "Artix package manifest supplies the TLP dinit service"

# These migrations are security cleanups for files written by retired upstream
# installers. They must never execute systemd; a new init-specific migration
# needs an explicit Omartix port and review before release.
mapfile -t init_specific_migrations < <(
  cd "$ROOT"
  rg -l -i 'systemctl|systemd-run|systemd-inhibit|timedatectl|systemd-resolved|systemd-oomd|power-profiles-daemon|/etc/systemd' migrations | sort
)
expected_init_specific_migrations=(
  migrations/1788025225.sh
  migrations/1788102906.sh
)
[[ "${init_specific_migrations[*]}" == "${expected_init_specific_migrations[*]}" ]] ||
  fail "new init-specific migration requires an explicit Omartix compatibility review"

require_command bsdtar
require_command makepkg
require_command rg

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
package_payload="$build_dir/payload"
mkdir -p "$package_payload"
bsdtar -xf "$package_archive" -C "$package_payload"

package_entries=$(bsdtar -tf "$package_archive")
grep -qx 'usr/bin/omarchy-apply-system' <<<"$package_entries" ||
  fail "package ships the Omartix system finalizer"
grep -qx 'usr/bin/omartix-app' <<<"$package_entries" ||
  fail "package ships the dinit-safe graphical application launcher"
grep -qx 'usr/share/omarchy/install/dinit/config/all.sh' <<<"$package_entries" ||
  fail "package ships the dinit system finalizer configuration"
grep -qx 'usr/share/omarchy/install/artix/dinit/user/omarchy-sleep-lock' <<<"$package_entries" ||
  fail "package ships dinit user service definitions"
grep -qx 'etc/elogind/logind.conf.d/20-inhibit-delay.conf' <<<"$package_entries" ||
  fail "package ships elogind configuration"
! grep -qx 'etc/limine-entry-tool.d/omarchy-uki.conf' <<<"$package_entries" ||
  fail "dinit package does not force the unavailable systemd UKI path"
grep -qx 'usr/share/omarchy/etc-overrides/cups-cups-files.conf' <<<"$package_entries" ||
  fail "package ships CUPS policy as a post-install override"
grep -qx 'usr/share/omarchy/etc-overrides/plymouth-plymouthd.conf' <<<"$package_entries" ||
  fail "package ships Plymouth theme selection as a post-install override"
! grep -Eq '^etc/(nsswitch\.conf|security/faillock\.conf|cups/cups-files\.conf|plymouth/plymouthd\.conf)$' <<<"$package_entries" ||
  fail "package archive does not conflict with Artix-owned configuration files"
! grep -Eq '(^|/)systemd(/|$)' <<<"$package_entries" ||
  fail "published package archive contains no systemd payload"
! grep -Eq '(^|/)uwsm(/|$)' <<<"$package_entries" ||
  fail "published package archive contains no UWSM payload"
! rg -i -q '\buwsm(-app)?[[:space:]]+--|\buwsm[[:space:]]+(start|stop)' "$package_payload" ||
  fail "published package contains no UWSM command invocation"
grep -Fxq 'Exec=start-hyprland' "$package_payload/usr/share/omarchy/default/wayland-sessions/omarchy.desktop" ||
  fail "published package starts the Omartix Hyprland session directly"
grep -Fq 'loginctl terminate-session' "$package_payload/usr/bin/omarchy-system-logout" ||
  fail "published package ends graphical sessions through elogind"
! rg -q '^ENABLE_UKI=yes$' "$package_payload/etc/limine-entry-tool.d" ||
  fail "published package leaves Limine on its Artix-compatible initramfs path"

package_info=$(bsdtar -xOf "$package_archive" .PKGINFO)
grep -qx 'pkgname = omartix' <<<"$package_info" ||
  fail "package archive metadata identifies Omartix"
pass "Omartix owns one provider-neutral dinit core package in the source repository"
