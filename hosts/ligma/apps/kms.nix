{
  config,
  pkgs,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  kmsBase = "/${hostname}/${hostname}/kms";
  kmsPort = 4050;
  # renovate: datasource=docker depName=ghcr.io/siderolabs/kms-server
  kmsTag = "v0.1.0";
in
{
  systemd.tmpfiles.rules = [
    "d '${kmsBase}' 0700 root root - -"
  ];

  # Generate a random 32-byte key on first boot.
  # The key persists in zstorage (backed up by Backrest).
  # Back it up manually before wiping zstorage.
  systemd.services.kms-key-setup = {
    description = "Generate KMS key on first run";
    before = [ "podman-kms.service" ];
    requiredBy = [ "podman-kms.service" ];
    after = [
      "local-fs.target"
      "zfs-mount.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      if [ ! -f ${kmsBase}/kms.key ]; then
        dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 -w 0 > ${kmsBase}/kms.key
        chmod 400 ${kmsBase}/kms.key
      fi
    '';
  };

  virtualisation.oci-containers.containers.kms = {
    image = "ghcr.io/siderolabs/kms-server:${kmsTag}";
    ports = [ "${hosts.ligma}:${toString kmsPort}:${toString kmsPort}" ];
    volumes = [ "${kmsBase}:/data:ro" ];
    cmd = [
      "--kms-api-endpoint=0.0.0.0:${toString kmsPort}"
      "--key-path=/data/kms.key"
    ];
  };

  # Allow sugma01 to reach the KMS server at boot.
  networking.firewall.extraInputRules = ''
    ip saddr 10.10.10.26/32 tcp dport ${toString kmsPort} accept
  '';
}
