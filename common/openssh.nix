{ ... }:
{
  systemd.tmpfiles.rules = [
    "d /persist/etc/ssh 0755 root root -"
  ];
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      AllowGroups = [ "wheel" ];
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
    };
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };
}
