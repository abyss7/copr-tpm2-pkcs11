# Shared helpers, sourced by the scripts.

# Release suffix of our build of a package: "pkcs11.<N>", where N is the number of
# commits that changed patches/<package>. Any change of the patches gives a newer
# version, and the same patches always give the same one. Without git: "pkcs11".
release_suffix() {
	local root=$1 pkg=$2 n
	n=$(git -C "$root" rev-list --count HEAD -- "patches/$pkg" 2>/dev/null) || n=""
	if [ -n "$n" ] && [ "$n" != 0 ]; then
		echo "pkcs11.$n"
	else
		echo pkcs11
	fi
}
