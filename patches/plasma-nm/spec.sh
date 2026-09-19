# Sourced by scripts/build-rpm.sh with $spec set.
# The OpenVPN plugin takes the p11-kit proxy module path from p11-kit-1.pc.
sed -i '0,/^BuildRequires:/s//BuildRequires: pkgconfig(p11-kit-1)\n&/' "$spec"
