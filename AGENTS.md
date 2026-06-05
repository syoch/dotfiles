# AGENTS.md - syoch/dotfiles

## What this repo is

Nix flake-based system configuration for multiple machines: desktop (syoch-nix), home server (sv01), rescue ISO, and Nix-on-Droid phone. Consumed by `syoch/infrastructure` as a flake input (`syoch-infra`).

## CRITICAL: pwd requirement

All `nix` commands require `pwd` at repository root (`~/dotfiles`). `flake.nix` lookup fails from subdirectories.

## Key commands

```bash
# pwd = ~/dotfiles (REQUIRED)
sudo nixos-rebuild switch --flake ~/dotfiles -j $(nproc --ignore=1)   # Local rebuild
nixos-rebuild switch --flake .#sv01 --sudo --ask-sudo-password --target-host syoch@100.96.100.1   # Remote sv01
nix run home-manager/master -- switch --flake .   # Home Manager only (no sudo)
nix flake update && make rebuild-hm && make rebuild   # Full upgrade
```

## Machine outputs

| Flake output | Machine | Role |
|---|---|---|
| `nixosConfigurations.syoch-nix` | Desktop | Hyprland, Docker, libvirtd |
| `nixosConfigurations.sv01` | Server | NAS, Nextcloud, Portal, router |
| `packages.x86_64-linux.iso` | Rescue | Bootable ISO (`nix build .#iso`) |

## Directory structure

- `modules-nixos/` — Reusable NixOS system modules (sshd, tailscale, router, etc.)
- `modules-hm/` — Home Manager user modules (zsh, git, hyprland, ags, etc.)
- `components/host/syoch-nix/` — Desktop-specific config
- `components/host/sv01/` — Server-specific config (imports `syoch-infra.nixosModules.syoch-portal`)
- `components/droid/p30t/` — Nix-on-Droid phone
- `config/` — App configs symlinked by HM (hypr, wezterm, ags)
- `keys/` — SOPS age key derivation from SSH keys

## Secrets (SOPS)

```bash
make edit-secrets          # Edit local secrets (VS Code)
make edit-secrets-sv01     # Edit sv01 secrets
make update-keys           # Re-derive age keys after SSH rotation
```

Encrypted: `components/host/syoch-nix/secrets.yaml`, `components/host/sv01/secrets.yaml`

## Gotchas

- `rebuild` and `rebuild-hm` run `git add .` before rebuild — working tree must be clean or committed
- sv01 is accessed via Tailscale IP `100.96.100.1`, not hostname
- Portal service config is in sv01 secrets (`portal-config`), not in this repo directly
- `portal_backup_*.tar.gz` at repo root is a test artifact for Obtainium integration tests
