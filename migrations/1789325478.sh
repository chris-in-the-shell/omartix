echo "Keep the Artix kernel; do not migrate to linux-omarchy"

# Omarchy quattro now defaults to linux-omarchy and dropped the installer
# linux-ptl path. Neither kernel is an Artix package. Omartix stays on Artix
# `linux` rather than pulling an Arch/Omarchy kernel on update.
exit 0
