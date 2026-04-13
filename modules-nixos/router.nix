{
  lib,
  config,
  ...
}:
let
  cfg = config.os-mod.router;
in
{
  options.os-mod.router = {
    enable = lib.mkEnableOption "router";
    upstream.interface = lib.mkOption {
      type = lib.types.str;
      description = "The upstream network interface connected to the internet.";
    };
    downstream.interface = lib.mkOption {
      type = lib.types.str;
      description = "The downstream network interface connected to the local network.";
    };
    downstream.ipAddress = lib.mkOption {
      type = lib.types.str;
      description = "Static IP address for the downstream interface.";
    };
    downstream.prefixLength = lib.mkOption {
      type = lib.types.int;
      description = "Prefix length for the downstream interface.";
    };
    downstream.dhcpRangeStart = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Start of DHCP range for downstream clients (if DHCP server is enabled).";
    };
    downstream.dhcpRangeEnd = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "End of DHCP range for downstream clients (if DHCP server is enabled).";
    };
    extraForwardableInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of interfaces from which forwarding is allowed.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.interfaces."${cfg.upstream.interface}" = {
      useDHCP = true;
    };

    networking.interfaces."${cfg.downstream.interface}".ipv4.addresses = [
      {
        address = cfg.downstream.ipAddress;
        prefixLength = cfg.downstream.prefixLength;
      }
    ];

    boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = 1;

    networking.firewall.enable = true;
    networking.nftables.enable = true;
    networking.firewall.filterForward = true;
    networking.firewall.extraForwardRules = lib.concatMapStringsSep "\n" (
      iface: "iifname ${cfg.downstream.interface} oifname ${iface} accept"
    ) (cfg.extraForwardableInterfaces ++ [ cfg.upstream.interface ]);
    networking.firewall.trustedInterfaces = [ cfg.downstream.interface ];

    networking.nftables.tables.RouterNAT = {
      enable = true;
      family = "inet";
      content = ''
        chain prerouting {
          type nat hook prerouting priority 100; policy accept;
          iifname "${cfg.downstream.interface}" meta nftrace set 1
        }
        chain postrouting {
          type nat hook postrouting priority 100; policy accept;
          oifname "${cfg.upstream.interface}" masquerade
          ${lib.concatMapStringsSep "\n" (
            iface: "iifname ${cfg.downstream.interface} oifname ${iface} masquerade"
          ) cfg.extraForwardableInterfaces}
        }
      '';
    };

    # DHCP server for downstream network
    services.dnsmasq.enable = (
      cfg.downstream.dhcpRangeStart != "" && cfg.downstream.dhcpRangeEnd != ""
    );
    services.dnsmasq.settings.interface = cfg.downstream.interface;
    services.dnsmasq.settings.bind-interfaces = true;
    services.dnsmasq.settings.dhcp-option = [
      "3,${cfg.downstream.ipAddress}"
      "6,1.1.1.1"

    ];
    services.dnsmasq.settings.dhcp-range = ''
      ${cfg.downstream.interface},${cfg.downstream.dhcpRangeStart},${cfg.downstream.dhcpRangeEnd},12h
    '';

    networking.firewall.allowedUDPPorts = [
      67
      68
    ];
  };
}
