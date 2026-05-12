# Server agent instructions: fix HermesWhisper02 API permissions

Use this file as the prompt for the server-side coding agent running on fsdc-avatar08 as `nick`.

## Context

1. HermesWhisper02 is deployed on the FSDC Ubuntu VM named `Avatar08`.
2. Public traffic enters through Maestro04 Nginx and is proxied to Avatar08.
3. The public API URL is:
   - `https://api.hermes-whisper.dashanddata.com`
4. The API service runs as `limited_user`.
5. `nick` is the administrative user and should perform repository, permission, environment, and systemd setup.
6. `limited_user` should not need login access or sudo. It should only run the app through systemd.

## Problem to fix

The deployed API crashed after the latest push and restart. The relevant syslog error was:

```text
PermissionError: [Errno 13] Permission denied: '/home/limited_user/applications/HermesWhisper02/api/app/pipecat_processors/mocks.py'
```

This means the Python process running as `limited_user` could not read one of the deployed source files. Because the app failed during import, Loguru app file logging may not have been configured early enough to write the failure to `PATH_TO_LOGS`; the traceback appeared in journald/syslog instead.

## Goals

1. Make the deployed repository readable and traversable by `limited_user`.
2. Make runtime write paths owned or writable by `limited_user`.
3. Keep secrets out of git.
4. Restart the systemd service and verify the API from localhost and the public URL.
5. Capture any remaining failure from both journald and the app log file.

## Paths to confirm on Avatar08

1. Repository:
   - `/home/limited_user/applications/HermesWhisper02`
2. API directory:
   - `/home/limited_user/applications/HermesWhisper02/api`
3. Python environment:
   - `/home/limited_user/environments/hermes_whisper_venv`
4. App logs:
   - `/home/limited_user/logs`
5. Database directory:
   - `/home/limited_user/databases`
6. Systemd unit:
   - `/etc/systemd/system/hermes-whisper-02.service`

If any path differs, inspect the active systemd unit and `.env` file first, then adapt the commands below to the actual paths.

## Read first on the server

1. `AGENTS.md`
2. `api/AGENTS.md`
3. `api/README.md`
4. `docs/LOGGING_PYTHON_V06.md`
5. `docs/20260510_PLAN_API_V01.md`
6. `docs/api.hermes-whisper.dashanddata.com`
7. The active systemd unit:
   - `/etc/systemd/system/hermes-whisper-02.service`
8. The active API `.env` file, without printing secrets into logs or chat.

## Inspect the current failure

1. Check service status:

```bash
sudo systemctl status hermes-whisper-02.service --no-pager
```

2. Read recent logs:

```bash
sudo journalctl -u hermes-whisper-02.service -n 200 --no-pager
```

3. Confirm the exact runtime user:

```bash
systemctl cat hermes-whisper-02.service
```

4. Confirm the failed file permissions:

```bash
namei -l /home/limited_user/applications/HermesWhisper02/api/app/pipecat_processors/mocks.py
ls -la /home/limited_user/applications/HermesWhisper02/api/app/pipecat_processors/
```

## Fix source tree ownership and readability

Run as `nick` on Avatar08.

1. Set the deployed app tree to `limited_user`.

```bash
sudo chown -R limited_user:limited_user /home/limited_user/applications/HermesWhisper02
```

2. Make directories traversable and readable by the owner.

```bash
sudo find /home/limited_user/applications/HermesWhisper02 -type d -exec chmod 755 {} \;
```

3. Make source and non-secret config files readable by the owner.

```bash
sudo find /home/limited_user/applications/HermesWhisper02 -type f ! -name '.env' -exec chmod 644 {} \;
```

4. If a live `.env` exists inside the app tree, keep it owner-only.

```bash
sudo find /home/limited_user/applications/HermesWhisper02 -type f -name '.env' -exec chmod 600 {} \;
```

5. Preserve executable bits for scripts that need them.

```bash
sudo find /home/limited_user/applications/HermesWhisper02 -type f -path '*/scripts/*.sh' -exec chmod 755 {} \;
```

