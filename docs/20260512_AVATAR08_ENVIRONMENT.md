# Avatar08 environment for Mac workstation coding agents

Use this document when coding on a Mac workstation for HermesWhisper02 while the API under test is deployed on avatar08.

## Purpose

This file explains the server environment so a Mac-side coding agent can avoid changes that break the avatar08 deployment or mobile app testing.

The companion server-side repair runbook is:

- `docs/20260512_SERVER_AGENT_FIX_PERMISSIONS_V02.md`

Use that file for exact avatar08 permission repair commands. Use this file to understand the environment before changing code, docs, deployment instructions, or test flows from the Mac.

## Host and traffic topology

1. The deployed API runs on FSDC Ubuntu VM `avatar08`.
2. Public traffic enters through Maestro04 Nginx and proxies to avatar08.
3. Public API URL:
   - `https://api.hermes-whisper.dashanddata.com`
4. Local avatar08 API health URL:
   - `http://127.0.0.1:8010/api/health`
5. Public API health URL:
   - `https://api.hermes-whisper.dashanddata.com/api/health`
6. The mobile app is tested from the Mac or iOS device against the public API URL unless explicitly testing a local development server.

## Repository and runtime paths on avatar08

Observed on 2026-05-12:

1. Repository checkout:
   - `/home/limited_user/applications/HermesWhisper02`
2. API working directory:
   - `/home/limited_user/applications/HermesWhisper02/api`
3. API virtual environment:
   - `/home/limited_user/environments/hermes_whisper_venv`
4. Runtime `.env` file:
   - `/home/limited_user/applications/HermesWhisper02/api/.env`
5. App logs directory:
   - `/home/limited_user/logs`
6. SQLite database directory:
   - `/home/limited_user/databases`
7. Current non-secret DB path:
   - `/home/limited_user/databases/voice_store.sqlite`
8. Current app log file:
   - `/home/limited_user/logs/hermes-whisper-02-api.log`

Do not commit or ask the Mac agent to print `.env`, database files, log files with secrets, API keys, email passwords, JWT secrets, bearer tokens, or 2FA codes.

## Systemd service

The deployed API is managed by systemd on avatar08:

```text
Service: hermes-whisper-02.service
User: limited_user
Group: limited_user
WorkingDirectory: /home/limited_user/applications/HermesWhisper02/api
ExecStart: /home/limited_user/environments/hermes_whisper_venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8010
```

Important implications:

1. The server does not run on the API development port `8765`.
2. The deployed service listens on avatar08 port `8010`.
3. `api/AGENTS.md` still lists `8765` for local development server runs.
4. Mac-side tests that target deployed avatar08 should use the public URL or port `8010` only through the server/proxy context.
5. Do not change service code or docs to assume avatar08 uses the local dev port unless explicitly changing the deployment.

## User and permission model

avatar08 intentionally separates admin/deployment work from runtime execution.

1. `nick` is the administrative/deployment user.
2. `limited_user` is the service runtime user.
3. The API service runs as `limited_user` through systemd.
4. The Git checkout may contain files created by `nick` after `git checkout`, `git pull`, merges, code generation, or copied files.
5. `limited_user` must be able to read and traverse deployed source files, but should not own the Git checkout as the normal recurring model.
6. `limited_user` should own runtime write paths such as logs and SQLite database files.
7. `.env` must not be world-readable. It needs only the access required by the service.

The recurring safe model is:

1. `nick` owns and updates the Git checkout.
2. `limited_user` receives read/traverse access to source through ACLs.
3. `limited_user` owns runtime write paths.
4. After branch changes on avatar08, the server-side agent runs the ACL repair from `docs/20260512_SERVER_AGENT_FIX_PERMISSIONS_V02.md` before restart/testing.

## Known permission failure mode

A branch checkout or generated file can create source files like this:

```text
-rw-rw---- nick:nick api/app/pipecat_processors/mocks.py
```

That looks readable to `nick`, but systemd starts Python as `limited_user`, so imports can fail with:

```text
PermissionError: [Errno 13] Permission denied: '/home/limited_user/applications/HermesWhisper02/api/app/pipecat_processors/mocks.py'
```

This is a deployment permission problem, not necessarily an application code bug.

Mac-side coding agents should avoid misdiagnosing this as a Python import path, FastAPI, Pipecat, or package dependency issue until avatar08 permissions and service logs have been checked.

## Sudo and verification constraints

Observed on 2026-05-12:

1. `sudo -n -u limited_user id` returns `sudo: a password is required`.
2. `sudo -n /usr/bin/systemctl status hermes-whisper-02.service --no-pager -l` returns `sudo: a password is required`.
3. Do not assume passwordless `sudo -u limited_user` is available.
4. Do not assume every privileged `systemctl status` form is available.
5. Non-sudo `systemctl status hermes-whisper-02.service --no-pager -l` may still be useful.
6. Health checks are the primary verification signal from a Mac-side workflow.

