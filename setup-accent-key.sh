#!/usr/bin/env bash
# Turn any key into a Spanish-style dead accent key on KDE Plasma (Wayland).
#   key          -> dead acute     (key, then e  => é)
#   Shift + key  -> dead diaeresis (Shift+key, then u => ü)
#
# Usage:  ./setup-accent-key.sh          interactive setup
#         ./setup-accent-key.sh --undo   remove everything this script set up

set -euo pipefail

XKB_DIR="$HOME/.config/xkb"
SYMBOLS_FILE="$XKB_DIR/symbols/custom"
RULES_FILE="$XKB_DIR/rules/evdev"
REGISTRY_FILE="$XKB_DIR/rules/evdev.xml"
OPTION="custom:spanish_accent"
KEYCODES_FILE="/usr/share/X11/xkb/keycodes/evdev"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

ask_yn() { # ask_yn "question" default(y|n)
    local reply prompt="[y/N]"
    [[ $2 == y ]] && prompt="[Y/n]"
    read -rp "$1 $prompt " reply
    reply=${reply:-$2}
    [[ $reply =~ ^[Yy] ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

# Current kxkbrc options with our option removed, comma-joined.
other_options() {
    local current
    current=$(kreadconfig6 --file kxkbrc --group Layout --key Options 2>/dev/null || true)
    tr ',' '\n' <<<"$current" | grep -v -x -e "$OPTION" -e '' | paste -sd, - || true
}

backup() { # back up a file we're about to overwrite, unless it's one we wrote
    if [[ -f $1 ]] && ! grep -q 'spanish_accent' "$1"; then
        local bak
        bak="$1.bak.$(date +%Y%m%d%H%M%S)"
        cp "$1" "$bak"
        warn "Existing $1 backed up to $bak"
    fi
}

# ---------------------------------------------------------------- undo

if [[ ${1:-} == --undo ]]; then
    if have kwriteconfig6; then
        kwriteconfig6 --file kxkbrc --group Layout --key Options "$(other_options)"
    fi
    rm -f "$SYMBOLS_FILE" "$RULES_FILE" "$REGISTRY_FILE"
    bold "Removed. Log out and back in for it to take effect."
    exit 0
fi

# ---------------------------------------------------------------- checks

[[ -r $KEYCODES_FILE ]] || die "Can't find $KEYCODES_FILE (is xkb-data installed?)"

if [[ ${XDG_SESSION_TYPE:-} == x11 ]]; then
    warn "You're on an X11 session. This setup only works on Wayland, because"
    warn "X11 doesn't read ~/.config/xkb."
    ask_yn "Continue anyway?" n || exit 1
fi

# ---------------------------------------------------------------- detect key

# Reads raw key events from /dev/input (needs root) and prints the evdev
# code of the first key pressed. Works for modifier keys like Right Ctrl,
# which a terminal never sees on their own.
read -r -d '' DETECT_PY <<'PY' || true
import glob, os, select, struct, sys, time
FMT = "llHHi"
SZ = struct.calcsize(FMT)
fds = []
for path in sorted(glob.glob("/dev/input/event*")):
    try:
        fds.append(os.open(path, os.O_RDONLY | os.O_NONBLOCK))
    except OSError:
        pass
if not fds:
    sys.exit(2)
time.sleep(0.4)  # let the Enter key you just pressed be released, then discard it
for fd in fds:
    try:
        while os.read(fd, SZ * 64):
            pass
    except BlockingIOError:
        pass
print(">>> Press the key now (30 s timeout)...", file=sys.stderr, flush=True)
deadline = time.time() + 30
while (left := deadline - time.time()) > 0:
    ready, _, _ = select.select(fds, [], [], left)
    for fd in ready:
        try:
            data = os.read(fd, SZ * 64)
        except BlockingIOError:
            continue
        for i in range(0, len(data) - SZ + 1, SZ):
            _, _, etype, code, value = struct.unpack(FMT, data[i:i + SZ])
            # EV_KEY press; codes >= 256 are mouse/joystick buttons
            if etype == 1 and value == 1 and code < 256:
                print(code)
                sys.exit(0)
sys.exit(1)
PY

# evdev code -> XKB key name like RCTL (XKB keycode = evdev code + 8)
xkb_name_for_code() {
    grep -oP '<\K[A-Z0-9]+(?=>\s*=\s*'"$(($1 + 8))"';)' "$KEYCODES_FILE" | head -n1
}

friendly_name() { # best-effort human name for an evdev code
    local hdr=/usr/include/linux/input-event-codes.h
    if [[ -r $hdr ]]; then
        grep -m1 -oP "^#define \KKEY_\w+(?=\s+$1\b)" "$hdr" || true
    fi
}

detect_key() {
    have python3 || return 1
    echo
    bold "Key detection needs to read your keyboard directly, which requires sudo."
    local code
    code=$(sudo python3 -c "$DETECT_PY") || return 1
    KEY_NAME=$(xkb_name_for_code "$code")
    [[ -n $KEY_NAME ]] || { warn "Key code $code isn't in the XKB keycode list."; return 1; }
    KEY_LABEL=$(friendly_name "$code")
    KEY_LABEL=${KEY_LABEL:-"evdev code $code"}
}

manual_key() {
    echo
    echo "Enter the XKB key name instead, e.g. RCTL (Right Ctrl), MENU (Menu key),"
    echo "RALT (AltGr), BKSL (# key), CAPS (Caps Lock), RWIN (Right Super)."
    while true; do
        read -rp "Key name: " KEY_NAME
        KEY_NAME=${KEY_NAME^^}
        KEY_NAME=${KEY_NAME//[<>]/}
        if grep -qP "<$KEY_NAME>\s*=" "$KEYCODES_FILE"; then
            KEY_LABEL="<$KEY_NAME>"
            return
        fi
        warn "'$KEY_NAME' isn't a known key name, try again."
    done
}

bold "Spanish accent key setup"
echo "You'll press the key you want to turn into the accent key."
echo "Afterwards:  key, then a vowel   -> á é í ó ú"
echo "             Shift+key, then u   -> ü"
echo
read -rp "Press Enter when you're ready..." _

while true; do
    if detect_key; then
        echo
        bold "Detected: $KEY_LABEL  (XKB name <$KEY_NAME>)"
        read -rp "Use this key? [Y]es / [r]etry / [m]anual entry / [q]uit: " choice
        case ${choice:-y} in
            [Yy]*) break ;;
            [Rr]*) continue ;;
            [Mm]*) manual_key; break ;;
            *) exit 1 ;;
        esac
    else
        warn "Couldn't detect a key press."
        if ask_yn "Retry detection?" y; then continue; fi
        manual_key
        break
    fi
