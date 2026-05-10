# HermesWhisper02 — Requirement Issues to Resolve Before Planning

**Date:** 2026-05-10
**Author:** generated for nrodrig1@gmail.com
**Predecessor:** [`docs/20260510_REQUIREMENTS.md`](20260510_REQUIREMENTS.md)

This document collects issues that should be resolved before a concrete implementation plan is written. Issues are split into three buckets:

1. **Blockers** — must be answered before any code is written; they shape file layout, dependencies, or deployment topology.
2. **Soon** — needed before the affected phase begins, but not before kickoff.
3. **Carry-forward** — open questions from the requirements that can default to a v1 choice and be revisited.

Items marked **(REQ §9.N)** correspond to numbered items in the requirements §9 open questions list.

---

## A. Blockers (must answer before kickoff)

### A-1. Deployment topology: where does Hermes live relative to the new API host?

The user has specified the production API URL as **`https://api.hermes-whisper.dashanddata.com`** on an Ubuntu server. The requirements (REQ §2.3, §7) describe Hermes as a **loopback-only service on `127.0.0.1:8642` co-located with the FastAPI/Pipecat host**, on a machine called `fsdc-avatar08`.

We need to confirm one of:

- **(a)** `api.hermes-whisper.dashanddata.com` resolves to the same Ubuntu box as the Hermes Agent (Hermes is loopback on that box). This matches REQ §2.3 and is the simplest topology.
- **(b)** The Ubuntu box runs only HermesWhisper02 and reaches Hermes over the LAN/private network on a different host. This breaks the "loopback only" rule (REQ §4.3) and needs new auth/transport.
- **(c)** `fsdc-avatar08` is being renamed/replaced by this new hostname, and the requirements text should be updated.

**Recommendation:** confirm (a). Update REQ §7 and §2.3 to use the concrete hostname.

#### Nick Answer

The fsdc-avatar08 Ubuntu server has a Hermes AI agent instance and it will deploy this FastAPI/Pipecat API (for HermesWhisper02). This Ubuntu server will be behind a reverse proxy server that uses Nginx to direct url traffic from `https://api.hermes-whisper.dashanddata.com` to this HermesWhisper02 api project.

### A-2. Mac dev/testing topology: how does Hermes get reached on a developer Mac?

You stated testing happens on a Mac and the Swift app is built on a Mac. The pipeline depends on Hermes at `127.0.0.1:8642`. We need to decide:

- **(a)** Run Hermes locally on the Mac during dev (requires Hermes to be portable / Mac-runnable).
- **(b)** Mac dev API talks to a remote Hermes instance over a tunnel (SSH port-forward or Tailscale) — violates loopback in spirit but works if scoped to dev only.
- **(c)** Mac dev runs the API + Pipecat with a **mocked** Hermes tool that returns canned responses, and only the Ubuntu deployment hits the real Hermes.

This decision drives whether `services/hermes.py` needs a mock implementation and whether dev `.env` carries an override `HERMES_BASE_URL`. **Recommendation:** (c) for fast iteration, with (b) available via a flag for end-to-end checks.

#### Nick Answer

There will not be a Hermes agent on the mac workstation. Make it so any testing will just verfy a connection or use some pre made responses that test up until the Hermes agent is needed.

### A-3. Front LLM choice for v1 — Ollama vs. Anthropic Haiku (REQ §9.1)

This is a blocker because:

- Ollama requires the Ubuntu box to have a GPU and a running `ollama serve` process; it changes the deployment story and the dev story (does the Mac also run Ollama?).
- Anthropic Haiku adds an outbound network dependency, an API key in the API's `.env`, and per-call cost; it does not need a GPU.
- Latency budgets in NFR-1 (≤ 800 ms p50 to first ack byte) are tight enough that the choice materially affects whether the budget is achievable.

**Recommendation for v1:** **Anthropic Claude Haiku 4.5** (`claude-haiku-4-5-20251001`) for the ack path. It removes the GPU prerequisite, gives predictable TTFB, and matches the "front LLM as ack/router, Hermes for substance" split. Keep the abstraction so Ollama can be enabled later via `FRONT_LLM_PROVIDER=ollama`.

#### Nick Answer

Can we start off with a using an external model? Ideally we would use the OpenAI pro subscription that Hermes connects to. But if not let's use an api. We will not run Ollama on Ubuntu. Does this pose a problem?

### A-4. Greenfield confirmation — start fresh, don't fork HermesVoice in place

Both `api/` and `mobile/` are currently empty. The requirements describe a new project that **migrates** code from HermesVoice (REQ §7). Confirm:

- We are creating a fresh FastAPI scaffold under `api/` and a fresh Xcode project under `mobile/ios/HermesWhisper02/`, **copying** specific files from HermesVoice rather than forking the repo.
- Files explicitly to be carried over (per REQ §7): `services/hermes.py`, `services/voice_store.py`, `routes/mobile_auth.py` (adapted), persistence schema for voice sessions/messages.
- Files explicitly **not** to be carried (per REQ §7, FR-1.4, FR-2.1): `services/stt.py`, `services/tts.py`, `services/pipeline.py`, `Vendor/sherpa-onnx*`, `VoiceActivityDetector.swift`, the entire `web/` client.

