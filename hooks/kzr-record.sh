#!/usr/bin/env bash
# kzr-record.sh — Kiro `agentSpawn` hook that records which Kiro session is
# running in which zellij pane, so kiro-zellij-restore can resume the right
# chat in the right pane after a crash/restart.
#
# CRITICAL: an agentSpawn hook's STDOUT (on exit 0) is injected into the agent's
# context. This script must therefore print NOTHING to stdout. It writes only to
# files under $KZR_HOME and always exits 0 so it never shows a warning to the user.
#
# Input : Kiro hook event JSON on stdin, e.g. {"hook_event_name":"agentSpawn","cwd":"/path"}
# Env   : KIRO_SESSION_ID (set by Kiro), ZELLIJ_SESSION_NAME, ZELLIJ_PANE_ID (set by zellij),
#         KZR_LABEL (optional, set by the `kzr agent` wrapper), KZR_HOME (state dir).

# Never let an error surface to the user or pollute context.
{
  KZR_HOME="${KZR_HOME:-$HOME/.kiro-zellij}"
  mkdir -p "$KZR_HOME" 2>/dev/null || true

  registry="$KZR_HOME/registry.jsonl"
  pins="$KZR_HOME/pins.json"

  # Read the hook event (may be empty); extract cwd, fall back to $PWD.
  _input="$(cat 2>/dev/null || true)"
  _cwd=""
  if command -v jq >/dev/null 2>&1 && [ -n "$_input" ]; then
    _cwd="$(printf '%s' "$_input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  fi
  [ -z "$_cwd" ] && _cwd="${PWD:-}"

  _sid="${KIRO_SESSION_ID:-}"
  _zs="${ZELLIJ_SESSION_NAME:-}"
  _pane="${ZELLIJ_PANE_ID:-}"
  _label="${KZR_LABEL:-}"

  # Only record when we have both a Kiro session and a zellij session.
  if [ -n "$_sid" ] && [ -n "$_zs" ]; then
    [ -z "$_label" ] && _label="pane-${_pane:-x}"
    _key="$_zs/$_label"
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

    if command -v jq >/dev/null 2>&1; then
      # Append an immutable audit line to the registry.
      jq -cn \
        --arg ts "$_ts" --arg zs "$_zs" --arg pane "$_pane" \
        --arg label "$_label" --arg cwd "$_cwd" --arg sid "$_sid" \
        '{ts:$ts, zellij_session:$zs, pane_id:$pane, label:$label, cwd:$cwd, kiro_session_id:$sid}' \
        >> "$registry" 2>/dev/null || true

      # Upsert the current pin for this pane/label.
      [ -s "$pins" ] || printf '{}\n' > "$pins" 2>/dev/null || true
      _tmp="$(mktemp "${TMPDIR:-/tmp}/kzr.pins.XXXXXX" 2>/dev/null || echo "$pins.tmp")"
      if jq \
          --arg k "$_key" --arg sid "$_sid" --arg cwd "$_cwd" --arg label "$_label" \
          --arg zs "$_zs" --arg pane "$_pane" --arg ts "$_ts" \
          '.[$k] = {session_id:$sid, cwd:$cwd, label:$label, zellij_session:$zs, pane_id:$pane, updated_at:$ts}' \
          "$pins" > "$_tmp" 2>/dev/null; then
        mv "$_tmp" "$pins" 2>/dev/null || rm -f "$_tmp" 2>/dev/null || true
      else
        rm -f "$_tmp" 2>/dev/null || true
      fi
    else
      # jq missing: still capture a raw audit line so nothing is lost.
      printf '{"ts":"%s","zellij_session":"%s","pane_id":"%s","label":"%s","cwd":"%s","kiro_session_id":"%s"}\n' \
        "$_ts" "$_zs" "$_pane" "$_label" "$_cwd" "$_sid" >> "$registry" 2>/dev/null || true
    fi
  fi
} >/dev/null 2>&1

# Absolutely no stdout, and never fail the hook.
exit 0
