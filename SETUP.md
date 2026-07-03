# Complete Setup Guide

## Prerequisites
- tmux installed
- claude CLI installed
- This repo cloned at `/home/mylappy/Projects/opencode-proxy`

---

## 1. Single Agent Setup

### Terminal 1 — Start proxy + launch Claude
```bash
cd /home/mylappy/Projects/opencode-proxy

# Kill old stuff if any
./toggle-model.sh stop
./stall-loop.sh stop

# Start proxy with 5 minute stall per response
STALL_SECONDS=300 ./toggle-model.sh start

# Launch Claude in tmux (your terminal becomes Claude)
./stall-loop.sh launch
```

### Terminal 2 — Auto-loop (sends prompts every ~5.5 min)
```bash
cd /home/mylappy/Projects/opencode-proxy
./stall-loop.sh start
```

---

## 2. Multi-Agent Setup

### Terminal 1 — Start proxy
```bash
cd /home/mylappy/Projects/opencode-proxy
./toggle-model.sh stop
STALL_SECONDS=300 ./toggle-model.sh start
```

### Terminal 2 — Launch multiple agents
```bash
cd /home/mylappy/Projects/opencode-proxy
./launch-agents.sh start
# Enter number of agents when prompted (e.g., 5)
```

---

## 3. Watching Agents

### Watch an agent live
```bash
./launch-agents.sh attach 1   # watch agent 1
# Ctrl+B then D to detach
```

### Check all agent statuses
```bash
./launch-agents.sh status
```

---

## 4. Stopping

### Stop all agents
```bash
./launch-agents.sh stop
```

### Stop proxy
```bash
./toggle-model.sh stop
```

### Quick stop all
```bash
./launch-agents.sh stop && ./toggle-model.sh stop
```

---

## How It Works

```
┌─────────────────────────────────────────────────────┐
│                   Terminal 1                        │
│  $ STALL_SECONDS=300 ./toggle-model.sh start        │
│  → Proxy running on port 5454                       │
│                                                     │
│  Terminal 2                                         │
│  $ ./launch-agents.sh start                         │
│  → How many agents? 3                               │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ agent-1  │  │ agent-2  │  │ agent-3  │          │
│  │ tmux     │  │ tmux     │  │ tmux     │          │
│  │ claude   │  │ claude   │  │ claude   │          │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       │              │              │                │
│       └──────────────┴──────────────┘                │
│                        │                             │
│               ┌────────┴────────┐                     │
│               │  Proxy (:5454)  │                     │
│               │  STALL=300s     │                     │
│               └────────┬────────┘                     │
│                        │                             │
│               ┌────────┴────────┐                     │
│               │  OpenCode API   │                     │
│               │  (free model)   │                     │
│               └─────────────────┘                     │
└─────────────────────────────────────────────────────┘
```

Each agent:
- Sends a prompt every `300s (stall) + 30s (buffer) = 330s`
- Gets fake thinking blocks for 5 minutes (ads run)
- Gets the real response after 5 minutes
- Loop sends next prompt immediately after
