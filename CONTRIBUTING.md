# Contributing to Masques

Thanks for your interest in contributing! This document outlines the process for contributing to Masques.

## Issue First

**Open an issue before starting work.** This isn't an approval gate—it's for context and traceability. It helps:

- Avoid duplicate efforts
- Get early feedback on approach
- Create a record linking discussion to code

## Workflow

1. **Open an issue** describing what you want to do
2. **Fork** the repository
3. **Create a branch** from `main` (e.g., `feature/my-change` or `fix/bug-description`)
4. **Implement** your changes
5. **Test manually** — run the commands, verify they work
6. **Open a PR** referencing the issue

## Guidelines

### Code Style

- Follow existing YAML formatting (2-space indent, quoted strings where used)
- Match existing command structure and patterns
- Keep masque definitions minimal and focused

### Scope

- **One logical change per PR** — easier to review, easier to revert if needed
- **Update docs** if your change affects behavior or adds features
- **Don't bundle unrelated changes** — formatting fixes, refactors, and features should be separate PRs

### Testing

There's no automated test suite (yet). Before submitting:

- Test your commands manually in Claude Code
- Verify masque definitions parse correctly
- Check that `/list`, `/don`, and `/id` work with your changes

## Expectations

This is a **personal project** maintained in spare time. Please understand:

- Response times vary
- Not all ideas will become features
- PRs may sit for a while before review
- Feedback may be direct and brief

I appreciate your patience and contributions!

## Questions?

Open an issue with your question. There's no dedicated support channel, but I'll respond when I can.
