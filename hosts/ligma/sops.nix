{ ... }:
{
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      initrd_ssh_host_ed25519_key = {
        format = "yaml";
        sopsFile = ./secrets.yaml;
      };
      luks_password = {
        format = "yaml";
        sopsFile = ./secrets.yaml;
      };
    };
  };
}