We need the path to the HermesVoice repo on the Mac so the plan can name the source files concretely.

#### Nick Answer

Start clean. No fork of HermesVoice

### A-5. Pipecat version pin and Python version

REQ §8 calls out "Pipecat upstream churn — pin version" but does not name one. Before kickoff we need:

- The exact Pipecat version (and matching `pipecat-ai[whisper,openai,silero]` extras) we will pin.
- The Python interpreter version. Per `docs/TODO_LIST_GUIDANCE.md`, every machine has a `python` alias — confirm what `python --version` resolves to on the target Ubuntu box and on the dev Mac, and whether they match.
- Whether dependencies are managed with `uv`, `poetry`, `pip-tools`, or plain `requirements.txt`.

This is a blocker because it determines the lockfile layout in the very first commit.

#### Nick Answer

Python version 13 on mac. Python version 12 on Ubuntu. If we need to we can upgrade locally. But hopefully we can keep these two different versions.

### A-6. Ack pipeline shape — serial vs. parallel (REQ §9.2)

This is "soon-ish" but it shapes the front-LLM processor's interface. Recommendation: **start serial (§6.3a)** for v1. Parallel ack/answer branches via `ParallelPipeline` are deferred to v1.1 once we have measured ack TTFB. Confirm.

#### Nick Answer

## What is this ? Let's go with your recommendation.

## B. Soon (needed before the affected phase)

### B-1. STT and TTS provider choices for v1 (REQ §9.4, §9.5)

The requirements list candidates but do not pick. These directly affect API keys, latency budgets, and Pipecat service imports.

**Recommendation:**

- **STT:** Deepgram streaming (`pipecat.services.deepgram`). Whisper batch is a poor fit for Pipecat's frame-by-frame model and will hurt NFR-1.
- **TTS:** Cartesia (`pipecat.services.cartesia`) for ack snappiness; OpenAI TTS as fallback.

Both add API keys; confirm the project owns accounts for them.

#### Nick Answer

Please add the .env variables necesary. There is an openai api key .env variable that was previously used for SST and TTS. If this won't work please craete a new file with the YYYYMMDD\_ prefix and name it something accordingly like "SST_TTS_PROVIDERS_INSTRUCTIONS" with the instrucitons for getting the appropriate credentials.

### B-2. Auth scheme on the new server

REQ §6 says v1 keeps the HermesVoice 2FA email-code → bearer token flow. For the new Ubuntu deployment we need to confirm:

- The same SMTP / email-sender configuration is available on the new box.
- The user table / SQLite store from HermesVoice is being migrated, or whether the new server starts with a fresh user list (in which case we need the seed user(s) for `nrodrig1@gmail.com`).
- Whether bearer tokens get an expiry + refresh story now (REQ §9.8) or stay long-lived for v1. **Recommendation:** long-lived for v1; revisit.

### B-3. iOS minimum version, Xcode version, signing identity (REQ §9.9)

REQ §9.9 proposes iOS 17+. Confirm, and provide:

- Xcode version target (Xcode 16+?).
- Apple Developer team / bundle id (`com.dashanddata.hermeswhisper02`?).
- Whether TestFlight distribution is wanted in v1 or local-install only.

#### Nick Answer

ios 17 is fine and the mac has `xcode-select version 2416.`

### B-4. Server registry persistence on iOS

REQ §5.3 / §7 mentions "Core Data or simple plist + Keychain" without picking. **Recommendation:** plist (or a small JSON file in App Support) for the registry + Keychain for credentials. Core Data is overkill for a list of < 20 server profiles. Confirm.

### B-5. TLS / Nginx config for `api.hermes-whisper.dashanddata.com`

We need from ops:

- Whether the Nginx + Let's Encrypt cert for `api.hermes-whisper.dashanddata.com` is already provisioned, or part of this project's deliverable.
- Confirmation that Nginx will proxy `wss://api.hermes-whisper.dashanddata.com/ws/voice` to the FastAPI app with `proxy_read_timeout` and `proxy_send_timeout` raised (default 60s will kill long voice sessions).
- The local port FastAPI should bind to behind Nginx (e.g. `127.0.0.1:8765`).
- The systemd unit name and log path (drives `PATH_TO_LOGS` per `LOGGING_PYTHON_V06.md`).

#### Nick Answer

we will certify with certbot. After the api is created we'll have the ai coding agent created the correct nginx config files that will be stored ont the reverse proxy server named Maestro04.

### B-6. Conversation memory ownership (REQ §9.10)

