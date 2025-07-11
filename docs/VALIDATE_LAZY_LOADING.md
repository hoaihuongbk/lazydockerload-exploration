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

## Troubleshooting: Missing Java Classes After Nydus Conversion (Spark Example)

If you see errors like:

```
Exception in thread "main" java.lang.NoClassDefFoundError: org/sparkproject/guava/util/concurrent/internal/InternalFutureFailureAccess
Caused by: java.lang.ClassNotFoundException: org.sparkproject.guava.util.concurrent.internal.InternalFutureFailureAccess
```

This usually means a required JAR/class is missing from the image. This can happen if the Nydus conversion process omits or corrupts files.

### Steps to Diagnose:
1. **Verify the standard image works** (before Nydus conversion).
2. **Compare the JAR files** in the standard and Nydus images:
   - List JARs: `ls /opt/spark/jars | grep guava`
   - Search for the missing class: `find /opt/spark/jars -name '*.jar' | xargs grep -l InternalFutureFailureAccess`
3. **If the JAR is missing only in the Nydus image**, the conversion is the culprit.
4. **Check for known issues** with the conversion tool and file types (see Nydus GitHub issues).

### Workarounds:
- Use the standard or eStargz image for Spark if Nydus conversion is problematic.
- Try a different conversion tool or version.

Documented for future investigation and resolution.

---

## References
- [stargz-snapshotter GitHub](https://github.com/containerd/stargz-snapshotter)
- [OCI Image Layout Spec](https://github.com/opencontainers/image-spec/blob/main/image-layout.md) 