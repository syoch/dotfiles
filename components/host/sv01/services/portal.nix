{ config, ... }:
{
  # The OS user/group and PostgreSQL db/role intentionally keep the historical
  # "syoch-portal" names (no data migration); only the NixOS option/unit names
  # follow the new "portal" naming from the infrastructure module.
  users.users.syoch-portal = {
    isSystemUser = true;
    group = "syoch-portal";
    description = "Android Device Provisioning Portal user";
  };
  users.groups.syoch-portal = { };

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

  services.portal = {
    enable = true;
    configFile = config.sops.secrets."portal-config".path;

    user = "syoch-portal";
    group = "syoch-portal";
  };
  systemd.services.portal = {
    requires = [ "postgresql-setup-passwords.service" ];
    after = [ "postgresql-setup-passwords.service" ];
  };

  servers.hosts."portal" = {
    ssl = "dns-01";
    upstream = "http://127.0.0.1:8000";
  };
  services.nginx.virtualHosts.${config.servers.hosts."portal".fqdn} = {
    extraConfig = ''
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
      add_header X-Frame-Options "DENY" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header Referrer-Policy "no-referrer" always;
      add_header Permissions-Policy "interest-cohort=()" always;
    '';
  };
}
