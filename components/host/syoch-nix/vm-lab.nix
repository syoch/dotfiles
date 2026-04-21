{ lib, ... }:
{
  virtualisation.libvirtd.allowedBridges = [
    "virbr0"
    "lab0"
    "lab1"
    "lab2"
    "lab3"
  ];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
  };

  systemd.network =
    let
      tapDev = name: bridgeDevName: {
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
          (tapDev "${labName}-0" labName)
          (tapDev "${labName}-1" labName)
          (tapDev "${labName}-2" labName)
        ];
      labNetworks =
        labName: address:
        lib.mkMerge [
          (bridgeNetwork labName address)
          (tapNetwork "${labName}-0" labName)
          (tapNetwork "${labName}-1" labName)
          (tapNetwork "${labName}-2" labName)
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
          "10.50.254.254/16"
        ])
        (labNetworks "lab1" [
          "10.61.254.254/16"
        ])
        (labNetworks "lab2" [
          "10.62.254.254/16"
        ])
        (labNetworks "lab3" [
          "10.63.254.254/16"
        ])
      ];
    };
}
