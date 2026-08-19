---
name: hashmap-iteration-determinism
description: Use when fixing non-deterministic output caused by unspecified HashMap iteration order in Rust. Trigger keywords: non-deterministic output, HashMap iteration, build determinism, md5sum mismatch between runs, sorted keys, reproducible build, inconsistent cell order, random output order.
---

# Fix non-deterministic HashMap iteration in Rust

Rust's `HashMap` does not guarantee iteration order and can vary between runs due to randomization. This causes pipelines (layout, emit, optimize) to produce varying output when they iterate over `HashMap` entries.

## How to detect
- Run the same pipeline twice: if checksums differ, iteration order is likely the cause.
- `md5sum output1 output2` — identical files should have identical hashes.
- Triple-run check: `for run in $(seq 1 3); do cmd > out_$run; done && md5sum out_* | sort -u` should show one hash.

## Fix procedure

1. **Find every `HashMap` iteration** — search for `for.*\.iter\(\)`, `for.*in &map`, `for.*in map` patterns.

2. **Collect and sort keys** before iterating:

```rust
// Before (non-deterministic):
for (name, cell) in &net.cells { ... }

// After (deterministic):
let mut sorted_names: Vec<&String> = net.cells.keys().collect();
sorted_names.sort();
for name in sorted_names.iter().cloned() {
    let cell = &net.cells[name];
    ...
}
```

3. **Watch out for type gotchas:**
   - `keys()` yields `&K`, so a `HashMap<String, V>` gives `Vec<&String>`.
   - Use `sorted_names.iter().cloned()` to get `&String` references (avoids `& &String` double-ref).
   - Index with `net.cells[name]` not `net.cells[*name]` after `.cloned()`.
   - When collecting a filtered sub-vector, `.cloned()` the sorted_names iterator before `.filter()`.

4. **Build and verify:**
```bash
cargo build 2>&1 | grep "^error"
for run in $(seq 1 5); do
  pipeline_command > /tmp/out_${run}
done
md5sum /tmp/out_* | sort -u
# Expect: one line (identical output across runs)
```

5. **Watch for additional order-dependent logic:** constant deduplication, cell merging, or pruning that may also traverse HashMaps.

## Pitfalls
- `BTreeMap` is an alternative but changes the API significantly (`keys()` returns `&K` directly, no sorted copy needed).
- Sorting adds `O(n log n)` per sort; acceptable for moderate `n` but batch if called in a hot loop.
- Only `HashMap`/`HashSet` are non-deterministic; `Vec`, `BTreeMap`, `BTreeSet` are ordered.
- The fix must be applied to **every** iteration site — one missed spot can still cause flakiness.

## Verification
- After applying all fixes, run the pipeline at least 5 times and confirm `md5sum` is identical across all runs.
- Also check that `HashMap` is not used anywhere in the hot path where iteration order could escape (serialization, display, file I/O).
