{ ... }:
{
  imports = [
    ./boot.nix
    ./openssh.nix
    ./users.nix
  ];
  time.timeZone = "Europe/Stockholm";
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
}
