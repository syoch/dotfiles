{ config, ... }:
{
  systemd.tmpfiles.rules = [
    "d /srv/xwiki 0700 999 999 - -"
  ];

  sops.secrets."xwiki-env" = {
    owner = "root";
    path = "/etc/nixos/xwiki-env";
  };

  services.postgresql.ensureDatabases = [ "xwiki" ];
  services.postgresql.ensureUsers = [
    {
      name = "xwiki";
      ensureDBOwnership = true;
    }
  ];
  services.postgresql.authentication = "host xwiki xwiki 10.88.0.1/16 scram-sha-256";

  virtualisation.oci-containers.containers.xwiki = {
    image = "docker.io/library/xwiki:lts-postgres-tomcat";
    ports = [ "8080:8080" ];

    environmentFiles = [
      config.sops.secrets."xwiki-env".path
    ];

    volumes = [
      "/srv/xwiki:/usr/local/xwiki"
    ];
  };
  services.nginx.virtualHosts."xwiki.syoch.org" = {
    listenAddresses = [
      "0.0.0.0"
      "[::0]"
    ];
    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
      proxyWebsockets = true;
    };
  };
}
