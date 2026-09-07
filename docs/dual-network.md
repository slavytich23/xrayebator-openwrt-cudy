# Direct/VPN networks on one Cudy

This layout keeps an ordinary ISP path and a fail-closed Xray path on one
OpenWrt router:

```text
WAN/PPPoE
  ├─ br-lan  192.168.10.0/24: LAN2–LAN4 + Direct SSID on both radios
  └─ br-vpn  192.168.20.0/24: LAN1 + VPN SSID on both radios → Xray TUN
```

Both radios advertise the same Direct name and the same VPN name. A client
therefore sees two logical networks and chooses 2.4 or 5 GHz itself. The bands
do not combine their speed, and switching bands never changes Direct versus
VPN routing.

## Safety boundary

Before changing bridges, keep an independent management path: a different LAN
port, an already working Direct SSID, or a direct ISP connection. Do not run the
reload through the port selected for migration. The configure tool saves all
changed UCI packages in a timestamped directory under `/root` before writing.

Install `openwrt/files/` first. The included `/etc/config/xrayebator_safe`
preserves the old single-LAN defaults until the dual-network tool changes them.
The preflight refuses to rewire bridges while `xrayebator-safe` is running;
stop it with `/etc/init.d/xrayebator-safe stop` first so its reload trigger
cannot race the network change.

## Preflight

Copy the tools to the router, make them executable, then run without the apply
flag:

```sh
VPN_PORT=lan1 \
DIRECT_SSID='Home Direct' \
VPN_SSID='Home VPN' \
./configure-dual-network.sh
```

Expected output includes `PREFLIGHT_OK=true` and `APPLY_REQUIRED=true`. No key
is requested and no configuration is changed.

## Apply

Run from the preserved management path:

```sh
APPLY_CHANGES=1 \
RELOAD_NETWORK=1 \
VPN_PORT=lan1 \
DIRECT_SSID='Home Direct' \
VPN_SSID='Home VPN' \
./configure-dual-network.sh
```

The two Wi-Fi keys are requested with terminal echo disabled. For unattended
use, point `DIRECT_WIFI_KEY_FILE` and `VPN_WIFI_KEY_FILE` to separate local
files readable only by root. Do not put keys in arguments or environment
variables.

The tool creates `br-vpn`, DHCP and firewall zones, moves only `VPN_PORT`,
creates four AP interfaces with two unique names, and updates
`xrayebator_safe.main` so route-guard and the health namespace use `vpn`.
Legacy SSIDs remain active at this stage. If writing, reload or post-reload
validation fails, the tool automatically restores its timestamped backup; the
manual rollback command below remains available as a second recovery path.

## Activate and verify Xray

Validate the private Xray config and use staged activation:

```sh
/etc/init.d/xrayebator-safe check
xrayebator-safe-activate 90
```

From a VPN client, verify DNS, HTTPS, the required blocked destinations and the
external address. From a Direct client, verify ordinary ISP access. The
read-only helper checks both router paths without printing either public IP:

```sh
./verify-dual-network.sh
```

After all checks pass:

```sh
xrayebator-safe-commit
```

Game-specific direct routing belongs in the private Xray client configuration.
This repository does not ship changing game address lists or a private
`client.json`.

## Hide legacy SSIDs

Only after both paths and router management are confirmed:

```sh
./finalize-dual-network.sh
APPLY_CHANGES=1 ./finalize-dual-network.sh
```

The first invocation is another preflight. The second saves the current Wi-Fi
configuration and disables `default_radio0` and `default_radio1`; it does not
delete them. A failed reload or validation restores that Wi-Fi backup
automatically.

## Roll back

Use the exact backup directory printed by the configure or finalize tool:

```sh
./rollback-dual-network.sh /root/pre-dual-network-YYYYMMDD-HHMMSS
APPLY_CHANGES=1 ./rollback-dual-network.sh /root/pre-dual-network-YYYYMMDD-HHMMSS
```

The rollback also has a read-only preflight and accepts only backup paths made
by these tools.
