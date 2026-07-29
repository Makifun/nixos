{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = map (f: ./. + "/${f}") (
    builtins.filter (f: f != "default.nix" && lib.hasSuffix ".nix" f) (
      builtins.attrNames (builtins.readDir ./.)
    )
  );
  time.timeZone = "Europe/Stockholm";
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "@wheel" ];
    };
  };
  networking = {
    enableIPv6 = false;
    nftables.enable = true;
    timeServers = [
      "sth1.ntp.se"
      "sth2.ntp.se"
      "gbg1.ntp.se"
      "gbg2.ntp.se"
    ];
  };
  environment = {
    systemPackages = with pkgs; [
      bat
      btop
      git
      jq
      ncdu
      nh
      nmap
      parted
      python3
      ripgrep
      screen
      tree
      vim
    ];
  };
  systemd.tmpfiles.rules = [
    "d '/${config.networking.hostName}/${config.networking.hostName}' 0755 root root - -"
  ];
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
    ];
    files = [
      "/etc/machine-id"
    ];
  };
  services.journald.extraConfig = ''
    SystemMaxUse=512M
    MaxRetentionSec=7day
    MaxFileSec=1day
  '';
  sops.secrets.initrd_ssh_host_ed25519_key = {
    format = "yaml";
    sopsFile = ../hosts/${config.networking.hostName}/secrets.yaml;
  };
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep-since 4d --keep 3";
    };
    flake = "github:makifun/nixos";
  };
}