6. If the repo contains local helper binaries or scripts that are intentionally executable, inspect them and restore execute bits only where required.

## Fix runtime write paths

1. Create required runtime directories.

```bash
sudo mkdir -p /home/limited_user/logs
sudo mkdir -p /home/limited_user/databases
```

2. Set runtime paths to `limited_user`.

```bash
sudo chown -R limited_user:limited_user /home/limited_user/logs
sudo chown -R limited_user:limited_user /home/limited_user/databases
```

3. Set directory permissions.

```bash
sudo chmod 755 /home/limited_user/logs
sudo chmod 755 /home/limited_user/databases
```

4. If the SQLite database already exists, ensure it is writable by `limited_user`.

```bash
sudo find /home/limited_user/databases -type f -exec chmod 600 {} \;
```

## Confirm environment variables

Do not print secret values in chat or commit them to git.

1. Confirm the active `.env` or `EnvironmentFile` provides:
   - `NAME_APP=hermes-whisper-02-api`
   - `RUN_ENVIRONMENT=testing` or `RUN_ENVIRONMENT=production`
   - `PATH_TO_LOGS=/home/limited_user/logs`
   - `DB_PATH=/home/limited_user/databases/hermes-whisper-02.sqlite`
   - `JWT_SECRET`
   - email settings required for 2FA
2. If `RUN_ENVIRONMENT=testing`, Loguru should write both:
   - app file logs under `PATH_TO_LOGS`
   - stderr logs to journald
3. If `RUN_ENVIRONMENT=production`, Loguru should write app file logs under `PATH_TO_LOGS`; systemd should still capture process startup failures in journald.

## Verify imports as limited_user before restart

Run an import smoke test as the same user that systemd uses.

```bash
cd /home/limited_user/applications/HermesWhisper02/api
sudo -u limited_user /home/limited_user/environments/hermes_whisper_venv/bin/python -c "import app.main; print('import ok')"
```

If this fails, fix the reported permission or environment issue before restarting systemd.

## Restart and verify

1. Reload systemd after any unit changes.

```bash
sudo systemctl daemon-reload
```

2. Restart the service.

```bash
sudo systemctl restart hermes-whisper-02.service
```

3. Check service status.

```bash
sudo systemctl status hermes-whisper-02.service --no-pager
```

4. Verify local API health on Avatar08.

```bash
curl -i http://127.0.0.1:8765/api/health
```

5. Verify app log file creation.

```bash
sudo ls -la /home/limited_user/logs
sudo tail -n 100 /home/limited_user/logs/hermes-whisper-02-api.log
```

6. Verify public API health from a client machine.

```bash
curl -i https://api.hermes-whisper.dashanddata.com/api/health
```

## Optional WebSocket smoke test

Only run this after REST health passes.

1. Confirm Nginx still has WebSocket upgrade headers.
2. Confirm the app can log in through the public URL.
3. Confirm `/ws/voice` accepts an authenticated mobile WebSocket connection.
4. If WebSocket fails but REST works, inspect:
   - Maestro04 Nginx config
   - `docs/api.hermes-whisper.dashanddata.com`
   - `journalctl -u hermes-whisper-02.service`
   - `/home/limited_user/logs/hermes-whisper-02-api.log`

## What not to do

1. Do not run the production API as `nick`.
2. Do not make `.env` world-readable if it contains secrets.
3. Do not commit `.env`, JWT secrets, email passwords, API keys, or database files.
4. Do not use `chmod -R 777`.
5. Do not change public API behavior while fixing permissions.
6. Do not remove Certbot-managed Nginx lines.

## Report back

Return a short status with:

1. The ownership and permission changes made.
2. Whether `import app.main` succeeds as `limited_user`.
3. Whether `systemctl status` is active.
4. Whether `/api/health` works locally and publicly.
5. Whether app logs are written to `PATH_TO_LOGS`.
6. Any remaining traceback, copied from journald or the app log with secrets redacted.
