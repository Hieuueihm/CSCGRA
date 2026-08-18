# Bare-metal software

Software is versioned alongside its matching RTL:

- `v2`: active applications and generated headers for RTL v2.
- Frozen v1 applications are under `archive/v1/sw` for provenance only.

SDK/Vitis projects, BSPs, exported hardware platforms, and compiled binaries
are generated artifacts and belong under `work/`.

Use v2 software only with the matching `rtl/v2` register map and generated
golden header. Current hardware status is documented in
`docs/PROJECT_STATUS.md`.
