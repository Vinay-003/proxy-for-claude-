#!/usr/bin/env node
// opencode-proxy: Anthropic API proxy for opencode free models
const http = require('http');

const PORT = parseInt(process.env.PORT || '5454');
const STALL_SECONDS = parseInt(process.env.STALL_SECONDS || '0');
// Default: 180s (3 min). Claude Code may terminate requests that think too long.
const STALL_JITTER = parseInt(process.env.STALL_JITTER || '60');
const FREE_API = 'https://opencode.ai/zen/v1';
const LOG = `${process.env.HOME || '/tmp'}/.claude-ad-loop.log`;

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  require('fs').appendFileSync(LOG, line + '\n');
}

const FREE_MODELS = [
  'deepseek-v4-flash-free',
  'big-pickle',
  'mimo-v2.5-free',
  'nemotron-3-ultra-free',
  'north-mini-code-free',
];

const DEFAULT_MODEL = 'deepseek-v4-flash-free';

// Map any model name to the default free model
const MODEL_ALIASES = {};
for (const m of FREE_MODELS) MODEL_ALIASES[m] = m;
// Every claude/gpt/gemini name maps to free model
const aliases = [
  'claude-opus-4-8','claude-opus-4-8-fast','claude-opus-4-7','claude-opus-4-7-fast','claude-opus-4-6','claude-opus-4-6-fast',
  'claude-opus-4-5','claude-opus-4-5-20251101','claude-opus-4-1','claude-opus-4-1-20250805','claude-opus-4-0','claude-opus-4-20250514',
  'claude-sonnet-5','claude-sonnet-4-6','claude-sonnet-4-5','claude-sonnet-4-5-20250929',
  'claude-sonnet-4-0','claude-sonnet-4-20250514',
  'claude-haiku-4-5','claude-haiku-4-5-20251001','claude-haiku-4-0','claude-haiku-4-0-20250414',
  'claude-fable-5','claude-3-5-haiku-20241022','claude-3-5-sonnet-20241022','claude-3-opus-20240229',
  'gpt-5.5','gpt-5.5-pro','gpt-5.4','gpt-5.4-fast','gpt-5.4-mini','gpt-5.4-mini-fast','gpt-5.4-nano',
  'gpt-5.3-codex','gpt-5.3-codex-spark','gpt-5.2','gpt-5.2-codex',
  'gpt-5.1','gpt-5.1-codex','gpt-5.1-codex-max','gpt-5.1-codex-mini','gpt-5','gpt-5-codex','gpt-5-nano',
  'gemini-3.5-flash','gemini-3.1-pro','gemini-3-flash','grok-build-0.1',
  'deepseek-v4-pro','deepseek-v4-flash','glm-5.2','glm-5.1','glm-5',
  'minimax-m3','minimax-m2.7','minimax-m2.5',
  'kimi-k2.7-code','kimi-k2.6','kimi-k2.5',
  'qwen3.6-plus','qwen3.5-plus',
];
for (const name of aliases) MODEL_ALIASES[name] = DEFAULT_MODEL;

function anthropicToOpenAI(aBody) {
  const messages = aBody.messages || [];
  const systemMsgs = messages.filter(m => m.role === 'system');
  const others = messages.filter(m => m.role !== 'system');
  const oaiMessages = [];
  for (const sm of systemMsgs) oaiMessages.push({ role: 'system', content: typeof sm.content === 'string' ? sm.content : JSON.stringify(sm.content) });
  for (const m of others) {
    if (m.role === 'assistant') {
      if (m.content) oaiMessages.push({ role: 'assistant', content: typeof m.content === 'string' ? m.content : m.content.map(p => p.type === 'text' ? p.text : '').join('') });
      continue;
    }
    if (typeof m.content === 'string') {
      oaiMessages.push({ role: 'user', content: m.content });
    } else if (Array.isArray(m.content)) {
      const parts = m.content.map(p => {
        if (p.type === 'text') return { type: 'text', text: p.text };
        if (p.type === 'image') return { type: 'image_url', image_url: { url: `data:${p.source?.media_type};base64,${p.source?.data}` } };
        return { type: 'text', text: JSON.stringify(p) };
      });
      oaiMessages.push({ role: 'user', content: parts });
    }
  }
  return {
    model: aBody.model,
    messages: oaiMessages,
    max_tokens: aBody.max_tokens || 4096,
    stream: aBody.stream !== false,
    temperature: aBody.temperature ?? 0.7,
  };
}

