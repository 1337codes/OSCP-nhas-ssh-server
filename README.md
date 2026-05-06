# OSCP-nhas-ssh-server

Bash helpers for spinning up an [NHAS reverse_ssh](https://github.com/NHAS/reverse_ssh) lab — installer, multi-arch client builder, and an opinionated server-side dashboard. Built for OSCP-style training and authorized internal testing.

> Use only on systems and networks you are explicitly authorized to administer or assess.

---

## What's in the box

| Script | Purpose |
| --- | --- |
| `setup-nhas.sh` | One-shot installer: pulls deps, clones NHAS source, compiles `bin/server`, installs `garble`, drops a `nhasup` alias, configures `ssh rssh` shortcut. |
| `nhas-build.sh` | Interactive multi-platform client builder (Linux/Windows/macOS, x86/ARM). Supports UPX compression and `garble` obfuscation when present. |
| `nhas-start.sh` | Dashboard wrapper: discovers your IP, lists compiled agents, prints ready-to-paste delivery one-liners (curl/wget/certutil/bitsadmin/etc.), then launches the server. |

---

## Requirements

- Linux host (tested on Kali/Debian/Ubuntu and **CachyOS / Arch**)
- Go ≥ 1.21
- `git`, `upx`, `rsync`
- Optional: `garble` (auto-installed by `setup-nhas.sh` to `~/go/bin/`)

The installer auto-detects your package manager and uses whichever is available:

| Distro family | Package manager used |
| --- | --- |
| Debian / Ubuntu / Kali | `apt-get` |
| Arch / CachyOS / Manjaro | `pacman` |
| Fedora / RHEL | `dnf` |
| openSUSE | `zypper` |

---

## Quick start

```bash
git clone https://github.com/1337codes/OSCP-nhas-ssh-server.git ~/Desktop/Tools/OSCP-nhas-ssh-server
cd ~/Desktop/Tools/OSCP-nhas-ssh-server
sudo bash setup-nhas.sh
```

Open a new shell (or `source` your rc file), then:

```bash
nhasup           # launches the dashboard + server
```

That's the whole loop. To rebuild client agents:

```bash
bash nhas-build.sh
```

---

## Workspace layout

The workspace is the repo directory itself — NHAS source code is rsynced in alongside the wrapper scripts:

```text
/home/<you>/Desktop/Tools/OSCP-nhas-ssh-server/
├── setup-nhas.sh                ← installer
├── nhas-build.sh                ← client builder
├── nhas-start.sh                ← dashboard / launcher
├── go.mod, cmd/, internal/, …   ← NHAS upstream source (gitignored)
└── bin/
    ├── server                   ← compiled NHAS server
    ├── authorized_keys          ← admin pubkeys (you)
    ├── authorized_controllee_keys ← client pubkey (auto-added)
    └── exploits/                ← built client agents
```

To override the workspace location, export `WORKSPACE` (for `setup-nhas.sh`) or `NHAS_DIR` (for the wrappers) before running.

---

## Agent model

Two flavors of client are built:

- **Direct agents** — callback `host:port` is compiled into the binary. Run with no arguments. Simplest for fixed-target labs.
- **Non-direct agents** — callback destination is supplied at runtime. More flexible when the catcher endpoint changes between runs.

`nhas-build.sh` produces both flavors for every selected platform.

---

## Build coverage

`nhas-build.sh` can produce binaries for:

- Linux: amd64, 386, arm64, armv7, armv6
- Windows: amd64, 386
- macOS: amd64, arm64

Optional variants per build:

- UPX-compressed (when `upx` is installed)
- `garble`-obfuscated (when `garble` is in `~/go/bin`)
- Direct (baked-in callback) and non-direct (runtime callback)

---

## What the dashboard gives you

`nhas-start.sh` (aliased to `nhasup`) auto-detects your active interface IP, then prints a numbered menu of copy-paste-ready delivery one-liners for each enrolled platform — `wget`, `curl`, `certutil`, `bitsadmin`, PowerShell `IWR`, systemd-user persistence, etc. — wired to the agents it found in `bin/exploits/`. After printing the cheat sheet it `exec`s `bin/server`, so the same terminal becomes the catcher console.

Connect to a callback once it lands:

```bash
ssh rssh                       # admin console (alias added by setup-nhas.sh)
ssh    -J rssh <client-id>     # Linux target
ssh -tt -J rssh <client-id>    # Windows target (use -tt to avoid ConPTY buffer issues)
```

List enrolled clients from inside the admin console:

```
ls -t
```

---

## What `setup-nhas.sh` actually does

1. Detects your package manager and installs Go, UPX, git.
2. Verifies Go ≥ 1.21.
3. Clones `NHAS/reverse_ssh` to a temp dir and rsyncs the source into the workspace, excluding `.git` and preserving the wrapper scripts.
4. Builds `bin/server` with `-trimpath -ldflags='-s -w'`.
5. Installs `garble` to `~/go/bin/` (as your user, not root).
6. Adds `~/go/bin` to `PATH` in `~/.bashrc` and `~/.zshrc`.
7. Adds `nhasup` alias to `~/.bashrc`, `~/.zshrc`, **and** `~/.config/fish/config.fish`.
8. Generates an ed25519 keypair if you don't have one, and authorizes its public key in `bin/authorized_keys`.
9. Adds `Host rssh → 127.0.0.1:3232` to `~/.ssh/config`.

Re-running is safe — every step is idempotent.

To refresh the NHAS upstream source later:

```bash
rm go.mod && sudo bash setup-nhas.sh
```

---

## Troubleshooting

**`nhasup: command not found`** — your shell was started before the alias existed. `source ~/.config/fish/config.fish` (or your bash/zsh equivalent), or open a new terminal.

**`ssh rssh` says "not authorized"** — restart `bin/server` after `setup-nhas.sh` ran; admin keys are loaded once at startup.

**Server build fails with old Go** — Arch usually ships current Go via `pacman`; on Debian-derived distros older `golang-go` packages may be too old. Install the latest from [go.dev/dl](https://go.dev/dl/) and rerun.

**`garble` install failed** — obfuscated builds will be skipped silently by `nhas-build.sh`. Retry as your user (not root): `go install mvdan.cc/garble@latest`.

---

## Disclaimer

This project does not modify NHAS itself; it just orchestrates installation, builds, and operator UX around it. All credit for the underlying reverse-SSH implementation goes to [NHAS/reverse_ssh](https://github.com/NHAS/reverse_ssh).

Use only against systems you are explicitly authorized to test.
