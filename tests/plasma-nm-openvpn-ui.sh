#!/bin/bash
# Build plasma-nm's OpenVPN plugin from src/plasma-nm and run the headless UI test
# against a SoftHSM token. Needs Fedora with the plasma-nm build dependencies,
# openvpn, softhsm and opensc, and src/plasma-nm (scripts/setup-src), e.g.:
#   scripts/enter.sh .cache/f43 /work/tests/plasma-nm-openvpn-ui.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
B=${BUILD_DIR:-$ROOT/.cache/plasma-nm-build}
T=$(mktemp -d)
export SOFTHSM2_CONF=$T/softhsm2.conf QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1

mkdir -p $B
cmake -S $ROOT/src/plasma-nm -B $B -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=OFF -DCMAKE_EXPORT_COMPILE_COMMANDS=ON > $B/cmake.log
make -C $B -s -j"$(nproc)" plasmanetworkmanagement_openvpnui

# compile the test with the flags of a plugin source file
flags=$(python3 - "$B" <<'EOF'
import json, shlex, sys
for e in json.load(open(sys.argv[1] + "/compile_commands.json")):
    if e["file"].endswith("vpn/openvpn/openvpnwidget.cpp"):
        a = shlex.split(e["command"])[1:]
        out = []
        for i, x in enumerate(a):
            if x == "-isystem":
                out += [x, a[i + 1]]
            elif x.startswith(("-I", "-D", "-std", "-f")):
                out.append(x)
        print(" ".join(shlex.quote(x) for x in out))
EOF
)
libs="$(pkg-config --cflags --libs Qt6Widgets Qt6Test Qt6DBus libnm)"
eval g++ $flags -I$ROOT/src/plasma-nm/libs/editor/widgets -o $T/uitest $ROOT/tests/plasma-nm-openvpn-ui.cpp \
	-L$B/bin -Wl,-rpath,$B/bin -lplasmanm_editor -lKF6CoreAddons -lKF6NetworkManagerQt $libs

# token with a certificate
mkdir -p $T/tokens
echo "directories.tokendir = $T/tokens" > $SOFTHSM2_CONF
softhsm2-util --init-token --free --label vpntoken --pin 123456 --so-pin 0000 > /dev/null
cd $T
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout k.pem -out c.pem -subj /CN=vpnclient -days 2 2> /dev/null
openssl pkey -in k.pem -outform DER -out k.der
openssl x509 -in c.pem -outform DER -out c.der
pkcs11-tool --module /usr/lib64/pkcs11/libsofthsm2.so --login --pin 123456 --write-object k.der --type privkey --id 01 --label vpnclient > /dev/null
pkcs11-tool --module /usr/lib64/pkcs11/libsofthsm2.so --login --pin 123456 --write-object c.der --type cert --id 01 --label vpnclient > /dev/null
id=$(openvpn --show-pkcs11-ids /usr/lib64/p11-kit-proxy.so | sed -n 's/.*Serialized id:\s*//p')

PLUGIN=$B/bin/plasmanetworkmanagement_openvpnui.so PKCS11_ID="$id" $T/uitest
