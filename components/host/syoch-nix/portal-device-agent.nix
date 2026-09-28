{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.portal-device-agent;
  portalPkg = inputs.syoch-infra.packages.${pkgs.stdenv.hostPlatform.system}.portal;
  agentPkg = inputs.syoch-infra.packages.${pkgs.stdenv.hostPlatform.system}.portal-device-agent;
  opencodeTool = "${portalPkg}/bin/portal-opencode-tool";

  opencodeOperations = [
    {
      id = "opencode.feedback";
      name = "Send Feedback";
      group = "opencode";
      description = "Inject a feedback prompt into a pinned OpenCode session";
      command = [ opencodeTool "feedback" "--session-id" "{session_id}" "--prompt" "{prompt}" ];
      shell = false;
      timeout_seconds = 30;
      params_schema = {
        type = "object";
        required = [ "session_id" "prompt" ];
        properties = {
          session_id = { type = "string"; title = "Session ID"; };
          prompt = { type = "string"; title = "Prompt"; ui_hint = { widget = "textarea"; }; };
        };
      };
      ui_hint = { kind = "form"; label = "Send Feedback"; };
    }
    {
      id = "opencode.list_sessions";
      name = "List Sessions";
      group = "opencode";
      description = "List OpenCode sessions for a directory";
      command = [ opencodeTool "list-sessions" "--directory" "{directory}" ];
      shell = false;
      params_schema = {
        type = "object";
        properties = { directory = { type = "string"; title = "Directory (optional)"; }; };
      };
      ui_hint = { kind = "form"; label = "List Sessions"; };
    }
    {
      id = "opencode.webui_url";
      name = "WebUI URL";
      group = "opencode";
      description = "Report the OpenCode WebUI base URL and server key";
      command = [ opencodeTool "webui-url" ];
      shell = false;
      params_schema = { type = "object"; properties = { }; };
      ui_hint = { kind = "button"; label = "WebUI URL"; };
    }
    {
      id = "traits.opencode-bridge";
      name = "OpenCode Bridge Trait";
      group = "opencode";
      description = "Advertise the opencode-bridge operation keys and WebUI info";
      command = [ opencodeTool "traits" ];
      shell = false;
      params_schema = { type = "object"; properties = { }; };
      ui_hint = { kind = "button"; label = "Traits"; };
    }
  ];

  agentConfig = {
    device_id = cfg.deviceId;
    display_name = cfg.displayName;
    server_url = cfg.serverUrl;
    bootstrap_token_file = cfg.bootstrapTokenFile;
    credentials_file = "${cfg.stateDirectory}/credentials.json";
    operations = opencodeOperations ++ cfg.extraOperations;
  };

  configFile = pkgs.writeText "portal-device-agent.json" (builtins.toJSON agentConfig);
in
{
  options.services.portal-device-agent = {
    enable = lib.mkEnableOption "the portal device agent (generic operations for this device)";

    deviceId = lib.mkOption {
      type = lib.types.str;
      default = "opencode-bridge";
      description = "Control-plane device id.";
    };

    displayName = lib.mkOption {
      type = lib.types.str;
      default = "OpenCode Bridge";
    };

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://portal.syoch.org";
      description = "Portal base URL reachable without Cloudflare Access (VPN / tailnet).";
    };

    opencodeUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:12000";
      description = "Local OpenCode server base URL (passed to portal-opencode-tool).";
    };

    webuiBaseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Browser-facing OpenCode WebUI base URL (defaults to opencodeUrl).";
    };

    bootstrapTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "File with the one-time bootstrap token (from sops).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "syoch";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/portal-device-agent";
    };

    extraOperations = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Additional device-agent operations (same schema as the agent config).";
    };

    extraPath = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra packages appended to the service PATH (for operation commands).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.portal-device-agent = {
      description = "Portal device agent (${
        cfg.deviceId
      }: opencode-bridge + configured operations)";
      after = [ "network-online.target" "sops-nix.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ agentPkg portalPkg pkgs.bash pkgs.coreutils ] ++ cfg.extraPath;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        StateDirectory = "portal-device-agent";
        StateDirectoryMode = "0700";

        ExecStart = "${agentPkg}/bin/portal-device-agent --config ${configFile}";
        Restart = "always";
        RestartSec = 5;

        Environment = [
          "OPENCODE_URL=${cfg.opencodeUrl}"
          "OPENCODE_WEBUI_BASE_URL=${if cfg.webuiBaseUrl != null then cfg.webuiBaseUrl else cfg.opencodeUrl}"
          "XDG_RUNTIME_DIR=/run/user/1000"
        ];

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        UMask = "0077";
      };
    };
  };
}
