# HermesWhisper02 deployment

## Scope

1. These artifacts describe the canonical v1 API deployment shape.
2. They are committed for avatar08 and Maestro04 operators to apply from the server side.
3. Do not run systemd or Nginx commands from the Mac workstation.
4. Current avatar08 testing may still use the observed `limited_user` and port `8010` service described in `docs/20260512_AVATAR08_ENVIRONMENT.md`.

## Files

1. `deploy/systemd/hermes-whisper-02-api.service`
   - API service unit for avatar08.
   - Runs from `/opt/hermes-whisper-02/api`.
   - Reads `/etc/hermes-whisper-02/env`.
   - Listens on `127.0.0.1:8765`.
2. `deploy/nginx/api.hermes-whisper.dashanddata.com.conf`
   - Maestro04 reverse proxy template.
   - Preserves Certbot-managed TLS directives.
   - Includes WebSocket upgrade headers for `/ws/voice`.
3. `deploy/monitor/healthcheck.py`
   - Cron-friendly health checker.
   - Writes Loguru file logs under `PATH_TO_LOGS`.

## Bring-up

1. Create the runtime user and directories on avatar08.

```bash
sudo useradd --system --home /nonexistent --shell /usr/sbin/nologin hermes
sudo mkdir -p /opt/hermes-whisper-02 /etc/hermes-whisper-02 /var/log/hermes-whisper-02 /var/lib/hermes-whisper-02
sudo chown -R hermes:hermes /var/log/hermes-whisper-02 /var/lib/hermes-whisper-02
```

2. Clone or sync the repo to `/opt/hermes-whisper-02`.

```bash
sudo git clone https://github.com/costa-rica/HermesWhisper02.git /opt/hermes-whisper-02
sudo chown -R root:root /opt/hermes-whisper-02
sudo chmod -R a+rX /opt/hermes-whisper-02
```

3. Install API dependencies.

```bash
cd /opt/hermes-whisper-02/api
sudo /usr/local/bin/uv sync --frozen
```

4. Write `/etc/hermes-whisper-02/env`.

```bash
sudo install -m 600 -o root -g root /dev/null /etc/hermes-whisper-02/env
sudo editor /etc/hermes-whisper-02/env
```

5. Include every variable read by the app. Use `api/.env.example` as the source shape.

```dotenv
NAME_APP=hermes-whisper-02-api
RUN_ENVIRONMENT=production
PATH_TO_LOGS=/var/log/hermes-whisper-02
DB_PATH=/var/lib/hermes-whisper-02/voice_store.sqlite
PUBLIC_BASE_URL=https://api.hermes-whisper.dashanddata.com
HERMES_BASE_URL=http://127.0.0.1:8642
HERMES_CHAT_PATH=/chat
HERMES_MOCK=false
EMAIL_DEV_CONSOLE_ONLY=false
WS_QUERY_TOKEN_FALLBACK_ENABLED=false
```

6. Install and start the systemd unit.

```bash
sudo cp /opt/hermes-whisper-02/deploy/systemd/hermes-whisper-02-api.service /etc/systemd/system/hermes-whisper-02-api.service
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-whisper-02-api.service
sudo systemctl status hermes-whisper-02-api.service --no-pager -l
```

7. Seed the mobile login user.

```bash
cd /opt/hermes-whisper-02/api
sudo -u hermes /usr/local/bin/uv run --project /opt/hermes-whisper-02/api scripts/seed_user.py nrodrig1@gmail.com
```

8. Install the Maestro04 Nginx config.

```bash
sudo cp deploy/nginx/api.hermes-whisper.dashanddata.com.conf /etc/nginx/sites-available/api.hermes-whisper.dashanddata.com
sudo editor /etc/nginx/sites-available/api.hermes-whisper.dashanddata.com
sudo ln -sfn /etc/nginx/sites-available/api.hermes-whisper.dashanddata.com /etc/nginx/sites-enabled/api.hermes-whisper.dashanddata.com
sudo nginx -t
sudo systemctl reload nginx
```

9. Replace `AVATAR08_INTERNAL_IP` before reloading Nginx.

10. Run Certbot only if the certificate has not already been issued.

```bash
sudo certbot --nginx -d api.hermes-whisper.dashanddata.com
```

11. Smoke-test the deployment.

```bash
curl -i http://127.0.0.1:8765/api/health
curl -i https://api.hermes-whisper.dashanddata.com/api/health
wscat -c wss://api.hermes-whisper.dashanddata.com/ws/voice -H "Authorization: Bearer TOKEN"
```

## Monitoring

1. Install a cron entry for the health checker.

```cron
*/5 * * * * cd /opt/hermes-whisper-02/api && /usr/local/bin/uv run --project /opt/hermes-whisper-02/api ../deploy/monitor/healthcheck.py
```

2. Confirm logs are written.

```bash
tail -n 50 /var/log/hermes-whisper-02/hermes-whisper-02-api-healthcheck.log
```

## Avatar08 compatibility note

1. The observed 2026-05-12 avatar08 service uses:
   - User `limited_user`
   - Working directory `/home/limited_user/applications/HermesWhisper02/api`
   - Port `8010`
2. If continuing with that service instead of the canonical unit above, keep the Nginx upstream pointed at the existing `8010` target.
3. After branch switches on avatar08, apply the ACL repair in `docs/20260512_SERVER_AGENT_FIX_PERMISSIONS_V02.md` before restarting the service.
