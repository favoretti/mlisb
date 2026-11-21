# Security policy

## Supported versions

Only the latest release gets security fixes. mlisb updates itself, so a fix reaches users as a new
release rather than as a patch to an older one.

## Reporting a vulnerability

Please report it privately through GitHub:
[**Report a vulnerability**](https://github.com/favoretti/mlisb/security/advisories/new).
Do not open a public issue.

Include what you can of:

- the mlisb version (**mlisb → About mlisb**) and macOS version,
- a Markdown file or steps that trigger the problem,
- what an attacker gains.

You should get a first reply within a week. Once a fix is released, the advisory is published and
you are credited, unless you would rather not be.

## What counts

mlisb opens Markdown files from anywhere, including ones written by coding agents or downloaded
from the internet, so a file should never be able to do more than display itself. Examples of
things worth reporting:

- A document that runs code, or reads or writes files the user did not open.
- A link or HTML in a document that opens a URL, app or file without asking first.
- A document that makes the app fetch something from the network. Remote images are not loaded,
  and diagrams render offline.
- Content that escapes the diagram renderer's web view, or reaches the app through it.
- Anything that gets around the App Sandbox or the update signature check (updates are verified
  with an EdDSA key).
- `mlisb hook install` or `mlisb notify` doing anything beyond what
  [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#coding-agent-hook) describes.

A crash on a malformed file is a bug, but report it privately too if you think it could be more
than a crash.
