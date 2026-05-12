# Server agent instructions: fix recurring API checkout permissions

Use this file instead of `docs/20260512_SERVER_AGENT_FIX_PERMISSIONS.md` on fsdc-avatar08.

## Decision

The V01 approach fixes the immediate import failure, but it is not the right recurring fix when `nick` checks out or pulls branches while `hermes-whisper-02.service` runs as `limited_user`.

The unsafe part is recursively changing the deployed Git checkout to `limited_user:limited_user`. That lets the service account own source and Git metadata, and it does not match the operating model where `nick` performs repository operations and `limited_user` only runs the app through systemd.

Use this model instead:

1. `nick` owns and updates the Git checkout.
2. `limited_user` has read and traverse access to deployed source through ACLs.
3. `limited_user` owns only runtime write paths, such as logs and SQLite files.
4. `.env` remains non-world-readable, with an explicit read ACL for `limited_user` if it is owned by `nick`.
5. After every checkout, pull, merge, or file generation step, run the ACL repair, restart the service, and use health checks plus logs as the runtime-user import verification.

## Observed avatar08 context

Observed on 2026-05-12:

1. Service unit:
   - `/etc/systemd/system/hermes-whisper-02.service`
2. Runtime user and group:
   - `User=limited_user`
   - `Group=limited_user`
3. Working directory:
   - `/home/limited_user/applications/HermesWhisper02/api`
4. ExecStart:
   - `/home/limited_user/environments/hermes_whisper_venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8010`
5. Runtime `.env` path:
   - `/home/limited_user/applications/HermesWhisper02/api/.env`
6. Non-secret runtime values observed in `.env`:
   - `NAME_APP=hermes-whisper-02-api`
   - `RUN_ENVIRONMENT=testing`
   - `PATH_TO_LOGS=/home/limited_user/logs`
   - `DB_PATH=/home/limited_user/databases/voice_store.sqlite`
7. Failing source file:
   - `/home/limited_user/applications/HermesWhisper02/api/app/pipecat_processors/mocks.py`
8. Observed failure:
   - `mocks.py` was owned by `nick:nick` with mode `660`, so `limited_user` could not read it.
9. Sudo limitation:
   - `sudo -n -u limited_user id` returns `sudo: a password is required`.
   - `sudo -n /usr/bin/systemctl status hermes-whisper-02.service --no-pager -l` returns `sudo: a password is required`.
   - Do not assume passwordless `sudo -u` or passwordless privileged `systemctl status` is available.

## What not to do

1. Do not run `sudo chown -R limited_user:limited_user /home/limited_user/applications/HermesWhisper02`.
2. Do not run `chmod -R 777`.
3. Do not make `api/.env` world-readable.
4. Do not run the production or testing API as `nick`.
5. Do not print API keys, bearer tokens, email passwords, JWT secrets, or 2FA codes.
6. Do not commit `.env`, database files, logs, or secrets.
7. Do not make verification depend on `sudo -n -u limited_user` or `sudo -n systemctl status`.

## Inspect without printing secrets

Run these as `nick` on avatar08.

```bash
systemctl show hermes-whisper-02.service \
  -p FragmentPath \
  -p User \
  -p Group \
  -p WorkingDirectory \
  -p ExecStart \
  -p EnvironmentFiles \
  -p LoadState \
  -p ActiveState \
  -p SubState \
  --no-pager
```

```bash
systemctl cat hermes-whisper-02.service --no-pager
```

```bash
ss -ltnp | grep -E ':(8010)\b|hermes|uvicorn|python' || true
```

```bash
namei -l /home/limited_user/applications/HermesWhisper02/api/app/pipecat_processors/mocks.py
```

```bash
getfacl -p \
  /home/limited_user/applications/HermesWhisper02 \
  /home/limited_user/applications/HermesWhisper02/api/.env \
  /home/limited_user/applications/HermesWhisper02/api/app/pipecat_processors/mocks.py
```

Print only non-secret `.env` values:

```bash
cd /home/limited_user/applications/HermesWhisper02
awk -F= '/^(NAME_APP|RUN_ENVIRONMENT|PATH_TO_LOGS|DB_PATH|API_HOST|API_PORT)=/ {print $1"="$2}' api/.env
```

Print only `.env` key names:

```bash
cd /home/limited_user/applications/HermesWhisper02
awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/ {print $1}' api/.env | sort
```

## One-time ownership baseline

Run as `nick` on avatar08.

This keeps the checkout under `nick` control while preserving service read access through ACLs.

```bash
sudo chown -R nick:nick /home/limited_user/applications/HermesWhisper02
```

If `nick` cannot traverse `/home/limited_user` without `sudo`, grant only the parent-directory access needed to reach the checkout:

