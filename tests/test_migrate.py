#!/usr/bin/python3
"""Unit test for scripts/migrate-legacy-connection (no NetworkManager needed)."""
import importlib.machinery
import importlib.util
import os

path = os.path.join(os.path.dirname(__file__), "..", "scripts", "migrate-legacy-connection")
loader = importlib.machinery.SourceFileLoader("migrate", path)
spec = importlib.util.spec_from_loader("migrate", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)

legacy = {"connection-type": "tls-pkcs11", "remote": "vpn.example.com", "ca": "/etc/ca.pem",
          "pkcs11-id": "pkcs11:token=PIV;id=%01", "pkcs11-providers": "/usr/lib64/opensc-pkcs11.so",
          "pkcs11-pin-flags": "2"}
data, secrets, notes = m.migrate(legacy, {"pkcs11-pin": "123456"})
assert data == {"connection-type": "pkcs11", "remote": "vpn.example.com", "ca": "/etc/ca.pem",
                "pkcs11-id": "pkcs11:token=PIV;id=%01", "cert-pass-flags": "2"}, data
assert secrets == {"cert-pass": "123456"}, secrets

data, secrets, notes = m.migrate({**legacy, "connection-type": "password-tls-pkcs11", "username": "u",
                                  "password-flags": "1"}, {"password": "p"})
assert data["connection-type"] == "pkcs11" and "username" not in data and "password-flags" not in data
assert secrets == {}
assert any("username" in n for n in notes)

# already migrated or unrelated connections are left alone
assert m.migrate({"connection-type": "pkcs11", "pkcs11-id": "x"}, {"cert-pass": "1"}) is None
assert m.migrate({"connection-type": "tls", "cert": "/c", "key": "/k"}, {}) is None
print("test_migrate: OK")
