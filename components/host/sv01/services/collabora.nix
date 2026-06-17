{
  services.collabora-online = {
    enable = true;
    port = 12003;
    settings.ssl.enable = false;
    settings.storage.wopi = {
      "@allow" = true;
      host = [
        "collabora.syoch.org"
      ];
    };
  };
  services.nginx.virtualHosts."collabora.syoch.org" = {
    listenAddresses = [
      "0.0.0.0"
      "[::0]"
    ];
    locations."/" = {
      proxyPass = "http://127.0.0.1:12003";
      proxyWebsockets = true;
    };
  };
}