```bash
sudo setfacl -m u:nick:--x /home/limited_user
sudo setfacl -m u:nick:--x /home/limited_user/applications
sudo setfacl -m u:nick:rwx /home/limited_user/applications/HermesWhisper02
```

Keep runtime paths owned by the service account:

```bash
sudo mkdir -p /home/limited_user/logs /home/limited_user/databases
sudo chown -R limited_user:limited_user /home/limited_user/logs /home/limited_user/databases
sudo chmod 750 /home/limited_user/logs /home/limited_user/databases
```

If the SQLite database already exists, keep it writable only by `limited_user`:

```bash
sudo find /home/limited_user/databases -type f -exec chown limited_user:limited_user {} \;
sudo find /home/limited_user/databases -type f -exec chmod 600 {} \;
```

## ACL repair after checkout or pull

Run as `nick` after every checkout, pull, merge, reset, generated-file step, or copied-file deployment.

```bash
cd /home/limited_user/applications/HermesWhisper02

sudo find . -path './.git' -prune -o -type d -exec chmod u+rwx {} \;
sudo find . -path './.git' -prune -o -type f ! -path './api/.env' -exec chmod u+rw {} \;

sudo find . -path './.git' -prune -o -exec setfacl -m u:limited_user:rX {} \;
sudo find . -path './.git' -prune -o -type d -exec setfacl -m d:u:limited_user:rX {} \;

sudo chmod 600 api/.env
sudo setfacl -m u:limited_user:r-- api/.env
```

If scripts must be executable, restore only the known script execute bits:

```bash
cd /home/limited_user/applications/HermesWhisper02
sudo find api/scripts -type f -name '*.sh' -exec chmod u+x {} \;
```

## Optional systemd hardening

Use this only after the permission repair and runtime verification pass.

The service does not need to write `.pyc` files into the source checkout. Prevent bytecode writes so source directories can stay read-only to `limited_user`:

```bash
sudo systemctl edit hermes-whisper-02.service
```

Add:

```ini
[Service]
Environment=PYTHONDONTWRITEBYTECODE=1
```

Then reload systemd:

```bash
sudo systemctl daemon-reload
```

## Runtime-user import verification

Do not assume `nick` can run passwordless `sudo -u limited_user` on avatar08.

Use the systemd restart as the practical import check because the service itself runs `app.main:app` as `limited_user`.

If restart or health verification fails, fix the reported file, directory, `.env`, log, database, or dependency permission problem before treating the checkout as repaired.

## Restart and verify

Use the observed avatar08 port `8010`.

```bash
sudo systemctl daemon-reload
sudo systemctl restart hermes-whisper-02.service
systemctl status hermes-whisper-02.service --no-pager -l
```

If non-sudo `systemctl status` is not readable enough for diagnosis, continue with the health checks and log checks below instead of assuming `sudo -n systemctl status` will work.

Verify local health:

```bash
curl -i http://127.0.0.1:8010/api/health
```

Verify public health:

```bash
curl -i https://api.hermes-whisper.dashanddata.com/api/health
```

Verify app logs under `PATH_TO_LOGS`:

```bash
ls -la /home/limited_user/logs
tail -n 100 /home/limited_user/logs/hermes-whisper-02-api.log
```

If these log commands are not readable as `nick`, report that limitation and use health checks plus non-sudo journald if available. Do not widen permissions on secret-bearing paths just to print logs.

If startup fails before Loguru writes app logs, inspect journald without sudo if readable:

```bash
journalctl -u hermes-whisper-02.service -n 200 --no-pager
```

If non-sudo journald is not readable, report that limitation. Do not print secrets from journald or app logs.

## Quick recurrence check

After a future pull or checkout, confirm ACLs and ownership without printing secrets:

```bash
cd /home/limited_user/applications/HermesWhisper02
namei -l api/app/pipecat_processors/mocks.py
getfacl -p api api/.env api/app/pipecat_processors/mocks.py
```

Then run the ACL repair and restart verification. The successful recurrence signal is:

1. `systemctl status hermes-whisper-02.service --no-pager -l` shows the service active when readable as `nick`.
2. `curl -i http://127.0.0.1:8010/api/health` succeeds locally.
3. `curl -i https://api.hermes-whisper.dashanddata.com/api/health` succeeds publicly.
4. App logs or non-sudo journald show no remaining import traceback, if readable.

## Report back

Return:

1. Whether ACL repair was applied after the latest checkout or pull.
2. Whether restart plus health checks show that `app.main` imports under the `limited_user` service.
3. Whether non-sudo `systemctl status` is active, if readable.
4. Whether local health works on `http://127.0.0.1:8010/api/health`.
5. Whether public health works on `https://api.hermes-whisper.dashanddata.com/api/health`.
6. Whether app logs are written under `/home/limited_user/logs`, if readable.
7. Whether non-sudo journald is readable.
8. Any remaining traceback from journald or the app log with secrets redacted.
