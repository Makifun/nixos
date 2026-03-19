{ ... }:
{
  boot = {
    blacklistedKernelModules = [
      "dccp"
      "sctp"
      "rds"
      "tipc"
    ];
    kernel.sysctl = {
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
      "fs.suid_dumpable" = false;
      "kernel.kptr_restrict" = 2;
      "kernel.sysrq" = false;
      "kernel.unprivileged_bpf_disabled" = true;
      "net.core.bpf_jit_harden" = 2;
      "net.ipv4.conf.all.accept_redirects" = false;
      "net.ipv4.conf.default.accept_redirects" = false;
      "net.ipv6.conf.all.accept_redirects" = false;
      "net.ipv6.conf.default.accept_redirects" = false;
      "net.ipv4.conf.all.log_martians" = true;
      "net.ipv4.conf.default.log_martians" = true;
      "net.ipv4.conf.all.rp_filter" = true;
      "net.ipv4.conf.all.send_redirects" = false;
    };
  };
  fileSystems."/proc" = {
    device = "proc";
    fsType = "proc";
    options = [
      "defaults"
      "hidepid=2"
    ];
  };
  services.dbus.implementation = "broker";
  systemd.services = {
    systemd-rfkill = {
      serviceConfig = {
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        PrivateTmp = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        LockPersonality = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
        IPAddressDeny = "any";
      };
    };
    systemd-journald = {
      serviceConfig = {
        UMask = 0077;
        PrivateNetwork = true;
        ProtectHostname = true;
        ProtectKernelModules = true;
      };
    };
  };
}
