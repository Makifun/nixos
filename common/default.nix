{ pkgs, ... }:
{
  imports = [
    ./boot.nix
    ./fail2ban.nix
    ./hardening.nix
    ./openssh.nix
    ./users.nix
  ];
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
      starship
      btop
      screen
      nmap
      git
      nh
      ncdu
    ];
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
