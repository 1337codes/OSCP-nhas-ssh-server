#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# setup-nhas.sh — prepares everything nhas-build.sh + nhas-start.sh need
#
#   Repo:   https://github.com/1337codes/OSCP-nhas-ssh-server
#   Usage:  chmod +x setup-nhas.sh && sudo bash setup-nhas.sh
#
# What this does:
#   1. Install Go + UPX + git via apt
#   2. Clone NHAS/reverse_ssh source into workspace (or git pull if exists)
#   3. Build the server binary (bin/server) as your user
#   4. Install garble as your user (goes to ~/go/bin — NOT root)
#   5. Ensure ~/go/bin is in PATH via ~/.zshrc / ~/.bashrc
#   6. Create workspace structure (bin/exploits/)
#   7. Verify everything the build script checks for
# ─────────────────────────────────────────────────────────────────────

set -u

R='\033[91m'; G='\033[92m'; Y='\033[93m'; C='\033[96m'; B='\033[1m'; N='\033[0m'

banner() { echo -e "\n${C}${B}[*]${N} ${B}$1${N}"; }
ok()     { echo -e "${G}[+]${N} $1"; }
warn()   { echo -e "${Y}[!]${N} $1"; }
fail()   { echo -e "${R}[-]${N} $1" >&2; }

if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo &>/dev/null; then
        fail "Run as root or install sudo."; exit 1
    fi
    SUDO="sudo"
else
    SUDO=""
fi

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
# Workspace = this repo's directory. NHAS source is laid down alongside the
# wrapper scripts. Override with WORKSPACE=/some/path before running.
WORKSPACE="${WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)}"
NHAS_REPO="https://github.com/NHAS/reverse_ssh.git"
GOBIN="$TARGET_HOME/go/bin"

run_as_user() {
    if [[ $EUID -eq 0 ]] && [[ "$TARGET_USER" != "root" ]]; then
        sudo -u "$TARGET_USER" -H "$@"
    else
        "$@"
    fi
}

# Run Go commands as user with correct PATH/GOPATH so go install lands in ~/go/bin
run_go_as_user() {
    run_as_user env \
        PATH="$GOBIN:/usr/local/go/bin:/usr/bin:/bin:$PATH" \
        GOPATH="$TARGET_HOME/go" \
        HOME="$TARGET_HOME" \
        "$@"
}

banner "NHAS reverse-SSH server installer"

# ─── package manager: Go + UPX + git ─────────────────────────────────
banner "Installing Go, UPX, and git"
if command -v pacman &>/dev/null; then
    # Arch / CachyOS / Manjaro
    $SUDO pacman -Sy --needed --noconfirm go upx git
    ok "go + upx + git installed (pacman)"
elif command -v apt-get &>/dev/null; then
    # Debian / Ubuntu / Kali
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq golang-go upx git
    ok "golang-go + upx + git installed (apt)"
elif command -v dnf &>/dev/null; then
    # Fedora / RHEL
    $SUDO dnf install -y golang upx git
    ok "golang + upx + git installed (dnf)"
elif command -v zypper &>/dev/null; then
    # openSUSE
    $SUDO zypper --non-interactive install go upx git
    ok "go + upx + git installed (zypper)"
else
    fail "No supported package manager found (apt-get, pacman, dnf, zypper)."
    fail "Install Go (>=1.21), UPX, and git manually, then rerun."
    exit 1
fi

# ─── verify Go version (NHAS needs >= 1.21) ──────────────────────────
banner "Verifying Go version"
GO_FULL=$(go version 2>/dev/null | grep -oP 'go\d+\.\d+\.?\d*' | head -1)
GO_VERSION=$(echo "$GO_FULL" | grep -oP '\d+\.\d+' | head -1)
MAJOR=$(echo "$GO_VERSION" | cut -d. -f1)
MINOR=$(echo "$GO_VERSION" | cut -d. -f2)
ok "$GO_FULL on PATH"

