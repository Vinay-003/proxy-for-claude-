# Commands

## 0. Quick start

```bash
cd /home/mylappy/Projects/opencode-proxy
./toggle-model.sh stop
STALL_SECONDS=300 ./toggle-model.sh start     # proxy with ~5min stall
./stall-loop.sh launch                         # open Claude in tmux
./stall-loop.sh start                          # start the auto-loop
```

Stop: `./stall-loop.sh stop` · Watch: `tmux attach -t stall-ads`

---

## 1. Single Agent

```bash
# Terminal 1 — Start proxy
STALL_SECONDS=300 ./toggle-model.sh start

# Then open Claude in tmux
./stall-loop.sh launch

# Terminal 2 — Start auto-loop (stops after 25 cycles by default)
MAX_CYCLES=25 ./stall-loop.sh start
```

Watch with `tmux attach -t stall-ads` · Detach with Ctrl+B then D.

**Env overrides:**

| Var | Default | Description |
|---|---|---|
| `STALL_SECONDS` | 300 | Base stall time for proxy thinking |
| `MIN_INTERVAL` | 180 | Min seconds between prompts |
| `MAX_INTERVAL` | 420 | Max seconds between prompts |
| `MAX_CYCLES` | 0 (unlimited) | Auto-stop after N prompts |

Example — work session (~3h then stops):
```bash
MIN_INTERVAL=200 MAX_INTERVAL=500 MAX_CYCLES=25 ./stall-loop.sh start
```

---

## 2. Multi-Agent (max 5)

```bash
./toggle-model.sh stop
STALL_SECONDS=300 ./toggle-model.sh start    # proxy with ±60s jitter

# Pane mode (all in one terminal)
./launch-agents.sh panes     # enter count (1-5)
tmux attach -t agents        # see all in tiled grid

# Tab mode (one GNOME tab per agent)
./launch-agents.sh tabs      # enter count (1-5)

# Interactive
./launch-agents.sh start     # asks mode + count
```

**Multi-agent features:**
- Each agent gets a unique shuffled prompt list from the 20-prompt pool
- Different interval ranges (agent 1: ~150-270s, agent 5: ~270-510s)
- Different max cycles (agent 1: ~10, agent 5: ~18 — stops at different times)
- Staggered start delays (8-60s apart, not simultaneous)
- Jitter: proxy adds ±60s to STALL_SECONDS per request

### Status / Stop

```bash
./launch-agents.sh status    # show all agents + config + cycle count
./launch-agents.sh stop      # kill all agents + loops
./toggle-model.sh stop       # kill proxy
```

---

## 3. Human-like behavior

All changes to avoid fraud detection patterns:

| What changed | Before | After |
|---|---|---|
| **Prompts** | 1 fixed (`count to 10000`) | **20 prompts** — prime checks, Collatz, random walk, etc. Randomly selected each cycle |
| **Interval** | Fixed 330s | **180-420s** random range (configurable) |
| **Stall time** | Fixed 300s | **300s ±60s** jitter per request |
| **Agent count** | Up to 9 | **Max 5** — lower concentration = less suspicious |
| **Agent behavior** | All identical | **Each varies** — interval, cycle count, prompt order, start delay |
| **Run time** | Forever (24/7) | **Configurable max cycles** — e.g. `MAX_CYCLES=25` = ~2-3h session |

---

## 4. How it works

```
                              ┌─ prompt pool (20 tasks, random pick)
Proxy (300s ±60s stall)       │
  │                           ├─ random interval (180-420s)
  ├── Agent 1 ── loop ────────┤
  ├── Agent 2 ── loop ────────┤
  ├── Agent 3 ── loop ────────┤
  ├── Agent 4 ── loop         └─ different max cycles per agent
  └── Agent 5 ── loop            (agents stop at different times)

Each request:
  → agent sends random prompt
  → proxy stalls ~300s (varies ±60s) showing "Thinking..." events
  → ads run during stall
  → real response from free model comes through
  → agent waits random interval, sends next prompt
```
