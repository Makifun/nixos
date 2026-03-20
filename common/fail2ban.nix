{ ... }:
{
  services.fail2ban = {
    enable = true;
    maxretry = 10;
    bantime-increment.enable = true;
  };
}
