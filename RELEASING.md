# Releasing SPS

`VERSION` is the source release number. A release tag is that number prefixed
with `v`; version `1.0.1` therefore uses tag `v1.0.1`.

Prepare the release on `main`, update `VERSION`, and commit all intended source
and documentation changes. Then create an annotated tag and run the release
gate:

```sh
version=$(sed -n '1p' VERSION)
make check
git tag -a "v$version" -m "SPS $version"
make release-check
```

`release-check` requires a clean work tree and the matching tag at `HEAD`. It
creates `dist/sps-$version.tar.gz` from the committed Git tree, checks its
layout, and builds it a second time to verify deterministic output. The archive
uses `gzip -n`, so gzip does not record a timestamp or source filename.

Inspect the tag and archive before publishing:

```sh
git show "v$version"
tar -tzf "dist/sps-$version.tar.gz"
(
    cd dist
    sha256sum "sps-$version.tar.gz" > "sps-$version.tar.gz.sha256"
    sha256sum -c "sps-$version.tar.gz.sha256"
)
```

Push the commit and tag without rewriting published history, then create the
GitHub release with the deterministic archive as an explicit asset:

```sh
gh auth status
git push origin main
git push origin "v$version"
gh release create "v$version" \
    "dist/sps-$version.tar.gz" \
    "dist/sps-$version.tar.gz.sha256" \
    --verify-tag --title "SPS $version" --generate-notes
```

Package recipes should use the uploaded `sps-$version.tar.gz` asset and its
verified checksum, not a branch archive. Creating or publishing a release is a
maintainer action; none of the Make targets contact GitHub.