if [[ "$MAJOR" -lt 1 ]] || { [[ "$MAJOR" -eq 1 ]] && [[ "$MINOR" -lt 21 ]]; }; then
    fail "Go ${GO_VERSION} too old — NHAS needs >= 1.21"
    fail "Install latest from https://go.dev/dl/ and rerun"
    exit 1
fi

# ─── NHAS source: clone into workspace alongside wrapper scripts ─────
# The workspace is this repo's directory (it already has its own .git for
# OSCP-nhas-ssh-server), so we never `git pull` here — that would touch
# the wrong remote. To refresh NHAS source, delete go.mod and rerun.
banner "Checking NHAS source at $WORKSPACE"

if [[ -f "$WORKSPACE/go.mod" ]]; then
    ok "NHAS source already present (delete $WORKSPACE/go.mod to refresh)"
else
    run_as_user mkdir -p "$WORKSPACE"
    TMP_CLONE=$(run_as_user mktemp -d)
    if run_as_user git clone --depth=1 "$NHAS_REPO" "$TMP_CLONE"; then
        # --exclude='.git' so we don't clobber OSCP-nhas-ssh-server's repo metadata
        # --ignore-existing so wrapper scripts (nhas-build.sh etc.) are preserved
        run_as_user rsync -a --ignore-existing --exclude='.git' "$TMP_CLONE/" "$WORKSPACE/"
        run_as_user rm -rf "$TMP_CLONE"
        ok "NHAS source merged into $WORKSPACE"
    else
        run_as_user rm -rf "$TMP_CLONE"
        fail "Failed to clone $NHAS_REPO — check network access"
        exit 1
    fi
fi

if [[ ! -f "$WORKSPACE/go.mod" ]]; then
    fail "go.mod still missing — check git access and retry"
    exit 1
fi
ok "go.mod confirmed ✓ (nhas-build.sh startup check will pass)"

# ─── workspace structure ─────────────────────────────────────────────
banner "Creating workspace structure"
run_as_user mkdir -p "$WORKSPACE/bin/exploits"
ok "$WORKSPACE/bin/exploits/ ready"

# ─── build server binary ─────────────────────────────────────────────
banner "Building NHAS server binary"
if [[ -f "$WORKSPACE/bin/server" ]]; then
    ok "bin/server already exists — skipping (delete it and rerun to rebuild)"
else
    echo -e "    Compiling from source — takes 30-90s on first run..."
    if run_go_as_user bash -c "cd '$WORKSPACE' && go build -trimpath -ldflags='-s -w' -o bin/server ./cmd/server 2>&1"; then
        SIZE=$(du -h "$WORKSPACE/bin/server" 2>/dev/null | cut -f1)
        ok "bin/server built ($SIZE)"
    else
        fail "server build failed — check Go version and network access"
        warn "Retry: cd $WORKSPACE && go build -o bin/server ./cmd/server"
    fi
fi

# ─── pre-generate server host key ────────────────────────────────────
# reverse_ssh server loads its host key from bin/id_ed25519 (not server_ed25519).
# nhas-build.sh reads this key at compile time to embed RSSH_FINGERPRINT into
# every client binary.  Without it, clients reject the server with a key mismatch.
banner "Pre-generating server host key (bin/id_ed25519)"
SERVER_KEY="$WORKSPACE/bin/id_ed25519"
run_as_user mkdir -p "$(dirname "$SERVER_KEY")"

if [[ -f "$SERVER_KEY" ]]; then
    ok "Server host key already exists at $SERVER_KEY"
else
    run_as_user ssh-keygen -t ed25519 -N "" -f "$SERVER_KEY" -q
    if [[ -f "$SERVER_KEY" ]]; then
        ok "Server host key generated at $SERVER_KEY"
    else
        fail "ssh-keygen failed — run manually: ssh-keygen -t ed25519 -N '' -f $SERVER_KEY"
    fi
fi
# Remove the .pub sidecar — server only uses the private key file
[[ -f "${SERVER_KEY}.pub" ]] && run_as_user rm -f "${SERVER_KEY}.pub"

