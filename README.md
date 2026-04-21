# OSCP-nhas-ssh-server

Bash helpers for managing an **NHAS reverse SSH server** lab workflow in authorized training and internal testing environments.

> Use only on systems and networks you are explicitly authorized to administer or assess.

---

## Overview

`OSCP-nhas-ssh-server` is a small shell-based toolkit built around two main scripts:

- `nhas-build.sh` — builds NHAS client binaries for multiple platforms and architectures
- `nhas-start.sh` — prepares and launches the server-side workflow, inventories available agents, and prints a quick-reference dashboard

The project is designed to make repeated NHAS setup faster by keeping build output, server startup, and agent selection in one place.

---

## What it does

At a high level, the repository helps you:

- build NHAS client binaries for common target platforms
- choose between **direct** and **non-direct** client variants
- configure callback IP/port values
- organize generated binaries under a single output directory
- authorize the bundled client public key for server-side use
- launch a reverse-SSH “catcher” style workflow from a fixed workspace
- display ready-to-use reference output for connecting to enrolled clients

---

## Repository structure

- `nhas-build.sh`
  - interactive builder for NHAS client binaries
  - outputs compiled artifacts to the local exploits/binaries directory
  - supports optional compression and optional obfuscation if supporting tools are installed

- `nhas-start.sh`
  - startup/dashboard wrapper for the NHAS server workflow
  - discovers local interface/IP values
  - lists available compiled agents
  - records the bundled client public key into the authorized key file if needed
  - prints reference material for the catcher console and client selection

---

## Agent model

The scripts distinguish between two client styles:

### Direct agents
These have the callback destination compiled in.

Best when:
- you want the simplest operator experience
- the callback endpoint is fixed for the engagement/lab

### Non-direct agents
These require the destination to be provided at runtime.

Best when:
- you want more flexibility
- the callback endpoint may change between runs

---

## Build coverage

From the build script, the project supports generating binaries for:

- Linux amd64
- Linux 386
- Linux ARM64
- Linux ARMv7
- Linux ARMv6
- Windows amd64
- Windows 386
- macOS amd64
- macOS ARM64

It also supports optional variants such as:

- compressed builds
- obfuscated builds
- direct builds with baked-in callback values
- non-direct builds for runtime destination selection

---

## Build workflow

The builder script is an interactive helper that:

- asks for interface/IP
- asks for callback IP and callback port
- verifies the NHAS source tree is present
- creates the output directory if needed
- checks for optional tooling:
  - `upx`
  - `garble`
- compiles the requested families of binaries
- prints a results summary at the end

This makes it useful as a one-command “build everything I might need” helper for a lab workspace.

---

## Startup workflow

The startup script is a dashboard-oriented launcher that:

- sets a fixed NHAS working directory
- discovers the active interface/IP
- prompts for callback and HTTP download ports
- lets you choose Linux and Windows agent defaults
- scans the local exploits directory and lists matching binaries with size/type hints
- auto-appends the bundled client public key to the authorized key file if it is not already present
- prints a compact operator reference for the server-side SSH console

---

## Output layout

The scripts expect a workspace similar to:

```text
/home/alien/Desktop/OSCP/NHAS/
├── bin/
│   ├── server
│   ├── authorized_controllee_keys
│   └── exploits/
├── internal/
│   └── client/
│       └── keys/
└── nhas-build.sh
