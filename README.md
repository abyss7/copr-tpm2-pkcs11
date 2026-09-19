# NetworkManager-openvpn with PKCS#11 for Fedora

Fedora rebuilds of `NetworkManager-openvpn` and `plasma-nm` that let OpenVPN use a
certificate and key stored on a smart card or token: a YubiKey (PIV), or anything else
p11-kit can see. The PIN is asked in the regular KDE (or GNOME) password dialog.

Prebuilt packages for the current Fedora releases are in COPR:
[abyss/tpm2-pkcs11](https://copr.fedorainfracloud.org/coprs/abyss/tpm2-pkcs11/).

```sh
sudo dnf copr enable abyss/tpm2-pkcs11
sudo dnf upgrade --refresh
```

The COPR repository has priority 50 (Fedora's repositories have 99), so dnf keeps these
builds even when Fedora ships a newer release of the same packages, and no versionlock is
needed.

## Why

Upstream doesn't support PKCS#11 tokens yet. NetworkManager-openvpn has had five attempts
since 2019 and none was merged. plasma-nm doesn't support it at all. The details are in
[docs/upstream-status.md](docs/upstream-status.md).

The base is NetworkManager-openvpn
[MR !108](https://gitlab.gnome.org/GNOME/NetworkManager-openvpn/-/merge_requests/108),
the most active attempt, which Ubuntu 26.10 already ships. It doesn't work on Fedora as is,
so a few fixes go on top of it.

## Patches

**NetworkManager-openvpn**, [patches/NetworkManager-openvpn/](patches/NetworkManager-openvpn/):

* 0001–0015: MR !108 unchanged. It adds the `pkcs11` connection type and the
  `pkcs11-id` option, keeps the PIN in the `cert-pass` secret, passes `--tls-exit`,
  handles `.ovpn` import and export, and gives the GTK editor certificate discovery.
* 0016: always passes `--pkcs11-providers <p11-kit-proxy.so>`. Fedora's openvpn is built
  without p11-kit, so it loads no PKCS#11 module on its own and `--pkcs11-id` finds
  nothing. The path comes from `p11-kit-1.pc` at build time, not from the connection
  profile, so users can't point it at an arbitrary `.so`.
* 0017: sends a saved PIN only once. When openvpn asks again, the PIN was wrong: it is
  dropped and the user is asked, instead of burning the token's retry counter (a YubiKey
  PIV locks after 3 wrong PINs). If the token is not plugged in, the
  `NEED-OK token-insertion-request` is cancelled and the connection fails right away
  instead of hanging until the timeout.

**plasma-nm**, [patches/plasma-nm/](patches/plasma-nm/):

* The OpenVPN plugin gets a "Certificates on Smart Card (PKCS#11)" connection type with
  CA certificate, certificate and PIN fields. **Detect** runs
  `openvpn --show-pkcs11-ids` through the p11-kit proxy and lists the certificates on
  the plugged-in tokens by subject. By default the PIN is asked on every connect.
* The PIN is always masked in the connect dialog. Without this, plasma-nm shows it in
  clear text whenever the prompt mentions a "token".

## Building locally

```sh
scripts/rebuild                 # current Fedora release → out/fc<N>/
scripts/rebuild -r 44           # a specific release
scripts/install -n              # show what would be installed
scripts/install                 # install already installed subpackages, add versionlocks
```

`scripts/rebuild` downloads the latest SRPM of each package from the enabled repositories,
adds `patches/<package>/*.patch`, appends `.pkcs11.<N>` to the Release, and builds.
`<N>` is the number of commits that changed `patches/<package>`, so a change of the
patches always gives a newer package version. On Fedora
it builds natively and installs build dependencies with `sudo dnf builddep`. On other
distributions it downloads a Fedora root filesystem into `.cache/f<N>` and builds inside
it through user namespaces, without root.

All plasma-nm subpackages are rebuilt because they require the exact same version of each
other.

### Publishing to COPR

The [COPR workflow](.github/workflows/copr.yml) does this automatically, see
[Automation](#automation). By hand:

```sh
scripts/copr-publish            # SRPMs for Fedora 43 and 44 → builds in abyss/tpm2-pkcs11
scripts/copr-publish -w 44      # only Fedora 44, wait for the result
```

This needs `~/.config/copr` with an API token from
<https://copr.fedorainfracloud.org/api/>. Tokens expire after 180 days. If `copr-cli` is
not installed on the host, it runs inside the Fedora root filesystem.

## Connections made with the old local patch

An earlier local patch used `connection-type=tls-pkcs11`, `pkcs11-providers` and a
`pkcs11-pin` secret. The new plugin rejects these keys, so such connections fail to start.
Convert them with:

```sh
scripts/migrate-legacy-connection           # show what would change
scripts/migrate-legacy-connection --apply
```

The script can't see a PIN stored in KWallet, so it is asked again on the first connect.
If the old `pkcs11-id` isn't found (older pkcs11-helper versions used a different ID
format), open the connection in the KDE settings, press **Detect** and pick the
certificate.

The old patch is kept for reference in [docs/legacy/](docs/legacy/).

## pkcs11-provider

These packages don't use pkcs11-provider: they go through pkcs11-helper. In November 2024
pkcs11-provider 0.5-4 enabled itself in the system OpenSSL configuration and broke
wpa_supplicant ([rhbz#2326839](https://bugzilla.redhat.com/show_bug.cgi?id=2326839)), and
the usual workaround was to versionlock 0.5-3. Fedora 43 and 44 ship 1.x with the
auto-activation disabled, so that lock can go. Rawhide re-enabled the auto-activation on
2026-08-11.

## Updating to new Fedora packages

The usual case is a new Fedora release or update where the patches still apply:

```sh
scripts/rebuild && scripts/install      # or: scripts/copr-publish
```

If a patch doesn't apply, the build stops in `%prep` and shows the failing hunk. The
upstream clones in `src/` carry a `pkcs11` branch based on the tag in
`patches/<package>/BASE`. Rebase that branch and export the patches again:

```sh
cd src/NetworkManager-openvpn           # or src/plasma-nm
git fetch origin --tags
git rebase --onto <new tag> "$(cat ../../patches/NetworkManager-openvpn/BASE)" pkcs11
echo <new tag> > ../../patches/NetworkManager-openvpn/BASE
cd ../.. && scripts/export-patches && scripts/rebuild
```

The clones are not part of this repository. `scripts/setup-src` recreates them: it clones
upstream and builds the `pkcs11` branch from the `BASE` tag and the patches.

If MR !108 is updated (`git fetch origin refs/merge-requests/108/head:mr108`), replace its
commits in the `pkcs11` branch. Once it is merged upstream, patches 0001–0015 disappear
during the rebase.

Package-specific spec changes (autoreconf and extra BuildRequires for
NetworkManager-openvpn) are in `patches/<package>/spec.sh`.

## Tests

The tests run in a Fedora environment, for example
`scripts/enter.sh .cache/f43 <command>`, with this repository mounted at `/work`:

* `python3 /work/tests/softhsm-openvpn.py` runs the real openvpn against a SoftHSM token
  loaded through the p11-kit proxy and drives the management interface the way
  nm-openvpn-service does. It covers a correct PIN, a wrong PIN (openvpn asks again) and
  a missing token (`NEED-OK`), which is the behaviour patch 0017 relies on.
* `/work/tests/plasma-nm-openvpn-ui.sh` builds the plasma-nm OpenVPN plugin and runs a
  headless UI test: saving and loading a profile, **Detect** against a SoftHSM token, and
  PIN masking.
* `python3 tests/test_migrate.py` tests the connection migration logic.

The tests pass on Fedora 43 (openvpn 2.6.22) and Fedora 44 (openvpn 2.7.7). The patches
have not been tested with a physical YubiKey and a running NetworkManager yet.

## Automation

* [CI](.github/workflows/ci.yml) runs on every push and pull request. It builds the RPMs
  in Fedora 43 and 44 containers, runs all tests, and attaches the RPMs to the run as
  artifacts.
* [COPR](.github/workflows/copr.yml) runs daily, on pushes to `main` that change the
  patches, and on demand (with an option to rebuild everything). For every
  `fedora-*-x86_64` chroot enabled in the COPR project, `scripts/copr-outdated` compares
  the latest Fedora version of each package plus the release suffix with what COPR has,
  and only the outdated packages are rebuilt. To add a new Fedora release, enable its
  chroot in the COPR project settings.

The COPR workflow needs the repository secret `COPR_CONFIG` with the contents of
`~/.config/copr`. The token expires after 180 days: the workflow warns three weeks ahead
and fails once it has expired.

## Layout

```
patches/<package>/*.patch   generated by scripts/export-patches from the pkcs11 branch
patches/<package>/BASE      upstream tag the pkcs11 branch is based on
patches/<package>/spec.sh   spec file changes needed by the patches
scripts/                    rebuild, build-rpm.sh, install, copr-publish, copr-outdated, setup-src, ...
tests/                      see above
docs/                       upstream status, the old local patch
.github/workflows/          CI and COPR publishing
src/, .cache/, out/         upstream clones, build root filesystems, built packages (ignored)
```

## License

GPL-2.0-or-later, the license of both patched packages. See [LICENSE](LICENSE).
