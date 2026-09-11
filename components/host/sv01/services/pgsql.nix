{ config, pkgs, ... }:
{
  services.postgresql = {
    enableTCPIP = true;
    authentication = ''
      host postgres postgres 10.42.0.0/16 scram-sha-256
    '';
  };

  sops.secrets."portal-db-password" = {
    owner = "postgres";
    path = "/etc/nixos/portal-db-password";
  };
  systemd.services.postgresql-setup-passwords = {
    description = "Set PostgreSQL passwords from SOPS secrets";
    path = [ pkgs.postgresql ];

    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    before = [ "syoch-portal.service" ];

    serviceConfig = {
      User = "postgres";
      Group = "postgres";
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -e
      portal_password="$(cat ${config.sops.secrets."portal-db-password".path})"
      psql -v ON_ERROR_STOP=1 -c "ALTER USER \"syoch-portal\" WITH PASSWORD '$portal_password';"
    '';
  };
}
