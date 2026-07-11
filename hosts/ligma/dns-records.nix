# ---------------------------------------------------------------------------
# DNS record maintenance via nsupdate + TSIG against Technitium at 10.10.10.3
#
# Each app .nix sets:
#   ligma.dnsRecords."foo.makifun.se".value = "<ip>";
#
# Prerequisites (one-time, manual):
#   1. Generate key:
#        nix run nixpkgs#bind -- tsig-keygen -a hmac-sha256 ligma-key
#      Note only the base64 secret (the "secret" line).
#   2. Technitium WebGUI → Zones → makifun.se → TSIG Keys: add ligma-key
#   3. Enable "Allow Dynamic Updates" on the zone, restrict to ligma-key TSIG
#   4. Add SOPS secret:
#        sops hosts/ligma/secrets.yaml
#        technitium-tsig-key: <base64-secret>
# ---------------------------------------------------------------------------
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ligma.dnsRecords;
  tsigKeyFile = config.sops.secrets.technitium-tsig-key.path;
  server = "10.10.10.3";
  zone = "makifun.se";
  keyName = "ligma-key";

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
      path = [ pkgs.bind ];
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
  options.ligma.dnsRecords = lib.mkOption {
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