Server-side agents may have narrowly allowed sudo for actions such as restarting the service, but Mac-side code should not be written around broad sudo assumptions.

## What Mac-side coding agents should do

Before making API/mobile integration changes:

1. Read:
   - `AGENTS.md`
   - `api/AGENTS.md` for API changes
   - `mobile/AGENTS.md` for mobile changes
   - `docs/20260510_PROTOCOL_V01.md` for Swift to API protocol behavior
   - `docs/20260512_SERVER_AGENT_FIX_PERMISSIONS_V02.md` for avatar08 permission repair context
2. Keep API and mobile changes separated unless the protocol requires both.
3. Treat `.env` values and secrets as server-local configuration, not source-controlled behavior.
4. Keep deployed URL assumptions explicit in mobile configuration.
5. If mobile testing fails after a branch switch or deployment, ask the server-side agent to verify avatar08 permissions and service health before changing app code.

## What Mac-side coding agents should not do

1. Do not commit `.env`, database files, log files, credentials, bearer tokens, email passwords, JWT secrets, or generated local caches.
2. Do not change the deployed service to run as `nick`.
3. Do not recommend `chmod -R 777`.
4. Do not recommend recursively changing the Git checkout to `limited_user:limited_user` as the recurring fix.
5. Do not assume avatar08 uses the local dev API port `8765`.
6. Do not mark a mobile or API test failure as an application bug until deployed service health and permissions have been checked.
7. Do not rely on Mac-only tools such as Xcode to verify avatar08 service behavior.

## Testing checklist for Mac to avatar08 mobile work

Use this sequence when the mobile app is pointed at avatar08:

1. Confirm the mobile app API base URL is:
   - `https://api.hermes-whisper.dashanddata.com`
2. Ask the server-side agent to confirm local avatar08 health:
   - `http://127.0.0.1:8010/api/health`
3. Confirm public health from the Mac:
   - `https://api.hermes-whisper.dashanddata.com/api/health`
4. If the API was recently checked out, pulled, or regenerated on avatar08, ask the server-side agent to apply the V02 ACL repair.
5. If login or 2FA email flow fails, inspect server logs with secrets redacted before changing mobile code.
6. If REST health works but WebSocket voice fails, investigate public proxy/WebSocket configuration separately from the backend route.
7. If avatar08 service is unhealthy, fix server deployment/permissions first and retest mobile only after health returns.

## Mapping common symptoms to likely layers

1. Public `/api/health` fails:
   - Public proxy, avatar08 service, service port, or deployment problem.
2. Local avatar08 health works but public health fails:
   - Maestro04 Nginx/proxy or DNS/TLS problem.
3. Service restart fails with `PermissionError` on a source file:
   - avatar08 checkout ACL/ownership problem.
4. Login request reaches API but email code is not delivered:
   - API email configuration, SMTP, or email delivery logging problem.
5. iOS cannot reach API but public `curl` health works:
   - Mobile app URL/configuration, ATS/network permission, device network, or app build issue.
6. WebSocket fails while REST health works:
   - WebSocket auth, route, proxy upgrade headers, or mobile WebSocket handling issue.

## Branch and deployment workflow notes

1. The active testing branch may be `dev_02` or another development branch.
2. avatar08 fetch configuration previously only fetched `main`; confirm remote branch refspecs if a branch appears missing.
3. After a branch switch on avatar08, file permissions may need ACL repair before the service can import code.
4. A clean git status on the Mac does not prove avatar08 can read the checked-out files.
5. A successful Mac build does not prove avatar08 has correct runtime permissions or server `.env` values.

## Server-side handoff language

If a Mac-side coding agent needs the server-side agent to verify avatar08, ask for this:

```text
Please apply the avatar08 ACL repair from docs/20260512_SERVER_AGENT_FIX_PERMISSIONS_V02.md, restart hermes-whisper-02.service, verify http://127.0.0.1:8010/api/health, verify https://api.hermes-whisper.dashanddata.com/api/health, and report any non-secret recent traceback from journald or /home/limited_user/logs/hermes-whisper-02-api.log.
```

## Current source of truth

For avatar08 permission repair commands, use:

- `docs/20260512_SERVER_AGENT_FIX_PERMISSIONS_V02.md`

For API implementation conventions, use:

- `api/AGENTS.md`

For mobile implementation conventions, use:

- `mobile/AGENTS.md`

For protocol behavior, use:

- `docs/20260510_PROTOCOL_V01.md`
