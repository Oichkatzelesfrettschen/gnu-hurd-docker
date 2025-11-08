# Docker Secrets Configuration

This directory contains Docker secrets for secure credential management in the GNU/Hurd environment.

## Setup Instructions

### 1. Create Actual Secret Files

**IMPORTANT**: The `.example` files are templates only. You must create the actual secret files:

```bash
# Copy examples to actual files
cp root_password.txt.example root_password.txt
cp agents_password.txt.example agents_password.txt

# Edit the files with your actual passwords
nano root_password.txt
nano agents_password.txt
```

### 2. Verify .gitignore

Ensure actual secret files are ignored by git:

```bash
# Check that secrets/*.txt is in .gitignore
grep "secrets/\*.txt" ../.gitignore
```

### 3. Set Proper Permissions

```bash
# Restrict access to secrets (owner read-only)
chmod 600 *.txt
```

## File Structure

```
secrets/
├── README.md                        # This file
├── root_password.txt.example        # Template for root password
├── agents_password.txt.example      # Template for agents password
├── root_password.txt                # Actual root password (gitignored)
└── agents_password.txt              # Actual agents password (gitignored)
```

## Docker Compose Integration

The `docker-compose.yml` file references these secrets:

```yaml
secrets:
  root_password:
    file: ./secrets/root_password.txt
  agents_password:
    file: ./secrets/agents_password.txt

services:
  hurd-x86_64:
    secrets:
      - root_password
      - agents_password
```

## Security Best Practices

1. **Never commit actual secrets** to version control
2. **Use strong passwords** for production environments
3. **Rotate secrets regularly** (every 90 days)
4. **Restrict file permissions** (600 for secret files)
5. **Use different passwords** for development vs production

## Default Credentials (Development Only)

**Root Account**:
- Username: `root`
- Password: (contents of `root_password.txt`)

**Agents Account**:
- Username: `agents`
- Password: (contents of `agents_password.txt`)

## Accessing Secrets in Container

Secrets are mounted at `/run/secrets/` inside the container:

```bash
# Inside container
cat /run/secrets/root_password
cat /run/secrets/agents_password
```

## Production Recommendations

For production deployments:
1. Use external secret management (HashiCorp Vault, AWS Secrets Manager)
2. Enable MFA for SSH access
3. Disable password authentication (use SSH keys only)
4. Change default passwords immediately
5. Implement key rotation policies

## Troubleshooting

**Secret file not found**:
```bash
# Verify secret files exist
ls -la secrets/
```

**Permission denied**:
```bash
# Fix permissions
chmod 600 secrets/*.txt
chown $USER:$USER secrets/*.txt
```

**Secrets not mounted in container**:
```bash
# Check docker-compose logs
docker-compose logs hurd-x86_64 | grep secret
```
