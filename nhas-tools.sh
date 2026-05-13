#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# nhas-tools.sh — thin launcher for tools.py (DualServe HTTP + SMB)
#
# Called automatically by nhas-start.sh.
# To update your file server: replace tools.py — this script stays the same.
#
# Usage (direct):
#   nhas-tools.sh <serve_dir> <http_port>
#
# Override tools.py location:
#   TOOLS_PY=/path/to/tools.py nhas-tools.sh <serve_dir> <http_port>
#
# SMB is always started on port 445 with share name "evil".
# ─────────────────────────────────────────────────────────────────────────────

SERVE_DIR="${1:-$PWD}"
HTTP_PORT="${2:-80}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'
GRAY=$'\033[0;90m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# ─── Locate tools.py ─────────────────────────────────────────────────────────
# Priority:
#   1. TOOLS_PY env var (explicit override)
#   2. Sibling repo next to OSCP-nhas-ssh-server
#   3. Common install locations under ~/Desktop/Tools and ~/tools

TOOLS_PY="${TOOLS_PY:-}"
_SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

if [[ -z "$TOOLS_PY" ]]; then
    for _candidate in \
        "${_SCRIPT_DIR}/tools.py" \
        "${_SCRIPT_DIR}/../OSCP-HTTP-SMB-File-Transfer-Server/tools.py" \
        "$HOME/Desktop/Tools/OSCP-HTTP-SMB-File-Transfer-Server/tools.py" \
        "$HOME/tools/OSCP-HTTP-SMB-File-Transfer-Server/tools.py" \
        "/opt/tools/OSCP-HTTP-SMB-File-Transfer-Server/tools.py" \
        "/opt/tools/tools.py"
    do
        if [[ -f "$_candidate" ]]; then
            TOOLS_PY="$(realpath "$_candidate")"
            break
        fi
    done
fi

# ─── Fallback: plain python3 http.server ─────────────────────────────────────
if [[ -z "$TOOLS_PY" ]]; then
    echo "${YELLOW}[!]${NC} tools.py not found."
    echo "    Clone your repo next to nhas or set: ${CYAN}TOOLS_PY=/path/to/tools.py${NC}"
    echo "    Expected: ${GRAY}$HOME/Desktop/Tools/OSCP-HTTP-SMB-File-Transfer-Server/tools.py${NC}"
    echo ""
    echo "${YELLOW}[!]${NC} Falling back to ${BOLD}python3 -m http.server ${HTTP_PORT}${NC}"
    echo "${RED}[!]${NC} SMB will NOT be available in fallback mode"
    echo ""
    exec python3 -m http.server "$HTTP_PORT" -d "$SERVE_DIR"
fi

# ─── Launch (silent — only transfer events surface) ──────────────────────────
# Trap kills python3+grep children when nhas-start sends SIGTERM on exit
trap 'kill $(jobs -p) 2>/dev/null; wait' EXIT INT TERM

# PYTHONUNBUFFERED=1: Python flushes every print() immediately when piped.
# Without it stdout is block-buffered and [TRY]/[DONE] lines never appear.
# Filter: TRY=starting, DONE=complete, UP=upload, FAIL=error, SMB HASH=NTLM
PYTHONUNBUFFERED=1 python3 "$TOOLS_PY" -dir "$SERVE_DIR" -p "$HTTP_PORT" -smb 2>&1 |     grep --line-buffered -E '\[(TRY|DONE|UP|FAIL|SAVE)\]|\[SMB\].*\[HASH\]'

# Keep wrapper alive so nhas-start can track and kill by PID
wait