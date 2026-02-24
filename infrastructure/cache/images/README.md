Local VM backup cache (not versioned)

Purpose:
- Store transient VM backup/snapshot files here instead of `images/`.
- Keep large scratch artifacts out of git history and out of pushes.

Suggested usage:
- Move backups here when created:
  - `mv images/debian-hurd-amd64.qcow2.bak* infrastructure/cache/images/`
  - `mv images/debian-hurd-amd64.qcow2.*.bak infrastructure/cache/images/`
  - `mv images/debian-hurd-amd64.qcow2.pre-* infrastructure/cache/images/`
  - `mv images/debian-hurd-amd64.qcow2.post-* infrastructure/cache/images/`
- Or run the helper script from repo root:
  - `./scripts/manage-image-backup-cache.sh`
  - Dry run: `./scripts/manage-image-backup-cache.sh --dry-run`

Cleanup examples:
- Remove everything in this cache:
  - `find infrastructure/cache/images -mindepth 1 -type f -delete`
- Remove backups older than 14 days:
  - `find infrastructure/cache/images -type f -mtime +14 -delete`
