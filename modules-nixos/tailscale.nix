{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.os-mod.tailscale;
in
{
  options.os-mod.tailscale = {
    enable = mkEnableOption "tailscale";
  };

  config = mkIf cfg.enable {
    services.tailscale.enable = true;
    services.tailscale.extraSetFlags = [ "--accept-dns=false" ];
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };
  };
}
