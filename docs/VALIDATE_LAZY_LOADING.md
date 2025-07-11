# Validating Lazy Loading (eStargz) Image Support

This guide explains how to inspect a container image to verify it supports lazy loading via eStargz (stargz-snapshotter).

---

## 1. Save the Image in OCI Format

```sh
nerdctl save --format oci -o <image-name>-oci.tar <image-name>
```

---

## 2. Extract the OCI Tarball

```sh
mkdir -p oci-inspect
tar -xf <image-name>-oci.tar -C oci-inspect
cd oci-inspect
```

---

## 3. Find the Manifest Digest

```sh
cat index.json | jq .
```
- Note the `digest` field in the `manifests` array (e.g., `sha256:...`).

---

## 4. Inspect the Manifest Blob

```sh
cat blobs/sha256/<manifest-digest> | jq .
```
- Look for the `layers` array.
- Each layer should have an `annotations` field with keys like:
  - `"containerd.io/snapshot/stargz/toc.digest"`
  - `"io.containers.estargz.uncompressed-size"`

### Example:

```json
"layers": [
  {
    "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
    "digest": "sha256:...",
    "annotations": {
      "containerd.io/snapshot/stargz/toc.digest": "sha256:...",
      "io.containers.estargz.uncompressed-size": "..."
    }
  }
]
```

---

## 5. Confirm Lazy Loading Support

- If the above annotations are present on each layer, the image supports eStargz lazy loading.

---

## Troubleshooting

- If you do not see the annotations, the image was not properly converted to eStargz.
- Re-run your conversion tool (e.g., `nerdctl image convert --estargz ...` or `ctr-remote image optimize ...`).

---

## References
- [stargz-snapshotter GitHub](https://github.com/containerd/stargz-snapshotter)
- [OCI Image Layout Spec](https://github.com/opencontainers/image-spec/blob/main/image-layout.md) 