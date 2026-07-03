# Commands

## Start everything

### Terminal 1 — Watch Claude live
```bash
cd /home/mylappy/Projects/opencode-proxy
STALL_SECONDS=300 ./toggle-model.sh start
./stall-loop.sh launch
```

### Terminal 2 — Auto-loop (sends prompts automatically)
```bash
cd /home/mylappy/Projects/opencode-proxy
./stall-loop.sh start
```

## Manual commands

### Send one prompt now
```bash
./stall-loop.sh send
```

### Attach/detach from tmux
```bash
./stall-loop.sh attach    # re-attach to watch Claude
# Ctrl+B then D to detach
```

### Check status
```bash
./stall-loop.sh status
```

## Stop everything

### Stop auto-loop and close tmux session
```bash
./stall-loop.sh stop
```

### Stop the proxy
```bash
./toggle-model.sh stop
```
