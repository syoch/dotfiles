---
name: nixos-rebuild
description: Rebuild NixOS system configurations and deploy to remote hosts
---

## What I do

Guide NixOS rebuild operations for local and remote machines.

## When to use me

Use this when:
- Modifying NixOS configuration in `components/` or `modules-nixos/`
- Changing Home Manager config in `modules-hm/`
- Deploying to sv01 (home server)
- Updating flake inputs

## Commands

```bash
# pwd MUST be the dotfiles repository root
cd /home/syoch/ghq/github.com/syoch/dotfiles

# Local machine rebuild
sudo nixos-rebuild switch
# or
make rebuild

# Remote rebuild (sv01 via SSH)
make rebuild-sv01

# Home Manager only (no sudo)
make rebuild-hm

# Full upgrade (flake lock + HM + NixOS)
make upgrade
```

## Machine configurations

| Output | Machine | Description |
|--------|---------|-------------|
| `nixosConfigurations.syoch-nix` | Desktop | Hyprland, triple-monitor, Docker, libvirtd |
| `nixosConfigurations.sv01` | Server | NAS, Nextcloud, Portal, router |
| `homeConfigurations.syoch` | User | Standalone HM config |
| `packages.x86_64-linux.iso` | Rescue | Bootable rescue ISO |

## Key modules

### System (`modules-nixos/`)
- `system.nix` — Boot, kernel (linux-zen), zram, Nix settings
- `sshd.nix` — OpenSSH hardening + fail2ban
- `tailscale.nix` — Tailscale VPN
- `router.nix` — nftables NAT, dnsmasq DHCP
- `nas.nix` / `nfs-server.nix` / `smb-server.nix` — Storage

### User (`modules-hm/`)
- `zsh/` — Shell with eza, bat, starship, direnv
- `git/` — Git with LFS and aliases
- `hyprland-utils/` — Wayland desktop
- `ags/` — GTK4 status bar

## Portal service (sv01)

The portal is imported from `syoch/infrastructure` as a Nix flake input:

```nix
inputs.syoch-infra.url = "github:syoch/infrastructure";
# Used as:
syoch-infra.nixosModules.syoch-portal
```

Configuration in `components/host/sv01/`:
```nix
services.syoch-portal = {
  enable = true;
  configFile = config.sops.secrets."portal-config".path;
};
```

## Notes

- `nixos-rebuild switch` requires `sudo` for system-level changes
- Home Manager can be rebuilt without sudo
- `make upgrade` updates flake.lock first, then rebuilds
- sv01 is accessed via Tailscale VPN (`syoch-vpn`)
