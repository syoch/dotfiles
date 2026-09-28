{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [
    "/etc/nixos/syoch-nix.key"
  ];
  sops.secrets."ssh-config" = {
    owner = "syoch";
    path = "/home/syoch/.ssh/config.d/secret";
  };

  # One-time bootstrap token for the portal OpenCode bridge.
  # The value is issued by `portal-manage control issue-bootstrap-token` on the
  # portal host and only needs to be present until the bridge registers once
  # (credentials are then persisted under /var/lib/portal-opencode-bridge).
  sops.secrets."portal-opencode-bridge-token" = {
    owner = "syoch";
    path = "/etc/nixos/portal-opencode-bridge.token";
  };

  sops.secrets."network-env" = { };
  networking.networkmanager.ensureProfiles.environmentFiles = [
    config.sops.secrets."network-env".path
  ];
}
