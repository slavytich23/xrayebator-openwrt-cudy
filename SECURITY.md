# Security and privacy

## Never publish connection material

Treat all of the following as secrets:

- Xray/VLESS UUIDs, private keys, short IDs and Reality parameters;
- subscription URLs, QR codes and tokens;
- VPS addresses, hostnames and SSH credentials;
- exported client JSON, packet captures and unredacted logs.

Keep the live configuration at `/etc/xrayebator-safe/client.json` only on the
router, set mode `0600`, and do not add it to Git. The repository intentionally
ships only a small non-secret XHTTP/XMUX fragment.

## Recovery boundary

Do not enable fail-closed routing until an independent recovery path is ready:
direct TP-Link Wi-Fi, a local Ethernet connection, serial console, or another
administrator-approved route. The staged activation command automatically
stops and disables the service unless it is explicitly committed.

## Reporting a problem

Open a GitHub issue with versions, anonymized pass/fail results and minimal
reproduction steps. Do not attach private configurations or raw captures.
