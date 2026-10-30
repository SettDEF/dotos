#!/usr/bin/env bash
# Screenshot the Dotos window headlessly: any page, any size, with an empty or
# populated throwaway store.
#
#   scripts/shoot.sh 1600 1000 full  /tmp/wide.png            # home
#   scripts/shoot.sh 1040 720  empty /tmp/open.png tasks      # a page key
#   scripts/shoot.sh 1280 800  full  /tmp/s.png sheet:shortcuts
#
# VIEW is whatever `qs ipc call dotos shot` takes: a page key, menu,
# sheet:<name>, task:<uid>, project:<name>, page:<id>. DOTOS_BIN picks the CLI
# (default: the installed one; set it to a fresh build to test new commands).
#
# One capture is a sample, not a verification: shoot every size you claim.
# Runs with no route to the compositor and a throwaway HOME, so it cannot put a
# window on the session or touch the real task store.
set -euo pipefail

[ $# -ge 4 ] || { sed -n '2,16p' "$0" | sed 's/^# \?//'; exit 2; }
W=$1; H=$2; MODE=$3; OUT=$4; VIEW=${5:-home}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER=~/.claude/skills/hands-off-desktop/scripts/headless-qt.sh
[ -x "$HELPER" ] || { echo "need $HELPER" >&2; exit 1; }

HOME_DIR=$(mktemp -d)
PID=
trap '[ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$HOME_DIR"' EXIT
mkdir -p "$HOME_DIR/.config/dotos" "$HOME_DIR/.local/share/dotos/lists/personal"
cp ~/.config/kdeglobals "$HOME_DIR/.config/" 2>/dev/null || true
printf '{"windowWidth":%s,"windowHeight":%s,"tasksView":"%s"%s}\n' "$W" "$H" "$([ "$VIEW" = board ] && echo board || echo list)" "${GUI_EXTRA:-}" > "$HOME_DIR/.config/dotos/gui.json"

if [ "$MODE" = "full" ]; then
  d=$(date +%F)
  i=0
  for row in "Call dentist|3|PRIORITY:1|30" "Write report|0|PRIORITY:5|120" "Send invoice|1|PRIORITY:5|15" "Water plants|0|PRIORITY:9|10"; do
    IFS='|' read -r title off pri est <<<"$row"; i=$((i+1))
    due=$(date -d "$d $off days ago" +%Y%m%d 2>/dev/null || date +%Y%m%d)
    printf 'BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//fixture//EN\nBEGIN:VTODO\nUID:t%s\nDTSTAMP:20260929T120000Z\nSUMMARY:%s\nDUE;VALUE=DATE:%s\n%s\nCATEGORIES:demo\nX-DOTOS-ESTIMATE:%s\nEND:VTODO\nEND:VCALENDAR\n' \
      "$i" "$title" "$due" "$pri" "$est" > "$HOME_DIR/.local/share/dotos/lists/personal/t$i.ics"
  done
  # three weeks of history: finished tasks, and timewarrior entries tagged like Dotos' own
  TW="$HOME_DIR/.local/share/timewarrior/data"; mkdir -p "$TW"
  for k in $(seq 1 24); do
    day=$(date -d "$k days ago" +%Y%m%d); mon=$(date -d "$k days ago" +%Y-%m)
    for j in $(seq 1 $(( (k * 7) % 4 + 1 ))); do
      printf 'BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//fixture//EN\nBEGIN:VTODO\nUID:h%s-%s\nDTSTAMP:%sT090000Z\nSUMMARY:Finished %s-%s\nSTATUS:COMPLETED\nCOMPLETED:%sT1%s0000Z\nCREATED:%sT080000Z\nX-DOTOS-ESTIMATE:%s\nEND:VTODO\nEND:VCALENDAR\n' \
        "$k" "$j" "$day" "$k" "$j" "$day" "$j" "$day" "$(( 20 + j * 10 ))" > "$HOME_DIR/.local/share/dotos/lists/personal/h$k-$j.ics"
    done
    proj=$([ $((k % 3)) -eq 0 ] && echo tela || echo loom)
    [ $((k % 6)) -eq 5 ] && continue
    printf 'inc %sT070000Z - %sT%02d0000Z # "+%s" "dotos:h%s-1" "Finished %s-1"\n' "$day" "$day" "$(( k % 3 + 8 ))" "$proj" "$k" "$k" >> "$TW/$mon.data"
    printf 'inc %sT120000Z - %sT%02d3000Z # "+tinct" "Review"\n' "$day" "$day" "$(( k % 2 + 13 ))" >> "$TW/$mon.data"
  done
  # EXTRA_TASKS=7: that many due-today tasks with no estimate; TRACK_TODAY_MIN=230: that much already tracked today
  for i in $(seq 1 ${EXTRA_TASKS:-0}); do
    printf 'BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//fixture//EN\nBEGIN:VTODO\nUID:x%s\nDTSTAMP:20260929T120000Z\nSUMMARY:Loom step %s: a longer task title for the layout\nDUE;VALUE=DATE:%s\nX-DOTOS-PROJECT:loom\nEND:VTODO\nEND:VCALENDAR\n' "$i" "$i" "$(date +%Y%m%d)" > "$HOME_DIR/.local/share/dotos/lists/personal/x$i.ics"
  done
  # THREAD_FIXTURE=1: a conversation on t1 (Call dentist): a person, a reply, an agent (the panel's Conversation)
  if [ -n "${THREAD_FIXTURE:-}" ]; then
    TH="$HOME_DIR/.local/share/dotos/threads"; mkdir -p "$TH"; now=$(date +%s)
    printf '{"id":"m1","item":"task:t1","author":"caesar","name":"Caesar","text":"@anna can you call them before 5? I am in the meeting","ts":%s,"mentions":["anna"]}\n{"id":"m2","item":"task:t1","author":"anna","name":"Anna","text":"sure, which number, the new one?","ts":%s}\n{"id":"m3","item":"task:t1","author":"agent:claude","name":"agent:claude","text":"Found it in your contacts: the practice moved, the new number is in the task notes.","ts":%s}\n' $((now-3600)) $((now-1800)) $((now-120)) > "$TH/task_t1.jsonl"
    sed -i "s/^END:VTODO/X-DOTOS-ASSIGNEE:anna\nEND:VTODO/" "$HOME_DIR/.local/share/dotos/lists/personal/t3.ics"
    sed -i "s/^END:VTODO/X-DOTOS-DECISION:m2 Anna calls, the new number from the notes\nEND:VTODO/" "$HOME_DIR/.local/share/dotos/lists/personal/t1.ics"
  fi
  # GRAPH_FIXTURE=1: a task linked to a note, a commit, and a subtask it also blocks (the graph, the local graph)
  if [ -n "${GRAPH_FIXTURE:-}" ]; then
    L="$HOME_DIR/.local/share/dotos/lists/personal"
    # an AI session on g1 and what it did (the panel's Agent activity, the graph's file nodes)
    AG="$HOME_DIR/agents"; mkdir -p "$AG" "$HOME_DIR/.local/state/ai-activity"
    now=$(date +%s)
    printf '{"id":"claude-fx","source":"claude-code","project":"loom","cwd":"/src/loom","state":"working","started":%s,"updated":%s,"prompt":"fix the click after a workspace switch"}\n' "$((now-900))" "$now" > "$AG/claude-fx.json"
    A="$HOME_DIR/.local/state/ai-activity/claude-fx.jsonl"
    for r in "600|cmd|cargo build --release|true|build" "560|read|/src/loom/src/binds.rs|true|" "500|edit|/src/loom/src/binds.rs|true|" "420|create|/src/loom/scripts/zen-input-probe.sh|true|" "300|cmd|scripts/zen-input-probe.sh|false|probe" "200|delete|/src/loom/old-notes.txt|true|" "100|cmd|git commit -m binds|true|commit"; do
      IFS='|' read -r ago kind what ok det <<<"$r"
      err=null; [ "$ok" = false ] && err='"FAIL  click after a workspace switch (page saw: md1 mu1 cl0 hc0)"'
      printf '{"t":%s,"tool":"x","kind":"%s","what":"%s","detail":"%s","ok":%s,"error":%s,"task":"g1"}\n' "$((now-ago))" "$kind" "$what" "$det" "$ok" "$err" >> "$A"
    done
    printf 'BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//fixture//EN\nBEGIN:VTODO\nUID:g1\nDTSTAMP:20260929T120000Z\nSUMMARY:Graph lead\nX-DOTOS-PROJECT:loom\nX-DOTOS-LINK:%s/.local/share/dotos/pages/loom.md\nX-DOTOS-LINK:git:loom@2897a65\nX-DOTOS-LINK:agent:claude-fx\nEND:VTODO\nEND:VCALENDAR\n' "$HOME_DIR" > "$L/g1.ics"
    printf 'BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//fixture//EN\nBEGIN:VTODO\nUID:g2\nDTSTAMP:20260929T120000Z\nSUMMARY:Graph sub step\nX-DOTOS-PROJECT:loom\nX-DOTOS-PARENT:g1\nX-DOTOS-BLOCKED:g1\nEND:VTODO\nEND:VCALENDAR\n' > "$L/g2.ics"
  fi
  if [ -n "${TRACK_TODAY_MIN:-}" ]; then
    printf 'inc %s - %s # "+loom" "work"\n' "$(date -u -d "01:00 today" +%Y%m%dT%H%M%SZ)" "$(date -u -d "01:00 today + ${TRACK_TODAY_MIN} minutes" +%Y%m%dT%H%M%SZ)" >> "$TW/$(date +%Y-%m).data"
  fi
  mkdir -p "$HOME_DIR/.local/share/dotos/pages"
  P="$HOME_DIR/.local/share/dotos/pages"
  printf -- "---\ntitle: Home\ntags: index\n---\n# Home\n[[Research]] [[Loom]] [[Ideas]]\n" > "$P/home.md"
  printf -- "---\ntitle: Research\nproject: loom\n---\n# Research\n[[Compositors]] [[Smithay]] [[Home]]\n" > "$P/research.md"
  printf -- "---\ntitle: Loom\nproject: loom\n---\n# Loom\n[[Compositors]] [[Protocols]] [[Not written yet]]\n" > "$P/loom.md"
  printf -- "---\ntitle: Compositors\n---\n# Compositors\n[[Protocols]]\n" > "$P/compositors.md"
  printf -- "---\ntitle: Protocols\n---\n# Protocols\n" > "$P/protocols.md"
  printf -- "---\ntitle: Ideas\n---\n# Ideas\n[[Home]] [[Loom]]\n" > "$P/ideas.md"
  printf -- "---\ntitle: Smithay\n---\n# Smithay\nThe base Loom is built on. [[Protocols]]\n" > "$P/smithay.md"
fi

# a fake kalends, so the calendar cards and the Plan timeline have meetings to show
mkdir -p "$HOME_DIR/.local/bin"
cat > "$HOME_DIR/.local/bin/kalends" <<'KAL'
#!/bin/sh
d=$(date +%F)
echo "[{\"summary\":\"Team sync\",\"calendar\":\"work\",\"start\":\"${d}T11:00:00\",\"end\":\"${d}T12:00:00\",\"all_day\":false},{\"summary\":\"Dentist call\",\"calendar\":\"personal\",\"start\":\"${d}T14:00:00\",\"end\":\"${d}T14:30:00\",\"all_day\":false}]"
KAL
chmod +x "$HOME_DIR/.local/bin/kalends"
PID=$(HOME="$HOME_DIR" DOTOS_AGENTS_DIR="$HOME_DIR/agents" XDG_CONFIG_HOME="$HOME_DIR/.config" TIMEWARRIORDB="$HOME_DIR/.local/share/timewarrior" DOTOS_NO_ACTIONS=1 DOTOS_BIN="${DOTOS_BIN:-$HOME/.local/bin/dotos}" "$HELPER" qs -p "$HERE/dotos.qml" 2>"$HOME_DIR/helper.err")
LOG=$(sed -n "s/^log: //p" "$HOME_DIR/helper.err")
# the app writes its defaults over gui.json as it starts; put the fixture back once it is up (the file is watched)
sleep 3
printf '{"windowWidth":%s,"windowHeight":%s,"tasksView":"%s"%s}\n' "$W" "$H" "$([ "$VIEW" = board ] && echo board || echo list)" "${GUI_EXTRA:-}" > "$HOME_DIR/.config/dotos/gui.json"
sleep 1
rm -f "$OUT"
# SETTLE=6 lets an animated page (the graph layout) come to rest first; start on it with DOTOS_PAGE=graph
sleep "${SETTLE:-0}"
for _ in $(seq 1 30); do
  sleep 1
  qs ipc --pid "$PID" call dotos shot "$OUT" "$VIEW" >/dev/null 2>&1 && break
done
sleep 4
# QML problems are the usual reason a page comes out blank
[ -n "${LOG:-}" ] && { grep -E "ERROR|WARN|Error|is not a type|not defined" "$LOG" | grep -Ev "iidecor|portal|Wayland" | head -"${ERRS:-12}" >&2 || true; }
[ -s "$OUT" ] && echo "wrote $OUT ($(stat -c%s "$OUT") bytes)" || { echo "no capture produced (view '$VIEW')" >&2; exit 1; }
