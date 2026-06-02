{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.os-mod.sshd;
in
{
  options.os-mod.sshd = {
    enable = mkEnableOption "sshd";
  };

  config = mkIf cfg.enable {
    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        MaxAuthTries = 3;
        PermitRootLogin = "prohibit-password";
        X11Forwarding = false;
      };
    };

    services.fail2ban = {
      enable = true;
      jails.sshd.settings = {
        enabled = true;
        maxretry = 3;
        findtime = 600;
        bantime = 3600;
      };
    };
  };
}
