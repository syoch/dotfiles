{ components, pkgs, ... }:
{
  imports = [
    (components + /cui/zsh)
    (components + /cui/tmux)
    (components + /cui/nvim)
    (components + /cui/bat)
    (components + /cui/eza)
  ];

  home.file.".profile".text = ''
    #!/bin/sh
    # . "$HOME/.cargo/env"
    # export PATH=$PATH:~/.cargo/bin

    if [ -e $HOME/.nix-profile/etc/profile.d/nix.sh ]; then
      . $HOME/.nix-profile/etc/profile.d/nix.sh
    fi
  '';
}
