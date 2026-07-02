# opencode-proxy

Anthropic API → OpenAI API translation proxy for using **opencode free models** in **Claude Code CLI**.

No API key required. No server to host. The proxy runs locally and forwards requests to `https://opencode.ai/zen/v1`.

---

## Architecture

```
Claude Code CLI  ──►  Proxy (port 5454)  ──►  opencode.ai/zen/v1 (free OpenAI API)
      │                    │
      │   Anthropic        │   OpenAI format
      │   format           │   No auth needed
      │                    │
  ┌────┴────┐         ┌───┴───┐
  │settings │         │proxy  │
  │.json    │         │.js    │
  │points to│         │transl-│
  │proxy    │         │ates   │
  └─────────┘         └───────┘
```

The proxy:
1. Receives Anthropic `/v1/messages` requests from Claude Code
2. Translates them to OpenAI `/v1/chat/completions` format
3. Forwards to `https://opencode.ai/zen/v1` (no auth)
4. Translates the streaming SSE response back to Anthropic format
5. Returns it to Claude Code — it has no idea it's not talking to real Claude

---

## Free Models

| Model | ID |
|-------|-----|
| DeepSeek V4 Flash (default) | `deepseek-v4-flash-free` |
| Big Pickle | `big-pickle` |
| Mimo V2.5 | `mimo-v2.5-free` |
| Nemotron 3 Ultra | `nemotron-3-ultra-free` |
| North Mini Code | `north-mini-code-free` |

All Claude, GPT, Gemini, and Grok model names are automatically aliased to the default model (`deepseek-v4-flash-free`). You can also use any free model ID directly in Claude Code's `/model` command.

---

## Files

| File | Purpose |
|------|---------|
| `proxy.js` | The proxy server (Node.js, no dependencies) |
| `toggle-model.sh` | Start/stop the proxy and switch between free models and aerolink |
| `stall-loop.sh` | Terminal automation: keeps Claude Code thinking for ad impressions |
| `claude-ad-loop.sh` | Alternative: headless API loop (no Claude UI, no ads) |
| `headless-loop.sh` | Direct API loop without Claude Code |
| `opencode-proxy.service` | systemd user service for auto-start on boot (optional) |

---

## Prerequisites

- **Node.js** 18+ (for `fetch` support)
- **Claude Code CLI** installed
- **Kickbacks.ai** (optional — for ad-based earnings; see below)

---

## Setup

### 1. Clone or copy the project

```bash
git clone <this-repo> ~/Projects/opencode-proxy
# or just copy the files manually
```

### 2. Make the toggle script executable

```bash
chmod +x ~/Projects/opencode-proxy/toggle-model.sh
```

### 3. Configure Claude Code settings

Edit `~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_API_KEY": "dummy",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:5454/",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "model": "haiku",
  "theme": "dark"
}
```

The `ANTHROPIC_API_KEY` value doesn't matter — the proxy ignores it. `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` prevents Claude Code from sending unnecessary network requests to Anthropic servers.

---

## Usage

### Start the proxy

```bash
~/Projects/opencode-proxy/toggle-model.sh start
```

This starts the proxy in the background and prints how many models are available. The proxy runs on `http://127.0.0.1:5454`.

### Stop the proxy

```bash
~/Projects/opencode-proxy/toggle-model.sh stop
```

### Check status

```bash
~/Projects/opencode-proxy/toggle-model.sh status
```

Shows whether the proxy is running and whether Claude Code is configured to use free models or aerolink.

### Switch to free models

```bash
~/Projects/opencode-proxy/toggle-model.sh free
```

This changes `~/.claude/settings.json` to point to the proxy at `http://127.0.0.1:5454/`. You must restart Claude Code for the change to take effect.

### Switch to aerolink (real Claude models)

```bash
~/Projects/opencode-proxy/toggle-model.sh aerolink
```

