{
  security.sudo.extraRules = [
    {
      commands = [ ];
      groups = [ "wheel" ];
    }
  ];

  security.rtkit.enable = true;
}
