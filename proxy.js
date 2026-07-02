#!/usr/bin/env node
// opencode-proxy: Anthropic API proxy for opencode free models
const http = require('http');

const PORT = parseInt(process.env.PORT || '5454');
const FREE_API = 'https://opencode.ai/zen/v1';

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

function* openaiToAnthropicSSE(line, model, ctx) {
  if (!line.startsWith('data: ')) return;
  const d = line.slice(6).trim();
  if (d === '[DONE]') {
    yield `event: message_delta\ndata: ${JSON.stringify({ type: 'message_delta', delta: { stop_reason: 'end_turn', stop_sequence: null }, usage: { output_tokens: 1 } })}\n\n`;
    yield `event: message_stop\ndata: ${JSON.stringify({ type: 'message_stop' })}\n\n`;
    return;
  }
  let chunk;
  try { chunk = JSON.parse(d); } catch { return; }
  const choice = chunk.choices?.[0];
  const delta = choice?.delta;
  const finish = choice?.finish_reason;
  if (!delta) return;

  if (delta.reasoning_content) {
    if (!ctx.thinkingStarted) {
      ctx.thinkingStarted = true;
      yield `event: content_block_start\ndata: ${JSON.stringify({ type: 'content_block_start', index: 0, content_block: { type: 'thinking', thinking: '' } })}\n\n`;
    }
    yield `event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: 0, delta: { type: 'thinking_delta', thinking: delta.reasoning_content } })}\n\n`;
  }
  if (delta.content) {
    if (!ctx.textStarted) {
      ctx.textStarted = true;
      yield `event: content_block_start\ndata: ${JSON.stringify({ type: 'content_block_start', index: ctx.thinkingStarted ? 1 : 0, content_block: { type: 'text', text: '' } })}\n\n`;
    }
    yield `event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: ctx.thinkingStarted ? 1 : 0, delta: { type: 'text_delta', text: delta.content } })}\n\n`;
  }
  if (finish) {
    if (ctx.thinkingStarted) yield `event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: 0 })}\n\n`;
    if (ctx.textStarted || !ctx.thinkingStarted) yield `event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: ctx.thinkingStarted ? 1 : 0 })}\n\n`;
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
        const oaiResp = await openaiFetch(oaiBody);

        if (!oaiResp.ok) {
          const txt = await oaiResp.text();
          res.writeHead(502, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: `API error: ${txt}` } }));
          return;
        }

        if (!isStream) {
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

        // Streaming
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        });
        sendMessageStart(res, modelId);
        const reader = oaiResp.body.getReader();
        const decoder = new TextDecoder();
        let buf = '';
        let sawFinish = false;
        const ctx = { thinkingStarted: false, textStarted: false };
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            buf += decoder.decode(value, { stream: true });
            const lines = buf.split('\n');
            buf = lines.pop() || '';
            for (const line of lines) {
              for (const evt of openaiToAnthropicSSE(line, modelId, ctx)) {
                if (evt.includes('message_stop')) sawFinish = true;
                res.write(evt);
              }
            }
          }
          if (buf.trim()) {
            for (const evt of openaiToAnthropicSSE(buf, modelId, ctx)) {
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
      } catch (e) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: e.message } }));
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
