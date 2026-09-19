#!/bin/bash
# Rebuild Fedora packages with our patches on top.
#
# Must run inside Fedora (natively, or in a rootfs via scripts/rebuild).
# For every package: downloads the latest SRPM from the enabled repos, adds
# patches/<package>/*.patch as Patch9000+, appends ".pkcs11.<N>" to Release (see lib.sh),
# installs build deps, builds, and puts binary RPMs into out/fc<N>/ (a dnf repo).
#
# usage: build-rpm.sh <package> [<package>...]
# patches/<package>/spec.sh, if present, is sourced with $spec set to tweak the spec.
#
#   env: SUFFIX (override the release suffix), SRPM_<package> (use given SRPM instead of downloading),
#        SUDO (default: "sudo" unless running as root),
#        SRPM_ONLY=1 (only build the patched SRPMs into out/fc<N>/srpm/, e.g. for COPR)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
DIST=$(rpm -E 'fc%fedora')
OUT=$ROOT/out/$DIST
if [ -z "${SUDO+x}" ]; then
	SUDO=$([ "$(id -u)" = 0 ] && echo "" || echo sudo)
fi

mkdir -p "$OUT"

for pkg in "$@"; do
	patchdir=$ROOT/patches/$pkg
	suffix=${SUFFIX:-$(release_suffix "$ROOT" "$pkg")}
	[ -d "$patchdir" ] || { echo "no patches dir: $patchdir" >&2; exit 1; }

	work=$(mktemp -d "${TMPDIR:-/var/tmp}/build-$pkg.XXXXXX")
	top=$work/rpmbuild
	mkdir -p "$top"/{SOURCES,SPECS}

	srpm_var="SRPM_${pkg//-/_}"
	if [ -n "${!srpm_var:-}" ]; then
		cp "${!srpm_var}" "$work/"
	else
		dnf -q download --srpm --destdir "$work" "$pkg"
	fi
	srpm=$(ls "$work"/*.src.rpm)
	echo "== $pkg: $(basename "$srpm")"
	rpm -i --define "_topdir $top" "$srpm"
	spec=$top/SPECS/$pkg.spec

	grep -q '^%autosetup.*-p1' "$spec" || { echo "$spec: no '%autosetup -p1', cannot add patches" >&2; exit 1; }

	# Add our patches after the last Patch/Source line.
	n=9000
	lines=""
	for p in "$patchdir"/*.patch; do
		[ -e "$p" ] || continue
		cp "$p" "$top/SOURCES/"
		lines+="Patch$n: $(basename "$p")\n"
		n=$((n + 1))
	done
	[ -n "$lines" ] || { echo "no patches in $patchdir" >&2; exit 1; }
	last=$(grep -nE '^(Patch|Source)[0-9]*:' "$spec" | tail -1 | cut -d: -f1)
	printf "$lines" > "$work/patchlines"
	awk -v last="$last" -v f="$work/patchlines" \
		'{ print } NR == last { while ((getline l < f) > 0) print l }' "$spec" > "$spec.new"
	mv "$spec.new" "$spec"

	# Package-specific spec adjustments
	if [ -f "$patchdir/spec.sh" ]; then
		. "$patchdir/spec.sh"
	fi

	sed -i -E "s/^(Release:\s*.*%\{\?dist\})\s*$/\1.$suffix/" "$spec"
	grep -qF ".$suffix" <(grep '^Release:' "$spec") || { echo "$spec: failed to patch Release" >&2; exit 1; }

	if [ -n "${SRPM_ONLY:-}" ]; then
		mkdir -p "$OUT/srpm"
		rpmbuild -bs --define "_topdir $top" "$spec" > "$work/build.log" 2>&1 || {
			cat "$work/build.log"; exit 1; }
		rm -f "$OUT/srpm/$pkg"-[0-9]*.src.rpm
		cp "$top"/SRPMS/*.src.rpm "$OUT/srpm/"
		echo "== $pkg: $(ls "$top"/SRPMS)"
		rm -rf "$work"
		continue
	fi

	if ! $SUDO dnf -y -q --setopt=install_weak_deps=0 builddep "$spec" 2>&1 | tee "$work/builddep.log"; then
		# In an unprivileged rootfs (scripts/rebuild) rpm cannot chown files to
		# users other than root. Unpack such packages by hand, register them, retry.
		failed=$(sed -n 's/.*Unpack error: \(.*\)$/\1/p' "$work/builddep.log" | sort -u)
		[ -n "${ROOTFS:-}" ] && [ -n "$failed" ] || exit 1
		echo "== unpacking without ownership: $failed"
		(cd "$work" && dnf -q download $failed)
		for r in "$work"/*.rpm; do
			[[ $r == *.src.rpm ]] && continue
			(cd / && rpm2cpio "$r" | cpio -idmu --no-preserve-owner --quiet)
			rpm -i --justdb --nodeps --noscripts "$r"
			rm "$r"
		done
		$SUDO dnf -y -q --setopt=install_weak_deps=0 builddep "$spec"
	fi
	rpmbuild -ba --define "_topdir $top" "$spec" > "$work/build.log" 2>&1 || {
		tail -40 "$work/build.log"; echo "build failed, see $work/build.log" >&2; exit 1; }

	find "$top/RPMS" -name '*.rpm' ! -name '*-debuginfo-*' ! -name '*-debugsource-*' -exec cp {} "$OUT/" \;
	cp "$top"/SRPMS/*.src.rpm "$OUT/"
	echo "== $pkg: built $(ls "$top"/SRPMS)"
	rm -rf "$work"
done

[ -n "${SRPM_ONLY:-}" ] || createrepo_c -q "$OUT"
echo "== repo: $OUT"
