{ pkgs, ... }:
{
  services.wayvnc.enable = true;

  systemd.user.services."wayvnc@tablet" = {
    Unit = {
      Description = "WayVNC service for tablet";
    };
    Service = {
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o tablet 0.0.0.0";
    };
  };
}
