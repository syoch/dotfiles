{ config, ... }: {
  nix.settings.substituters = [
    "https://nnctrobo.cachix.org"
  ];
  nix.settings.trusted-public-keys = [
    "nnctrobo.cachix.org-1:1dKKIMpU2HT8hYTQVOxaE8YGT1rVvHpZNjgkMCrIRzM="
  ];

  sops.secrets."netbird-wt0-setup-key" = {
    owner = "root";
    path = "/etc/nixos/netbird-wt0-setup-key";
  };
  services.netbird.clients.wt0 = {
    login = {
      enable = true;
      setupKeyFile = config.sops.secrets."netbird-wt0-setup-key".path;
    };
    port = 51821;
    ui.enable = false;
    dns-resolver.address = "127.0.0.53";
    dns-resolver.port = 5053;
    openFirewall = true;
    openInternalFirewall = true;
  };
  services.dnsmasq.servers = [
    "/nnctrobo.internal/127.0.0.53#5053"
  ];

  networking.hosts."10.50.10.1" = [
    "sv01.nnctrobo.internal"
    "id.nnctrobo.internal"
    "nextcloud.nnctrobo.internal"
    "nextcloud-wb.nnctrobo.internal"
    "smb.nnctrobo.internal"
    "luminary.nnctrobo.internal"
  ];
}
