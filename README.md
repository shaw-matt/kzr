# kiro-zellij-restore (`kzr`)

Resume your **Kiro CLI chats** *and* your **zellij layout** after an unexpected
restart — with one command. Built for people running **multiple Kiro agents in
multiple zellij panes** who lose track of which chat belonged to which pane when
the machine reboots.

> **Your chats were never actually lost.** Kiro CLI auto-saves every session on
> every turn to `~/.kiro/sessions/cli/`. The hard part is knowing *which* saved
> session belongs to *which* pane, and relaunching them all. That's what `kzr`
> automates.

---

## How it works

1. **Capture.** A tiny Kiro `agentSpawn` hook fires whenever an agent starts. It
   records `(zellij_session, pane, label) → KIRO_SESSION_ID` into
   `~/.kiro-zellij/pins.json`. Because zellij exports `ZELLIJ_SESSION_NAME` and
   `ZELLIJ_PANE_ID` to every pane, each agent is pinned to its pane — even when
   several agents run in the **same directory**.
   *(The hook writes only to files and prints nothing, so it never pollutes the
   agent's context.)*
2. **Restore.** `kzr restore` reads those pins and rebuilds a zellij layout where
   each tab relaunches the correct chat with `kiro-cli chat --resume-id <id>`.

Nothing about your Kiro data is changed or copied — `kzr` only stores a small
map of pane → session id and shells out to `kiro-cli`/`zellij`.

## Requirements

- [`zellij`](https://zellij.dev) (tested on 0.44)
- [`kiro-cli`](https://kiro.dev) with session auto-save (default)
- [`jq`](https://jqlang.github.io/jq/)

## Install

```bash
git clone <this-repo> kiro-zellij-restore
cd kiro-zellij-restore
./install.sh
```

`install.sh` will:
- install the `kzr` command into `~/.local/bin` (override with `--prefix DIR`),
- stage the capture hook at `~/.kiro-zellij/kzr-record.sh`,
- wire the `agentSpawn` hook into every agent in `~/.kiro/agents/*.json`
  (additive + de-duplicated; skip with `--no-wire`),
- optionally install a periodic snapshot timer (`--with-timer`, macOS launchd),
- run `kzr doctor`.

> If you only use Kiro's **built-in default agent** (no JSON file), create one so
> the hook has somewhere to live:
> ```bash
> kiro-cli agent create --name kzr
> kzr install-hook --agent kzr
> # then launch chats through that agent:
> kzr agent <label> -- --agent kzr
> ```

## Usage

```bash
# Launch (or resume) a chat pinned to this pane. Pick a stable label per pane.
kzr agent api
kzr agent frontend
kzr agent db

# See what's captured
kzr status

# After a reboot — rebuild the whole workspace and resume every chat:
kzr restore my-session

# ...or let zellij resurrect the exact geometry; panes self-resume:
kzr restore --native my-session

# Preview the generated layout without launching:
kzr restore my-session --print
```

### Two restore modes

| Mode | Command | Brings back | Notes |
|------|---------|-------------|-------|
| **Rebuild** (default) | `kzr restore SESSION` | One tab per captured agent, each resumed | Portable; works on a fresh zellij or new machine. Loses exact split geometry. |
| **Native** | `kzr restore --native SESSION` | Exact panes/splits/cwds via zellij resurrection | Panes must have been launched with `kzr agent …` so they self-resume. |

Tip: for the native mode, enable viewport serialization in
`~/.config/zellij/config.kdl` (`serialize_pane_viewport true`) to also recover
scrollback.

## Commands

| Command | Description |
|---------|-------------|
| `kzr agent [LABEL] [-- kiro args…]` | Launch/resume a Kiro chat pinned to this pane |
| `kzr snapshot [SESSION]` | Snapshot the live zellij layout (`dump-layout`) + pins |
| `kzr restore [SESSION] [--print|--native]` | Rebuild a resuming layout, or resurrect natively |
| `kzr status [SESSION]` | List captured pane→session pins (flags MISSING sessions) |
| `kzr install-hook [--all|--agent NAME]` | Wire the capture hook into agent config(s) |
| `kzr prune [--days N]` | Drop pins whose Kiro session no longer exists |
| `kzr doctor` | Check dependencies + hook wiring |

## Configuration (env vars)

| Var | Default | Purpose |
|-----|---------|---------|
| `KZR_HOME` | `~/.kiro-zellij` | State dir (pins, registry, snapshots, layouts) |
| `KZR_KIRO_BIN` | `kiro-cli` | Kiro CLI binary name/path |
| `KIRO_SESSIONS_DIR` | `~/.kiro/sessions/cli` | Where Kiro stores sessions |
| `KIRO_AGENTS_DIR` | `~/.kiro/agents` | Where agent configs live |

## Uninstall

```bash
./install.sh --uninstall     # removes the command + timer; keeps your state + pins
```

## Limitations / honest caveats

- The capture hook lives in an **agent config**, so only agents that have the
  hook are captured. `install.sh` wires all agents in `~/.kiro/agents`; the
  built-in default agent needs a config created first (see above).
- **Native** restore depends on zellij's session serialization; resurrected
  *command* panes may require a keypress to re-run depending on your zellij
  settings. The **rebuild** path avoids this.
- `kzr` resumes the saved conversation; it can't restore an in-flight,
  mid-response TUI — Kiro's per-turn autosave is the source of truth.
- Labels should be **stable per pane** (a worktree/directory name is ideal). If
  two panes share a label in the same zellij session, the later one wins.

## License

MIT — see [LICENSE](LICENSE).
