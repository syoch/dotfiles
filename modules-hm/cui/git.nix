{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.git;
in
{
  options.hm-module.git = {
    enable = mkEnableOption "git";
  };

  config = mkIf cfg.enable {
    programs.git = {
      enable = true;
      lfs.enable = true;
      settings.user.name = "syoch";
      settings.user.email = "syoch64@gmail.com";
      settings.aliases = {
        co = "checkout";
        br = "branch";
        ci = "commit";
        st = "status";
        lg = "log --oneline --graph --all --decorate";
        amend = "commit --amend --no-edit";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        fix-perm = "!f(){ git diff -p | grep -E '^(diff|old mode|new mode)' | sed -e 's/^old/NEW/;s/^new/old/;s/^NEW/new/' | git apply; }; f";
      };
    };
  };
}
