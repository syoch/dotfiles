{ ... }:
{
  programs.ssh.enable = true;
  programs.ssh.enableDefaultConfig = false;
  programs.ssh.matchBlocks."*" = { };
  programs.ssh.extraConfig = ''
    Include /home/syoch/.ssh/config.d/*
  '';
}
