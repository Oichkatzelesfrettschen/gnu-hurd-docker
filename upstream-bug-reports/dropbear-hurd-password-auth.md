# dropbear 2026.91-1 on debian gnu/hurd rejects all password logins (pubkey works fine though)

**heads up**: this is filed somewhat sheepishly -- I set this up for
fun on my own machine to learn hurd and I hit this, figured I'd at
least write it up.  apologies for any rough edges in the report.

## the symptom

on debian gnu/hurd 0.9, dropbear-bin 2026.91-1 from debian-ports
hurd-amd64 won't accept any password.  every attempt logs:

```
[715] May 13 17:36:18 Bad password attempt for 'root' from 10.0.0.141:39190
[715] May 13 17:36:19 Exit before auth from <10.0.0.141:39190>: (user 'root', 3 fails): Exited normally
```

same for `user`, same with the password hash baked directly into
`/etc/passwd` (`root:ABE3UhboE3geg:0:0:...`) instead of via shadow,
same with both DES and SHA-512 (`$6$...`) format hashes.

pubkey auth works perfectly on the exact same dropbear binary with
the exact same accounts.  so the network side / kex / fork / etc is
fine -- it's purely the password comparison that fails.

## the weird thing

I wrote a tiny C reproducer that calls `getpwnam` + `crypt` directly:

```c
struct passwd *pw = getpwnam(argv[1]);
const char *stored = pw->pw_passwd;
/* if stored is "x", fall back to getspnam->sp_pwdp */
char *computed = crypt(argv[2], stored);
int eq = strcmp(stored, computed);
```

running this as root, as nobody, and as the unprivileged "user"
account, it ALWAYS matches:

```
pw_name=root pw_uid=0 pw_passwd=ABE3UhboE3geg
stored=ABE3UhboE3geg
computed=ABE3UhboE3geg
strlen(stored)=13 strlen(computed)=13
strcmp(stored, computed) = 0 (MATCH)
```

so the system layer (libcrypt + getpwnam + getspnam) is fine.  it's
something *inside dropbear's auth child* that's mishandling the
comparison.

## hypotheses (these are guesses, sorry)

looking at `src/svr-authpasswd.c`:

```c
password = buf_getstring(ses.payload, &passwordlen);
if (valid_user && passwordlen <= DROPBEAR_MAX_PASSWORD_LEN) {
    passwdcrypt = ses.authstate.pw_passwd;
    testcrypt = crypt(password, passwdcrypt);
}
m_burn(password, passwordlen);
m_free(password);
[...]
if (constant_time_strcmp(testcrypt, passwdcrypt) == 0) {
    /* success */
} else {
    dropbear_log(LOG_WARNING, "Bad password attempt ...");
}
```

things I'd want to check in a DEBUG_TRACE build:

1. on hurd does `crypt()` maybe return a pointer that gets
   invalidated by the subsequent `m_burn(password)` /
   `m_free(password)`?  some libcrypt impls return a pointer into
   thread-local static storage that could overlap with other heap.
   easy fix would be `testcrypt = m_strdup(crypt(...))` right after
   the call.
2. dropbear 2025.89's changelog mentions "the server now drops
   privileges of the dropbear process after authentication" -- on
   hurd this privsep happens through different mechanisms than
   `setresuid` and maybe the order is wrong, so getpwnam in the auth
   child returns stale or zeroed pw_passwd.
3. hurd's glibc might lack `getspnam_r` and the thread-unsafe
   `getspnam` could be racing during connection bursts.  I don't
   *think* this is my issue (single connection at a time) but worth
   ruling out.

## the workaround I'm using

just use pubkey auth.  it works on the same dropbear binary with the
same accounts.  not ideal but functional.

## affected

* dropbear-bin 2026.91-1 (debian-ports hurd-amd64)
* gnu hurd 0.9 git20251029
* gnu mach 1.8+git20250731 amd64
* libcrypt1 (libxcrypt) -- exact debian version 1:4.4.38+hurd.X
* glibc 2.41+hurd.X

## not affected

* same dropbear binary on debian-linux amd64 (I didn't test exhaustively
  but accepted password from my notes)
* pubkey auth on hurd (works fine)

---

**disclaimer**: I used a large language model (claude) to help dig
into the dropbear source, write the C reproducer, and reason about
the failure mode.  the C reproducer's output is real and reproducible.
the hypothesis section is uneducated guesses though -- if anyone
familiar with dropbear's privsep model on hurd wants to take a look,
that would be amazing.  this was a hobby setup with no production
implications, sorry for the noise if it turns out to be something
silly on my end.
