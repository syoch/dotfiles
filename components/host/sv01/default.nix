{ config, pkgs, ... }:

{
  system.stateVersion = "25.11";

  imports = [
    ./hardware-configuration.nix
    ./secrets.nix
    ./cloudflared.nix
    ./nnctrobo.nix
    ./services/collabora.nix
    ./services/nextcloud.nix
    ./services/pgsql.nix
    ./services/portal.nix
  ];

  # Config
  os-mod.system.enable = true;
  os-mod.system.allowWheelToRunSudo = true;
  security.sudo.wheelNeedsPassword = false;

  os-mod.user-syoch.enable = true;

  os-mod.tailscale.enable = true;
  services.tailscale.extraSetFlags = [ "--advertise-routes=10.42.0.0/16" ];
  os-mod.sshd.enable = true;

  programs.tmux.enable = true;

  networking.hostName = "sv01";
  servers.domain = "syoch.org";
  networking.domain = config.servers.domain;
  networking.networkmanager.enable = true;

  fileSystems."/boot/efi".options = [ "nofail" ];

  users.groups.nas-agent = { };
  users.users.syoch.extraGroups = [ "nas-agent" ];
  users.users.nextcloud.extraGroups = [ "nas-agent" ];

  os-mod.router = {
    enable = true;
    upstream.interface = "enp0s31f6";
    downstream.interface = "enp0s20f0u4u4i5";
    downstream.ipAddress = "10.42.0.1";
    downstream.prefixLength = 16;
    downstream.dhcpRangeStart = "10.42.100.0";
    downstream.dhcpRangeEnd = "10.42.200.0";
    extraForwardableInterfaces = [ "wg-vpn" ];
  };

  services.dnsmasq = {
    enable = true;
    settings.bind-interfaces = true;
    settings.interface = "lo";
    servers = [
      "/${config.servers.domain}/10.42.0.1"
      "127.0.0.1#54"
    ];
  };
  networking.hosts = {
    "10.42.0.1" = [
      "${config.networking.hostName}.${config.servers.domain}"
      config.servers.hosts."nextcloud".fqdn
      config.servers.hosts."collabora".fqdn
      config.servers.hosts."portal".fqdn
      "db.${config.servers.domain}"
    ];
    "100.96.128.3" = [
      "laptop.syoch.org"
      "z-procon-main.syoch.org"
      "opencode.syoch.org"
      "code.syoch.org"
    ];
  };

  sops.secrets."acme-env" = {
    owner = "root";
    path = "/etc/nixos/acme.env";
  };
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "syoch64@gmail.com";
  security.acme.defaults.dnsProvider = "cloudflare";
  security.acme.defaults.environmentFile = config.sops.secrets."acme-env".path;

  os-mod.smb-server = {
    enable = true;
    serverName = "sv01";
    validUsers = [ "syoch" ];
    allowedIPs = [
      "10.42. "
      "100."
      "127.0.0.1"
      "localhost"
    ];
    folders.NAS = {
      path = "/srv/NAS";
    };
  };

  os-mod.nfs-server = {
    enable = true;
    openFirewall = true;
    exports."/srv/NAS" = {
      clients."100.96.128.3" = { };
      clients."10.42.0.0/16" = { };
    };
  };

  services.syncthing.enable = true;

  virtualisation.podman.enable = true;
  networking.firewall.interfaces."podman0".allowedTCPPorts = [ 5432 ];
  virtualisation.oci-containers.backend = "podman";

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

  environment.systemPackages = with pkgs; [
    neovim
    wget
    podman
  ];

  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans
  ];
}
