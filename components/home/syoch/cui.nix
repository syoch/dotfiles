{ components, ... }:
{
  imports = [
    (components + /cui/tmux)
    (components + /cui/nvim)
  ];

  hm-module.zsh.enable = true;
}
