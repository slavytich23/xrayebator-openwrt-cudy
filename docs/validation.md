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

## Dual-network field evidence — 2026-09-07

A second field pass used the Cudy itself as the primary PPPoE router. LAN1 was
moved from `br-lan` to `br-vpn`; LAN2–LAN4 remained Direct. Two SSID names were
advertised on both 2.4 and 5 GHz, and the two legacy SSIDs were disabled only
after Ethernet and Direct Wi-Fi had independent working paths.

Fresh primary signals after the cutover:

- Ethernet received a `192.168.20.x` lease through `br-vpn`; Direct Wi-Fi
  received `192.168.10.x` through `br-lan`;
- WAN reported `pppoe-wan`, Xray stayed enabled/running and the policy rule was
  scoped to `br-vpn`/`192.168.20.0/24`;
- an isolated client in the router network namespace received HTTP responses
  through Xray, while Direct HTTP also passed; the two egress addresses differed;
- Windows network status and interface-bound HTTP passed on both adapters;
- six consecutive combined VPN/Direct/router-state samples had zero failures;
- both physical WAN and LAN1 links negotiated at 100 Mbit/s on this ISP/cable
  path, so this pass does not establish gigabit throughput.

This was a short cutover validation, not a long-duration reliability claim.

## Repository checks

`tests/run-all.ps1` verifies:

- PowerShell and POSIX shell syntax where WSL is available;
- staged rollback and fail-closed invariants;
- dual-network preflight/apply/rollback invariants and unified SSID wiring;
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
- long-duration stability of the dual-network topology.
