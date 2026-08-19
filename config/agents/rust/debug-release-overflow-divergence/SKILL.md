---
name: debug-release-overflow-divergence
description: Use when a Rust debug build panics with integer overflow (e.g. 'attempt to shift left with overflow') but the release build does not, or when debug and release builds produce different results and you must decide whether the bug is real or a profile artifact. Trigger keywords: attempt to shift left with overflow, shift overflow, attempt to add with overflow, debug vs release, release build different result, panic only in debug, integer overflow divergence, probe crate, characterize rust semantics.
---

## Use when

- A Rust binary/test panics in debug (`cargo run`, `cargo test`) with `attempt to shift left with overflow`, `attempt to add with overflow`, `attempt to multiply with overflow`, etc.
- The same input succeeds in the release build (`cargo run --release`) — either producing output or silently wrong results.
- You suspect a bug is masked or only visible in one of the two profiles (bus bit index, shift amount >= bit width, wrap-around arithmetic).

This is the debug/release divergence problem: debug builds panic on overflow, release builds wrap silently, so a real bug can crash one profile and quietly corrupt results in the other.

## Procedure

1. **Reproduce in debug.** Run the failing command against `target/debug/<bin>` and capture the panic message and backtrace (`--debug` flags often help).
2. **Test the release build** on the identical input. Note whether it panics, succeeds, or produces a *different* value. Both outcomes are signal: a silent wrong answer in release is the same bug, just wrapped.
3. **Characterize the Rust semantics with a minimal probe crate** (`/tmp/opencode/probe`):
   - `cargo new --bin /tmp/opencode/probe`, then add the crate as a dev-dependency if you need to call internal functions, or keep it standalone for language semantics.
   - Write the minimal expression (e.g. `let v: u8 = 1; let r = v << shift;`).
   - **Crucially, take the volatile value from runtime input** (`std::env::args().nth(1).unwrap().parse()`) — a constant overflow like `1u8 << 11` is a *compile-time* error (`this arithmetic operation will overflow`) and never reaches runtime.
   - Build/run in both profiles: `cargo run --release` vs `cargo run`. Record wrap vs panic per profile.
4. **Find the root cause in the real source** (`rg` for the shifting sites, bus width vs index, test assert widths).
5. **Fix**, preferring `checked_shl`/`saturating_shl`/wrapping-with-mask or validating indices against declared widths.
6. **Verify in BOTH profiles:** `cargo test` (debug) AND `cargo test --release`, plus re-running the original failing input against both `target/debug` and `target/release` binaries.

## Pitfalls

- Constant overflow fails at compile time; always parameterize the probe via runtime args.
- Passing `cargo test` in debug does NOT prove release is correct — the two profiles can mask each other's bugs. Run both.
- The panic may be indirect: a huge bus index in a test/assert reaching a `1 << idx` where `idx >= 64` will panic in debug but silently zero out in release.
- Fix the source, not the profile: suppressing by only ever running release builds hides real wrap-around bugs.

## Verification

Debug and release builds produce identical outputs for the same inputs, no debug panic remains, and both `cargo test` and `cargo test --release` pass.
