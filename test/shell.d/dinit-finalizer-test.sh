#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

finalizer="$ROOT/bin/omarchy-apply-system"
config_dir="$ROOT/install/dinit/config"
services="$config_dir/enable-services.sh"
packages="$ROOT/install/omarchy-other.packages"

bash -n "$finalizer" "$config_dir/all.sh" "$config_dir/snapper.sh" "$config_dir/firewall.sh" \
  "$services" "$ROOT/bin/omarchy-snapper-cleanup"

grep -F 'source "$OMARCHY_INSTALL/dinit/config/all.sh"' "$finalizer" >/dev/null ||
  fail "system finalizer enters the dinit-only configuration"
grep -F 'omarchy-snapper-cleanup' "$config_dir/snapper.sh" >/dev/null ||
  fail "dinit finalizer owns Snapper cleanup"
grep -F 'dinit/config/enable-services.sh' "$config_dir/all.sh" >/dev/null ||
  fail "dinit finalizer enables installed-system services"
grep -F 'for service in dbus logind NetworkManager bluetoothd dockerd cups avahi-daemon power-profiles-daemon sddm limine-snapper-sync zramen earlyoom; do' "$services" >/dev/null ||
  fail "dinit finalizer enables Omarchy's installed-system services"
for package in avahi-dinit bluez-dinit cups-dinit dbus-dinit dbus-dinit-user docker-dinit earlyoom earlyoom-dinit elogind-dinit limine-snapper-sync-dinit networkmanager-dinit pipewire-dinit pipewire-pulse-dinit power-profiles-daemon-dinit sddm-dinit wireplumber-dinit zramen zramen-dinit; do
  rg -Fx "$package" "$packages" >/dev/null ||
    fail "Artix package manifest supplies $package"
done
if rg -n '\bsystemctl\b|\bsystemd-run\b' "$finalizer" "$config_dir"; then
  fail "dinit finalizer does not invoke systemd"
fi

pass "system finalization is dinit-only"
