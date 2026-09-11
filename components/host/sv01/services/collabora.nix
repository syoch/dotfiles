{ config, ... }: {
  services.collabora-online = {
    enable = true;
    port = 12003;
    settings.ssl.enable = false;
    settings.ssl.termination = true;
    settings.storage.wopi = {
      "@allow" = true;
      host = [
        config.servers.hosts."collabora".fqdn
      ];
    };
  };
  servers.hosts."collabora" = {
    ssl = "dns-01";
    upstream = "http://127.0.0.1:12003";
  };
}
