---
name: cli-integration-tests
description: Use when writing Rust CLI integration tests that spawn a binary via std::process::Command. Keywords: Rust CLI test, integration test, cargo test binary, std::process::Command test, TempFile atomic counter, CLI subcommand test, test binary path, parallel test temp file race.
---

# Rust CLI Integration Tests

Write integration tests that compile and invoke a Rust CLI binary, testing subcommands, flags, success/error paths, and output content.

## When to use
- Adding CLI integration tests to a Rust project
- Testing subcommands (`build`, `check`, `test`, `run`, etc.)
- Testing both success (exit 0) and error (exit non-zero) paths
- Verifying stdout/stderr content
- Needing temp files with inputs that differ per test

## Procedure

### 1. Create test file
Create `tests/cli_tests.rs` (Cargo discovers `tests/*.rs` as integration tests).

### 2. Add helper utilities
```rust
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

fn cargo_bin() -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.push("target");
    path.push("debug");
    if cfg!(target_os = "windows") {
        path.push("mybin.exe");
    } else {
        path.push("mybin");
    }
    path
}

fn run(args: &[&str]) -> std::process::Output {
    Command::new(cargo_bin()).args(args).output().unwrap()
}

fn stdout(out: &std::process::Output) -> &str {
    std::str::from_utf8(&out.stdout).unwrap()
}

fn stderr(out: &std::process::Output) -> &str {
    std::str::from_utf8(&out.stderr).unwrap()
}
```

### 3. Atomic TempFile (avoids parallel test races)
```rust
static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

struct TempFile { path: PathBuf }

impl TempFile {
    fn new(content: &str) -> Self {
        let dir = std::env::temp_dir();
        let id = TEMP_COUNTER.fetch_add(1, Ordering::SeqCst);
        let path = dir.join(format!("test_{}.ext", id));
        std::fs::write(&path, content).unwrap();
        TempFile { path }
    }
    fn path_str(&self) -> &str {
        self.path.to_str().unwrap()
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        std::fs::remove_file(&self.path).ok();
    }
}
```

### 4. Group by subcommand
```rust
mod build {
    use super::*;
    #[test]
    fn test_build_basic() {
        let out = run(&["build", "input.ext"]);
        assert!(out.status.success(), "stderr: {}", stderr(&out));
        assert!(!out.stdout.is_empty());
    }
    #[test]
    fn test_build_missing_file() {
        let out = run(&["build", "nonexistent.ext"]);
        assert!(!out.status.success());
    }
}
```

### 5. Iterative fix cycle
When tests fail:
- Read the CLI arg parser source to discover actual flag names
- Read the CLI handler source to discover error message text
- Fix test expectations (flags, stderr strings) and rerun
- Use `cargo test --test cli_tests` for fast iteration

### 6. Verify
```
cargo test --test cli_tests
```

## Pitfalls
- **Race condition**: Without `AtomicU64`, parallel test execution creates colliding temp file names. Always use the atomic counter.
- **Binary not built**: Run `cargo build` first, or `cargo test` handles it automatically.
- **Path separator**: Use `to_string_lossy()` on `Path` for cross-platform args.
- **Stderr messages**: Match exact strings from source. When source changes, update tests.
- **CARGO_MANIFEST_DIR**: Only available at compile time via `env!()` macro.
- **Temp file cleanup**: `Drop` may not run on panic. For critical cleanup, use `std::panic::catch_unwind` or test harness setup.

## Testing strategy checklist
- [ ] Each subcommand has at least one success test
- [ ] Each subcommand has at least one error test (missing file, invalid input)
- [ ] Tests for --out / --debug / other flags
- [ ] Tests verify stdout content contains expected strings
- [ ] Tests compile in CI without extra dependencies