if [[ -f "$SERVER_KEY" ]]; then
    # Convert SSH fingerprint from SHA256:base64 → raw hex (the format the server prints
    # and RSSH_FINGERPRINT expects)
    _FP_B64=$(ssh-keygen -lf "$SERVER_KEY" -E sha256 2>/dev/null | awk '{print $2}' | sed 's/SHA256://')
    _FP_HEX=$(printf '%s==' "$_FP_B64" | base64 -d 2>/dev/null | xxd -p | tr -d '\n')
    if [[ -n "$_FP_HEX" ]]; then
        ok "Server fingerprint (hex): ${_FP_HEX}"
        echo ""
        echo -e "    ${C}RSSH_FINGERPRINT=${_FP_HEX}${N}"
        echo -e "    ${Y}Baked into every client at build time — do NOT delete bin/id_ed25519${N}"
        echo -e "    ${Y}To rotate: delete the key, rerun setup-nhas.sh, then rebuild all clients.${N}"
    else
        warn "Could not extract fingerprint — ensure ssh-keygen and xxd are installed"
    fi
fi

# ─── pre-generate client embed keypair ───────────────────────────────
# reverse_ssh embeds a keypair into every client binary at build time from
# internal/client/keys/private_key (no extension).  Without it every go build
# fails with: pattern private_key: no matching files found
banner "Pre-generating client embed keypair (internal/client/keys/private_key)"
CLIENT_KEY_DIR="$WORKSPACE/internal/client/keys"
CLIENT_KEY="$CLIENT_KEY_DIR/private_key"
run_as_user mkdir -p "$CLIENT_KEY_DIR"

if [[ -f "$CLIENT_KEY" ]]; then
    ok "Client embed keypair already exists at $CLIENT_KEY"
else
    # Generate to a temp path then rename — ssh-keygen always writes .pub alongside
    run_as_user ssh-keygen -t ed25519 -N "" -f "$CLIENT_KEY" -q
    if [[ -f "$CLIENT_KEY" ]]; then
        ok "Client embed keypair generated at $CLIENT_KEY"
        ok "Client public key at ${CLIENT_KEY}.pub"
    else
        fail "ssh-keygen failed — run manually: ssh-keygen -t ed25519 -N '' -f $CLIENT_KEY"
    fi
fi

# Ensure the client's public key is in NHAS's authorized_controllee_keys so
# the server trusts callbacks from clients built with this keypair
CTRL_KEYS="$WORKSPACE/bin/authorized_controllee_keys"
if [[ -f "${CLIENT_KEY}.pub" ]]; then
    run_as_user mkdir -p "$(dirname "$CTRL_KEYS")"
    _CPUB=$(cat "${CLIENT_KEY}.pub")
    if grep -qF "$_CPUB" "$CTRL_KEYS" 2>/dev/null; then
        ok "Client public key already in authorized_controllee_keys"
    else
        run_as_user bash -c "echo '$_CPUB' >> '$CTRL_KEYS'"
        ok "Client public key added to authorized_controllee_keys"
    fi
fi

# ─── install garble (must be as user — goes to ~/go/bin) ─────────────
banner "Installing garble (obfuscation — installs to ~/go/bin)"
if [[ -f "$GOBIN/garble" ]]; then
    ok "garble already at $GOBIN/garble"
else
    echo -e "    Installing mvdan.cc/garble@latest as $TARGET_USER..."
    if run_go_as_user go install mvdan.cc/garble@latest; then
        [[ -f "$GOBIN/garble" ]] && ok "garble installed at $GOBIN/garble" || \
            warn "garble install ran but binary not found at $GOBIN — check GOPATH"
    else
        warn "garble install failed — obfuscated builds will be skipped by nhas-build.sh"
        warn "Retry as $TARGET_USER: go install mvdan.cc/garble@latest"
    fi
fi

# ─── ensure ~/go/bin is in PATH in shell rc ──────────────────────────
banner "Ensuring ~/go/bin is in PATH"
GOBIN_EXPORT='export PATH="$HOME/go/bin:$PATH"'

