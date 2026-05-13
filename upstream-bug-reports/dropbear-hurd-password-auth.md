# Upstream bug report: dropbear 2026.91-1 password auth rejected on Debian GNU/Hurd

**To file:** Debian BTS against `src:dropbear`, then upstream at
https://lists.ucc.gu.uwa.edu.au/mailman/listinfo/dropbear

## Summary

Password authentication against `dropbear 2026.91-1` on Debian
GNU/Hurd 0.9 (gnumach 1.8) rejects all valid passwords with
*"Bad password attempt for '$user' from $ip"*.  Public-key
authentication on the same daemon, against the same accounts, with
the same configuration, succeeds.

`crypt()` and `getpwnam()` from the system libraries produce the
expected output: the comparison `crypt(pass, stored) == stored`
succeeds outside of dropbear, including when run as `nobody`.  So the
bug is dropbear-specific, not a Hurd libc/libcrypt issue.

## Reproduction

Debian GNU/Hurd 0.9 (Jan-2026 baseline `debian-hurd-amd64.qcow2`)
running under QEMU/KVM with the gnu-hurd-docker harness.  Image
overlaid with `dropbear-bin_2026.91-1_hurd-amd64.deb` from
debian-ports.

1. Configure two accounts with DES-format (13-char) password hashes:

   ```
   root:ABE3UhboE3geg:0:0:root:/root:/bin/bash
   user:CDv6FgFIrADYk:1001:1001:user,,,:/home/user:/bin/bash
   ```

   (passwords are literally `root` and `user`; salts are `AB` and `CD`.)

2. Start `dropbear` from rc.local:

   ```sh
   /usr/sbin/dropbear -E -P /run/dropbear.pid -p 22 \
       -r /etc/dropbear/dropbear_ed25519_host_key \
       -r /etc/dropbear/dropbear_rsa_host_key
   ```

3. From the host, attempt SSH with the same passwords:

   ```sh
   sshpass -p 'root' ssh -o PreferredAuthentications=password \
       -p 2222 root@127.0.0.1
   ```

Observed:
```
[715] May 13 17:36:18 Bad password attempt for 'root' from 10.0.0.141:39190
[715] May 13 17:36:19 Exit before auth from <10.0.0.141:39190>: (user 'root', 3 fails): Exited normally
```

Same with user `user`, password `user`.  Same with SHA-512 (`$6$...`)
hashes set via `mkpasswd -m sha-512`.  Same whether the hash is in
`/etc/shadow` (with `x` in passwd) or directly in `/etc/passwd`.

## Validation that the system layer is fine

A minimal C program calling `getpwnam` then `crypt` matches the stored
hash both as root and as nobody:

```c
#include <stdio.h>
#include <string.h>
#include <crypt.h>
#include <pwd.h>

int main(int argc, char **argv) {
    struct passwd *pw = getpwnam(argv[1]);
    char *computed = crypt(argv[2], pw->pw_passwd);
    printf("stored=%s computed=%s match=%d\n",
           pw->pw_passwd, computed,
           strcmp(pw->pw_passwd, computed) == 0);
    return 0;
}
```

Output as root:
```
pw_name=root pw_uid=0 pw_passwd=ABE3UhboE3geg
stored=ABE3UhboE3geg
computed=ABE3UhboE3geg
strlen(stored)=13 strlen(computed)=13
strcmp(stored, computed) = 0 (MATCH)
```

Output as nobody (after `su -s /bin/sh nobody`):
```
pw_name=root pw_uid=0 pw_passwd=ABE3UhboE3geg
stored=ABE3UhboE3geg
computed=ABE3UhboE3geg
strlen(stored)=13 strlen(computed)=13
strcmp(stored, computed) = 0 (MATCH)
```

So `crypt()` works, `getpwnam()` works, the underlying comparison works.

## Suspected cause

Dropbear `svr_auth_password()` in
[`src/svr-authpasswd.c`](https://sources.debian.org/data/main/d/dropbear/2026.91-1/src/svr-authpasswd.c)
reduces to:

```c
passwdcrypt = ses.authstate.pw_passwd;
testcrypt = crypt(password, passwdcrypt);
[...]
if (constant_time_strcmp(testcrypt, passwdcrypt) == 0) {
    /* success */
} else {
    dropbear_log(LOG_WARNING, "Bad password attempt ...");
}
```

The auth child process appears to receive `password` correctly
(non-empty, not too long) and reach the comparison, but the result of
`crypt(password, passwdcrypt)` inside the child does not match
`passwdcrypt` -- whereas the same call from a sibling C program in
the same Hurd guest matches.

Hypotheses worth testing in a DEBUG_TRACE-built dropbear:

1. The `m_burn(password)` then `m_free(password)` after the `crypt()`
   call corrupts a libcrypt static buffer if Hurd's `crypt` returns a
   pointer into the salt argument (as some libcrypt versions do for
   DES-fast paths).  Mitigation: `m_strdup(testcrypt)` immediately
   after the `crypt()` call, before `m_burn(password)`.
2. Hurd's `fork()` (a Mach `task_create` + cthreads dance) differs
   from POSIX `fork()` enough that libcrypt's thread-local static
   buffer is not preserved across fork in the privsep child.  This is
   plausible given the dropbear 2025.89 changelog
   *"The server now drops privileges of the dropbear process after
   authentication"* -- on Hurd that privsep happens via a different
   mechanism than `setresuid` and might be misordered.
3. Glibc on Hurd lacks `getspnam_r` thread-safe variant, so dropbear
   might be calling the non-reentrant `getspnam` which would race
   internally if multiple auth attempts come in.  Mitigation: serialize
   auth or always use `getpwnam_r`.

## Workaround

Use public-key authentication.  We have verified that the same
dropbear binary on the same Hurd accepts pubkey logins for both root
and user with no issues.

## Affected versions

* `dropbear-bin` 2026.91-1 (debian-ports hurd-amd64)
* GNU Hurd 0.9 git20251029
* GNU Mach 1.8+git20250731 amd64
* glibc 2.41+hurd.X (per `libc0.3` in dpkg status)

## Not affected

* The same dropbear binary on Linux amd64 accepts these same hashes.
