#!/bin/bash
# Enter a Fedora rootfs as fake root via user namespaces (no privileges needed).
# The project directory is bind-mounted at /work.
# usage: enter.sh <rootfs> [cmd...]
ROOT=$(cd "$(dirname "$0")/.." && pwd)
R=$(readlink -f "$1"); shift
exec unshare -r -m -p -f --mount-proc=/proc bash -c '
R="$1"; P="$2"; shift 2
mount --rbind /dev "$R/dev"; mount -t proc proc "$R/proc"; mount --rbind /sys "$R/sys" 2>/dev/null
mount -t tmpfs tmpfs "$R/tmp"
cp -L /etc/resolv.conf "$R/etc/resolv.conf"
mkdir -p "$R/work"; mount --bind "$P" "$R/work"
# copr-cli credentials, read-only
if [ -f "$HOME/.config/copr" ]; then
	mkdir -p "$R/root/.config"; touch "$R/root/.config/copr"
	mount --bind "$HOME/.config/copr" "$R/root/.config/copr"; mount -o remount,bind,ro "$R/root/.config/copr"
fi
exec chroot "$R" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin TERM=dumb LANG=C.UTF-8 "$@"
' _ "$R" "$ROOT" "${@:-/bin/bash}"