Does the front LLM keep its own short-term context window, or is every turn stateless and Hermes owns all memory? **Recommendation for v1:** front LLM keeps the last N messages (Pipecat's `context_aggregator` default) for ack continuity; Hermes still owns long-term memory. Confirm.

### B-7. Telemetry destination (REQ §9.11)

**Recommendation for v1:** Loguru files only, per `docs/LOGGING_PYTHON_V06.md`. No Grafana / Prometheus in v1. Confirm.

#### Nick Answer

## yes, use loguru

## C. Carry-forward (default a v1 answer; revisit later)

| ID  | Item                              | Default for v1                      | Source   |
| --- | --------------------------------- | ----------------------------------- | -------- |
| C-1 | Uplink codec (PCM vs. Opus)       | Raw PCM16 16 kHz mono               | REQ §9.3 |
| C-2 | LAN IP + self-signed cert support | No — public DNS + LE cert only      | REQ §9.6 |
| C-3 | Cross-server session continuity   | No — switching profile ends session | REQ §9.7 |
| C-4 | Auth refresh tokens               | No — re-2FA on expiry               | REQ §9.8 |

---

## D. Cross-cutting concerns the requirements don't yet cover

These are gaps I noticed while reading; flagging them so we can fold answers into the plan.

### D-1. Project conventions file — `AGENTS.md`

`CLAUDE.md` at the repo root says "use `AGENTS.md` instead of `CLAUDE.md`" and "search the repository for `AGENTS.md` files," but **no `AGENTS.md` exists yet**. Before substantive work begins, we should author at least:

- `/AGENTS.md` (root) — top-level conventions (commit style ref, logging ref, error format ref, Python tooling).
- `/api/AGENTS.md` — Python-specific conventions (Loguru config, FastAPI patterns, Pipecat layout).
- `/mobile/AGENTS.md` — Swift conventions (SwiftUI vs UIKit choice, Keychain helper, async/await).

#### Nick Answer

Instruct the coding agent to create the AGENTS.md files after the apps have been built.

### D-2. Environment variable inventory

`docs/LOGGING_PYTHON_V06.md` requires `NAME_APP`, `RUN_ENVIRONMENT`, and `PATH_TO_LOGS` (testing/prod). The requirements imply more env vars but don't enumerate them. Pre-plan, we should agree on the canonical list:

```
NAME_APP=hermes-whisper-02-api
RUN_ENVIRONMENT=development|testing|production
PATH_TO_LOGS=/var/log/hermes-whisper-02
LOG_MAX_SIZE_IN_MB=3
LOG_MAX_FILES=3

API_HOST=127.0.0.1
API_PORT=8765
PUBLIC_BASE_URL=https://api.hermes-whisper.dashanddata.com

FRONT_LLM_PROVIDER=anthropic
FRONT_LLM_MODEL=claude-haiku-4-5-20251001
ANTHROPIC_API_KEY=...
OLLAMA_BASE_URL=http://127.0.0.1:11434     # if provider=ollama

STT_PROVIDER=deepgram
DEEPGRAM_API_KEY=...
TTS_PROVIDER=cartesia
CARTESIA_API_KEY=...

HERMES_BASE_URL=http://127.0.0.1:8642
HERMES_MOCK=false                          # true on dev Mac

DB_PATH=./var/voice_store.sqlite
JWT_SECRET=...
TOKEN_TTL_SECONDS=2592000                  # 30 days
SMTP_HOST=...
SMTP_FROM=...
```

Confirm/edit; this list will become `api/.env.example` in the first commit.

### D-3. Test strategy

The requirements have acceptance criteria (REQ §10) but no test plan. Pre-plan, decide:

- Unit tests: `pytest` for the API. Pipecat processors are awkward to unit-test; do we mock the transport or run a smoke test against a recorded WAV?
- Swift tests: `XCTest` unit tests for `ServerRegistry` and Keychain helpers; UI tests deferred.
- An end-to-end smoke test that drives a recorded WAV through the WebSocket and asserts an ack and answer come back. Where does this live (`api/tests/e2e_voice.py`)?

### D-4. CI / pre-commit

Not mentioned in the requirements. Suggest at minimum:

- `ruff` + `ruff format` for Python, run via pre-commit.
- `swift-format` for Swift.
- A GitHub Actions workflow that runs `pytest` on push (no Pipecat audio tests on CI; just unit + import smoke).

Confirm whether CI is in scope for v1.

### D-5. Versioning and release artifacts

- API: a `VERSION` constant surfaced via `GET /api/server/info` (REQ §5.1.2). Where does the version live — `pyproject.toml`, a constant in `app/main.py`?
- Mobile: build number scheme (semver `1.0.0` + monotonic build).

Trivial, but worth pinning before the first commit.

---

## E. Suggested next step

Once the **Blockers (§A)** are answered (especially A-1, A-2, A-3, A-4, A-5), I will produce two plan files:

- `20260510_PLAN_API_V01.md` — FastAPI + Pipecat backend, phased.
- `20260510_PLAN_MOBILE_V01.md` — Swift iOS app, phased.

Splitting the plans makes sense because the two tracks have different toolchains, different test stories, and can largely proceed in parallel once the protocol (§5 of REQ) is frozen. A separate small doc, `20260510_PROTOCOL_V01.md`, may be worthwhile as the contract between them.
