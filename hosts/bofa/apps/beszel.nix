{ config, ... }:
{
  sops.secrets.beszel_agent_key.sopsFile = ../secrets.yaml;

  systemd.tmpfiles.rules = [
    "d '/bofa/.beszelbofa' 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent.volumes = [
    "/bofa/.beszelbofa:/extra-filesystems/bofa__bofa:ro"
  ];
}
