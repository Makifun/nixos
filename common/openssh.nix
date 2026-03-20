{ ... }:
{
  systemd.tmpfiles.rules = [
    "d /persist/etc/ssh 0755 root root -"
  ];
  networking.firewall = {
    extraInputRules = ''
      ip saddr 10.10.10.0/24 tcp dport 22 accept comment "SSH local access"
    '';
  };
  services.openssh = {
    enable = true;
    allowSFTP = false;
    ports = [ 22 ];
    openFirewall = false;
    settings = {
      AllowGroups = [ "wheel" ];
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      LogLevel = "VERBOSE";
      PermitRootLogin = "no";
      KexAlgorithms = [
        "curve25519-sha256@libssh.org"
        "ecdh-sha2-nistp521"
        "ecdh-sha2-nistp384"
        "ecdh-sha2-nistp256"
        "diffie-hellman-group-exchange-sha256"
      ];
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
        "aes256-ctr"
        "aes192-ctr"
        "aes128-ctr"
      ];
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
        "umac-128-etm@openssh.com"
        "hmac-sha2-512"
        "hmac-sha2-256"
        "umac-128@openssh.com"
      ];
    };
    extraConfig = ''
      ClientAliveCountMax 2
      ClientAliveInterval 300
      AllowTcpForwarding no
      AllowAgentForwarding no
      MaxAuthTries 3
      MaxSessions 2
      TCPKeepAlive no
    '';
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };
}
