---
name: emscripten-mlua-jsglue
description: Use when building a Rust crate (esp. mlua/lua-sys) to wasm32-unknown-emscripten and you need emcc to emit the JS glue (.js) alongside .wasm plus a .d.ts type file, or when debugging 'Wasm only output is not compatible', '--emit-tsd', SIDE_MODULE/MAIN_MODULE, MODULARIZE/EXPORT_ES6/EXPORTED_RUNTIME_METHODS, and undefined 'luaopen_'/'luaL_openlibs' symbols in the static Lua archive. Trigger keywords: wasm32-unknown-emscripten cargo build, mlua emscripten, luaopen_ undefined, Wasm only output is not compatible, --emit-tsd, SIDE_MODULE MAIN_MODULE, llvm-nm liblua, mlua-sys out lua-build.
---

Use when compiling a Rust cdylib to the `wasm32-unknown-emscripten` target and you must control what emcc emits: normally `cargo build` lets rustc append a single `-o foo.wasm` (wasm-only output), which is incompatible with `-sSIDE_MODULE` and produces no JS glue or type declarations. Also use when the resulting Lua module fails to load with undefined `luaopen_*` symbols.

## When to use
- Building mlua / lua-sys (or any cdylib with loadable modules) to wasm32-unknown-emscripten.
- Need `.js` glue + `.wasm` + `.d.ts` for a Node/browser consumer.
- Linker errors like "Wasm only output is not compatible" or missing `luaopen_`/`luaL_openlibs` at runtime.

## Procedure
1. Inspect your emcc install to find the guard: `E=$(dirname $(readlink -f $(which emcc)))/../share/emscripten; rg -n "Wasm only output" $E/emcc.py; sed -n '810,960p' $E/tools/link.py` (nix store path varies). This reveals why `-o file.wasm` alone is rejected with SIDE_MODULE.
2. Confirm the flag-to-emcc plumbing: `rg -n "emit_tsd|oformat" $E/emcc.py`. `--emit-tsd` needs a `.d.ts` output file.
3. Drive emcc through rustc link args. Multiple `-o` flags force js+wasm together; use `-sSIDE_MODULE=0` plus `-sMAIN_MODULE=2` so wasm-only mode is bypassed and JS glue is produced:
```
unset EMCC_CFLAGS
RUSTFLAGS="-C link-arg=-sSIDE_MODULE=0 -C link-arg=-o/path/out/lua.js -C link-arg=--emit-tsd -C link-arg=/path/out/lua.d.ts -C link-arg=-sMODULARIZE=1 -C link-arg=-sEXPORT_ES6=1 -C link-arg=-sEXPORTED_RUNTIME_METHODS=ccall -C link-arg=-sMAIN_MODULE=2" \
  cargo build --target wasm32-unknown-emscripten --release
```
4. If `luaopen_*` is undefined at runtime, inspect the bundled Lua archive: `LB=$(ls -d target/wasm32-unknown-emscripten/release/build/mlua-sys-*/out/lua-build/lib | tail -1)`. Then `llvm-nm --defined-only $LB/liblua5.4.a | rg luaopen_` to confirm symbols exist, and `llvm-nm $LB/linit.o | grep ' U '` to see unresolved refs in linit.

## Verification
- Build exits 0 and `ls` shows all of `lua.js`, `lua.wasm`, `lua.d.ts`.
- `head` the `.d.ts` and confirm it exports the expected module functions.
- `llvm-nm` shows each `luaopen_*` as `T` (defined) and `linit.o`'s `U` refs resolve against the archive.

## Pitfalls
- Ordering of `-o` flags matters because rustc appends its own `-o <out>.wasm`; place the `-o x.js` BEFORE the implicit wasm output so glue is generated.
- `-sSIDE_MODULE` alone forbids wasm-only output; pair with `-sMAIN_MODULE=2` or supply a `.js` target.
- Nix `direnv` may export `EMCC_CFLAGS` that pollute the link; `unset EMCC_CFLAGS` first.
- `llvm-nm` (not `nm`) because wasm objects use LLVM bitcode; `file` on the `.o` confirms format.
