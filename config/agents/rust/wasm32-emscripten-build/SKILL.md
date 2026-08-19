---
name: wasm32-emscripten-build
description: Use when building a Rust crate to wasm32-unknown-emscripten with cargo and emcc, especially mlua/lua-sys crates: controlling emcc output files (.wasm/.js/.d.ts), SIDE_MODULE vs MAIN_MODULE, MODULARIZE, EXPORT_ES6, --emit-tsd, EMCC_CFLAGS -o ordering, passing -C link-arg flags, and locating emscripten in a Nix shell. Trigger keywords: wasm32-unknown-emscripten, emcc, EMCC_CFLAGS, SIDE_MODULE, MAIN_MODULE, MODULARIZE, EXPORT_ES6, --emit-tsd, mlua wasm, cargo build wasm emscripten, link-arg.
---

# Building Rust crates to wasm32-unknown-emscripten

## When to use
Debugging cargo builds targeting `wasm32-unknown-emscripten` (e.g. mlua/lua-sys, any crate that links through emscripten), when the produced `.wasm`/`.js`/`.d.ts` files are missing or in the wrong place, or when emcc flags like MODULARIZE/EXPORT_ES6/SIDE_MODULE seem to have no effect.

## Procedure
1. Ensure emcc is available. In Nix envs it usually is only inside the dev shell: run everything through `direnv exec . bash -lc '<cmd>'`. To check which emscripten packages nixpkgs exposes: `nix-instantiate --eval -E 'let p=import <nixpkgs>{}; in builtins.filter (n: builtins.match "emscripten.*" n != null) (builtins.attrNames p)'`.
2. Capture the exact emcc command cargo generates: `cargo build --target wasm32-unknown-emscripten --release --verbose 2>&1 | grep -A1 'Running `rustc'`. Cargo runs emcc at the final link step; its own `-o target/.../deps/<crate>.wasm` is always appended.
3. To relocate/rename output, do NOT rely on `EMCC_CFLAGS` containing `-o`: emcc uses only the LAST `-o` flag, so cargo's overrides yours (verified with `emcc -s SIDE_MODULE=2 -o a.js t.c -o b.wasm` -> only b.wasm is produced, and reversed only a.js). Instead pass output via RUSTFLAGS link-args: `-C link-arg=-o/path/out.js`.
4. Pass emcc flags through RUSTFLAGS: `RUSTFLAGS="-C link-arg=-sMAIN_MODULE=2 -C link-arg=-sMODULARIZE=1 -C link-arg=-sEXPORT_ES6=1 -C link-arg=-sEXPORTED_RUNTIME_METHODS=ccall -C link-arg=--emit-tsd -C link-arg=/path/out.d.ts" cargo build --target wasm32-unknown-emscripten --release`.
5. Note that a dependency's build script (e.g. mlua-sys `build/main.rs`, `build/find_normal.rs`) may spawn its OWN emcc invocation independent of the crate's link step; that is the one that actually consumes `EMCC_CFLAGS`. Read the dep source under `~/.cargo/registry/src/index.crates.io-*/` to see who drives emcc and what flags it honors.
6. SIDE_MODULE=2 emits a bare .wasm with no JS glue (works only when loaded as a side module). MAIN_MODULE=2 emits a full JS loader; combine with MODULARIZE + EXPORT_ES6 for a modern ESM consumer, and `--emit-tsd` for TypeScript bindings.

## Verification
- `ls -la` the expected outputs: `.wasm`, `.js`, `.d.ts` all present and non-trivial sizes. A missing `.js` when using SIDE_MODULE is expected, not a bug.
- Check `--emit-tsd` is supported by the installed emcc version (older/newer toolchains vary).
- Force a clean re-link before each attempt: `rm -f target/wasm32-unknown-emscripten/release/deps/<crate>.wasm` (cargo may skip relinking if it thinks the wasm is fresh).

## Pitfalls
- Multiple `-o` flags: last one wins.
- `EMCC_CFLAGS` alone is often ignored by the final crate link; prefer RUSTFLAGS `-C link-arg`.
- `EXPORT_ES6` requires `MODULARIZE`.
- grep the verbose build for the literal `"emcc"` command to confirm which flags actually reached it.