This changes `~/.claude/settings.json` to point to `https://capi.aerolink.lat/`. You must restart Claude Code for the change to take effect.

### Full workflow

```bash
# 1. Start the proxy
toggle-model.sh start

# 2. Point Claude Code to the proxy
toggle-model.sh free

# 3. Open Claude Code
claude
```

---

## Selecting a Specific Free Model

Claude Code's `/model` picker only shows hardcoded Anthropic model names. To use a specific free model:

1. Type `/model` in Claude Code
2. Type a free model ID directly: `deepseek-v4-flash-free`, `big-pickle`, `mimo-v2.5-free`, `nemotron-3-ultra-free`, or `north-mini-code-free`

Or change the default model in `proxy.js`:

```js
const DEFAULT_MODEL = 'big-pickle';  // change this to any free model
```

Then restart the proxy.

---

## Proxy Lifecycle

- The proxy is **not** configured to start on boot
- It runs as a background process (`nohup`) in the current session
- It only runs when you explicitly start it with `toggle-model.sh start`
- Closing the terminal does **not** stop it — use `toggle-model.sh stop` to kill it
- Logs are written to `/tmp/opencode-proxy.log`

### Optional: Auto-start on boot (systemd)

```bash
systemctl --user enable opencode-proxy.service
systemctl --user start opencode-proxy.service
```

---

## Network Behavior

The proxy only makes outbound requests to:
- `https://opencode.ai/zen/v1/chat/completions` — the free model API

No authentication headers, no keys, no telemetry. The API is public.

---

## Kickbacks.ai Integration

[Kickbacks.ai](https://kickbacks.ai) replaces the Claude Code spinner text with sponsored ads and shares revenue with you.

### How it works

1. **VS Code extension** (required): Fetches ads from Kickbacks and caches them locally
2. **Terminal CLI integration**: Settings in `~/.claude/settings.json` display the cached ads
3. **Two surfaces in the terminal**:
   - **Status line**: A clickable ad line below your prompt (runs `~/.vibe-ads/vibe-ads-statusline.mjs`)
   - **Spinner verbs**: The thinking text shows sponsored messages

### Installation

```bash
# 1. Download and install the VS Code extension
curl -L https://kickbacks.ai/vsix -o kickbacks.vsix
code --install-extension kickbacks.vsix

# 2. Sign in via VS Code Command Palette:
#    Ctrl+Shift+P → "Kickbacks: Sign in" → Authenticate with Google
```

### Required settings.json entries

These are added by the Kickbacks extension and should remain in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "node \"/home/mylappy/.vibe-ads/vibe-ads-statusline.mjs\"",
    "padding": 0
  },
  "spinnerVerbs": {
    "mode": "replace",
    "verbs": ["Claude is $200/mo. We made it free"]
  }
}
```

The `spinnerVerbs` verbs array is updated automatically by the VS Code extension when new ads are fetched. On first install, it will have a single static verb — after the extension runs, real ads will appear.

**Important**: The VS Code extension must be running periodically to fetch new ads. Without it, the cache goes stale and you'll only see the last cached ad.

### Files

| File | Purpose |
|------|---------|
| `~/.vibe-ads/vibe-ads-statusline.mjs` | Renders the ad line in the Claude Code status bar |
| `~/.vibe-ads/cli-ad.json` | Cached ad data (fetched by the VS Code extension) |
| `~/.vibe-ads/debug.log` | Debug logging for the statusline script |

### Does the proxy interfere with Kickbacks?

**No.** They are completely independent:

| Component | What it does | Config location |
|-----------|-------------|-----------------|
| **Proxy** | Translates API requests (conversation) | `env.ANTHROPIC_BASE_URL` |
| **Kickbacks** | Renders ads in the UI (status line + spinner) | `statusLine` + `spinnerVerbs` |

You can use both simultaneously — the proxy handles what the model says, Kickbacks handles what the spinner shows while waiting.

---

## Troubleshooting

### "Model not available" error

The proxy rejects unknown model names. If you see:
```
Model 'some-model' not available. Use one of: deepseek-v4-flash-free, ...
```

Either:
- Use one of the listed free model IDs
- Add the model name to the `aliases` array in `proxy.js` and restart the proxy

### Proxy won't start (EADDRINUSE)

Port 5454 is already in use:
```bash
kill $(lsof -ti:5454)
toggle-model.sh start
```

### "API error" from proxy

The upstream API (`opencode.ai/zen/v1`) may be down or rate-limited. Check the proxy logs:
```bash
cat /tmp/opencode-proxy.log
```

### Kickbacks ads not rotating

- Make sure the VS Code extension is installed and signed in
- Run VS Code so the extension fetches new ads into the cache
- Check `~/.vibe-ads/cli-ad.json` has fresh content
- Check `~/.claude/settings.json` has the `statusLine` and `spinnerVerbs` entries

---

## Switching Between Providers

| Provider | Endpoint | Cost | API Key |
|----------|----------|------|---------|
| Free models (proxy) | `http://127.0.0.1:5454/` | Free | None needed |
| Aerolink | `https://capi.aerolink.lat/` | Paid | `aero_live_*` |

