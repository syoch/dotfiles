---
name: emscripten-vendored-c
description: Use when cross-compiling a Rust crate with vendored C (cc crate, e.g. mlua/Lua, curl) to wasm32-unknown-emscripten and wasm-ld fails with __cxa_find_matching_catch_3 undefined, relocation, or SLEB errors. Trigger keywords: wasm32-unknown-emscripten, wasm-ld error, __cxa_find_matching_catch_3, fwasm-exceptions, TARGET_CFLAGS, vendored C, emcc, MAIN_MODULE, cargo fingerprint stale rebuild.
---

# Rust crate + vendored C to wasm32-unknown-emscripten (wasm exception mode fix)

## When to use
Native `cargo build` succeeds, but `cargo build --target wasm32-unknown-emscripten --release` fails at link time with `wasm-ld: error` (undefined symbol `__cxa_find_matching_catch_3`, or relocation/SLEB errors) that trace back to objects compiled by the `cc` crate (vendored C like mlua's bundled Lua, curl, etc.).

## Root cause
rustc's wasm32-emscripten backend compiles Rust with wasm exception handling. The C/C++ sources compiled by emcc/`cc` must use the SAME exception mode. If the C side is not compiled with `-fwasm-exceptions`, the C++ unwinding symbols (`__cxa_find_matching_catch_3`, `__cxa_throw`) are never defined, so wasm-ld fails. `-fPIC` must be REMOVED when linking a MAIN_MODULE (it is only for SIDE_MODULE).

## Procedure
1. Confirm the failing symbol: `cargo build --target wasm32-unknown-emscripten --release 2>&1 | grep -B2 -A6 "wasm-ld: error"`; check `echo "=== exit ${PIPESTATUS[0]} ==="` (grep swallows cargo's exit code).
2. Set the flags in build.sh (do not hardcode in env):
```
export TARGET_CFLAGS="-fwasm-exceptions"
export TARGET_CXXFLAGS="-fwasm-exceptions"
```
3. CRITICAL: cargo does NOT rebuild vendored C after a CFLAGS change — it only tracks the crate fingerprint, not env/CFLAGS. Delete the vendored crate's build artifacts and fingerprints so it truly recompiles:
```
rm -rf target/<triple>/release/build/mlua-sys-* \
       target/<triple>/release/deps/libmlua_sys-* \
       target/<triple>/release/deps/libmlua-* \
       target/<triple>/release/.fingerprint/mlua-sys-* \
       target/<triple>/release/.fingerprint/mlua-*
```
(adjust the crate name, e.g. `curl-sys`).
4. Rebuild and check the link error is gone.
5. Verify at runtime: copy a test script into the wasm output dir (e.g. `pkg/`) and run `node test.mjs`; confirm embedded C (Lua etc.) executes without undefined-symbol traps.

## Pitfalls
- Skipping the `rm -rf` step: stale non-exception / `-fPIC` objects get re-linked and the identical wasm-ld error persists — you will chase the wrong flag.
- `TARGET_CFLAGS` may be injected by devShell/flake; `unset TARGET_CFLAGS TARGET_CXXFLAGS` first to establish a baseline, then export the corrected value.
- Mixing exception modes on the two sides always reproduces `__cxa_find_matching_catch_3` undefined; do not silence it with linker flags.
- Verify output artifacts: `ls -la pkg/` and `file` the .wasm to confirm a MAIN_MODULE, not a SIDE_MODULE.
