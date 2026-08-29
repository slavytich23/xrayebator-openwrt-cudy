# Validation record

## Field evidence

The initial implementation was validated on a Cudy WR3000H 1.0 with OpenWrt
25.12.x, behind another home router. The Windows PC used Cudy Ethernet as the
preferred route and the upstream router's Wi-Fi as fallback.

Observed controls after physical-link stabilization:

- 90 samples with no Ethernet-down, Cudy LAN or adapter-error event;
- 40/40 local LAN controls passed;
- 4/4 interface-bound HTTPS controls passed on each route;
- no WAN/LAN carrier delta during the final control.

XHTTP/XMUX memory control after setting `maxConnections: 1`:

- 1,805 seconds, 59 samples;
- 0 failed probes and 0 new supervisor incidents;
- unchanged Xray PID;
- maximum RSS 53,660 KiB;
- 5/5 replacement bulk downloads, 47,002,980 bytes total.

Earlier restarts occurred around 105–107 MiB RSS. These values describe one
device and configuration and must not be treated as universal limits.

## Repository checks

`tests/run-all.ps1` verifies:

- PowerShell and POSIX shell syntax where WSL is available;
- staged rollback and fail-closed invariants;
- WAN-aware restart and cooldown behavior;
- bound primary/backup HTTPS probes;
- absence of live client configuration and common secret patterns.

`tests/run-all.ps1 -Integration` additionally creates a temporary isolated
Linux network namespace, validates the policy route and nftables DNS capture,
removes the TUN device to prove the prohibit route remains, then verifies full
cleanup. It requires WSL/Linux root.

## Not proven by local tests

- compatibility with every OpenWrt release or router;
- behavior of every Xray transport or subscription client;
- ISP-specific filtering behavior after August 2026;
- live failover on a machine other than the original field deployment.