```bash
# Switch to free
toggle-model.sh free

# Switch to aerolink
toggle-model.sh aerolink

# Check current mode
toggle-model.sh status
```

You must restart Claude Code after switching.

---

## Stall Mode — Keep Ads Running

The proxy can **stall** responses by sending fake "thinking" blocks for a set duration before forwarding the real API response. Claude Code shows the spinner the whole time — which means **Kickbacks ads keep showing**.

### How it works

```
Prompt sent ──► Proxy receives ──► Fake thinking blocks (N minutes) ──► Real API call ──► Response
                                        │                                      │
                                    Spinner shows ads                    Actual model reply
                                    (Kickbacks earns)                    delivered to Claude
```

The API call starts in **parallel** with the stall, so the real response is ready when the stall ends.

### Start the proxy with stall

```bash
# 5 minute stall per request (300 seconds)
STALL_SECONDS=300 ./toggle-model.sh start

# Point Claude Code to the proxy
./toggle-model.sh free
```

### Auto-loop for continuous ads

The `stall-loop.sh` script launches Claude Code in a `tmux` session and repeatedly sends prompts that trigger long internal "thinking". Combined with stall mode, each prompt keeps the spinner running for ~5 minutes.

```bash
# Prerequisites
sudo apt-get install -y tmux

# Start everything
STALL_SECONDS=300 ./toggle-model.sh start
./toggle-model.sh free
./stall-loop.sh start

# Watch the ads
tmux attach -t stall-ads
# Detach: Ctrl+B then D

# Check status
./stall-loop.sh status

# Stop
./stall-loop.sh stop
./toggle-model.sh stop
```

### Timeline

| Phase | Duration | What Claude Code shows |
|-------|----------|----------------------|
| 1. Prompt sent | instant | User message appears |
| 2. Proxy stall | 5 minutes | Spinner with "Processing..." / "Analyzing..." |
| 3. API response | ~5 seconds | Model reply streams in |
| 4. Idle | ~5 seconds | Prompt ready for next message |
| 5. Next prompt | auto | Loop repeats |

### Custom prompt

Edit `stall-loop.sh` and change the `PROMPT` variable. The prompt should trigger long internal reasoning with minimal output:

```
Count silently from 1 to 10000. For each number check if it is prime
and compute its square root. Only output 'OK [N]' when done.
```

### Only real API calls consume your usage

The stall phase is entirely local — zero API calls. One real API call happens at the end of the stall to get an actual response. That's **~12 API calls per hour** of continuous ads.

### Works with Kickbacks

- Kickbacks ads show in the Claude Code spinner during the stall
- Kickbacks status line shows sponsor messages at the bottom
- No proxy configuration needed — Kickbacks and the proxy are independent
