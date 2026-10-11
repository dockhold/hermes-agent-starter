# Dockhold changelog

Changes this starter makes on top of the upstream template. Each entry names
the upstream commit it is built on and the Hermes Agent version that commit
pins, and says whether moving to it changes your data. The upstream
template's own `CHANGELOG.md` covers everything else. Download a backup from
the admin panel before any upgrade.

## Hermes v2026.9.24 (upstream `78c4725`), second change (2026-10-11)

This repository is about running on Dockhold only:

- `README.md` is this starter's own. The upstream template's README stays in its repository, linked from Credits.
- Removed the upstream deploy config for another host.
- Admin panel: removed the "Other Templates" page, and reworded the few hints, the sign-in footnote and the pairing message that named another host. No change to how anything works.

No data migration.

## Hermes v2026.9.24 (upstream `78c4725`, 2026-10-11)

Initial release. Adds `dockhold/entrypoint.sh`, the two `Dockerfile` lines
that run it, `dockhold/smoke.sh` and the two Dockhold workflows. No data
migration.