done

# ---------------------------------------------------------------- key warnings

KEEP_HASH=false
case $KEY_NAME in
    RALT)
        warn "This is AltGr. You'll lose all AltGr characters (€, @ on some layouts, etc.)."
        ask_yn "Use it anyway?" n || exit 1 ;;
    LCTL|LFSH|RTSH|LALT|LWIN|RWIN)
        warn "<$KEY_NAME> is a modifier you probably use for shortcuts; it will stop working as one."
        ask_yn "Use it anyway?" n || exit 1 ;;
    BKSL)
        echo "This is the # key. Its normal characters can move to AltGr:"
        echo "  AltGr+key -> #   AltGr+Shift+key -> ~"
        ask_yn "Keep # and ~ on AltGr?" y && KEEP_HASH=true ;;
    RTRN|SPCE|BKSP|TAB|ESC)
        warn "<$KEY_NAME> is a key you need for normal typing."
        ask_yn "Use it anyway?" n || exit 1 ;;
esac

if [[ $KEY_NAME =~ ^A[A-E][0-9]{2}$ || $KEY_NAME == TLDE || $KEY_NAME == LSGT ]]; then
    warn "<$KEY_NAME> normally types a character; you'll lose it."
    ask_yn "Use it anyway?" n || exit 1
fi

# ---------------------------------------------------------------- write files

if $KEEP_HASH; then
    KEY_BODY='        type[Group1] = "FOUR_LEVEL",
        symbols[Group1] = [ dead_acute, dead_diaeresis, numbersign, asciitilde ],
        actions[Group1] = [ NoAction(), NoAction(), NoAction(), NoAction() ]'
else
    KEY_BODY='        type[Group1] = "TWO_LEVEL",
        symbols[Group1] = [ dead_acute, dead_diaeresis ],
        actions[Group1] = [ NoAction(), NoAction() ]'
fi

mkdir -p "$XKB_DIR/symbols" "$XKB_DIR/rules"
backup "$SYMBOLS_FILE"
backup "$RULES_FILE"
backup "$REGISTRY_FILE"

cat > "$SYMBOLS_FILE" <<EOF
partial modifier_keys
xkb_symbols "spanish_accent" {
    key <$KEY_NAME> {
$KEY_BODY
    };
};
EOF

cat > "$RULES_FILE" <<EOF
! include %S/evdev

! option = symbols
  $OPTION = +custom(spanish_accent)
EOF

cat > "$REGISTRY_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xkbConfigRegistry SYSTEM "xkb.dtd">
<xkbConfigRegistry version="1.1">
  <optionList>
    <group allowMultipleSelection="true">
      <configItem>
        <name>custom</name>
        <description>Custom options</description>
      </configItem>
      <option>
        <configItem>
          <name>$OPTION</name>
          <description>$KEY_LABEL as Spanish accent key</description>
        </configItem>
      </option>
    </group>
  </optionList>
</xkbConfigRegistry>
EOF

echo
bold "Wrote:"
echo "  $SYMBOLS_FILE"
echo "  $RULES_FILE"
echo "  $REGISTRY_FILE"

# ---------------------------------------------------------------- enable

echo
if have kreadconfig6 && have kwriteconfig6; then
    others=$(other_options)
    [[ -n $others ]] && echo "Your existing keyboard options will be kept: $others"
    if ask_yn "Enable the option now (instead of ticking it in System Settings)?" y; then
        kwriteconfig6 --file kxkbrc --group Layout --key ResetOldOptions true
        kwriteconfig6 --file kxkbrc --group Layout --key Options "${others:+$others,}$OPTION"
        echo
        bold "Done. Log out and back in to start using it."
    else
        echo
        bold "Next steps:"
        echo "  1. Log out and back in."
        echo "  2. System Settings -> Keyboard -> Key Bindings -> Custom options:"
        echo "     tick '$KEY_LABEL as Spanish accent key', then Apply."
    fi
else
    warn "kwriteconfig6 not found; enable it manually:"
    echo "  Log out and in, then System Settings -> Keyboard -> Key Bindings ->"
    echo "  Custom options -> '$KEY_LABEL as Spanish accent key' -> Apply."
fi

echo
echo "Tip: this doesn't give you ñ. Pair it with a Compose key (Compose ~ n)."
echo "Undo any time with: $0 --undo"
