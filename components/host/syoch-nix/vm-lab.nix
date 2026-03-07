{ lib, ... }:
{
  networking.networkmanager = {
    enable = true;
    unmanaged = [
      "tap0"
      "br0"
    ];
  };

  systemd.network =
    let
      tapDev = name: {
        "20-${name}" = {
          enable = true;
          netdevConfig.Kind = "tap";
          netdevConfig.Name = "${name}";
        };
      };
      bridgeDev = name: {
        "20-${name}" = {
          enable = true;
          netdevConfig.Kind = "bridge";
          netdevConfig.Name = "${name}";
        };
      };
      tapNetwork = name: bridgeName: {
        "40-${name}" = {
          matchConfig.Name = name;
          bridgeConfig = { };
          linkConfig.ActivationPolicy = "always-up";
          linkConfig.RequiredForOnline = "no";
          bridge = [ bridgeName ];
        };
      };
      bridgeNetwork = name: addresses: {
        "40-${name}" = {
          matchConfig.Name = name;
          linkConfig.ActivationPolicy = "always-up";
          linkConfig.RequiredForOnline = "no";
          address = addresses;
        };
      };
      labDevices =
        labName:
        lib.mkMerge [
          (bridgeDev labName)
          (tapDev "${labName}-0")
          (tapDev "${labName}-1")
          (tapDev "${labName}-2")
          (tapDev "${labName}-3")
          (tapDev "${labName}-4")
        ];
      labNetworks =
        labName: address:
        lib.mkMerge [
          (bridgeNetwork labName address)
          (tapNetwork "${labName}-0" labName)
          (tapNetwork "${labName}-1" labName)
          (tapNetwork "${labName}-2" labName)
          (tapNetwork "${labName}-3" labName)
          (tapNetwork "${labName}-4" labName)
        ];
    in
    {
      enable = true;
      wait-online.enable = false;
      netdevs = lib.mkMerge [
        (labDevices "lab0")
        (labDevices "lab1")
        (labDevices "lab2")
        (labDevices "lab3")
      ];
      networks = lib.mkMerge [
        (labNetworks "lab0" [
          # "10.50.99.99/16"
        ])
        (labNetworks "lab1" [
          # "10.51.99.99/16"
        ])
        (labNetworks "lab2" [
          # "10.52.99.99/16"
        ])
        (labNetworks "lab3" [
          # "10.53.99.99/16"
        ])
      ];
    };
}
