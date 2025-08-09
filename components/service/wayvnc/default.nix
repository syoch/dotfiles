{
  services.wayvnc = {
    enable = true;
    settings = {
      address = "0.0.0.0";
      port = 5900;
    };
  };

  systemd.user.services."wayvnc@tablet" = {
    Unit = {
      Description = "WayVNC service for tablet";
    };
    Service = {
      ExecStart = "/usr/bin/wayvnc -o tablet 0.0.0.0";
    };
  };
}
