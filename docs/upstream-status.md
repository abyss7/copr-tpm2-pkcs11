# OpenVPN + PKCS#11 (YubiKey PIV) in NetworkManager-openvpn / plasma-nm: upstream status

Status as of 2026-09-19. Everything was checked against the APIs of gitlab.gnome.org, invent.kde.org, bugs.kde.org,
bugzilla.redhat.com, bodhi, mdapi, src.fedoraproject.org, Koji build logs and the sources
(local clones in `src/`). Anything that could not be verified is stated explicitly.

---

## 0. Verdict (short version)

* **There is no ready-made upstream solution.** NetworkManager-openvpn (latest release 1.12.5, 2025-12-22;
  `main` has had only translations and a sysusers fix since then) has no PKCS#11 support. Since 2019 there
  have been five attempts (issue #29, MR !32, !67, !79, !108); none was merged. The most active one now is
  **MR !108** (opened 2026-04-29, last updated 2026-09-18). It is being reviewed not by the
  project maintainers but by Sergio Costas from Canonical; there are no approvals. **Ubuntu 26.10 already
  ships !108 as a distro patch** (`network-manager-openvpn 1.12.5-1ubuntu1`).
* **plasma-nm**: has no PKCS#11 support of its own for OpenVPN, neither in the Qt Widgets editor nor in the
  QML port (MR !645). bugs.kde.org has not a single OpenVPN-specific PKCS#11 request.
  **However, the plasma-nm secrets dialog is generic**: if NM-openvpn requests a secret with a hint
  (e.g. `cert-pass`), plasma-nm shows an input field for it. So PIN entry via the KDE UI works without
  patching plasma-nm, and the QML port !645 keeps this behavior.
* **OpenVPN**: `--cert/--key` as an OSSL_STORE URI (`pkcs11:...`) via `--providers` is available
  **only since 2.7.0** (commit 3512e8d3, 2024-09-06; 2.7.0 was released on 2026-02-10). 2.6.x
  has nothing like it. The pkcs11-helper path (`--pkcs11-id`/`--pkcs11-providers`) works in both 2.6
  and 2.7. Fedora builds openvpn with `--enable-pkcs11` (F43 = 2.6.22, F44+ = 2.7.7), **but without
  p11-kit** (configure: `checking for P11KIT... no`). Therefore on Fedora `--pkcs11-id` without an explicit
  `--pkcs11-providers` is **ignored**, and !108 as it stands will not work
  on Fedora.
* **pkcs11-provider versionlock 0.5-3.fc41**: almost certainly a leftover from November 2024.
  Build 0.5-4 added `/etc/pki/tls/openssl.d/pkcs11-provider.conf` with `activate = 1`, which
  broke wpa_supplicant (eduroam/PEAP-MSCHAPv2, MD4 from the legacy provider; rhbz#2326839), and the
  bug explicitly suggested downgrading to 0.5-3. The underlying OpenSSL bug (#26038) was fixed in December
  2024 (PR #26197, included in 3.5.x). Fedora 43 currently has **pkcs11-provider 1.0-4.fc43, with
  auto-activation commented out** (`##activate = 1`), so **the lock is no longer needed on F43**.
  The pkcs11-helper path does not use pkcs11-provider at all. Note: in
  rawhide/F46 auto-activation was re-enabled on 2026-08-11.
* **Minimal reliable path**:
  * **F43 (openvpn 2.6.22)**: pkcs11-helper only. A small NM-openvpn patch is needed:
    `--pkcs11-id` plus a fixed `--pkcs11-providers /usr/lib64/p11-kit-proxy.so`,
    handling `>PASSWORD:Need '… token' password` through the existing `cert-pass` secret,
    not resending the PIN (otherwise a wrong PIN will lock the YubiKey after 3
    attempts), and `access_file()` must leave `pkcs11:` values alone. The current local patch
    (essentially !67) is functionally adequate, but it adds unnecessary connection types and a separate secret,
    and the `.so` path is set in the profile, which is exactly why upstream rejected such MRs.
  * **F44+ (openvpn 2.7.7)**: the same pkcs11-helper patch keeps working. The pkcs11-provider path
    (`--providers pkcs11 default --cert pkcs11:… --key pkcs11:…`)
    is optional. It also requires an NM-openvpn patch: pass `--providers` and handle
    `'PKCS#11 token'`. The alternative (activating the provider globally in openssl.d) would again
    affect all OpenSSL applications, which is exactly what the lock was protecting against.

---

## 1. NetworkManager-openvpn (GNOME GitLab)

### 1.1 All relevant issues/MRs

| # | Type | State | Dates | Author | Summary |
|---|-----|-----------|------|-------|------|
| [#29](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/issues/29) | issue + patch | closed (by bot for inactivity, 2020-04-06) | 2019-05-07 | ghost | Text fields `pkcs11-id`/`pkcs11-providers`, import from .ovpn. Afterwards only "+1"s (2021–2022) |
| [#78](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/issues/78) | issue | **open** | 2021-11-02 | Anthony Rabbito | Request to reconsider !32. Only "+1"s and a link to !79 |
| [!32](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/32) | MR | **open** (auto-closed and reopened twice) | 2020-11-01, upd 2026-05-05 | Ignat Loskutov | `pkcs11-id` + `pkcs11-provider` passed through to openvpn; PIN detected by the `" token"` suffix; PIN is forgotten after sending |
| [!67](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/67) | MR | **open**, abandoned | 2023-04-07, upd 2024-08-06 | Anton K (tracefinder) | Types `tls-pkcs11` / `password-tls-pkcs11`, providers/id/pin fields, `pkcs11-pin` secret. **The local patch is essentially !67** |
| [!79](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/79) | MR (Draft) | **open** | 2024-06-28, upd 2026-05-06 | Florian Apolloner | Minimal approach: `key` = `pkcs11:` URI (selected via NMACertChooser from libnma/GCR), the service passes `--pkcs11-id <uri>` and a **hardcoded** `--pkcs11-providers /usr/lib64/p11-kit-proxy.so`; `" token"` is handled as "Private Key" (`cert-pass`) |
| [!81](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/81) | MR | **open** | 2024-08-06, upd 2024-08-08 | Timofey Mischenko | Not PKCS#11: TSS2 keys via `--providers tpm2 default`. No review |
| [!108](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/108) | MR | **open**, can_be_merged, 0 approvals | 2026-04-29, upd **2026-09-18** | Piotr Filiciak (lenz1111) | New `pkcs11` type, `pkcs11-id` key, `--pkcs11-id` + `--tls-exit`, PIN via `cert-pass`, drop-down lists in the GTK editor via p11-kit + pkcs11-helper, import/export of `pkcs11-id` |
| [#165](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/issues/165), [#98](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/issues/98) | issue | open | 2026 / 2022 | — | Matched on "PKCS"/"token", but they are about 2FA (static challenge). Unrelated to smart cards |

Other: Red Hat Bugzilla has no PKCS#11 requests against the NetworkManager-openvpn component
(the closest, #581992 about pkcs#8, was closed as WONTFIX in 2010).

### 1.2 What the maintainers said and why everything is stalled

* **Beniamino Galvani** (bgalvani, !32, 2021-02-10): "none of the developers is familiar with
  pkcs11 … wouldn't even know how to test it"; "it doesn't seem acceptable to pass a shared
  library as connection property, because it can be used by normal users to run arbitrary code
  as root".
* **Thomas Haller** (!32, 2021-02-11): even with `--user nm-openvpn` this is unsafe on a
  multi-user machine; mentions Lubomir Rintel's unfinished work on p11-kit
  remoting (branch `lr/p11-forward`).
* **bgalvani** (!67, 2023-07-10): this is privilege escalation; the way out is to "restrict the
  plugin path to a specific directory owned by root". Asked for the commits to be cleaned up and
  documentation to be written. On 2024-06-28 (!67/!79) pinged lkundrak. The maintainers have not
  responded in these MRs since.
* **!108**: the entire review (113 notes) was done by Sergio Costas (63 comments; according to the Ubuntu
  changelog he is from Canonical) and Alessandro Astone (5). The doap file lists as maintainers Galvani,
  Huguet, Ján Václav, Stanislas Faye, Gris Ge, Vladimir Benes. **None of them has commented
  in !108.** Key decision on 2026-05-22: do not store the library path (Timofey Mischenko:
  "Arbitrary shared library loading is a show stopper. Most previous attempts were
  unsuccessful because of it"), and instead rely on openvpn loading `p11-kit-proxy.so` itself.
  Currently !108 ignores `pkcs11-providers`.
* The general reason for the stall: the Red Hat NM team maintainers have no interest and no hardware for
  testing, plus the security issue of an arbitrary `.so`. Nothing but translations has been merged into `main`
  since January 2026, while 20+ MRs are open.

### 1.3 Does 1.12.5/main pass a `pkcs11:` URI through in `cert`/`key`?

Based on the code in `src/nm-openvpn-service.c` (1.12.5 = `main` in this area):

* `args_add_vpn_certs()` calls `access_file()` for `cert` and `key`.
  * **System connection** (`connection.permissions` empty): it returns `g_strdup(value)`,
    `is_pkcs12("pkcs11:…")` yields FALSE, and then `--cert pkcs11:… --key pkcs11:…` are passed to
    openvpn **unchanged**.
  * **Private connection** (`permissions=user:…`; in plasma-nm this is the unchecked "All users
    may connect to this network" box): `nm_utils_copy_cert_as_user()` tries to read
    `pkcs11:…` as a file on behalf of the user, and **startup fails**. This also involves the file
    permission check (CVE-2025-9615, 1.12.4).
* `check_need_secrets()`: `is_encrypted("pkcs11:…")` returns FALSE, i.e. the PIN is not requested
  up front.
* The options `providers`, `pkcs11-id`, `pkcs11-providers` **do not exist at all**. An unknown vpn.data
  key will fail validation.
* `handle_auth()` only knows `Auth`, `Private Key`, `HTTP Proxy`. On
  `>PASSWORD:Need 'PKCS#11 token' password` and `>PASSWORD:Need '<label> token' password` it
  logs "Unhandled management socket request" and terminates the connection with
  `NM_VPN_PLUGIN_FAILURE_CONNECT_FAILED`. `>NEED-OK:Need 'token-insertion-request' …` is not
  handled at all.

Bottom line: on openvpn 2.6 URIs are meaningless, since 2.6 treats them as file names. On 2.7
the URI reaches openvpn, but (a) NM cannot pass `--providers`, so the provider would have to
be activated globally in openssl.cnf, and (b) the PIN request is not handled. The only way around (b) without
a UI is `pin-source=` in the URI or `pkcs11-module-token-pin` in the provider config.

### 1.4 MR !108 details (current head `32043c8f`, base `7fb52f40`)

* `shared/nm-service-defines.h`: `NM_OPENVPN_KEY_PKCS11_ID "pkcs11-id"`,
  `NM_OPENVPN_CONTYPE_PKCS11 "pkcs11"`.
* service: when `pkcs11-id` is set, it passes only `--pkcs11-id <id>`, without `--cert/--key`; for the
  `pkcs11` type it adds `--client` and `--tls-exit`. In `handle_auth` the condition is
  `nm_streq(auth,"Private Key") || g_str_has_suffix(auth," token")`; the PIN is taken from
  `cert-pass`, and if it is missing, the `cert-pass` hint is requested with the message "Password.".
  `need_secrets` for `pkcs11` relies on `cert-pass` and its flags.
* The build now **requires** `libpkcs11-helper-1 >= 1.29` and `p11-kit-1 >= 0.25`. The GTK editor
  needs them for the module and certificate lists.
* **This will not work on Fedora as is**: Fedora's openvpn is built without p11-kit (see §3.4),
  and without `--pkcs11-providers` it logs "Option pkcs11-id is ignored as no pkcs11-providers are
  specified". It needs either an openvpn rebuild with `BuildRequires: p11-kit-devel`, or an
  NM-openvpn patch with a fixed root-owned path to `p11-kit-proxy.so`.
* The PIN is resent from `io_data->priv_key_pass` on every request. `--tls-exit` prevents looping
  at the TLS level, but pkcs11-helper makes up to 3 attempts within a single login
  (`_PKCS11H_DEFAULT_MAX_LOGIN_RETRY 3`), and YubiKey PIV allows 3 PIN attempts by default.
  Therefore **a stored wrong PIN can lock the PIV**. (Inferred from the code, not tested on
  hardware.)
* Ubuntu: `network-manager-openvpn (1.12.5-1ubuntu1) stonking` dated 2026-07-14, by
  Sergio Costas Rodriguez, with the note "Added support for PKCS#11 tokens. Extracted from …/merge_requests/108".
  Ubuntu's openvpn is most likely built with p11-kit, so the scheme works there (not verified
  for Ubuntu).

---

## 2. plasma-nm (KDE)

* **Sources** (`vpn/openvpn/*` in master 6.7.90+): no mentions of pkcs11/providers/pkcs11-id.
  The editor knows four types: `tls`, `static-key`, `password`, `password-tls`.
  The editor does not recognize an unknown type (`pkcs11` from !108, `tls-pkcs11` from the local patch), and
  **saving from the KDE editor will overwrite the type and fields**. Such connections should be edited via
  `nmcli` or the keyfile. The cert/key fields go through `QUrl::fromLocalFile()` and `toLocalFile()`.
  Whether a `pkcs11:…;id=%01` string survives this round-trip unchanged has not been checked.
* **Secrets dialog** (`openvpnauth.cpp`, kded): if NM sent hints, a field named after the secret is
  created for **any** hint. The label is taken from `x-vpn-message:` (the plugin
  message), otherwise "Key Password:" for `cert-pass`. So with a `cert-pass` hint (as in !79/!108)
  or `pkcs11-pin` (as in the local patch) the PIN is requested by the standard KDE UI. Caveat: if the
  message text contains "token", "code", "OTP", etc. (via i18n), plasma-nm **shows the field
  unmasked** (an OTP heuristic). Do not use the word "token" in the PIN message.
* **MRs**:
  * [!645](https://invent.kde.org/plasma/plasma-nm/-/merge_requests/645) "Port the OpenVPN
    editor to QML" (xbito, GSoC, open, 2026-09-06, upd 2026-09-16). No PKCS#11, the same four
    types. `OpenvpnAuthSetting::readHints()` keeps the generic hint handling (the secret
    goes into `m_challengeSecretKey`), so the PIN prompt will keep working.
  * [!662](https://invent.kde.org/plasma/plasma-nm/-/merge_requests/662) and
    [!665](https://invent.kde.org/plasma/plasma-nm/-/merge_requests/665) (open, 2026-09-15/16)
    move the kded secrets prompt to QML. They do not touch PKCS#11.
  * [!368](https://invent.kde.org/plasma/plasma-nm/-/merge_requests/368) (merged 2024-08-16):
    in 802.1x, do not percent-decode non-`file` schemes (relevant for `pkcs11:` in Wi-Fi/802.1x,
    unrelated to OpenVPN).
* **bugs.kde.org** (plasma-nm bugs now live under the plasmashell product, component
  "Networking in general"): nothing for OpenVPN+PKCS#11. There are only
  [384652](https://bugs.kde.org/show_bug.cgi?id=384652) "[Openconnect] pkcs11: add support for
  separate pin value" (CONFIRMED) and [514263](https://bugs.kde.org/show_bug.cgi?id=514263)
  "[Openconnect] … should support PKCS11 usercerts" (CONFIRMED, 2026-01-07). Both are about OpenConnect.
* For comparison: GNOME/libnma can select `pkcs11:` objects (`NMACertChooser` +
  `nma-pkcs11-cert-chooser-dialog`, built with `-Dgcr=true`, enabled in Fedora). This is what
  !79 relies on. KDE has no equivalent.

---

## 3. OpenVPN

### 3.1 URIs for `--cert/--key` via an OpenSSL provider

* Commit **3512e8d3** "Interpret --key and --cert option argument as URI" (Selva Nair,
  2024-09-06, PR #591). Related: 67124dcf (initializing `user_pass` in `ui_reader`) and
  e9ad1b31 (do not abort reading on an `OSSL_STORE_load` error). **First released in 2.7.0**
  (tagged 2026-02-10). In v2.6.22 `ssl_openssl.c` does not use `OSSL_STORE_open`, and
  `man tls-options` there has no "file|uri".
* Syntax (from the commit and the 2.7 man page):
  ```
  --providers pkcs11 default
  --cert "pkcs11:token=…;object=…;type=cert"
  --key  "pkcs11:token=…;id=%01;type=private"
  ```
  `--providers` has existed since 2.6.0, but in 2.6 it is only useful for legacy/tpm2 with files. Providers
  are loaded into the default libctx, after which **all active providers of the default context**
  (including those activated via openssl.cnf) are copied into `tls_libctx`
  (`OSSL_PROVIDER_do_all(NULL, provider_load, tls_libctx)`). So either
  `--providers` or global activation works. `default` must be listed explicitly: once any provider
  is loaded explicitly, default is not loaded automatically.
* "cert as a file, key via URI" is possible (confirmed by Selva Nair in openvpn#958).

### 3.2 How the PIN is requested (management strings)

The format is defined in `manage.c`: `">%s:Need '%s' %s"`.

| Path | Where in the code | Management string |
|------|-----------|-------------------|
| pkcs11-helper (`--pkcs11-id`) | `pkcs11.c` `_pkcs11_openvpn_pin_prompt`: `"%s token"`, `GET_USER_PASS_PASSWORD_ONLY`, nocache | `>PASSWORD:Need '<token label> token' password` (for YubiKey/OpenSC usually `'PIV Card Holder pin (PIV_II) token'`). Reply: `password "<same type>" "<PIN>"` |
| pkcs11-helper, token not inserted | `_pkcs11_openvpn_token_prompt`, `GET_USER_PASS_NEED_OK` | `>NEED-OK:Need 'token-insertion-request' confirmation MSG:Please insert <label> token` |
| provider (2.7, OSSL_STORE) | `ssl_openssl.c` `ui_reader()`: if the prompt contains "PKCS#11", it calls `get_user_pass(…, "PKCS#11 token", MANAGEMENT\|PASSWORD_ONLY)`. pkcs11-provider builds the prompt as `UI_construct_prompt(ui,"PIN", "PKCS#11 Token (Slot N - …)")` | `>PASSWORD:Need 'PKCS#11 token' password` |
| provider, if the prompt lacks "PKCS#11" | pem password callback | `>PASSWORD:Need 'Private Key' password` |

The `" token"` suffix is common to both PKCS#11 cases, so the check
`g_str_has_suffix(auth, " token")` (!32/!79/!108/the local patch) is sufficient for 2.6 and 2.7.
pkcs11-provider also has UI-less alternatives: `pin-source=file:/…` or `env:` in the URI,
`pkcs11-module-token-pin` in the config, and the `pkcs11-module-cache-pins` cache.

Side note: openvpn#993 (2.7.0, "private key password verification failed" with a PEM password
of ≥64 characters; closed 2026-03-06) concerns only the PEM password, not the PKCS#11 path.

### 3.3 Other known issues

* rhbz#2177834 (F38, openvpn 2.6.0 + YubiKey ECDSA via pkcs11-helper, "bad signature"):
  fixed in openvpn-2.6.1-2.fc38. It also contains an example of a working `pkcs11-id` in RFC 7512 URI format
  (`pkcs11:model=PKCS%2315%20emulated;…;id=%01`) together with `pkcs11-providers
  /usr/lib64/pkcs11/opensc-pkcs11.so`.
* Open on GitHub: #1031 (PIN prompt during `pkcs11-id-count` via management), #656/#851
  (YubiKey + ykcs11, EC keys). Advice from #851: use OpenSC, not ykcs11.

### 3.4 Fedora: versions and build options

| Branch | openvpn | `--enable-pkcs11` | p11-kit in configure | OpenSSL |
|-------|---------|-------------------|---------------------|---------|
| f41 | 2.6.14 | yes | — | — |
| f42 | 2.6.20 | yes | — | — |
| **f43** | **2.6.22-1.fc43** | yes (`[PKCS11]` in the banner) | **no** (`checking for P11KIT... no`) | 3.5.7 at build time; 3.5.8 in updates |
| **f44** | **2.7.7-1.fc44** | yes | **no** (`checking for p11-kit-1... no`) | 3.5.8 |
| f45 / rawhide | 2.7.7 | yes | — (spec without `p11-kit-devel`) | — |

The spec has `%bcond_without pkcs11` (disabled only for RHEL 9), `BuildRequires:
pkcs11-helper-devel >= 1.11`, and **no `p11-kit-devel` in BuildRequires**. Therefore on Fedora
`DEFAULT_PKCS11_MODULE` is not defined, and `--pkcs11-id` requires an explicit `--pkcs11-providers`
(man: "If default loading is not enabled in the build and no providers are specified, the former
options will be ignored"). It is worth filing a Fedora bug asking to add `BuildRequires:
p11-kit-devel`.

Other versions: pkcs11-helper 1.30.0 (f43/f44), opensc 0.27.1, NetworkManager-openvpn
1.12.5-2.fc43 / 1.12.5-4.fc44 / 1.12.5-5 rawhide (the only patch is upstream !104 about
sysusers), plasma-nm 6.7.5-1.fc43.

---

## 4. pkcs11-provider: why a lock on 0.5-3.fc41 may have been needed

Fedora timeline (dist-git `rpms/pkcs11-provider` and Bodhi):

| Date | Event |
|------|---------|
| 2024-06-05 | 0.5-2 (F41) |
| 2024-07-19/23 | **0.5-3.fc41**, mass rebuild, **no config in openssl.d yet** |
| 2024-08-06 | **0.5-4**: Simo Sorce "Add automatic configuration on install", `/etc/pki/tls/openssl.d/pkcs11-provider.conf` with `activate = 1` (`%config(noreplace)`) |
| 2024-11-17 | [rhbz#2326839](https://bugzilla.redhat.com/show_bug.cgi?id=2326839) (wpa_supplicant, F41): after 0.5-4, eduroam/PEAP-MSCHAPv2 and 802.1x over Ethernet fail to connect, error `EVP_DigestInit_ex failed` (MD4). Workarounds in the comments: remove the package or the config, `pkcs11-module-load-behavior = early`, **"Just downgrading to pkcs11-provider-0.5-3.fc41 also solves the problem"** (comment #9). Closed as EOL |
| 2024-11-22 | 0.6-2: "Temporarily disable loading by default … until we can resolve openssl/openssl#26038 … unbreaks wpa_supplicant" (config commented out with `##`) |
| 2024-12-20 | [openssl#26038](https://github.com/openssl/openssl/issues/26038) "Broken providers no_cache support" closed, fix [PR #26197](https://github.com/openssl/openssl/pull/26197) in master (3.5) and 3.2+, backports to 3.0/3.1 in #26231/#26232 |
| 2025-02-11 | 1.0-1 (F42/F43), auto-activation still disabled |
| 2025-09-16 | 1.1-1 (F44) |
| 2026-02-19 | 1.2.0-1 (F45/rawhide) |
| **2026-08-11** | 1.2.0-4 (rawhide = F46): Jakub Jelen "Revert "Temporarily disable loading by default" … issues … should be resolved". **Auto-activation re-enabled** |

State per branch: f41–f45 `##activate = 1` (disabled), rawhide/F46 `activate = 1`.
**Fedora 43 currently: pkcs11-provider-1.0-4.fc43, no updates in f43-updates.** It also has OpenSSL
3.5.8 with the #26038 fix.

Conclusions:

* The 0.5-3.fc41 lock is almost certainly a workaround for rhbz#2326839 (or simply the last version
  "without auto-config"). On F43 the problem no longer applies: the provider is not activated and OpenSSL
  is fixed. **The lock can be removed**, and if PKCS#11-via-provider is not needed, the package can
  be removed too (it is pulled in as a weak dependency).
* A possible second reason (hypothesis, unconfirmed): with the provider activated globally, every
  process using OpenSSL, including openvpn and wpa_supplicant, initializes
  p11-kit-proxy and OpenSC on the YubiKey itself. This may interfere with pkcs11-helper inside openvpn (two
  concurrent PKCS#11 sessions to the PIV).
* After moving to **F46**, auto-activation will return. If it causes problems, comment out
  `activate` in `/etc/pki/tls/openssl.d/pkcs11-provider.conf` (the file is `%config(noreplace)`, so
  the edit is preserved) instead of versionlocking an old fc41 build.
* Upstream pkcs11-provider now lives at `github.com/openssl-projects/pkcs11-provider`
  (the Fedora spec still points to latchset).

---

## 5. Final recommendations

### Does anything work "out of the box"?

No. Neither Fedora nor upstream NM-openvpn and plasma-nm offer anything for PKCS#11. All the necessary
building blocks exist: openvpn with pkcs11-helper in Fedora, p11-kit-proxy + OpenSC for
YubiKey PIV, the generic secrets prompt in plasma-nm. Only the glue in
NM-openvpn is missing, and it will have to be maintained locally until !108 (or an equivalent) is accepted. Even if
!108 is merged as it stands, it will only work on Fedora after openvpn is rebuilt with
p11-kit.

### Minimal reliable option for F43 (openvpn 2.6.22) — pkcs11-helper

A patch to NM-openvpn 1.12.5 (≈50 lines, no UI changes and no new connection types):

1. A `pkcs11-id` key in `valid_properties`, as in !108. The !79-style alternative: the trigger is a
   `key` starting with `pkcs11:`.
2. In `args_add_vpn_certs()`: if pkcs11-id is set (or `key` = `pkcs11:`), **do not call** `access_file()`
   for cert/key; instead pass `--pkcs11-providers /usr/lib64/p11-kit-proxy.so
   --pkcs11-id <id>`. The path is fixed and root-owned, which addresses bgalvani's security
   objection: modules are defined by the administrator in `/usr/share/p11-kit/modules/`, and OpenSC
   (`opensc.module`) is already there.
3. `handle_auth()`: `" token"` is handled as `Private Key` with the `cert-pass` secret.
   **Clear the PIN after sending it** (`priv_key_pass = NULL`) so that a repeated request goes to the UI
   instead of burning PIV attempts.
4. Nice to have: `--tls-exit` (as in !108) and handling of `>NEED-OK:Need 'token-insertion-request'`
   (a clear error instead of hanging until timeout).
5. Profile: `connection-type=tls`, `ca=<file>`, `pkcs11-id=<serialized id or pkcs11: URI>`,
   `cert-pass-flags=2` (not saved, ask every time), empty `connection.permissions`.
   Edit only via `nmcli` or the keyfile: the KDE editor will not preserve the type and fields.
6. The PIN will be requested by the plasma-nm kded via the `cert-pass` hint. The message text must not contain "token",
   otherwise the field will be shown in clear text.

The current local patch (≈ !67) works, but it stores the `.so` path in the profile (upstream will not accept this),
introduces 2 new types and a separate `pkcs11-pin` secret, and also resends the stored PIN.
For long-term maintenance it is better to switch to the scheme above: it is close to !79/!108 and easier
to rebase. pkcs11-provider is not needed for this path, so the lock can be removed.

### F44+ (openvpn 2.7.7)

* The same pkcs11-helper patch works unchanged (2.7 still has `[PKCS11]`). This is the
  lowest-risk option.
* The pkcs11-provider option (without pkcs11-helper): `connection-type=tls`,
  `cert=pkcs11:…;type=cert`, `key=pkcs11:…;type=private`. Requires an NM-openvpn patch: let
  `pkcs11:` bypass `access_file()`, add `--providers pkcs11 default` when key is `pkcs11:`
  (the idea from !81), and handle `'PKCS#11 token'` (the same `" token"` handler). Enabling the provider
  globally in openssl.d is not recommended: that is exactly the rhbz#2326839 scenario.
* To avoid NM-openvpn patches entirely: on 2.7 it can be made to work without a UI PIN prompt.
  The provider is activated in openssl.d, and the PIN comes from `pin-source=file:` (a root-only file)
  or `pkcs11-module-token-pin`. This contradicts the "PIN from the UI" requirement, so it is only a
  temporary workaround.

---

## Links

NetworkManager-openvpn
- https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/issues/29
- https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/issues/78
- https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/32
- https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/67
- https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/79
- https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/81
- https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/108
- https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/104 (patch in Fedora, sysusers)
- NEWS 1.10.x–1.12.5: `src/NetworkManager-openvpn/NEWS` says nothing about PKCS#11
- Ubuntu: https://launchpad.net/ubuntu/+source/network-manager-openvpn/1.12.5-1ubuntu1

plasma-nm / KDE
- https://invent.kde.org/plasma/plasma-nm/-/merge_requests/645
- https://invent.kde.org/plasma/plasma-nm/-/merge_requests/662
- https://invent.kde.org/plasma/plasma-nm/-/merge_requests/665
- https://invent.kde.org/plasma/plasma-nm/-/merge_requests/368
- https://bugs.kde.org/show_bug.cgi?id=384652
- https://bugs.kde.org/show_bug.cgi?id=514263

OpenVPN
- https://github.com/OpenVPN/openvpn/commit/3512e8d3ada4fa7d04925a89fd9f3669655c7887
- https://github.com/OpenVPN/openvpn/pull/591
- https://github.com/OpenVPN/openvpn/issues/958
- https://github.com/OpenVPN/openvpn/issues/993
- https://github.com/OpenVPN/openvpn/issues/1031
- https://github.com/OpenVPN/openvpn/issues/851
- man: `doc/man-sections/tls-options.rst` (`--cert/--key file|uri`), `generic-options.rst` (`--providers`), `pkcs11-options.rst`
- Code: `src/openvpn/ssl_openssl.c` (`ui_reader`, `OSSL_STORE_open_ex`), `src/openvpn/pkcs11.c`, `src/openvpn/manage.c`, `src/openvpn/options.c` (`DEFAULT_PKCS11_MODULE`)

Fedora
- https://src.fedoraproject.org/rpms/openvpn (spec f43: 2.6.22, f44: 2.7.7)
- https://kojipkgs.fedoraproject.org/packages/openvpn/2.6.22/1.fc43/data/logs/x86_64/build.log
- https://kojipkgs.fedoraproject.org/packages/openvpn/2.7.7/1.fc44/data/logs/x86_64/build.log
- https://src.fedoraproject.org/rpms/pkcs11-provider (commits e1965f5, 7e719e7, ac0f694)
- https://bodhi.fedoraproject.org/updates/?packages=pkcs11-provider
- https://bugzilla.redhat.com/show_bug.cgi?id=2326839
- https://bugzilla.redhat.com/show_bug.cgi?id=2177834

OpenSSL / pkcs11-provider
- https://github.com/openssl/openssl/issues/26038
- https://github.com/openssl/openssl/pull/26197
- https://github.com/openssl-projects/pkcs11-provider (docs/provider-pkcs11.7.md: `pkcs11-module-token-pin`, `pin-source`, `pkcs11-module-load-behavior`)
- pkcs11-helper: `lib/_pkcs11h-core.h` (`_PKCS11H_DEFAULT_MAX_LOGIN_RETRY 3`)
