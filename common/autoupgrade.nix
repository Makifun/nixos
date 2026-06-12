{ ... }:
{
  system.autoUpgrade = {
    flake = "github:makifun/nixos";
    enable = true;
    randomizedDelaySec = "30min";
    allowReboot = false;
    rebootWindow = {
      lower = "03:00";
      upper = "06:00";
    };
  };
}
