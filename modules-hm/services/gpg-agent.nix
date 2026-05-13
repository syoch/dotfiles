{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hm-module.gpg-agent;
in
{
  options.hm-module.gpg-agent = {
    enable = lib.mkEnableOption "gpg-agent";
  };

  config = lib.mkIf cfg.enable {
    services.gpg-agent.enable = true;
    services.gpg-agent.enableZshIntegration = true;
    services.gpg-agent.enableSshSupport = true;
    services.gpg-agent.pinentry.package = pkgs.pinentry-all;
    programs.gpg.enable = true;
    home.packages = [ pkgs.gnupg ];
  };
}
