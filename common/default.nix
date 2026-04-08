{ pkgs, lib, ... }:
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
      screen
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
