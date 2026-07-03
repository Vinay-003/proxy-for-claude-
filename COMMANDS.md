# Commands

## 1. Single Agent (manual tmux)

```bash
# Terminal 1 — Start proxy
cd /home/mylappy/Projects/opencode-proxy
./toggle-model.sh stop
STALL_SECONDS=300 ./toggle-model.sh start

# Then open Claude in tmux
./stall-loop.sh launch

# Terminal 2 — Start auto-loop
./stall-loop.sh start
```

Watch with `tmux attach -t stall-ads` · Detach with Ctrl+B then D.

---

## 2. Multi-Agent

### Start proxy
```bash
cd /home/mylappy/Projects/opencode-proxy
./toggle-model.sh stop
STALL_SECONDS=300 ./toggle-model.sh start
```

### Launch agents — pick a mode

**Pane mode** — all visible in one terminal:
```bash
./launch-agents.sh panes     # enter count (1-9)
tmux attach -t agents        # see all in tiled grid
```
Zoom: Ctrl+B then Z · Unzoom: Ctrl+B then Z · Detach: Ctrl+B then D

**Tab mode** — one GNOME terminal tab per agent:
```bash
./launch-agents.sh tabs      # enter count (1-9)
# Opens N GNOME tabs, each showing one agent full-screen
```

**Interactive menu:**
```bash
./launch-agents.sh start     # asks panes (1) or tabs (2) + count
```

### Status
```bash
./launch-agents.sh status
```

### Stop
```bash
./launch-agents.sh stop      # kill all agents + loops
./toggle-model.sh stop       # kill proxy
```

---

## How it works

```
Proxy (STALL_SECONDS=300)
  │
  ├── Agent 1 ── loop (sends prompt every 330s)
  ├── Agent 2 ── loop (sends prompt every 330s)
  ├── Agent 3 ── loop (sends prompt every 330s)
  └── ...

Each agent:
  → sends prompt
  → proxy sends fake thinking blocks for 300 seconds (ads run)
  → real response comes through
  → loop waits 30s, sends next prompt
```