for rc in "$TARGET_HOME/.zshrc" "$TARGET_HOME/.bashrc"; do
    [[ -f "$rc" ]] || continue
    if grep -q 'go/bin' "$rc" 2>/dev/null; then
        ok "~/go/bin already in $(basename $rc)"
    else
        run_as_user bash -c "printf '\n# Go binaries (garble, etc.)\n%s\n' '$GOBIN_EXPORT' >> '$rc'"
        ok "Added ~/go/bin to PATH in $(basename $rc)"
    fi
done

# ─── nhasup alias (bash / zsh / fish) ────────────────────────────────
banner "Installing 'nhasup' alias"
NHASUP_TARGET="$WORKSPACE/nhas-start.sh"
NHASUP_POSIX="alias nhasup='bash \"$NHASUP_TARGET\"'"
NHASUP_FISH="alias nhasup 'bash \"$NHASUP_TARGET\"'"

# bash + zsh: append to rc files if missing
for rc in "$TARGET_HOME/.zshrc" "$TARGET_HOME/.bashrc"; do
    [[ -f "$rc" ]] || continue
    if grep -q '^alias nhasup=' "$rc" 2>/dev/null; then
        ok "nhasup alias already in $(basename $rc)"
    else
        run_as_user bash -c "printf '\n# NHAS reverse-SSH server launcher\n%s\n' \"$NHASUP_POSIX\" >> '$rc'"
        ok "Added nhasup alias to $(basename $rc)"
    fi
done

# fish: drop into config.fish (created if needed)
FISH_CFG_DIR="$TARGET_HOME/.config/fish"
FISH_CFG="$FISH_CFG_DIR/config.fish"
if command -v fish &>/dev/null || [[ -d "$FISH_CFG_DIR" ]] || [[ "$SHELL" == */fish ]]; then
    run_as_user mkdir -p "$FISH_CFG_DIR"
    if [[ -f "$FISH_CFG" ]] && grep -q '^alias nhasup ' "$FISH_CFG" 2>/dev/null; then
        ok "nhasup alias already in config.fish"
    else
        run_as_user bash -c "printf '\n# NHAS reverse-SSH server launcher\n%s\n' \"$NHASUP_FISH\" >> '$FISH_CFG'"
        ok "Added nhasup alias to config.fish"
    fi
fi

# ─── configure ssh alias for `ssh rssh` ─────────────────────────────
banner "Configuring SSH alias (ssh rssh → localhost:3232)"
SSH_DIR="$TARGET_HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"

run_as_user mkdir -p "$SSH_DIR"
run_as_user chmod 700 "$SSH_DIR"

if grep -q '^Host rssh' "$SSH_CONFIG" 2>/dev/null; then
    ok "~/.ssh/config already has 'Host rssh' entry"
else
    run_as_user bash -c "cat >> '$SSH_CONFIG' << 'EOF'

Host rssh
    HostName 127.0.0.1
    Port 3232
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF"
    run_as_user chmod 600 "$SSH_CONFIG"
    ok "Added 'Host rssh' → localhost:3232 to ~/.ssh/config"
fi

# Ensure the user has an SSH keypair (needed to authenticate to NHAS console)
if ! run_as_user ls "$SSH_DIR"/id_*.pub &>/dev/null 2>&1; then
    warn "No SSH keypair found — generating ed25519 keypair for $TARGET_USER"
    run_as_user ssh-keygen -t ed25519 -N "" -f "$SSH_DIR/id_ed25519" -q && \
        ok "SSH keypair generated at $SSH_DIR/id_ed25519"
else
    ok "SSH keypair already exists"
fi

# Add the user's public key to NHAS's admin authorized_keys file.
# NHAS loads admin keys from bin/authorized_keys in its working directory.
# Without this, `ssh rssh` gets "not authorized" even with a valid keypair.
NHAS_AUTH_KEYS="$WORKSPACE/bin/authorized_keys"
PUBKEY=$(run_as_user cat "$SSH_DIR/id_ed25519.pub" 2>/dev/null || \
         run_as_user ls "$SSH_DIR"/id_*.pub 2>/dev/null | head -1 | xargs cat)

