{ ... }:
{
  system.autoUpgrade = {
    flake = "github:makifun/nixos";
    enable = true;
    randomizedDelaySec = "60min";
    allowReboot = false;
  };
}
