#!/usr/bin/env bash
# Install Dotos for the current user — no root, nothing outside $HOME.
#
#   ./install.sh                    build and install (or update) everything
#   ./install.sh --no-serve         skip the background service (reminders, sources)
#   ./install.sh --update-extensions  overwrite the bundled extensions with this version's
#   ./install.sh --uninstall        remove what this script installed (your tasks, pages and settings stay)
#
# Puts:
#   ~/.local/bin/dotos                      the CLI (Rust) — the one door to the data
#   ~/.local/bin/dotos-gui                  starts the window
#   ~/.local/share/dotos-app/               the window (QML, run by quickshell)
#   ~/.local/share/applications/dotos.desktop, and its icon
#   ~/.config/dotos/extensions/             the bundled extensions — only ones you do not
#                                           already have, so your edits are never replaced
#   ~/.config/systemd/user/dotos-serve.service   reminders + extension sources
#
# Your data is not touched: tasks in ~/.local/share/dotos/lists (VTODO),
# pages and journal in ~/.local/share/dotos, the change log in ~/.local/state/dotos.
#
# Needs: cargo (to build), quickshell (`qs`, for the window). Optional:
# timewarrior (time tracking), ripgrep (TODO comments), gh (GitHub).
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
SRC=$PWD
BIN=${XDG_BIN_HOME:-$HOME/.local/bin}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
CONF=${XDG_CONFIG_HOME:-$HOME/.config}
APP=$DATA/dotos-app
UNIT=$CONF/systemd/user/dotos-serve.service

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

SERVE=1 UPDATE_EXT=0
for a in "$@"; do
    case $a in
        --no-serve) SERVE=0 ;;
        --update-extensions) UPDATE_EXT=1 ;;
        --uninstall)
            say "removing Dotos"
            if [ -f "$UNIT" ]; then
                systemctl --user disable --now dotos-serve.service 2>/dev/null || true
                rm -f -- "$UNIT"
            fi
            rm -f -- "$BIN/dotos" "$BIN/dotos-gui" "$DATA/applications/dotos.desktop" \
                     "$DATA/icons/hicolor/scalable/apps/dotos.svg"
            [ -n "${APP:-}" ] && rm -rf -- "${APP:?}"
            say "done — tasks, pages, journal, habits and settings were left in place"
            exit 0 ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) die "unknown option $a (try --help)" ;;
    esac
done

command -v cargo >/dev/null || die "cargo is needed to build dotos (https://rustup.rs)"
command -v qs >/dev/null || command -v quickshell >/dev/null \
    || warn "quickshell (qs) is not installed: the CLI will work, the window will not"
for opt in timew rg gh; do command -v $opt >/dev/null || warn "optional: $opt is not installed"; done

say "building"
# the cargo workspace is the folder above (icalcore, kalends, dotos)
(cd .. && nice -n 19 cargo build --release --quiet -j 4 -p dotos)
TARGET=${CARGO_TARGET_DIR:-$SRC/../target}/release/dotos
[ -x "$TARGET" ] || die "build produced no binary at $TARGET"

say "installing the CLI to $BIN"
mkdir -p "$BIN"
# a new inode, so a running `dotos serve` keeps its old binary until restarted
cp -f "$TARGET" "$BIN/dotos.new"
chmod 755 "$BIN/dotos.new"
mv -f "$BIN/dotos.new" "$BIN/dotos"

say "installing the window to $APP"
mkdir -p "$APP"
rm -rf -- "${APP:?}/gui.new"
mkdir -p "$APP/gui.new"
cp -rL "$SRC/dotos.qml" "$SRC/modules" "$SRC/ui" "$APP/gui.new/"
rm -rf -- "${APP:?}/gui"
mv "$APP/gui.new" "$APP/gui"

cat > "$BIN/dotos-gui" <<EOF
#!/bin/sh
# Starts the Dotos window (installed by $SRC/install.sh).
# DOTOS_PAGE=<page> opens on that page (home, tasks, board, projects, agents, …); "capture" opens on Home with a new task being typed.
QS=\$(command -v qs || command -v quickshell) || { echo "dotos-gui: quickshell (qs) is not installed" >&2; exit 1; }
export DOTOS_BIN="$BIN/dotos"
[ -n "\${1:-}" ] && export DOTOS_PAGE="\$1"
exec "\$QS" -p "$APP/gui/dotos.qml"
EOF
chmod 755 "$BIN/dotos-gui"

say "installing the launcher entry and icon"
mkdir -p "$DATA/applications" "$DATA/icons/hicolor/scalable/apps"
# a new file swapped in, never rewritten in place: a launcher reading it mid-copy
# cached a blank icon for the rest of the session (2026-10-16)
cp -f packaging/dotos.svg "$DATA/icons/hicolor/scalable/apps/.dotos.svg.new" && mv -f "$DATA/icons/hicolor/scalable/apps/.dotos.svg.new" "$DATA/icons/hicolor/scalable/apps/dotos.svg"
sed "s|dotos-gui|$BIN/dotos-gui|g" packaging/dotos.desktop > "$DATA/applications/dotos.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database -q "$DATA/applications" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$DATA/icons/hicolor" 2>/dev/null || true

say "bundled extensions → $CONF/dotos/extensions"
mkdir -p "$CONF/dotos/extensions"
added=0 kept=0
for f in extensions/*; do
    dest=$CONF/dotos/extensions/$(basename "$f")
    if [ -e "$dest" ] && [ $UPDATE_EXT = 0 ]; then kept=$((kept + 1)); continue; fi
    # a folder is a view extension (view.qml, maybe a program): copied whole
    if [ -d "$f" ]; then rm -rf -- "${dest:?}"; cp -r "$f" "$dest"; else cp -f "$f" "$dest"; chmod +x "$dest"; fi
    added=$((added + 1))
done
say "  $added added, $kept already there (kept as they are; --update-extensions replaces them)"
# Sources start switched off on a first install: they write into your task
# list on a schedule, and that should be your decision, made on the Extensions page.
if [ ! -f "$CONF/dotos/config.json" ]; then
    printf '{\n  "disabledExtensions": ["todo-comments", "github"]\n}\n' > "$CONF/dotos/config.json"
    say "  sources (TODO comments, GitHub) start switched off — turn them on in Extensions"
fi

if [ $SERVE = 1 ]; then
    say "background service (dotos serve: reminders, extension sources)"
    mkdir -p "$(dirname "$UNIT")"
    cat > "$UNIT" <<EOF
[Unit]
Description=Dotos: reminders and extension sources
After=graphical-session.target

[Service]
ExecStart=$BIN/dotos serve
Restart=on-failure
RestartSec=30
Nice=10
# quiet: a sync is never urgent
IOSchedulingClass=idle

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable dotos-serve.service >/dev/null 2>&1 || true
    systemctl --user restart dotos-serve.service
fi

case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not on your PATH — add it, or run $BIN/dotos directly" ;; esac
say "installed: 'dotos' in a terminal, 'dotos-gui' or Dotos in your launcher"