if [[ -z "$PUBKEY" ]]; then
    warn "Could not find a public key to authorize — add one manually to $NHAS_AUTH_KEYS"
else
    run_as_user mkdir -p "$(dirname "$NHAS_AUTH_KEYS")"
    if grep -qF "$PUBKEY" "$NHAS_AUTH_KEYS" 2>/dev/null; then
        ok "Public key already in $NHAS_AUTH_KEYS"
    else
        run_as_user bash -c "echo '$PUBKEY' >> '$NHAS_AUTH_KEYS'"
        ok "Public key added to $NHAS_AUTH_KEYS (restart server to take effect)"
    fi
fi

# ─── check wrapper scripts ───────────────────────────────────────────
banner "Checking wrapper scripts"
for script in nhas-build.sh nhas-start.sh; do
    if [[ -f "$WORKSPACE/$script" ]]; then
        ok "$script found in workspace"
    else
        warn "$script NOT in $WORKSPACE — copy from 1337codes/OSCP-nhas-ssh-server repo"
    fi
done

# ─── verification ────────────────────────────────────────────────────
banner "Verifying build environment"

for tool in go upx git; do
    command -v "$tool" &>/dev/null && \
        ok "$tool ✓" || fail "$tool ✗ MISSING"
done

[[ -f "$GOBIN/garble" ]] && \
    ok "garble ✓ (optional — obfuscated builds enabled)" || \
    warn "garble ✗ not found — obfuscated builds will be skipped"

[[ -f "$WORKSPACE/go.mod" ]] && \
    ok "go.mod ✓ NHAS source confirmed" || \
    fail "go.mod ✗ MISSING — nhas-build.sh will abort"

[[ -f "$WORKSPACE/bin/server" ]] && \
    ok "bin/server ✓ $(du -h "$WORKSPACE/bin/server" | cut -f1)" || \
    warn "bin/server not built"

_SKEY="$WORKSPACE/bin/id_ed25519"
if [[ -f "$_SKEY" ]]; then
    _FPB=$(ssh-keygen -lf "$_SKEY" -E sha256 2>/dev/null | awk '{print $2}' | sed 's/SHA256://')
    _FPH=$(printf '%s==' "$_FPB" | base64 -d 2>/dev/null | xxd -p | tr -d '\n')
    ok "bin/id_ed25519 ✓  fingerprint (hex): ${_FPH}"
else
    fail "bin/id_ed25519 ✗ MISSING — clients will not connect to server"
fi

_CKEY="$WORKSPACE/internal/client/keys/private_key"
[[ -f "$_CKEY" ]] && \
    ok "internal/client/keys/private_key ✓" || \
    fail "internal/client/keys/private_key ✗ MISSING — all client builds will fail"

# ─── done ────────────────────────────────────────────────────────────
echo
echo -e "${G}${B}[✓] NHAS ready to roll.${N}"
echo
echo -e "    ${C}Workspace:${N}  $WORKSPACE"
echo -e "    ${C}Server:${N}     $WORKSPACE/bin/server"
echo -e "    ${C}Exploits:${N}   $WORKSPACE/bin/exploits/"
echo
echo -e "${C}${B}Quick start:${N}"
echo -e "    ${C}# Launch the dashboard + server (after sourcing your shell rc):${N}"
echo -e "    nhasup"
echo
echo -e "    ${C}# Or run it directly:${N}"
echo -e "    bash $WORKSPACE/nhas-start.sh"
echo
echo -e "    ${C}# Build all client variants:${N}"
echo -e "    cd $WORKSPACE && bash nhas-build.sh"
echo
echo -e "    ${C}# Connect to a callback client:${N}"
echo -e "    ssh -p 3232 -i ./bin/client_keys <id>@localhost"
echo
echo -e "${Y}[!] Open a new terminal (or: source ~/.zshrc) to pick up ~/go/bin in PATH.${N}"
