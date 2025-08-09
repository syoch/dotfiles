{ config, pkgs, ... }:
{
  programs.ssh.enable = true;
  programs.ssh.extraConfig = ''
    Include /home/syoch/.ssh/config.d/secret
  '';
}