function sendMessageStart(res, model) {
  const id = `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  res.write(`event: message_start\ndata: ${JSON.stringify({
    type: 'message_start', message: {
      id, type: 'message', role: 'assistant', content: [], model,
      stop_reason: null, stop_sequence: null,
      usage: { input_tokens: 0, output_tokens: 0 },
    },
  })}\n\n`);
  return id;
}

function* openaiToAnthropicSSE(line, model, ctx, indexOffset = 0) {
  if (!line.startsWith('data: ')) return;
  const d = line.slice(6).trim();
  if (d === '[DONE]') {
    yield `event: message_delta\ndata: ${JSON.stringify({ type: 'message_delta', delta: { stop_reason: 'end_turn', stop_sequence: null }, usage: { output_tokens: 1 } })}\n\n`;
    yield `event: message_stop\ndata: ${JSON.stringify({ type: 'message_stop' })}\n\n`;
    return;
  }
  let chunk;
  try { chunk = JSON.parse(d); } catch { return; }
  if (chunk.error) {
    log(`API stream error: ${JSON.stringify(chunk.error)}`);
    if (!ctx.textStarted) {
      ctx.textStarted = true;
      yield `event: content_block_start\ndata: ${JSON.stringify({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } })}\n\n`;
    }
    yield `event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: `[API Error: ${JSON.stringify(chunk.error)}]` } })}\n\n`;
    yield `event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: 0 })}\n\n`;
    yield `event: message_delta\ndata: ${JSON.stringify({ type: 'message_delta', delta: { stop_reason: 'end_turn', stop_sequence: null }, usage: { output_tokens: 1 } })}\n\n`;
    yield `event: message_stop\ndata: ${JSON.stringify({ type: 'message_stop' })}\n\n`;
    return;
  }
  const choice = chunk.choices?.[0];
  const delta = choice?.delta;
  const finish = choice?.finish_reason;
  if (!delta) return;

  if (delta.reasoning_content) {
    if (!ctx.thinkingStarted) {
      ctx.thinkingStarted = true;
      yield `event: content_block_start\ndata: ${JSON.stringify({ type: 'content_block_start', index: 0 + indexOffset, content_block: { type: 'thinking', thinking: '' } })}\n\n`;
    }
    yield `event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: 0 + indexOffset, delta: { type: 'thinking_delta', thinking: delta.reasoning_content } })}\n\n`;
  }
  if (delta.content) {
    if (!ctx.textStarted) {
      ctx.textStarted = true;
      yield `event: content_block_start\ndata: ${JSON.stringify({ type: 'content_block_start', index: (ctx.thinkingStarted ? 1 : 0) + indexOffset, content_block: { type: 'text', text: '' } })}\n\n`;
    }
    yield `event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: (ctx.thinkingStarted ? 1 : 0) + indexOffset, delta: { type: 'text_delta', text: delta.content } })}\n\n`;
  }
  if (finish) {
    if (ctx.thinkingStarted) yield `event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: 0 + indexOffset })}\n\n`;
    if (ctx.textStarted || !ctx.thinkingStarted) yield `event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: (ctx.thinkingStarted ? 1 : 0) + indexOffset })}\n\n`;
    const sr = finish === 'length' ? 'max_tokens' : 'end_turn';
    yield `event: message_delta\ndata: ${JSON.stringify({ type: 'message_delta', delta: { stop_reason: sr, stop_sequence: null }, usage: { output_tokens: 1 } })}\n\n`;
    yield `event: message_stop\ndata: ${JSON.stringify({ type: 'message_stop' })}\n\n`;
  }
}

async function openaiFetch(body) {
  body.stream = body.stream !== false;
  return fetch(`${FREE_API}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const path = url.pathname;

  if (path === '/v1/models') {
    const data = FREE_MODELS.map(id => ({
      type: 'model',
      id,
      display_name: id.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
      created_at: new Date().toISOString(),
      owned_by: 'opencode',
    }));
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ data }));
    return;
  }

  if (path === '/v1/messages' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', async () => {
      try {
        const aBody = JSON.parse(body);
        const rawModel = aBody.model || '';
        const modelId = rawModel.includes('/') ? rawModel.split('/').pop() : rawModel;
        const resolvedModel = MODEL_ALIASES[modelId];
        if (!resolvedModel) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: `Model '${modelId}' not available. Use one of: ${FREE_MODELS.join(', ')}` } }));
          return;
        }
        aBody.model = resolvedModel;
        const isStream = aBody.stream !== false;
        const oaiBody = anthropicToOpenAI(aBody);

        if (!isStream) {
          const oaiResp = await openaiFetch(oaiBody);
          if (!oaiResp.ok) {
            const txt = await oaiResp.text();
            res.writeHead(502, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: { message: `API error: ${txt}` } }));
            return;
          }
          const json = await oaiResp.json();
          const text = json.choices?.[0]?.message?.content || '';
          const reasoning = json.choices?.[0]?.message?.reasoning_content || '';
          const usage = json.usage || {};
          const resp = {
            id: json.id || `msg_${Date.now()}`,
            type: 'message', role: 'assistant', content: [], model: modelId,
            usage: { input_tokens: usage.prompt_tokens || 0, output_tokens: usage.completion_tokens || 0 },
          };
          if (reasoning) resp.content.push({ type: 'thinking', thinking: reasoning });
          resp.content.push({ type: 'text', text });
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(resp));
          return;
        }

        // Start API call in background (parallel with stall)
        const oaiRespPromise = openaiFetch(oaiBody);

        // Streaming
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        });
        sendMessageStart(res, modelId);

        const ctx = { thinkingStarted: false, textStarted: false };
        let indexOffset = 0;

        // Stall phase: send fake thinking blocks before the real response
        if (STALL_SECONDS > 0) {
          // Add jitter: vary actual stall time per request
          const jitter = Math.floor(Math.random() * STALL_JITTER * 2) - STALL_JITTER;
          const actualStall = Math.max(10, STALL_SECONDS + jitter);
          indexOffset = 1;
          ctx.thinkingStarted = true;
          res.write(`event: content_block_start\ndata: ${JSON.stringify({ type: 'content_block_start', index: 0, content_block: { type: 'thinking', thinking: '' } })}\n\n`);
          const stallEnd = Date.now() + actualStall * 1000;
          const stallWords = [
            'Processing', 'Analyzing', 'Computing', 'Reasoning', 'Thinking',
            'Evaluating', 'Synthesizing', 'Calculating', 'Examining', 'Formulating',
            'Checking', 'Verifying', 'Running computations', 'Working through this',
            'Breaking down the problem', 'Let me think about this carefully',
            'Computing step by step', 'Going through the sequence',
          ];
          let wi = 0;
          while (Date.now() < stallEnd) {
            if (res.writableEnded) break;
            const remaining = Math.ceil((stallEnd - Date.now()) / 1000);
            const word = stallWords[wi % stallWords.length];
            // Vary update interval between 1.5-4s instead of fixed 2s
            const tick = 1500 + Math.floor(Math.random() * 2500);
            res.write(`event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: 0, delta: { type: 'thinking_delta', thinking: `${word}... (${Math.floor(remaining / 60)}m ${remaining % 60}s remaining)\n` } })}\n\n`);
            await new Promise(r => setTimeout(r, tick));
            wi++;
          }
          res.write(`event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: 0 })}\n\n`);
          ctx.thinkingStarted = false;
          ctx.textStarted = false;
        }

        // Wait for API response (was running in parallel) with retry for terminated errors
        let oaiResp = await oaiRespPromise;
        let attempt = 1;
        let errText = '';
        while (!oaiResp.ok && attempt <= 3) {
          errText = await oaiResp.text();
          log(`API attempt ${attempt}/3 failed: HTTP ${oaiResp.status} — ${errText}`);
          if (errText.includes('terminated') && attempt < 3) {
            const backoff = 2000 * attempt;
            log(`Retrying in ${backoff}ms...`);
            await new Promise(r => setTimeout(r, backoff));
            oaiResp = await openaiFetch(oaiBody);
            attempt++;
          } else {
            break;
          }
        }
        if (!oaiResp.ok) {
          log(`API request failed after ${attempt} attempts: ${errText}`);
          res.write(`event: content_block_start\ndata: ${JSON.stringify({ type: 'content_block_start', index: 0 + indexOffset, content_block: { type: 'text', text: '' } })}\n\n`);
          res.write(`event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: 0 + indexOffset, delta: { type: 'text_delta', text: `[API Error: ${errText}]` } })}\n\n`);
          res.write(`event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: 0 + indexOffset })}\n\n`);
          res.write(`event: message_delta\ndata: ${JSON.stringify({ type: 'message_delta', delta: { stop_reason: 'end_turn', stop_sequence: null }, usage: { output_tokens: 1 } })}\n\n`);
          res.write(`event: message_stop\ndata: ${JSON.stringify({ type: 'message_stop' })}\n\n`);
          if (!res.writableEnded) res.end();
          return;
        }

        // Stream the real API response
        const reader = oaiResp.body.getReader();
        const decoder = new TextDecoder();
        let buf = '';
        let sawFinish = false;
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            buf += decoder.decode(value, { stream: true });
            const lines = buf.split('\n');
            buf = lines.pop() || '';
            for (const line of lines) {
              for (const evt of openaiToAnthropicSSE(line, modelId, ctx, indexOffset)) {
                if (evt.includes('message_stop')) sawFinish = true;
                res.write(evt);
              }
            }
          }
          if (buf.trim()) {
            for (const evt of openaiToAnthropicSSE(buf, modelId, ctx, indexOffset)) {
              if (evt.includes('message_stop')) sawFinish = true;
              res.write(evt);
            }
          }
          if (!sawFinish) {
            res.write(`event: message_stop\ndata: ${JSON.stringify({ type: 'message_stop' })}\n\n`);
          }
        } catch (e) {
          if (!res.writableEnded) res.write(`event: error\ndata: ${JSON.stringify({ error: e.message })}\n\n`);
        }
        if (!res.writableEnded) res.end();
        log(`Stream complete (${ctx.thinkingStarted||ctx.textStarted ? 'success' : 'no content'})`);
      } catch (e) {
        log(`Stream error: ${e.message}`);
        if (!res.headersSent) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: e.message } }));
        } else if (!res.writableEnded) {
          res.write(`event: error\ndata: ${JSON.stringify({ error: e.message })}\n\n`);
          res.end();
        }
      }
    });
    return;
  }

  res.writeHead(404);
  res.end('not found');
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`opencode-proxy on http://127.0.0.1:${PORT}`);
  console.log(`Free models: ${FREE_MODELS.join(', ')}`);
  console.log(`Set ANTHROPIC_BASE_URL=http://127.0.0.1:${PORT} in Claude Code`);
});
