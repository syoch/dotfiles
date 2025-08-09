{
  security.sudo = {
    enable = true;
    extraRules = [
      {
        commands = [ ];
        groups = [ "wheel" ];
      }
    ];
  };

  security.rtkit.enable = true;

}
