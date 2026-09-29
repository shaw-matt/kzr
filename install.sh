#!/usr/bin/env bash
# install.sh — one-shot bootstrap for kiro-zellij-restore.
#
#   ./install.sh                 install kzr + capture hook, wire your agents
#   ./install.sh --prefix DIR    install the `kzr` command into DIR (default ~/.local/bin)
#   ./install.sh --no-wire       don't touch agent configs (wire later: kzr install-hook)
#   ./install.sh --with-timer    also install a periodic layout-snapshot timer (macOS launchd)
#   ./install.sh --uninstall     remove the installed command + timer (state is kept)
#
# Safe to re-run (idempotent). Only edits files it owns; agent-config edits are
# additive and de-duplicated.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PREFIX="${KZR_PREFIX:-$HOME/.local/bin}"
KZR_HOME="${KZR_HOME:-$HOME/.kiro-zellij}"
LABEL_PLIST="com.kiro-zellij-restore.snapshot"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL_PLIST.plist"

WIRE=1 WITH_TIMER=0 DO_UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix needs a dir}"; shift ;;
    --no-wire) WIRE=0 ;;
    --with-timer) WITH_TIMER=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m ok:\033[0m %s\n' "$*"; }

uninstall() {
  say "Uninstalling kiro-zellij-restore"
  rm -f "$PREFIX/kzr" "$PREFIX/kzr-agent" && ok "removed command(s) from $PREFIX"
  if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    rm -f "$PLIST_PATH" && ok "removed launchd timer"
  fi
  warn "left state in $KZR_HOME and any agentSpawn hooks in ~/.kiro/agents intact."
  warn "remove those manually if desired:  rm -rf \"$KZR_HOME\"  and edit agent JSONs."
  exit 0
}
[ "$DO_UNINSTALL" = 1 ] && uninstall

# ------------------------------------------------------------- dep checks ----
say "Checking dependencies"
missing=0
for dep in jq zellij; do
  if command -v "$dep" >/dev/null 2>&1; then ok "$dep found"; else warn "$dep NOT found (required)"; missing=1; fi
done
if command -v kiro-cli >/dev/null 2>&1; then ok "kiro-cli found"; else warn "kiro-cli not on PATH (set \$KZR_KIRO_BIN if it's named differently)"; fi
if [ "$missing" = 1 ]; then
  warn "install missing deps first (macOS: brew install jq zellij), then re-run."
  exit 1
fi

# ---------------------------------------------------------------- install ----
say "Installing the kzr command into $PREFIX"
mkdir -p "$PREFIX" "$KZR_HOME"
install -m 0755 "$REPO_DIR/bin/kzr" "$PREFIX/kzr"
# Provide a `kzr-agent` shim so zellij layouts can call a single command.
cat > "$PREFIX/kzr-agent" <<EOF
#!/usr/bin/env bash
exec "$PREFIX/kzr" agent "\$@"
EOF
chmod 0755 "$PREFIX/kzr-agent"
ok "installed kzr and kzr-agent"

# Stage the capture hook at a stable absolute path.
install -m 0755 "$REPO_DIR/hooks/kzr-record.sh" "$KZR_HOME/kzr-record.sh"
ok "installed capture hook -> $KZR_HOME/kzr-record.sh"

case ":$PATH:" in
  *":$PREFIX:"*) : ;;
  *) warn "$PREFIX is not on your PATH. Add:  export PATH=\"$PREFIX:\$PATH\"" ;;
esac

# ------------------------------------------------------------- wire hooks ----
if [ "$WIRE" = 1 ]; then
  say "Wiring the agentSpawn capture hook into your Kiro agents"
  if "$PREFIX/kzr" install-hook --all; then :; else
    warn "no agents wired automatically — see guidance above."
  fi
else
  warn "skipped agent wiring (--no-wire). Run later:  kzr install-hook"
fi

# ------------------------------------------------------------- opt timer -----
if [ "$WITH_TIMER" = 1 ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    say "Installing periodic snapshot timer (launchd)"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL_PLIST</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PREFIX/kzr</string>
    <string>snapshot</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>$KZR_HOME/snapshot.log</string>
  <key>StandardOutPath</key><string>$KZR_HOME/snapshot.log</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    launchctl load "$PLIST_PATH" >/dev/null 2>&1 && ok "loaded launchd timer ($LABEL_PLIST, every 60s)" \
      || warn "could not load launchd timer; load manually: launchctl load $PLIST_PATH"
    warn "note: snapshot needs a zellij session; the timer no-ops until one is running."
  else
    warn "timer auto-setup is macOS-only. On Linux, run 'kzr snapshot <session>' from cron/systemd."
  fi
fi

# ----------------------------------------------------------------- doctor ----
say "Running doctor"
"$PREFIX/kzr" doctor || true

cat <<EOF

$(say "Done.")
Next:
  1) Make sure $PREFIX is on your PATH.
  2) Launch each Kiro agent through kzr so it's pinned to its pane:
         kzr agent <label>        # e.g.  kzr agent api   /   kzr agent frontend
     (Use a stable label per pane — a git-worktree/dir name works well.)
  3) After a reboot, bring everything back:
         kzr restore <zellij-session>            # rebuild layout + resume every chat
         kzr restore --native <zellij-session>   # or let zellij resurrect, panes self-resume
  4) Inspect what's captured any time:  kzr status

Uninstall:  ./install.sh --uninstall
EOF
