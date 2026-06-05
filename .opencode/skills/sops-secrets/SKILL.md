---
name: sops-secrets
description: Manage encrypted secrets with SOPS and age encryption
---

## What I do

Guide secrets management using SOPS with age encryption for NixOS and Home Manager.

## When to use me

Use this when:
- Adding or modifying secrets (passwords, API keys, etc.)
- Debugging secret decryption issues
- Rotating SSH keys or age keys
- Configuring secrets for new services

## Encrypted files

| File | Contents |
|------|----------|
| `components/host/syoch-nix/secrets.yaml` | SSH config, wifi PSKs |
| `components/host/sv01/secrets.yaml` | Networking, Cloudflared, Portal DB, Nextcloud admin |

## Commands

```bash
# pwd MUST be the dotfiles repository root
cd /home/syoch/ghq/github.com/syoch/dotfiles

# Edit secrets (opens in $EDITOR)
make edit-secrets          # Local machine
make edit-secrets-sv01     # sv01

# Update age keys (after SSH key rotation)
make update-keys           # Local machine
make update-keys-sv01      # sv01
```

## Key derivation

Age keys are derived from SSH ed25519 keys:

```bash
# In keys/Makefile
ssh-to-age -i ~/.ssh/id_ed25519.pub
```

Current age key: `age17jjjatas2ts9ht6zm6lh2d75kmrx87ncujphwg9r9flzn32jtf7sd2nsfv`

## SOPS configuration (`.sops.yaml`)

Defines which keys can decrypt each file. Each host has its own age key.

## NixOS integration

Secrets are declared in NixOS config and accessed via:

```nix
config.sops.secrets."portal-config".path
```

sops-nix handles decryption at boot time.

## Adding a new secret

1. Add the value to the appropriate `secrets.yaml`:
   ```bash
   make edit-secrets-sv01
   ```
2. Reference in NixOS config:
   ```nix
   sops.secrets."my-secret" = {
     owner = "my-service";
     group = "my-service";
   };
   ```
3. Rebuild:
   ```bash
   make rebuild-sv01
   ```

## Notes

- Never commit unencrypted secrets
- `.gitignore` excludes `tailscale/.env` and `keys/` directory
- Age key must be available on the machine performing decryption
- sops-nix decrypts secrets at systemd service startup
