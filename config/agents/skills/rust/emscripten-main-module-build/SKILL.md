---
name: emscripten-main-module-build
description: Use when building a Rust crate to wasm32-unknown-emscripten and the plain cdylib output yields only a wasm SIDE_MODULE with no JS glue or .d.ts. Covers forcing emscripten MAIN_MODULE link via CARGO_TARGET_..._RUSTFLAGS link-args (-sSIDE_MODULE=0, -o<out>.js, --emit-tsd, -sMAIN_MODULE=2), the tsc-in-PATH requirement for --emit-tsd, TARGET_CC/TARGET_CFLAGS overriding Nix CC=gcc for the cc crate, -fwasm-exceptions alignment, and node smoke-testing the MODULARIZE output. Trigger keywords: wasm32-unknown-emscripten cargo build, emit-tsd, SIDE_MODULE, MAIN_MODULE=2, MODULARIZE, EXPORTED_RUNTIME_METHODS ccall, TARGET_CC emcc, mlua vendored Lua wasm, lua-rs.js, missing JS glue, EMCC_CFLAGS.
---

# Rust → wasm32-unknown-emscripten MAIN_MODULE build with JS glue + .d.ts

## When to use
Use when cross-compiling a Rust crate (e.g. an mlua/lua wrapper) to `wasm32-unknown-emscripten` and the link produces only a bare `*.wasm` (SIDE_MODULE) with **no** `*.js` glue or `*.d.ts`.

## Why this is needed
`rustc` links a `cdylib` as a wasm-only SIDE_MODULE, so emscripten never runs its JS-glue / tsd steps. You must override the output to a JS file and request MAIN_MODULE linking via target-specific `RUSTFLAGS`.

## Procedure
1. Put all env in a `build.sh` and always run through the Nix shell: `direnv exec . bash -lc '...'`.
2. Pin the C compiler for the `cc` crate (Nix devShell exports `CC=gcc` which would otherwise win):
   ```bash
   export TARGET_CC=emcc
   export TARGET_CXX=em++
   export TARGET_CFLAGS="-fPIC -fwasm-exceptions"
   export TARGET_CXXFLAGS="-fPIC -fwasm-exceptions"
   unset EMCC_CFLAGS   # stale flags break emcc
   ```
3. `--emit-tsd` shells out to `tsc`; it is NOT bundled with emscripten. Prepend a `tsc` to PATH, e.g. `export PATH="$PROJECT/node_modules/.bin:$PATH"` (verify: `node_modules/.bin/tsc`).
4. Set target-scoped RUSTFLAGS (host builds unaffected):
   ```bash
   export CARGO_TARGET_WASM32_UNKNOWN_EMSCRIPTEN_RUSTFLAGS="\
   -C link-arg=-sSIDE_MODULE=0 \
   -C link-arg=-o$(pwd)/pkg/lua-rs.js \
   -C link-arg=--emit-tsd \
   -C link-arg=$(pwd)/pkg/lua-rs.d.ts \
   -C link-arg=-sMODULARIZE=1 \
   -C link-arg=-sEXPORT_ES6=1 \
   -C link-arg=-sEXPORTED_RUNTIME_METHODS=ccall \
   -C link-arg=-sMAIN_MODULE=2"
   ```
5. When changing link flags, force a real relink: `rm -rf target/wasm32-unknown-emscripten/release/{build,.fingerprint,deps}` for the crate (`mlua-sys-*`), or `cargo clean`; otherwise stale fingerprints skip the link.
6. Build: `cargo build --target wasm32-unknown-emscripten --release`.

## Verification
- `ls pkg/` shows `lua-rs.js`, `lua-rs.d.ts`.
- Smoke test with Node, importing the MODULARIZE default export and calling a C-ABI symbol via `ccall`:
  ```js
  import lua_mod from "./lua-rs.js";
  const mod = await lua_mod();
  const ptr = mod.___ffi_lufenv_new();
  mod.ccall("__ffi_luaenv_run", null, ["number", "string"], [ptr, "print('hi')"]);
  ```
  Run with `direnv exec . bash -lc 'cd pkg && node test.mjs'`.

## Pitfalls
- `--emit-tsd` fails/skips silently without `tsc` on PATH → no `.d.ts`.
- Forgetting `-sSIDE_MODULE=0` yields wasm-only output, no JS glue.
- If `build.sh` is invoked from another cwd, compute `script_dir=$(cd "$(dirname "$0")" && pwd)` first; `-o` needs an absolute path.
- `-sWASM_LEGACY_EXCEPTIONS` must match between C and Rust (use `-fwasm-exceptions`).
- Debug hangs: re-run with `-v` and grep the `rustc` invocation to confirm link-args are actually passed.
