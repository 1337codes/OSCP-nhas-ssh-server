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
WORKSPACE="$TARGET_HOME/Desktop/OSCP/NHAS"
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

# ─── apt: Go + UPX + git ─────────────────────────────────────────────
banner "Installing Go, UPX, and git"
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq golang-go upx git
ok "golang-go + upx + git installed"

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

# ─── NHAS source: clone or pull ──────────────────────────────────────
banner "Checking NHAS source at $WORKSPACE"

if [[ -f "$WORKSPACE/go.mod" ]]; then
    ok "NHAS source present — pulling latest"
    run_as_user git -C "$WORKSPACE" pull --ff-only 2>&1 | tail -3
else
    if [[ -d "$WORKSPACE" ]]; then
        warn "$WORKSPACE exists but has no go.mod — need to clone NHAS source into it"
        # Clone to temp dir, rsync over (preserves user's existing files)
        TMP_CLONE=$(run_as_user mktemp -d)
        run_as_user git clone --depth=1 "$NHAS_REPO" "$TMP_CLONE" && \
            run_as_user rsync -a --ignore-existing "$TMP_CLONE/" "$WORKSPACE/" && \
            run_as_user rm -rf "$TMP_CLONE" && \
            ok "NHAS source merged into existing workspace"
    else
        run_as_user git clone --depth=1 "$NHAS_REPO" "$WORKSPACE"
        ok "NHAS source cloned to $WORKSPACE"
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

# ─── done ────────────────────────────────────────────────────────────
echo
echo -e "${G}${B}[✓] NHAS ready to roll.${N}"
echo
echo -e "    ${C}Workspace:${N}  $WORKSPACE"
echo -e "    ${C}Server:${N}     $WORKSPACE/bin/server"
echo -e "    ${C}Exploits:${N}   $WORKSPACE/bin/exploits/"
echo
echo -e "${C}${B}Quick start:${N}"
echo -e "    ${C}# Start the server (default port 3232):${N}"
echo -e "    cd $WORKSPACE && ./bin/server -p 3232"
echo
echo -e "    ${C}# Build all client variants:${N}"
echo -e "    cd $WORKSPACE && bash nhas-build.sh"
echo
echo -e "    ${C}# Connect to a callback client:${N}"
echo -e "    ssh -p 3232 -i ./bin/client_keys <id>@localhost"
echo
echo -e "${Y}[!] Open a new terminal (or: source ~/.zshrc) to pick up ~/go/bin in PATH.${N}"
