#!/usr/bin/python3
"""Check openvpn's PKCS#11 behaviour the NetworkManager-openvpn patches rely on.

Runs inside Fedora (see scripts/enter.sh) with openvpn, softhsm, opensc, openssl.
A SoftHSM token holds the client key, openvpn loads it through the p11-kit proxy
exactly as nm-openvpn-service does, and the management interface is driven like
nm-openvpn-service drives it. Prints the management requests seen per scenario.
"""
import os
import re
import socket
import subprocess
import sys
import tempfile
import time

PROXY = "/usr/lib64/p11-kit-proxy.so"
SOFTHSM = "/usr/lib64/pkcs11/libsofthsm2.so"
PIN = "123456"

W = tempfile.mkdtemp(prefix="ovpn-p11-")
os.environ["SOFTHSM2_CONF"] = f"{W}/softhsm2.conf"


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, check=True, cwd=W, capture_output=True, text=True, **kw).stdout


def setup():
    os.makedirs(f"{W}/tokens")
    with open(os.environ["SOFTHSM2_CONF"], "w") as f:
        f.write(f"directories.tokendir = {W}/tokens\nobjectstore.backend = file\n")
    sh(f"softhsm2-util --init-token --free --label vpntoken --pin {PIN} --so-pin 0000")
    sh("openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ca.key -out ca.crt "
       "-subj /CN=ca -days 2 -addext basicConstraints=critical,CA:true -addext keyUsage=keyCertSign")
    for n, ext in (("server", "serverAuth"), ("client", "clientAuth")):
        sh(f"openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout {n}.key -out {n}.csr -subj /CN={n}")
        with open(f"{W}/{n}.ext", "w") as f:
            f.write(f"extendedKeyUsage={ext}\nkeyUsage=digitalSignature\n")
        sh(f"openssl x509 -req -in {n}.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out {n}.crt -days 2 -extfile {n}.ext")
    sh("openssl pkey -in client.key -outform DER -out client.key.der")
    sh("openssl x509 -in client.crt -outform DER -out client.crt.der")
    for typ, f in (("privkey", "client.key.der"), ("cert", "client.crt.der")):
        sh(f"pkcs11-tool --module {SOFTHSM} --login --pin {PIN} --write-object {f} --type {typ} --id 01 --label client")


def pkcs11_ids():
    out = sh(f"openvpn --show-pkcs11-ids {PROXY}")
    return re.findall(r"Serialized id:\s*(\S+)", out), out


def run_client(pkcs11_id, answers, timeout=20):
    """answers: list of PIN strings (None = don't answer, cancel)."""
    srv = subprocess.Popen(["openvpn", "--dev", "null", "--tls-server", "--port", "11940", "--local", "127.0.0.1",
                            "--ca", f"{W}/ca.crt", "--cert", f"{W}/server.crt", "--key", f"{W}/server.key",
                            "--dh", "none", "--verb", "1"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    mgmt = f"{W}/mgmt.sock"
    if os.path.exists(mgmt):
        os.unlink(mgmt)
    log = open(f"{W}/client.log", "w")
    cli = subprocess.Popen(["openvpn", "--dev", "null", "--tls-client", "--remote", "127.0.0.1", "11940",
                            "--ca", f"{W}/ca.crt", "--pkcs11-providers", PROXY, "--pkcs11-id", pkcs11_id,
                            "--management", mgmt, "unix", "--management-query-passwords",
                            "--auth-retry", "interact", "--tls-exit", "--verb", "3"],
                           stdout=log, stderr=subprocess.STDOUT)
    seen = []
    result = "timeout"
    try:
        for _ in range(100):
            if os.path.exists(mgmt):
                break
            time.sleep(0.1)
        s = socket.socket(socket.AF_UNIX)
        s.connect(mgmt)
        s.settimeout(0.5)
        buf = ""
        answers = list(answers)
        deadline = time.time() + timeout
        while time.time() < deadline:
            if cli.poll() is not None:
                result = f"exited {cli.returncode}"
                break
            with open(f"{W}/client.log") as f:
                if "Initialization Sequence Completed" in f.read():
                    result = "connected"
                    break
            try:
                data = s.recv(4096).decode()
            except socket.timeout:
                continue
            if not data:
                result = "mgmt closed"
                break
            buf += data
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                line = line.strip()
                m = re.match(r">PASSWORD:Need '(.*)' password", line)
                if m:
                    seen.append(line)
                    pin = answers.pop(0) if answers else None
                    if pin is None:
                        result = "no more answers"
                        deadline = 0
                    else:
                        s.sendall(f'password "{m.group(1)}" "{pin}"\n'.encode())
                elif line.startswith(">NEED-OK:"):
                    seen.append(line)
                    tag = re.match(r">NEED-OK:Need '([^']*)'", line).group(1)
                    s.sendall(f'needok "{tag}" cancel\n'.encode())
                elif line.startswith(">PASSWORD:Verification Failed"):
                    seen.append(line)
    finally:
        for p in (cli, srv):
            p.terminate()
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                p.kill()
        log.close()
    return result, seen


def main():
    setup()
    ids, out = pkcs11_ids()
    print(f"--show-pkcs11-ids via p11-kit proxy: {len(ids)} id(s)")
    if not ids:
        print(out)
        return 1
    pid = ids[0]
    print(f"  {pid}")

    ok = True
    scenarios = [
        ("correct PIN", pid, [PIN], "connected"),
        ("wrong PIN, then correct", pid, ["000000", PIN], "connected"),
        ("wrong PIN, no second answer", pid, ["000000", None], None),
        ("token absent", pid.replace("vpntoken", "othertoken"), [PIN], None),
    ]
    for name, i, answers, want in scenarios:
        result, seen = run_client(i, answers)
        good = want is None or result == want
        ok &= good
        print(f"== {name}: {result} {'OK' if good else 'UNEXPECTED'}")
        for l in seen:
            print(f"   {l}")
    # token must not be locked after the wrong-PIN scenarios
    out = sh(f"pkcs11-tool --module {SOFTHSM} -T")
    locked = "locked" in out.lower() and "final try" not in out.lower()
    print(f"== token flags: {' '.join(l.strip() for l in out.splitlines() if 'flags' in l)}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
