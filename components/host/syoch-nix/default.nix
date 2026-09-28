{ pkgs, config, ... }:
{
  system.stateVersion = "25.11";

  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./secrets.nix
    ./de.nix
    ./wifi.nix
    ./vm-lab.nix
    ./cloudflared.nix
    ./portal-device-agent.nix
  ];

  nixpkgs.config.allowUnfree = true;

  # config
  os-mod.system.enable = true;
  os-mod.system.allowWheelToRunSudo = true;

  os-mod.user-syoch.enable = true;
  os-mod.sshd.enable = true;
  os-mod.pipewire.enable = true;
  os-mod.i18n-jp.enable = true;
  os-mod.bluetooth.enable = true;
  os-mod.libvirtd.enable = true;
  os-mod.tailscale.enable = true;

  programs.vim.enable = true;
  programs.htop.enable = true;
  programs.wireshark.enable = true;
  programs.git.enable = true;

  services.libinput.enable = true;
  services.upower.enable = true;
  services.flatpak.enable = true;

  virtualisation.docker.enable = true;

  networking.hostName = "laptop";
  servers.domain = "syoch.org";
  networking.networkmanager.enable = true;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  nix.settings.extra-sandbox-paths = [
    "/nix/var/cache/ccache"
  ];

  services.cloudflared.enable = true;

  # Portal device agent: one generic agent per device. It exposes the OpenCode
  # feedback operations (via portal-opencode-tool) plus any local operations.
  services.portal-device-agent = {
    enable = true;
    bootstrapTokenFile = config.sops.secrets."portal-opencode-bridge-token".path;
    extraPath = [ pkgs.hyprland ];
    deviceId = "syoch-laptop";
    extraOperations = [
      {
        id = "sys.dpms_toggle";
        name = "Toggle DPMS";
        group = "system";
        description = "Toggle monitor DPMS power (Hyprland)";
        shell = true;
        timeout_seconds = 10;
        # Discover the Hyprland instance signature from the user runtime dir.
        command = ''
          export HYPRLAND_INSTANCE_SIGNATURE="''${HYPRLAND_INSTANCE_SIGNATURE:-$(basename "$(ls -d "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/ 2>/dev/null | head -n1)")}"
          exec hyprctl dispatch dpms toggle
        '';
        params_schema = {
          type = "object";
          properties = { };
        };
        ui_hint = {
          kind = "button";
          label = "Toggle DPMS";
        };
      }
    ];
  };

  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1w"
  ];

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    openssl
    gobject-introspection
    nss
    nspr
  ];

  services.udev.extraRules = ''
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="374b", MODE="0666"
  '';

  nix.settings.substituters = [
    "https://nnctrobo.cachix.org"
  ];
  nix.settings.trusted-public-keys = [
    "nnctrobo.cachix.org-1:1dKKIMpU2HT8hYTQVOxaE8YGT1rVvHpZNjgkMCrIRzM="
  ];

  services.resolved.enable = false;

  sops.secrets."netbird-wt0-setup-key" = {
    owner = "root";
    path = "/etc/nixos/netbird-wt0-setup-key";
  };
  services.netbird.clients.wt0 = {
    login = {
      enable = true;
      setupKeyFile = config.sops.secrets."netbird-wt0-setup-key".path;
    };
    port = 51821;
    ui.enable = false;
    dns-resolver.address = "127.0.0.53";
    dns-resolver.port = 5053;
    openFirewall = true;
    openInternalFirewall = true;
  };

  services.blocky = {
    enable = true;
    settings = {
      ports.dns = 54; # Port for incoming DNS Queries.
      upstreams.groups.default = [
        "https://one.one.one.one/dns-query" # Using Cloudflare's DNS over HTTPS server for resolving queries.
      ];
      # For initially solving DoH/DoT Requests when no system Resolver is available.
      bootstrapDns = {
        upstream = "https://one.one.one.one/dns-query";
        ips = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
      #Enable Blocking of certain domains.
      blocking = {
        denylists = {
          #Adblocking
          ads = [ "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" ];
          #Another filter for blocking adult sites
          adult = [ "https://blocklistproject.github.io/Lists/porn.txt" ];
          #You can add additional categories
        };
        #Configure what block categories are used
        clientGroupsBlock = {
          default = [ "ads" ];
          kids-ipad = [
            "ads"
            "adult"
          ];
        };
      };
    };
  };

  services.dnsmasq = {
    enable = true;
    settings.bind-interfaces = true;
    settings.interface = "lo";
    servers = [
      "/nnctrobo.internal/127.0.0.53#5053"
      # "/syoch.org/10.42.0.1"
      "127.0.0.1#54"
    ];
  };

  programs.steam = {
    enable = true;
  };

  networking.hosts = {
    "10.50.10.1" = [
      "sv01.nnctrobo.internal"
      "id.nnctrobo.internal"
      "nextcloud.nnctrobo.internal"
      "nextcloud-wb.nnctrobo.internal"
      "smb.nnctrobo.internal"
      "luminary.nnctrobo.internal"
    ];
    "10.42.0.1" = [
      "sv01.syoch.org"
      "files.pri.syoch.org"
    ];
    "127.0.0.1" = [
      "z-procon-main.syoch.org"
      "opencode.syoch.org"
      "code.syoch.org"
    ];
  };

  services.nginx.enable = true;
  services.nginx.clientMaxBodySize = "1G";
  services.nginx.recommendedProxySettings = true;
  services.nginx.recommendedTlsSettings = true;
  services.nginx.appendHttpConfig = ''
    log_format main escape=json '{'
        '"time":"$time_iso8601",'                    # 日時（ISO8601形式）
        '"client_ip":"$remote_addr",'                # クライアントIP
        '"forwarded_for":"$http_x_forwarded_for",'    # X-Forwarded-Forヘッダ
        '"host":"$http_host",'                       # Hostヘッダ
        '"method":"$request_method",'                # HTTPメソッド（GET/POSTなど）
        '"uri":"$request_uri",'                      # リクエストURI
        '"status":$status,'                          # ステータスコード
        '"body_bytes":$body_bytes_sent,'             # 送信バイト数
        '"referer":"$http_referer",'                 # Refererヘッダ
        '"user_agent":"$http_user_agent",'           # User-Agentヘッダ
        '"request_time":$request_time,'              # NGINX全体の処理時間
        '"upstream_time":"$upstream_response_time",'  # アプリ側の処理時間
        '"request_id":"$request_id"'                 # リクエスト一意ID
    '}';
    access_log /var/log/nginx/access.log main;

  '';

  sops.secrets."acme-env" = {
    owner = "root";
    path = "/etc/nixos/acme.env";
  };
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "syoch64@gmail.com";
  security.acme.defaults.dnsProvider = "cloudflare";
  security.acme.defaults.environmentFile = config.sops.secrets."acme-env".path;
  servers.hosts.code = {
    ssl = "dns-01";
    upstream = "http://localhost:9101";
  };
  servers.hosts.opencode = {
    ssl = "dns-01";
    upstream = "http://localhost:12000";
  };
  servers.hosts."z-procon-main" = {
    ssl = "dns-01";
    upstream = "http://localhost:10002";
  };
  environment.systemPackages = with pkgs; [
    wget
    jq
    ruff
    python314
    gnumake
    ghq
    binwalk
    nixfmt
    brightnessctl
    hexyl
    fastfetch
    ddcutil
    netdiscover
    displaylink
    socat
    file
    ffmpeg
    github-desktop
    keepassxc
    cifs-utils
    wshowkeys
    tetrio-desktop
    techmino
    ntfs3g
  ];
}
