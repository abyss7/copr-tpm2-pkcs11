import sys, json, urllib.request, tarfile, os, io
ver, dest = sys.argv[1], sys.argv[2]
repo = "fedora/fedora"
def get(url, tok, accept=None):
    h = {"Authorization": "Bearer " + tok}
    if accept: h["Accept"] = accept
    return urllib.request.urlopen(urllib.request.Request(url, headers=h))
tok = json.load(urllib.request.urlopen(f"https://quay.io/v2/auth?service=quay.io&scope=repository:{repo}:pull"))["token"]
idx = json.load(get(f"https://quay.io/v2/{repo}/manifests/{ver}", tok, "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json"))
dg = [m["digest"] for m in idx["manifests"] if m["platform"]["architecture"] == "amd64"][0]
man = json.load(get(f"https://quay.io/v2/{repo}/manifests/{dg}", tok, "application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"))
os.makedirs(dest, exist_ok=True)
for l in man["layers"]:
    data = get(f"https://quay.io/v2/{repo}/blobs/{l['digest']}", tok).read()
    with tarfile.open(fileobj=io.BytesIO(data)) as t:
        t.extractall(dest, members=[m for m in t.getmembers() if not m.isdev()])
print("ok", dest)
