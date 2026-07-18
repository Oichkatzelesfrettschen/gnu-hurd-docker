# Credentials

This project runs a Debian GNU/Hurd **x86_64 guest** under QEMU. Guest
authentication depends on whether you have provisioned the image.

If you need the previous, long-form credentials document (including
historical notes and legacy compose examples), see
`docs/08-REFERENCE/archive/CREDENTIALS-LEGACY.md`.

## Out-of-box accounts (provisioned images)

Images staged with `scripts/oobe-first-login.sh` ship two generic
accounts whose passwords are **expired on purpose**: the first
interactive login asks you to set your own password before you get a
shell. This is the intended first-run experience for anyone picking up
a published image.

| Account | Initial password | Role |
|---|---|---|
| `user` | `user` | Primary account, member of `sudo` |
| `root` | `root` | Console recovery |

The forced change is enforced by PAM (`pam_unix` account management,
driven by the zeroed last-change field that `passwd -e` writes), which
covers the VNC console and OpenSSH logins. The fallback dropbear
daemon skips password aging; treat it as a break-glass path only.

An `agents` account (passwordless sudo) may additionally exist on
images built by the unattended-install automation; it is an internal
automation account, not part of the out-of-box story.

## SSH

The default port mapping is:

- Host: `localhost:2222`
- Guest: `:22` (via QEMU user networking)

```bash
ssh -p 2222 user@localhost
ssh -p 2222 root@localhost
```

Key-based auth: the provisioning flow in
`docs/reports/HURD-CONFIG-2026-05-13.md` generates a fresh keypair per
install (`ssh-keygen -t ed25519 -f hurd_test_key`). The
`ssh-test-keys/hurd_test_key.pub` tracked in this repository is a
throwaway development key: never authorize it on an image you intend
to expose, and rotate any image that still trusts it.

## Serial console (emergency access)

```bash
telnet localhost 5555
```

## Security notes

- The generic passwords exist only to hand the image over; the forced
  first-login change is what makes them shippable. Do not disable it.
- For anything long-lived, prefer SSH keys and disable password auth.
- Review `SECURITY.md` for host/container threat model constraints.
