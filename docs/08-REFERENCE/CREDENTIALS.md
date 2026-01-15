# Credentials

This project runs a Debian GNU/Hurd **x86_64 guest** under QEMU. Guest authentication depends on whether you have provisioned the image.

If you need the previous, long-form credentials document (including historical notes and legacy compose examples), see `docs/08-REFERENCE/archive/CREDENTIALS-LEGACY.md`.

## Defaults (development)

After running the project’s provisioning flows, the expected development credentials are:

- `root` / `root`
- `agents` / `agents` (passwordless sudo when configured)

Upstream Debian ports images may ship with different defaults (for example: password auth disabled and key-based SSH required) until provisioning is applied.

## SSH

The default port mapping is:

- Host: `localhost:2222`
- Guest: `:22` (via QEMU user networking)

```bash
ssh -p 2222 root@localhost
ssh -p 2222 agents@localhost
```

## Serial console (emergency access)

```bash
telnet localhost 5555
```

## Security notes

- Treat the default credentials as “development only”.
- For anything long-lived, rotate passwords and prefer SSH keys.
- Review `SECURITY.md` for host/container threat model constraints.

