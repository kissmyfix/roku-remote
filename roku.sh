#!/usr/bin/env bash

# ─────────────────────────────────────────────
#  CONFIG — populated by setup wizard on first run
#  To reconfigure: run with --setup flag
# ─────────────────────────────────────────────
ROKU_IP=""
ROKU_APP_NAMES=()
ROKU_APP_IDS=()
# ─────────────────────────────────────────────

SCRIPT="$(readlink -f "$0")"

write_config() {
    local ip="$1"
    shift
    local names=("$@")
    local half=$(( ${#names[@]} / 2 ))
    local name_arr=("${names[@]:0:$half}")
    local id_arr=("${names[@]:$half}")
    local name_str id_str
    name_str=$(printf '"%s" ' "${name_arr[@]}")
    id_str=$(printf '"%s" ' "${id_arr[@]}")
    sed -i \
        -e "s|^ROKU_IP=.*|ROKU_IP=\"${ip}\"|" \
        -e "s|^ROKU_APP_NAMES=.*|ROKU_APP_NAMES=(${name_str})|" \
        -e "s|^ROKU_APP_IDS=.*|ROKU_APP_IDS=(${id_str})|" \
        "$SCRIPT"
}

discover_rokus() {
    python3 - <<'PYEOF'
import socket, re, sys

SSDP_ADDR = "239.255.255.250"
SSDP_PORT = 1900
MSG = (
    "M-SEARCH * HTTP/1.1\r\n"
    "HOST: 239.255.255.250:1900\r\n"
    'MAN: "ssdp:discover"\r\n'
    "ST: roku:ecp\r\n"
    "MX: 3\r\n\r\n"
).encode()

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 4)
sock.settimeout(3)
sock.sendto(MSG, (SSDP_ADDR, SSDP_PORT))

seen = set()
try:
    while True:
        data, _ = sock.recvfrom(65536)
        text = data.decode(errors="ignore")
        m = re.search(r'LOCATION:\s*http://([\d.]+):8060', text)
        if m:
            ip = m.group(1)
            if ip not in seen:
                seen.add(ip)
                print(ip)
except socket.timeout:
    pass
finally:
    sock.close()
PYEOF
}

run_setup() {
    clear
    echo ""
    echo "  ╔════════════════════════════════════╗"
    echo "  ║        ROKU REMOTE  •  SETUP       ║"
    echo "  ╚════════════════════════════════════╝"
    echo ""

    # ── Step 1: Discover or enter IP ─────────
    local ip="" found_ips=() found_names=()

    if command -v python3 &>/dev/null; then
        echo -n "  Scanning for Roku devices..."
        while IFS= read -r candidate; do
            local dname
            dname=$(curl -sf --max-time 2 "http://${candidate}:8060/query/device-info" \

                | sed -n 's|.*<friendly-device-name>\(.*\)</friendly-device-name>.*|\1|p')
            found_ips+=("$candidate")
            found_names+=("${dname:-Roku @ ${candidate}}")
        done < <(discover_rokus)

        if [[ ${#found_ips[@]} -eq 0 ]]; then
            echo " nothing found."
            echo ""
        elif [[ ${#found_ips[@]} -eq 1 ]]; then
            echo " found 1 device."
            echo ""
            echo "  Found: ${found_names[0]} (${found_ips[0]})"
            echo -n "  Use this device? [Y/n]: "
            read -r confirm
            if [[ -z "$confirm" || "$confirm" =~ ^[Yy] ]]; then
                ip="${found_ips[0]}"
            fi
        else
            echo " found ${#found_ips[@]} devices."
            echo ""
            local j
            for j in "${!found_ips[@]}"; do
                printf "  %2d)  %s  (%s)\n" "$((j+1))" "${found_names[$j]}" "${found_ips[$j]}"
            done
            echo ""
            echo -n "  Pick a device (or Enter to type IP manually): "
            read -r pick
            if [[ "$pick" =~ ^[0-9]+$ ]]; then
                local idx=$(( pick - 1 ))
                if [[ $idx -ge 0 && $idx -lt ${#found_ips[@]} ]]; then
                    ip="${found_ips[$idx]}"
                fi
            fi
        fi
    else
        echo "  (python3 not found — skipping discovery)"
        echo ""
    fi

    # Manual fallback
    if [[ -z "$ip" ]]; then
        while true; do
            echo -n "  Roku IP address [e.g. 192.168.1.35]: "
            read -r ip
            [[ -z "$ip" ]] && { echo "  ✗ Required."; continue; }
            echo -n "  Checking ${ip}..."
            if curl -sf --max-time 3 "http://${ip}:8060/query/device-info" > /dev/null 2>&1; then
                echo " ✓"
                break
            else
                echo " ✗ No Roku found at that address. Try again."
                ip=""
            fi
        done
    fi

    echo ""

    # ── Step 2: Fetch app list ───────────────
    echo -n "  Fetching installed apps..."
    local raw
    raw=$(curl -sf --max-time 5 "http://${ip}:8060/query/apps")
    if [[ -z "$raw" ]]; then
        echo " ✗ Failed to fetch app list. Check IP and try again."
        exit 1
    fi
    echo " ✓"
    echo ""

    local all_names=() all_ids=()
    while IFS= read -r line; do
        local app_id app_name
        app_id=$(echo "$line" | sed -n 's/.*id="\([^"]*\)".*/\1/p')
        app_name=$(echo "$line" | sed -n 's|.*>\(.*\)</app>|\1|p')
        [[ -n "$app_id" && -n "$app_name" ]] && {
            all_ids+=("$app_id")
            all_names+=("$app_name")
        }
    done <<< "$raw"

    if [[ ${#all_names[@]} -eq 0 ]]; then
        echo "  ✗ Couldn't parse app list."
        exit 1
    fi

    # ── Step 3: Pick apps ────────────────────
    echo "  Installed apps:"
    echo ""
    local i
    for i in "${!all_names[@]}"; do
        printf "  %3d)  %s\n" "$((i+1))" "${all_names[$i]}"
    done
    echo ""
    echo "  Enter up to 10 app numbers, space-separated."
    echo -n "  Your picks: "
    read -r picks

    local sel_names=() sel_ids=()
    for pick in $picks; do
        local idx=$(( pick - 1 ))
        if [[ $idx -ge 0 && $idx -lt ${#all_names[@]} ]]; then
            sel_names+=("${all_names[$idx]}")
            sel_ids+=("${all_ids[$idx]}")
        fi
        [[ ${#sel_names[@]} -ge 10 ]] && break
    done

    if [[ ${#sel_names[@]} -eq 0 ]]; then
        echo "  ✗ No valid selections. Run --setup again."
        exit 1
    fi

    write_config "$ip" "${sel_names[@]}" "${sel_ids[@]}"

    echo ""
    echo "  ✓ Config saved. Launching remote..."
    sleep 1
    exec "$SCRIPT"
}

reset_config() {
    sed -i \
        -e 's|^ROKU_IP=.*|ROKU_IP=""|' \
        -e 's|^ROKU_APP_NAMES=.*|ROKU_APP_NAMES=()|' \
        -e 's|^ROKU_APP_IDS=.*|ROKU_APP_IDS=()|' \
        "$SCRIPT"
    echo "  Config cleared. Re-run the script to set up."
    exit 0
}


# ── Flag handling ─────────────────────────────
case "$1" in
    --setup) run_setup ;;
    --reset) reset_config ;;
    --help|-h)
        echo ""
        echo "  Usage: $(basename "$0") [flag | command]"
        echo ""
        echo "  Flags:"
        echo "    --setup     Run the first-time configuration wizard"
        echo "    --reset     Clear saved config (IP and app list)"
        echo "    --help,-h   Show this help"
        echo ""
        echo "  CLI commands (no TUI):"
        echo "    up down left right select back home info play fwd rev"
        echo ""
        echo "  No argument opens the TUI remote."
        echo "  Press S inside the TUI to re-run setup without quitting."
        echo ""
        exit 0
        ;;
esac

# ── First-run check ───────────────────────────
if [[ -z "$ROKU_IP" ]]; then
    echo ""
    echo "  No configuration found. Starting setup..."
    echo ""
    sleep 1
    run_setup
fi

ROKU="http://${ROKU_IP}:8060"
ecp() { curl -sf -X POST "$ROKU/$1" > /dev/null; }

# ── CLI passthrough ───────────────────────────
case "$1" in
    up)       ecp "keypress/Up"      ; exit ;;
    down)     ecp "keypress/Down"    ; exit ;;
    left)     ecp "keypress/Left"    ; exit ;;
    right)    ecp "keypress/Right"   ; exit ;;
    select)   ecp "keypress/Select"  ; exit ;;
    back)     ecp "keypress/Back"    ; exit ;;
    home)     ecp "keypress/Home"    ; exit ;;
    info)     ecp "keypress/Info"    ; exit ;;
    play)     ecp "keypress/Play"    ; exit ;;
    fwd)      ecp "keypress/Fwd"     ; exit ;;
    rev)      ecp "keypress/Rev"     ; exit ;;
esac

# ── Terminal launcher ─────────────────────────
if [[ -z "$1" && -z "$ROKU_TUI" ]]; then
    TERM_CMD=""
    for t in gnome-terminal xterm konsole xfce4-terminal lxterminal; do
        command -v "$t" &>/dev/null && { TERM_CMD="$t"; break; }
    done
    if [[ -n "$TERM_CMD" ]]; then
        case "$TERM_CMD" in
            gnome-terminal)
                gnome-terminal --hide-menubar --geometry=44x24 --title="Roku Remote" \
                    -- env ROKU_TUI=1 "$SCRIPT" ;;
            xterm)
                xterm -geometry 44x24 -title "Roku Remote" -e env ROKU_TUI=1 "$SCRIPT" ;;
            *)
                "$TERM_CMD" -e "env ROKU_TUI=1 $SCRIPT" ;;
        esac
        exit
    else
        export ROKU_TUI=1
    fi
fi

# ── Build dynamic app grid ────────────────────
APP_COUNT=${#ROKU_APP_NAMES[@]}

LABELS=(
    "Home"   "Back"   "Info"
    " "      " Up "   " "
    "Left"   " OK "   "Right"
    " "      "Down"   " "
    "Prev"   "Play"   "Next"
)
CMDS=(
    "keypress/Home"   "keypress/Back"   "keypress/Info"
    ""                "keypress/Up"     ""
    "keypress/Left"   "keypress/Select" "keypress/Right"
    ""                "keypress/Down"   ""
    "keypress/Rev"    "keypress/Play"   "keypress/Fwd"
)
SKIP=(3 5 9 11)

i=0
while [[ $i -lt $APP_COUNT ]]; do
    LABELS+=("${ROKU_APP_NAMES[$i]:0:7}")
    CMDS+=("launch/${ROKU_APP_IDS[$i]}")
    (( i++ ))
done

while (( ${#LABELS[@]} % 3 != 0 )); do
    LABELS+=(" ")
    CMDS+=("")
done

TOTAL_CELLS=${#LABELS[@]}
TOTAL_ROWS=$(( TOTAL_CELLS / 3 ))
APPS_START=15

is_skip() {
    local i=$1
    for s in "${SKIP[@]}"; do [[ $i -eq $s ]] && return 0; done
    [[ -z "${CMDS[$i]}" && $i -ge $APPS_START ]] && return 0
    return 1
}

next_cell() {
    local cur=$1 dir=$2 cols=3 rows=$TOTAL_ROWS
    local row=$((cur / cols)) col=$((cur % cols))
    local nr=$row nc=$col
    case $dir in
        up)    nr=$(( (row - 1 + rows) % rows )) ;;
        down)  nr=$(( (row + 1) % rows )) ;;
        left)  nc=$(( (col - 1 + cols) % cols )) ;;
        right) nc=$(( (col + 1) % cols )) ;;
    esac
    local next=$(( nr * cols + nc ))
    is_skip $next && next=$(next_cell $next $dir)
    echo $next
}

cell() {
    local i=$1 cur=$2 label="${LABELS[$1]}"
    if is_skip $i; then
        printf "           "
    elif [[ $i -eq $cur ]]; then
        tput rev; printf "  %-7s  " "$label"; tput sgr0
    else
        printf "  %-7s  " "$label"
    fi
}

BAR=$(printf '═%.0s' $(seq 1 36))
TITLE="       ROKU      REMOTE             "

box_line() {
    local content=$1 hl=$2
    printf "  ║"
    if [[ $hl -eq 1 ]]; then
        tput rev; printf "%-36s" "$content"; tput sgr0
    else
        printf "%-36s" "$content"
    fi
    printf "║\n"
}

draw_legend() {
    local mode=$1 r1
    [[ $mode == "remote" ]] && r1="  Arrows + Enter -> D-Pad / OK" \
                            || r1="  Arrows + Enter -> Move / Select"
    box_line "$r1" 0
    box_line "  Backspace -> Back     Home -> Home" 0
    box_line "  End -> Info          Space -> Play" 0
    [[ $mode == "remote" ]] \
        && box_line "  Tab -> Navigate        S -> Setup" 0 \
        || box_line "  Tab -> Remote          S -> Setup" 0
    box_line "  Esc / Q -> Quit" 0
}

draw_remote() {
    tput clear; echo ""
    echo "  ╔${BAR}╗"
    box_line "$TITLE" 0
    echo "  ╠${BAR}╣"
    box_line "  Apps -- PgUp/PgDn, Enter opens" 0
    local i hl
    for i in "${!ROKU_APP_NAMES[@]}"; do
        hl=0; [[ $APP_SEL -eq $i ]] && hl=1
        box_line "    ${ROKU_APP_NAMES[$i]}" $hl
    done
    echo "  ╠${BAR}╣"
    draw_legend remote
    echo "  ╚${BAR}╝"; echo ""
}

draw_nav() {
    tput clear; echo ""
    echo "  ╔${BAR}╗"
    box_line "$TITLE" 0
    echo "  ╠${BAR}╣"
    local i row col
    for row in $(seq 0 $((TOTAL_ROWS - 1))); do
        printf "  ║  "
        for col in 0 1 2; do
            i=$(( row * 3 + col ))
            cell $i $POS
        done
        printf " ║\n"
    done
    echo "  ╠${BAR}╣"
    draw_legend nav
    echo "  ╚${BAR}╝"; echo ""
}

cleanup() { tput cnorm; tput rmcup; exit; }
trap cleanup INT TERM

tput smcup
tput civis

POS=7
MODE="remote"
APP_SEL=-1

while true; do
    [[ $MODE == "remote" ]] && draw_remote || draw_nav
    IFS= read -rsn1 key

    if [[ $key == $'\x1b' ]]; then
        read -rsn2 -t 0.1 key2
        if [[ $key2 == '[5' || $key2 == '[6' ]]; then
            read -rsn1 -t 0.1 key3
            key2+="$key3"
        fi
        if [[ $MODE == "remote" ]]; then
            case "$key2" in
                '[A') APP_SEL=-1; ecp "keypress/Up"    ;;
                '[B') APP_SEL=-1; ecp "keypress/Down"  ;;
                '[D') APP_SEL=-1; ecp "keypress/Left"  ;;
                '[C') APP_SEL=-1; ecp "keypress/Right" ;;
                '[H') APP_SEL=-1; ecp "keypress/Home"  ;;
                '[F') APP_SEL=-1; ecp "keypress/Info"  ;;
                '[5~')
                    last=$(( APP_COUNT - 1 ))
                    if [[ $APP_SEL -lt 0 ]]; then APP_SEL=$last
                    else APP_SEL=$(( (APP_SEL - 1 + APP_COUNT) % APP_COUNT )); fi
                    ;;
                '[6~')
                    if [[ $APP_SEL -lt 0 ]]; then APP_SEL=0
                    else APP_SEL=$(( (APP_SEL + 1) % APP_COUNT )); fi
                    ;;
                '') cleanup ;;
            esac
        else
            case "$key2" in
                '[A') POS=$(next_cell $POS up)    ;;
                '[B') POS=$(next_cell $POS down)  ;;
                '[D') POS=$(next_cell $POS left)  ;;
                '[C') POS=$(next_cell $POS right) ;;
                '[H') ecp "keypress/Home" ;;
                '[F') ecp "keypress/Info" ;;
                '') cleanup ;;
            esac
        fi

    elif [[ $key == $'\t' ]]; then
        APP_SEL=-1
        [[ $MODE == "remote" ]] && MODE="nav" || MODE="remote"

    elif [[ $key == $'\n' || $key == $'\r' || $key == '' ]]; then
        if [[ $MODE == "remote" ]]; then
            if [[ $APP_SEL -ge 0 ]]; then
                ecp "launch/${ROKU_APP_IDS[$APP_SEL]}"
                APP_SEL=-1
            else
                ecp "keypress/Select"
            fi
        else
            cmd="${CMDS[$POS]}"
            [[ -n $cmd ]] && ecp "$cmd"
        fi

    elif [[ $key == $'\x7f' || $key == $'\x08' ]]; then
        APP_SEL=-1; ecp "keypress/Back"

    elif [[ $key == ' ' ]]; then
        APP_SEL=-1; ecp "keypress/Play"

    elif [[ $key == 's' || $key == 'S' ]]; then
        tput cnorm; tput rmcup
        run_setup

    elif [[ $key == 'q' || $key == 'Q' ]]; then
        cleanup

    elif [[ $MODE == "remote" ]]; then
        APP_SEL=-1
    fi
done
