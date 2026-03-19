{ ... }:
{
  services.fail2ban = {
    enable = true;
    maxretry = 5;
  };
}
