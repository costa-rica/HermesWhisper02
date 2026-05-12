# Hermes HTTP contract discovery

Date: 2026-05-12 Pacific
Repo branch: dev_02
Host: avatar08

## Summary

- The local HTTP service on `127.0.0.1:8642` is the Hermes Agent gateway API server, not a custom `/chat` service.
- The correct chat endpoint is `POST /v1/chat/completions`.
- HermesWhisper02 should set `HERMES_CHAT_PATH=/v1/chat/completions` when `HERMES_BASE_URL=http://127.0.0.1:8642`.
- The endpoint is OpenAI Chat Completions compatible.
- It supports both non-streaming JSON responses and streaming Server-Sent Events when `stream: true` is sent.
- The API server currently requires bearer authentication for most `/v1/*` endpoints because `API_SERVER_KEY` is configured in the Hermes Agent environment. Do not log or commit the key.

## Process and service

- Listener: `127.0.0.1:8642`
- Process: `/home/nick/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run --replace`
- PID observed during discovery: `804`
- User: `nick`
- Systemd service: user service `hermes-gateway.service`
- Unit file: `/home/nick/.config/systemd/user/hermes-gateway.service`
- Working directory: `/home/nick/.hermes/hermes-agent`
- Source file implementing the API server: `/home/nick/.hermes/hermes-agent/gateway/platforms/api_server.py`
- Framework/server header: `Python/3.11 aiohttp/3.13.5`

Non-secret service details observed:

```ini
[Service]
ExecStart=/home/nick/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run --replace
WorkingDirectory=/home/nick/.hermes/hermes-agent
Environment="HERMES_HOME=/home/nick/.hermes"
Restart=always
```

## Available routes

The route registration in `gateway/platforms/api_server.py` shows these HTTP routes:

- `GET /health`
- `GET /health/detailed`
- `GET /v1/health`
- `GET /v1/models`
- `GET /v1/capabilities`
- `POST /v1/chat/completions`
- `POST /v1/responses`
- `GET /v1/responses/{response_id}`
- `DELETE /v1/responses/{response_id}`
- `GET /api/jobs`
- `POST /api/jobs`
- `GET /api/jobs/{job_id}`
- `PATCH /api/jobs/{job_id}`
- `DELETE /api/jobs/{job_id}`
- `POST /api/jobs/{job_id}/pause`
- `POST /api/jobs/{job_id}/resume`
- `POST /api/jobs/{job_id}/run`
- `POST /v1/runs`
- `GET /v1/runs/{run_id}`
- `GET /v1/runs/{run_id}/events`
- `POST /v1/runs/{run_id}/approval`
- `POST /v1/runs/{run_id}/stop`

The following attempted paths returned `404` during discovery and should not be used for chat:

- `/`
- `/docs`
- `/openapi.json`
- `/chat`

## Health and discovery checks

`GET /health` is unauthenticated and returned:

```json
{"status":"ok","platform":"hermes-agent"}
```

`GET /v1/models` with bearer auth returned a model list containing:

```json
{
  "id": "hermes-agent",
  "object": "model",
  "owned_by": "hermes",
  "root": "hermes-agent"
}
```

`GET /v1/capabilities` with bearer auth reported:

- `chat_completions: true`
- `chat_completions_streaming: true`
- `responses_api: true`
- `responses_streaming: true`
- `run_submission: true`
- `run_events_sse: true`
- session continuity header: `X-Hermes-Session-Id`
- session key header: `X-Hermes-Session-Key`

## Exact curl command for a valid chat response

Use an API key from the local Hermes Agent environment without printing it. This command is safe to paste into a shell on avatar08 because the secret is read locally and never echoed:

```bash
BASE=http://127.0.0.1:8642
API_KEY_VALUE=$(awk -F= '/^API_SERVER_KEY=/{sub(/^[^=]*=/,"",$0); print $0; exit}' /home/nick/.hermes/.env)

curl -sS \
  --oauth2-bearer "$API_KEY_VALUE" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "hermes-agent",
    "messages": [
      {"role": "system", "content": "Answer with exactly: HERMES_CONTRACT_OK"},
      {"role": "user", "content": "contract probe"}
    ],
    "stream": false
  }' \
  "$BASE/v1/chat/completions"
```

Discovery result:

- HTTP status: `200`
- Response header included: `X-Hermes-Session-Id: api-...`
- Response object: `chat.completion`
- Assistant message content: `HERMES_CONTRACT_OK`
- Finish reason: `stop`

## Required HermesWhisper02 configuration

With:

```env
HERMES_BASE_URL=http://127.0.0.1:8642
```

Use:

```env
HERMES_CHAT_PATH=/v1/chat/completions
```

Do not use:

```env
HERMES_CHAT_PATH=/chat
```

## Expected request JSON shape

Minimum non-streaming request:

```json
{
  "model": "hermes-agent",
  "messages": [
    {"role": "user", "content": "Your prompt here"}
  ],
  "stream": false
}
```

Optional system prompt and history are accepted through the `messages` array:

```json
{
  "model": "hermes-agent",
  "messages": [
    {"role": "system", "content": "System instructions"},
    {"role": "user", "content": "Previous user message"},
    {"role": "assistant", "content": "Previous assistant message"},
    {"role": "user", "content": "Current user message"}
  ],
  "stream": false
}
```

Content can be a plain string. The implementation also normalizes OpenAI-style content arrays with text parts, such as:

```json
{"role":"user","content":[{"type":"text","text":"Your prompt here"}]}
```

Useful optional headers:

- Auth: required when `API_SERVER_KEY` is configured; curl can provide it with `--oauth2-bearer "$API_KEY_VALUE"`.
- `X-Hermes-Session-Id`: continue a specific Hermes session. This requires API key authentication.
- `X-Hermes-Session-Key`: stable per-channel memory scope. This also requires API key authentication.
- `Idempotency-Key`: supported for non-streaming chat completion requests.

## Expected non-streaming response format

A successful non-streaming response is OpenAI Chat Completions shaped:

```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1778626586,
  "model": "hermes-agent",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "HERMES_CONTRACT_OK"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```

The exact token counts vary. The server also returns `X-Hermes-Session-Id` in the response headers.

## Streaming behavior

Streaming is enabled by sending:

```json
{"stream": true}
```

The response uses `Content-Type: text/event-stream` and emits OpenAI-compatible chat completion chunks:

```text
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"H"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":13971,"completion_tokens":33,"total_tokens":14004}}

data: [DONE]
```

When tools run during a streamed request, Hermes may also emit custom SSE events:

```text
event: hermes.tool.progress
data: {"tool":"...","emoji":"...","label":"...","toolCallId":"...","status":"running"}
```

Clients that only need assistant text should process `data:` chat completion chunks and ignore unknown `event:` types.

## Unresolved questions

- HermesWhisper02 must have a safe way to supply the bearer token if the API key remains configured. This discovery did not inspect or document secret values.
- The ideal session strategy for HermesWhisper02 is not yet decided: either send full conversation history in `messages`, use `X-Hermes-Session-Id`, or use a stable `X-Hermes-Session-Key` for memory scoping.
- The `/v1/responses` endpoint is also available, but this discovery focused on the Chat Completions endpoint because HermesWhisper02 currently has `HERMES_CHAT_PATH`.
