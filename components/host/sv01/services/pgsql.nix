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
  # Read by postgresql-setup-passwords (as postgres, via the owner bits) and by
  # talk-bridge (as nextcloud, via the group bits). 0440 keeps it unreadable
  # for everyone else. Note this is the sops-nix option `group`, not
  # `ownerGroup`.
  sops.secrets."talk-db-password" = {
    owner = "postgres";
    group = "nextcloud";
    mode = "0440";
    path = "/etc/nixos/talk-db-password";
  };
  systemd.services.postgresql-setup-passwords = {
    description = "Set PostgreSQL passwords from SOPS secrets";
    path = [ pkgs.postgresql ];

    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    before = [ "portal.service" "talk-bridge.service" ];

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

      talk_password="$(cat ${config.sops.secrets."talk-db-password".path})"
      psql -v ON_ERROR_STOP=1 -c "ALTER USER \"syoch-talk\" WITH PASSWORD '$talk_password';"
    '';
  };
}
