{ config, ... }:
{
  systemd.tmpfiles.rules = [
    "d /srv/syoch-portal 0700 syoch-portal syoch-portal - -"
  ];

  sops.secrets."portal-config" = {
    owner = "syoch-portal";
    path = "/etc/nixos/portal-config";
  };

  services.postgresql.ensureDatabases = [ "syoch-portal" ];
  services.postgresql.ensureUsers = [
    {
      name = "syoch-portal";
      ensureDBOwnership = true;
    }
  ];
  services.postgresql.authentication = "host syoch-portal syoch-portal 127.0.0.1/32 scram-sha-256";

  services.syoch-portal = {
    enable = true;
    configFile = config.sops.secrets."portal-config".path;

    user = "syoch-portal";
    group = "syoch-portal";
  };
  systemd.services.syoch-portal = {
    requires = [ "postgresql-setup-passwords.service" ];
    after = [ "postgresql-setup-passwords.service" ];
  };

  services.nginx.virtualHosts."portal.syoch.org" = {
    listenAddresses = [
      "0.0.0.0"
      "[::0]"
    ];
    extraConfig = ''
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
      add_header X-Frame-Options "DENY" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header Referrer-Policy "no-referrer" always;
      add_header Permissions-Policy "interest-cohort=()" always;
      add_header Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'" always;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:8000";
      proxyWebsockets = true;
    };
  };
}
