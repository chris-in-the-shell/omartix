#!/bin/bash

# Enable Artix-provided dinit services for the same user-visible facilities
# Omarchy enables on its installed systems. This runs in the target root, where
# dinit is not yet PID 1, so enablement is an explicit boot.d link rather than
# a dinitctl request.

set -euo pipefail

enable_dinit_service() {
  local service="$1"
  local definition="/etc/dinit.d/$service"

  [[ -f $definition ]] || {
    echo "Error: required dinit service is unavailable: $service" >&2
    return 1
  }

  install -d -m 0755 /etc/dinit.d/boot.d
  ln -sfn "../$service" "/etc/dinit.d/boot.d/$service"
}

# Dependencies supplied by the respective Artix *-dinit packages start
# automatically from these roots. Do not add a resolved/oomd substitute here:
# DNS is owned by NetworkManager and dinit has no systemd slice model.
for service in dbus logind NetworkManager bluetoothd dockerd cups avahi-daemon power-profiles-daemon sddm limine-snapper-sync zramen earlyoom; do
  enable_dinit_service "$service"
done
