{ config, lib, pkgs, ... }:

let
  cfg = config.services.talk-bridge;
  # ../talk-bridge because this module lives in services/, the source in the
  # sibling talk-bridge/ directory.
  src = ../talk-bridge/src;
in
{
  options.services.talk-bridge = {
    enable = lib.mkEnableOption "NextCloud Talk <-> opencode bridge";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8787;
      description = "Loopback port the bridge listens on.";
    };

    nextcloudUrl = lib.mkOption {
      type = lib.types.str;
      description = "Base URL of the NextCloud instance Talk runs in.";
    };

    # Two distinct directories, and conflating them breaks occ:
    #
    #   configDatadir  = services.nextcloud.datadir (/var/lib/nextcloud)
    #       State dir. Holds config.php, which the occ wrapper reaches via
    #       NEXTCLOUD_CONFIG_DIR=<configDatadir>/config.
    #
    #   dataDirectory  = settings.datadirectory (/srv/NAS/nextcloud)
    #       User file storage. NextCloud's permission check probes this for
    #       writability on every occ invocation ("Your data directory is not
    #       writable"), so it must ALSO be writable by the service user.
    #
    # Only the first is a module option; the second lives in `settings`, so it
    # is read from there rather than hardcoded.
    configDatadir = lib.mkOption {
      type = lib.types.str;
      default = config.services.nextcloud.datadir;
      defaultText = lib.literalExpression "config.services.nextcloud.datadir";
      description = ''
        NextCloud state directory. The occ wrapper sets
        NEXTCLOUD_CONFIG_DIR to <configDatadir>/config, so this path must be
        writable by the service user.
      '';
    };

    dataDirectory = lib.mkOption {
      type = lib.types.str;
      default = config.services.nextcloud.settings.datadirectory;
      defaultText = lib.literalExpression "config.services.nextcloud.settings.datadirectory";
      description = ''
        NextCloud user file storage (config.php datadirectory). Checked for
        writability by occ on every run, so it must be writable too.
      '';
    };

    opencodeUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:12000";
      description = "Default opencode server that hosts role sessions.";
    };

    agent = lib.mkOption {
      type = lib.types.str;
      # Empty = the session's own agent. Role identity is prompt-level, so this
      # only controls capability. Hardcoding `general` here would quietly strip
      # the tools of any session a role gets bound to.
      default = "";
      example = "build";
description = ''
          opencode agent used for role turns. Leave empty to let each session use
          its own agent, which is the default and the right choice when a role is
          bound to a pre-existing session.
        '';
    };

    delegateBudget = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 12;
      description = ''
        Maximum number of delegated role turns spawned from one human message.
        Delegation is explicit (talk-delegate), so a chain only grows when an
        agent deliberately asks another role; this bounds a runaway
        lead<->specialist loop. The counter resets on each human message.
      '';
    };

    humanUser = lib.mkOption {
      type = lib.types.str;
      default = "syoch";
      description = "NextCloud user id added to every new venue conversation.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString cfg.port}";
      description = "Base URL Talk uses to reach this bridge for bot webhooks. Must be reachable from the NextCloud process on this host.";
    };
  };

  config = lib.mkIf cfg.enable {
    # The bridge runs as `nextcloud`, not as a dedicated user.
    #
    # Reason: the nixpkgs `nextcloud-occ` wrapper escalates to the `nextcloud`
    # user, and when it does it execs `env NEXTCLOUD_CONFIG_DIR=... php occ ...`
    # -- NOT the wrapper path. A sudoers rule on the wrapper would therefore
    # never match, and the bridge (unprivileged, non-interactive) would fail
    # every occ call. Being `nextcloud` makes the wrapper take its final
    # `exec $command` branch with no escalation at all.
    #
    # This is acceptable because the bridge is a dumb HTTP relay: it has no
    # tool access and cannot execute code as `nextcloud`. It only reads the
    # NextCloud config dir via occ, which is exactly what occ needs.
    #
    # Dedicated database + role, following the portal pattern. The password is
    # applied from SOPS by postgresql-setup-passwords (see pgsql.nix).
    services.postgresql.ensureDatabases = [ "syoch-talk" ];
    services.postgresql.ensureUsers = [
      {
        name = "syoch-talk";
        ensureDBOwnership = true;
      }
    ];
    # portal.nix sets services.postgresql.authentication as a plain string,
    # which replaces the nixpkgs default (including the 127.0.0.1/32 rule).
    # Append rather than overwrite so TCP auth keeps working.
    services.postgresql.authentication = lib.mkAfter ''
      host syoch-talk syoch-talk 127.0.0.1/32 scram-sha-256
    '';

      systemd.services.talk-bridge = {
        description = "NextCloud Talk <-> opencode bridge";
        wantedBy = [ "multi-user.target" ];
        # postgresql-setup-passwords must run first: without the role password
        # the bridge's first query fails and systemd restarts it in a loop.
        after = [
          "network.target"
          "postgresql.service"
          "nextcloud.service"
          "postgresql-setup-passwords.service"
        ];
        wants = [
          "postgresql.service"
          "postgresql-setup-passwords.service"
        ];

      serviceConfig = {
        Type = "simple";
        User = "nextcloud";
        Group = "nextcloud";
        # `occ` writes to the NextCloud config dir and occasionally reads $HOME.
        Environment = [
          "BRIDGE_PORT=${toString cfg.port}"
          "BRIDGE_PUBLIC_URL=${cfg.publicUrl}"
          "NEXTCLOUD_URL=${cfg.nextcloudUrl}"
          "OPENCODE_URL=${cfg.opencodeUrl}"
          "NEXTCLOUD_HUMAN_USER=${cfg.humanUser}"
          # Empty means "use the session's own agent". That is what lets a role
          # be bound to an existing session without silently downgrading it to
          # `general` and losing that session's tool access.
          "BRIDGE_AGENT=${cfg.agent}"
          # Delegation is explicit (talk-delegate); this bounds the delegated
          # turns spawned from one human message so a loop cannot run forever.
          "BRIDGE_DELEGATE_BUDGET=${toString cfg.delegateBudget}"
          # occ and php expect $HOME to be the instance home.
          "HOME=${cfg.configDatadir}"
        ];
        Restart = "on-failure";
        RestartSec = "5";
        RuntimeDirectory = "talk-bridge";
        RuntimeDirectoryMode = "0700";
        # Hardening. `occ` needs to read the NextCloud tree and write its
        # config, so ProtectSystem stays "strict" but NextCloud's datadir and
        # the runtime directory are the only writable exceptions.
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "%t/talk-bridge"
          # config.php lives here.
          cfg.configDatadir
          # NextCloud's writability probe targets the user data dir.
          cfg.dataDirectory
        ];
        PrivateDevices = true;
        NoNewPrivileges = true;
        RestrictNamespaces = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        SystemCallFilter = [ "@system-service" ];
      };

      # Loopback only: the webhook and control API must never be reachable
      # from outside this host. Enforced by the socket bind in the bridge
      # itself (hostname: 127.0.0.1), not by firewall rules.

      # The DB password must not sit in the unit's Environment= (it would be
      # visible via `systemctl show`). Read it here and write a complete
      # connection URL into a 0600 file under RuntimeDirectory, then source it.
      preStart = ''
        set -o errexit
        secret="$(cat ${config.sops.secrets."talk-db-password".path})"
        escaped="$(printf '%s' "$secret" | sed -e 's/[\\^$.*+?(){}[\]|]/\\&/g')"
        umask 0077
        printf 'export TALK_DB_URL="postgresql://syoch-talk:%s@127.0.0.1:5432/syoch-talk"\n' \
          "$escaped" > "$RUNTIME_DIRECTORY/db-url.sh"
      '';

      # `nextcloud-occ` comes from the NextCloud NixOS module via
      # environment.systemPackages; occ needs the php extensions that module
      # configures, so the bridge must reuse that wrapper rather than call
      # php directly.
      path = [
        pkgs.bun
        pkgs.postgresql
        # `nextcloud-occ` is provided by the NextCloud module through
        # environment.systemPackages; php + its extensions come with it.
        config.services.nextcloud.occ
      ];

      script = ''
        set -o errexit
        # shellcheck disable=SC1091
        . "$RUNTIME_DIRECTORY/db-url.sh"
        exec bun ${src}/index.ts
      '';
    };
  };
}