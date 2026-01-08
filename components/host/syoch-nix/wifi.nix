{
  networking.networkmanager.ensureProfiles.profiles = {
    "syoch AP" = {
      connection.id = "syoch AP";
      connection.type = "wifi";
      wifi.ssid = "$my_ssid";
      wifi-security = {
        auth-alg = "open";
        key-mgmt = "wpa-psk";
        psk = "$my_psk";
      };
    };
    "Home AP" = {
      connection.id = "Home AP";
      connection.type = "wifi";
      wifi.ssid = "$home_ssid";
      wifi-security = {
        auth-alg = "open";
        key-mgmt = "wpa-psk";
        psk = "$home_psk";
      };
    };
    "Phone Tethering" = {
      connection.id = "Pixel8 Tethering";
      connection.type = "wifi";
      wifi.ssid = "$tether_ssid";
      wifi-security = {
        auth-alg = "open";
        key-mgmt = "wpa-psk";
        psk = "$tether_psk";
      };
    };
  };
}
