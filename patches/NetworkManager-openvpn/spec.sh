# Sourced by scripts/build-rpm.sh with $spec set.
# The PKCS#11 patches touch configure.ac/Makefile.am and need pkcs11-helper and p11-kit.
sed -i '0,/^BuildRequires:/s//BuildRequires: autoconf automake libtool gettext-devel autoconf-archive\nBuildRequires: pkgconfig(libpkcs11-helper-1) pkgconfig(p11-kit-1)\n&/' "$spec"
sed -i 's/^%autosetup -p1.*/&\nautoreconf -fi/' "$spec"
