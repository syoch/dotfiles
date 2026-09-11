# A nixos module that manages the virtualHosts of nginx
# - servers.domain: suffix of the domain name of the virtualHost.
# - servers.hosts."<name>"
#   - ssl: null | "dns-01" | "http-01"
#   - upstream: null | url
#   - fqdn: (readonly) the FQDN of the vHost
{ config, lib, ... }:
let
  cfg = config.servers;
  domain = cfg.domain;
in
{
  options = {
    servers.domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The domain name of the virtualHosts. This is used to construct the FQDN
        of the virtualHosts. If null, the FQDN will be the same as the name of
        the virtualHost.
      '';
    };
    servers.hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: {
            options = {
              ssl = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.enum [
                    "dns-01"
                    "http-01"
                  ]
                );
                default = null;
                description = ''
                  Whether to enable SSL for the virtualHost. If set to "dns-01", the
                  virtualHost will be configured to use DNS-01 challenge for ACME.
                  If set to "http-01", the virtualHost will be configured to use
                  HTTP-01 challenge for ACME.
                '';
              };
              upstream = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  The upstream URL to proxy requests to. If null, the virtualHost
                  will not proxy requests.
                '';
              };
              fqdn = lib.mkOption {
                type = lib.types.str;
                default = null;
                description = ''
                  The FQDN of the virtualHost. This is automatically set based on
                  the name of the virtualHost and the domain name.
                '';
              };
            };
            config = {
              fqdn = if domain != null then "${name}.${domain}" else name;
            };
          }
        )
      );
      default = { };
      description = ''
        A set of virtualHosts to configure in nginx. Each virtualHost is
        identified by its domain name, and can be configured with the options
        above.
      '';
    };
  };

  config =
    let
      getFQDN = name: if domain != null then "${name}.${domain}" else name;
      serverUpstreamConfig = upstream: {
        listenAddresses = [
          "0.0.0.0"
          "[::0]"
        ];
        locations."/" = {
          proxyPass = upstream;
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
      serverConfig =
        name: cfg:
        lib.mkMerge [
          {
            enableACME = cfg.ssl != null;
            forceSSL = cfg.ssl != null;
            acmeRoot = lib.mkIf (cfg.ssl == "dns-01") null;
          }
          (lib.mkIf (cfg.upstream != null) (serverUpstreamConfig cfg.upstream))
        ];
    in
    {
      # servers."A" = { ssl = "dns-01"; upstream = "http://127.0.0.1"; }
      # --> virtualHosts."A.<domain>" = { ... }
      services.nginx.virtualHosts = lib.attrsets.mapAttrs' (
        name: cfg: lib.nameValuePair (getFQDN name) (serverConfig name cfg)
      ) cfg.hosts;
    };
}
