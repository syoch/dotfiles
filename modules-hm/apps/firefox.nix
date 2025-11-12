{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.firefox;
in
{
  options.hm-module.firefox = {
    enable = mkEnableOption "firefox";
  };

  config = mkIf cfg.enable {
    programs.firefox.enable = true;
    programs.firefox.languagePacks = [
      "jp"
      "ja-JP"
    ];
  };
}
