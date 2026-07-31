# Evidence / design notes — r2t corrected package

## Corrected validation baseline

The first r2t ZIP contained r2r backend fixture files while its fixture manifest
listed the reconstructed r2s hashes. Its checksum gate correctly refused to
continue before cloning or modifying GitHub.

This package reconstructs and includes the actual r2s backend:

```text
backend/osys_n64_libdragon.cpp
0fa15967558b1ab423b0e05e5fe2686e7fbd46c48449def1ea5fd7d7291dfbef

backend/n64libdragon-fs.cpp
a5b171e75ea987e242a053c9390c88772b9a7d4c07c646d9b9d25a6f18173f34
```

The backend diagnostic patch is generated only after committing that exact r2s
baseline.

## ScummVM patch

The consolidated ScummVM patch touches exactly four files and does not touch
`resource.cpp`.

SHA-256:

```text
e1af9d2c0a4f8e6a0c745817ba931e214e53e5ebd7091118a831838c70fd35bf
```

## Backend allocator patch

The allocator patch transforms exact r2s into r2t.

SHA-256:

```text
b069c1335f521258d73b8d46dc40d15201a9d75ce7764017248535cad0ec35f2
```

It instruments normal object and array allocation, reports allocations of at
least 64 KiB plus every failed allocation, and reads libdragon heap statistics
at the allocation boundary.

Because the N64 backend is compiled with `-fno-exceptions`, the diagnostic
failure path does not use `throw`; it logs the failure and calls `abort()`.

## Validation policy

Both patches are independently tested with:

```text
git apply --check
git apply
git diff --check
```

The package also verifies the exact post-patch backend hashes, shell syntax,
internal checksums, staged-path policy, and ZIP integrity.

No fuzzy application, `--3way`, rebase, regex source mutation, or fallback
patching is used.
