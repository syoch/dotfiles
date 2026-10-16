{ config, pkgs, ... }:

let
  base = "dc=id,dc=syoch,dc=org";
  configAdmin = "cn=admin,cn=config";
  dataAdmin = "uid=admin,ou=Users,${base}";
  # Read-only account that the NextCloud user_ldap app binds as.
  ncService = "uid=nextcloud,ou=Services,${base}";

  seedTemplate = ../ldifs/initial.ldif.in;
  ldapTools = with pkgs; [ openldap coreutils ];
in
{
  sops.secrets."ldap-admin-password" = {
    owner = "root";
    path = "/etc/nixos/ldap-admin-password";
  };
  sops.secrets."ldap-nextcloud-password" = {
    owner = "root";
    path = "/etc/nixos/ldap-nextcloud-password";
  };

  services.openldap = {
    enable = true;
    # Configuration comes from the Nix store; the mdb directory is the only
    # mutable state, so a rebuild never drifts from what is checked in.
    mutableConfig = false;
    user = "root";

    # Loopback on purpose. NextCloud runs on this host, so nothing outside sv01
    # needs to reach the directory, and leaving 389 closed means a stray urlList
    # edit cannot publish it.
    urlList = [
      "ldap://127.0.0.1/"
      "ldapi:///"
    ];

    settings = {
      attrs = {
        olcLogLevel = "conns config";
        olcLocalSSF = "128";
      };

      children = {
        # posixAccount / posixGroup are defined in nis.ldif.
        "cn=schema".includes = [
          "${pkgs.openldap}/etc/schema/core.ldif"
          "${pkgs.openldap}/etc/schema/cosine.ldif"
          "${pkgs.openldap}/etc/schema/inetorgperson.ldif"
          "${pkgs.openldap}/etc/schema/nis.ldif"
        ];

        "olcDatabase={0}config".attrs = {
          objectClass = [ "olcDatabaseConfig" ];
          olcDatabase = "{0}config";
          olcRootDN = configAdmin;
          olcRootPW.path = config.sops.secrets."ldap-admin-password".path;
          olcAccess = [
            ''
              {0}to *
                by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
                by dn.exact="${configAdmin}" manage
                by * none''
          ];
        };

        "olcDatabase={1}mdb".attrs = {
          objectClass = [
            "olcDatabaseConfig"
            "olcMdbConfig"
          ];
          olcDatabase = "{1}mdb";
          olcDbDirectory = "/var/lib/openldap/data";

          olcSuffix = base;

          olcRootDN = dataAdmin;
          olcRootPW.path = config.sops.secrets."ldap-admin-password".path;

          # Access is expressed with explicit DNs. `group.exact=` is avoided on
          # purpose: groups here are posixGroup/memberUid, which group.exact=
          # does not match, so a group-based rule would silently deny everything.
          #
          # cn=admin,cn=config is allowed to write here purely so ldap-init can
          # populate the tree before dataAdmin exists. It is not a privilege
          # boundary: that DN can already rewrite these very rules.
          olcAccess = [
            ''
              {0}to attrs=userPassword
                by self write
                by dn.exact="${dataAdmin}" write
                by dn.exact="${configAdmin}" write
                by anonymous auth
                by * none''

            ''
              {1}to *
                by dn.exact="${dataAdmin}" manage
                by dn.exact="${configAdmin}" write
                by dn.exact="${ncService}" read
                by users read
                by * none''
          ];
        };
      };
    };
  };

  # Seeds the tree after slapd is up, and is idempotent so a rebuild is a no-op
  # once the base entries exist.
  #
  # The LDIF is rendered at runtime rather than with pkgs.writeText because
  # writeText would bake the passwords into the world-readable Nix store.
  systemd.services.ldap-init = {
    wantedBy = [ "multi-user.target" ];
    after = [ "openldap.service" ];
    requires = [ "openldap.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    path = ldapTools;
    script = ''
      set -euo pipefail

      if ldapsearch -x -H ldap://127.0.0.1/ -b '${base}' -s base dn >/dev/null 2>&1; then
        echo "ldap-init: ${base} already present, skipping seed"
        exit 0
      fi

      umask 0077
      rendered=$(mktemp /run/ldap-seed.XXXXXX.ldif)
      trap 'rm -f "$rendered" "$rendered".d' EXIT
      sed \
        -e "s|@ADMIN_PASSWORD@|$(cat ${config.sops.secrets."ldap-admin-password".path})|" \
        -e "s|@NEXTCLOUD_PASSWORD@|$(cat ${config.sops.secrets."ldap-nextcloud-password".path})|" \
        ${seedTemplate} > "$rendered"

      # Entries are added one at a time so a partially applied seed can be
      # completed by re-running: ldapadd aborts the whole file on the first
      # duplicate, which would strand everything after it. 68 is
      # entryAlreadyExists and is the expected outcome on a rebuild.
      bind_pw=$(cat ${config.sops.secrets."ldap-admin-password".path})
      csplit -s -z -f "$rendered.d" -b '%02d.ldif' "$rendered" '/^dn: /' '{*}' || true
      for f in "$rendered".d*.ldif; do
        [ -s "$f" ] || continue
        # `if ! cmd; then rc=$?` would capture the negated status, so the
        # failure code has to be captured before it is inspected.
        rc=0
        ldapadd -x -H ldap://127.0.0.1/ -D '${configAdmin}' -w "$bind_pw" -f "$f" || rc=$?
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 68 ]; then
          echo "ldap-init: failed to add $(head -1 "$f") (exit $rc)" >&2
          exit "$rc"
        fi
      done
      echo "ldap-init: ${base} seeded"
    '';
  };
}