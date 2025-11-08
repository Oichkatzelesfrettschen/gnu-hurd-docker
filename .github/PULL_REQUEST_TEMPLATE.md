# Pull Request

## Description

**What does this PR do?**


**Why is this change needed?**


## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Refactoring (code improvement without changing functionality)
- [ ] Performance improvement
- [ ] CI/CD or build system change

## Related Issues

**Closes**: #(issue number)
**Related to**: #(issue number)

## Changes Made

**List the specific changes**:
-
-
-

## Testing

**How has this been tested?**


**Test configuration**:
- Host OS:
- Docker version:
- Docker Compose version:
- KVM available: [yes/no]

**Test steps**:
1.
2.
3.

**Test results**:
```
# Paste test output here
```

## Screenshots/Logs

**If applicable, add screenshots or logs**:


## Checklist

### Code Quality
- [ ] My code follows the project's coding standards
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] My changes generate no new warnings
- [ ] I have run `shellcheck -S error` on any shell scripts (passes without errors)
- [ ] I have run `hadolint Dockerfile` if Dockerfile was modified

### Documentation
- [ ] I have updated the documentation accordingly
- [ ] I have updated the README if needed
- [ ] I have added usage examples (if applicable)
- [ ] I have run `markdown-link-check` on documentation changes

### Testing
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing unit tests pass locally with my changes
- [ ] I have tested the Docker build: `docker-compose build`
- [ ] I have tested the container start: `docker-compose up -d`
- [ ] I have tested SSH access: `ssh -p 2222 root@localhost`
- [ ] I have verified no regression in existing functionality

### Git Best Practices
- [ ] I have created a feature branch (not committing directly to main)
- [ ] My commits follow [Conventional Commits](https://www.conventionalcommits.org/) format
- [ ] I have rebased on the latest main branch
- [ ] I have resolved all merge conflicts

### Security (if applicable)
- [ ] No secrets or credentials committed to version control
- [ ] Security implications have been considered and documented
- [ ] I have updated SECURITY.md if needed
- [ ] Vulnerabilities introduced by dependencies have been checked

## Breaking Changes

**Does this PR introduce breaking changes?**


**If yes, describe the impact and migration path**:


## Additional Context

**Any other information that reviewers should know**:


## For Reviewers

**What should reviewers focus on?**


**Are there any areas of concern?**


## Post-Merge Checklist

- [ ] Documentation deployed (if applicable)
- [ ] Release notes updated (for significant changes)
- [ ] GitHub release created (for version bumps)
