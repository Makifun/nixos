{
  config,
  hosts,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.arrma.dnsRecords;
  tsigKeyFile = config.sops.secrets.technitium-tsig-key.path;
  server = hosts.technitium;
  zone = "makifun.se";
  keyName = "arrma-key";

  mkService =
    fqdn: opts:
    lib.nameValuePair "dns-record-${lib.replaceStrings [ "." ] [ "-" ] fqdn}" {
      description = "DNS record: ${fqdn} -> ${opts.value}";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitIntervalSec = 0;
      };
      path = [ pkgs.bind.dnsutils ];
      script = ''
        nsupdate -y "hmac-sha256:${keyName}:$(tr -d '\n' < ${tsigKeyFile})" <<EOF
        server ${server}
        zone ${zone}.
        update delete ${fqdn}. ${opts.type}
        update add ${fqdn}. ${toString opts.ttl} ${opts.type} ${opts.value}
        send
        EOF
      '';
    };
in
{
  options.arrma.dnsRecords = lib.mkOption {
    description = "DNS records to maintain in Technitium via nsupdate/TSIG.";
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          type = lib.mkOption {
            type = lib.types.str;
            default = "A";
          };
          value = lib.mkOption {
            type = lib.types.str;
            description = "Record value (IP for A records).";
          };
          ttl = lib.mkOption {
            type = lib.types.int;
            default = 3600;
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg != { }) {
    sops.secrets.technitium-tsig-key = {
      format = "yaml";
      sopsFile = ./secrets.yaml;
    };

    systemd.services = lib.mapAttrs' mkService cfg;
  };
}
