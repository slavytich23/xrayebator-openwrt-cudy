# Contributing

Focused fixes, anonymized compatibility reports and reproducible tests are
welcome.

Before opening a pull request:

1. Run `tests/run-all.ps1` from PowerShell.
2. Keep all network values generic or documented examples.
3. Do not commit client JSON, subscriptions, keys, server addresses, raw logs
   or packet captures.
4. Explain router model/revision, OpenWrt and Xray versions without publishing
   private connection material.
5. Preserve staged activation and rollback behavior for routing changes.

Large firmware images and generated root filesystems are intentionally out of
scope.
