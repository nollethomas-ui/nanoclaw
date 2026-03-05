# CLAUDE.md — nanoclaw-assistant

## Project Overview

Personal voice-enabled AI assistant based on [NanoClaw](https://github.com/qwibitai/nanoclaw) (v1.1.3, MIT, ~17k Stars), deployed on GCP with WhatsApp and Telegram channels.

**Architecture:**
```
Voice Message (WhatsApp/Telegram)
  → OGG/Opus Audio
    → GCP VM (e2-micro, us-central1, Free Tier)
      → Groq Whisper STT (Free Tier) → Text
        → NanoClaw (Claude Agent SDK, Haiku 3.5) → Response with <voice> tags
          → ElevenLabs TTS ($5/Mo) or Google Cloud TTS (Free, Fallback) → OGG/Opus Audio
            → Voice Note (short summary) + Text Message (full detail) back to user
```

**Key Difference from upstream NanoClaw:** NanoClaw is text-only. This project patches it with a voice layer: STT transcription on inbound, TTS synthesis on outbound. NanoClaw already has an `add-voice-transcription` skill (OpenAI Whisper) — our patches replace it with Groq Whisper (free) and add TTS response.

### Smart Voice Response (`<voice>` Tag Pattern)
Agent generates `<voice>short summary</voice>` + full detailed text. `voice-response.ts` parses the tag:
- **Voice note:** Only the `<voice>` summary (~15 seconds, 1-3 sentences)
- **Text message:** Full response without `<voice>` tags
- **Fallback:** No `<voice>` tag → old behavior (TTS entire text)
- Instructions in `groups/main/CLAUDE.md` + `groups/global/CLAUDE.md`

### TTS Provider Selection
`TTS_PROVIDER` env var controls which TTS engine is used:
- `elevenlabs` — ElevenLabs Multilingual v2, OGG/Opus direct output, $5/Mo Starter
- `google` (default) — Google Cloud TTS Standard, free tier
- Automatic fallback: ElevenLabs error → Google TTS
- Setup: `bash deploy/setup-elevenlabs.sh <API_KEY> <VOICE_ID>`

## Repository Structure

```
nanoclaw-assistant/
├── CLAUDE.md                           # This file
├── .env.example                        # Required environment variables
├── .gitignore
├── config/
│   └── settings.json                   # Voice middleware configuration
├── deploy/
│   ├── create-gcp-project.sh           # GCP project + VM creation
│   ├── setup-vm.sh                     # VM provisioning (Docker, Node, ffmpeg, swap)
│   ├── nanoclaw.service                # systemd service file
│   ├── sync-voice-middleware.sh        # Deploy voice-middleware to VM
│   └── health-check.sh                # Cron health check (every 5 min)
├── voice-middleware/                    # Standalone voice layer (TypeScript)
│   ├── package.json                    # groq-sdk, @google-cloud/text-to-speech
│   ├── tsconfig.json
│   ├── vitest.config.ts
│   ├── src/
│   │   ├── index.ts                    # Barrel export
│   │   ├── types.ts                    # STTProvider, TTSProvider interfaces
│   │   ├── stt/
│   │   │   └── groq-whisper.ts         # Groq Whisper STT client
│   │   ├── tts/
│   │   │   ├── google-tts.ts           # Google Cloud TTS (primary, free)
│   │   │   └── elevenlabs.ts           # ElevenLabs TTS (premium, optional)
│   │   └── audio/
│   │       └── converter.ts            # MP3→OGG/Opus via ffmpeg
│   └── tests/
│       ├── groq-whisper.test.ts
│       ├── google-tts.test.ts
│       └── elevenlabs.test.ts
└── patches/                            # NanoClaw fork modifications
    ├── apply-patches.sh                # Auto-apply script
    ├── 01-transcription-groq.ts        # Replace: src/transcription.ts (Groq statt OpenAI)
    ├── 02-whatsapp-voice-handler.patch # Modify: src/channels/whatsapp.ts (voice messages)
    ├── 03-voice-response.ts            # Add: src/voice-response.ts (TTS synthesis)
    ├── 04-dockerfile-no-chromium.patch # Replace: container/Dockerfile (~400MB smaller)
    ├── 05-router-voice-routing.patch   # Modify: src/index.ts (TTS on voice-originated msgs)
    └── 06-package-json-additions.patch # Add: groq-sdk + @google-cloud/text-to-speech
```

## NanoClaw Upstream (v1.1.3)

**Architecture insight:** NanoClaw runs as two processes:
1. **Host process** (Node.js, `src/index.ts`) — WhatsApp/Telegram connection, message queue, SQLite DB
2. **Agent container** (Docker, `container/agent-runner/`) — Claude Agent SDK, MCP tools, isolated per group

Messages flow: Channel → SQLite → Poll loop (2s) → Docker container (stdin JSON) → Claude SDK → stdout JSON → Channel.

**Key upstream files for patching:**
- `src/channels/whatsapp.ts` — Baileys socket, `messages.upsert` handler, text extraction
- `src/index.ts` — `processGroupMessages()`, `runAgent()` callback, response routing
- `src/types.ts` — `Channel` interface (add `sendAudio?`)
- `container/Dockerfile` — Chromium + agent-browser (remove for RAM savings)
- `src/env.ts` — `.env` parser (reads secrets, passes to container via stdin)

**NanoClaw existing `add-voice-transcription` skill:** Uses OpenAI Whisper, only STT (no TTS response). Our patches extend this to: Groq Whisper (free) + Google TTS response.

## Fork Status

**Fork:** `nollethomas-ui/nanoclaw` (Branch: `voice-support`, Commit `c68454c`)
**Alle 6 Patches angewendet** (01.03.2026):
- Patch 01: `src/transcription.ts` (Groq Whisper STT)
- Patch 02: `src/channels/whatsapp.ts` (Voice-Download + Transkription + `sendAudio()`)
- Patch 02: `src/types.ts` (`sendAudio?` auf Channel-Interface)
- Patch 03: `src/voice-response.ts` (Google TTS + `synthesizeAndSend()`)
- Patch 04: `container/Dockerfile` (Lightweight, ohne Chromium)
- Patch 05: `src/index.ts` (Voice-Routing via `synthesizeAndSend`)
- Patch 06: `package.json` (`groq-sdk` + `@google-cloud/text-to-speech`)

**Lokaler Klon:** `nanoclaw-fork/` im Workspace-Root

**Hinweis:** `npm install` schlaegt auf Windows fehl (`better-sqlite3` braucht Visual Studio C++ Build Tools). Build nur auf Linux-VM moeglich.

### TypeScript-Fixes (01.03.2026, waehrend Deployment)
- `readEnvFile()` in upstream erwartet `keys: string[]` Argument — Patches 01 + 03 gefixt
- `Buffer` nicht kompatibel mit `BlobPart` in Node 22 — `new Uint8Array(buffer)` Workaround
- `Transcription` Cast via `unknown` fuer Groq SDK Typen
- `textToSpeech` Default-Import → Named Import `{ TextToSpeechClient }` fuer @google-cloud/text-to-speech

### TTS Feedback-Loop Fix (im Fork, Commit `c68454c`)
- Bot-sent voice notes via `sendAudio()` were transcribed by the bot itself → infinite loop
- Root cause: `ASSISTANT_HAS_OWN_NUMBER=false` detects bot messages via `Nano:` prefix, but audio has no prefix
- Discovery: User messages come from LID-JID (`@lid`), bot messages from PN-JID (`@s.whatsapp.net`)
- Fix: Skip voice messages where `fromMe && sender.endsWith('@s.whatsapp.net')` in `whatsapp.ts`
- Result: Voice→Text+Voice dual response works cleanly, no feedback loop

### K1 Allowlist Self-Chat Fix (im Fork, Commit `d742801`)
- Self-Chat Sender kommt als LID-JID (`93651963277451@lid`), nicht als Telefonnummer
- Allowlist prüft Telefonnummern → blockierte eigene Nachrichten
- Fix: `fromMe` Nachrichten umgehen Allowlist: `if (!fromMe && !isSenderAllowed(sender))`
- `fromMe` Variable nach oben verschoben (war vorher doppelt deklariert)

### Main Group Bootstrap
- NanoClaw pollt nur `registeredGroups` — ohne registrierte Gruppen passiert nichts
- Henne-Ei-Problem: Registrierung via IPC vom Agent-Container, der nur für registrierte Gruppen startet
- **Lösung:** Self-Chat manuell in `messages.db` (`registered_groups` Tabelle) eintragen:
  ```bash
  # Auf VM, im NanoClaw-Verzeichnis:
  node -e "const Database = require('better-sqlite3'); const db = new Database('store/messages.db'); db.prepare('INSERT OR REPLACE INTO registered_groups (jid,name,folder,trigger_pattern,added_at,container_config,requires_trigger) VALUES (?,?,?,?,?,?,?)').run('491774124474@s.whatsapp.net','Main','main','@Nano',new Date().toISOString(),null,0); db.close();"
  ```
- `folder=main` → MAIN_GROUP_FOLDER, `requires_trigger=0` → kein @Nano Prefix nötig

### Headless Pairing Code (im Fork, Commit `0e03366`)
- `WHATSAPP_PHONE` in `.env` setzen (z.B. `491774124474`) → aktiviert Pairing-Code-Modus
- Bei QR-Event: statt `process.exit(1)` wird `requestPairingCode()` aufgerufen
- 8-stelliger Code erscheint prominent im `journalctl` Log
- Eingabe in WhatsApp: Einstellungen → Verknüpfte Geräte → Stattdessen mit Telefonnummer verknüpfen
- Kein QR-Rendering mehr nötig — perfekt für headless SSH-Server
- Ohne `WHATSAPP_PHONE`: Fallback auf `process.exit(1)` mit Hinweis auf `.env`

### Original Patch Workflow (Referenz)
```bash
# Auto-apply patches (copies files + installs deps)
bash /path/to/nanoclaw-assistant/patches/apply-patches.sh /path/to/nanoclaw-fork

# Manual patches (whatsapp.ts, index.ts, types.ts) — bereits auf Fork angewendet
```

## GCP Deployment

- **GCP Project:** `nanoclaw-tnoll` (erstellt 01.03.2026)
- **VM:** `nanoclaw-vm` e2-micro (us-central1-a, Free Tier), Ubuntu 24.04, 30GB disk, IP: 34.133.165.94
- **Service Account:** `nanoclaw-tts@nanoclaw-tnoll.iam.gserviceaccount.com` (TTS Key auf VM)
- **APIs:** Compute Engine, Cloud Text-to-Speech, Secret Manager
- **Secrets:** `ANTHROPIC_API_KEY`, `GROQ_API_KEY` (in Secret Manager), optional: `ELEVENLABS_API_KEY`
- **Status (03.03.2026):** VOLL PRODUKTIV. Text-Chat + Voice-STT + Voice-TTS funktionieren. Dual Response: Voice→Text+Voice, Text→Text only.
- **Health-Check:** Cron `*/5 * * * *` → `/opt/nanoclaw/health-check.sh` (root crontab, Log: `/var/log/nanoclaw-health.log`)
- **Logrotate:** `/etc/logrotate.d/nanoclaw-health` (weekly, 4 rotate, compress)
- **link-preview-js:** Installiert (Baileys URL-Preview Warnung behoben)

### Deployment Commands
```bash
# Create GCP project + VM
bash deploy/create-gcp-project.sh nanoclaw-assistant-XXXXXX

# SSH to VM
gcloud compute ssh nanoclaw-vm --zone=us-central1-a --project=<PROJECT_ID>

# Provision VM (Docker, Node 22, ffmpeg, swap)
sudo bash setup-vm.sh

# Install systemd service
sudo cp nanoclaw.service /etc/systemd/system/
sudo systemctl daemon-reload && systemctl enable nanoclaw

# Start & watch logs (scan QR code for WhatsApp)
sudo systemctl start nanoclaw
sudo journalctl -u nanoclaw -f

# Sync voice-middleware updates
bash deploy/sync-voice-middleware.sh <PROJECT_ID>
```

### Memory Optimization (e2-micro, 1GB RAM)
- Chromium removed from agent container (patch 04, saves ~400MB)
- `MAX_CONCURRENT_CONTAINERS=1`
- `CONTAINER_TIMEOUT=300000` (5 min instead of default 30 min)
- `NODE_OPTIONS=--max-old-space-size=256`
- 2GB swap file configured (`vm.swappiness=10`)
- Health check restarts at >90% memory usage

## Channels

### WhatsApp (Built-in, Baileys)
- Connects via Baileys v7 (unofficial WhatsApp Web API)
- QR code scan on first run (`journalctl -u nanoclaw -f`)
- Session stored in `store/auth/` directory
- **Risk:** Unofficial API, account ban possible. Keep volume moderate.

### Telegram (via /add-telegram skill)
- Bot created via @BotFather → Token
- Polling mode (no inbound ports needed)
- Same voice modifications applied

## Voice Pipeline

### STT: Groq Whisper Large v3
- **Cost:** $0 (Free Tier: 28,800 audio seconds/day)
- **Model:** `whisper-large-v3`
- **Language:** `de` (German), auto-detect also works
- **Input:** OGG/Opus (native WhatsApp/Telegram format)
- **Fallback:** OpenAI Whisper API ($0.006/min) if Groq is down

### TTS: Google Cloud TTS Standard (Primary)
- **Cost:** $0 (Free Tier: 4M characters/month)
- **Voice:** `de-DE-Standard-B` (male) or configurable
- **Output:** `OGG_OPUS` (native for both WhatsApp and Telegram)
- No ffmpeg conversion needed in happy path

### TTS: ElevenLabs (Premium, Optional)
- **Cost:** $5/month (Starter, 30k chars ≈ ~150 short responses)
- **Output:** MP3 → convert to OGG/Opus via ffmpeg (converter.ts)
- Triggered by config or explicit command

## Cost Summary (~20-50 interactions/day)

| Component | Service | Monthly |
|-----------|---------|---------|
| VM | e2-micro (Free Tier) | $0 |
| LLM | Claude Haiku 3.5 | $3–8 |
| STT | Groq Whisper | $0 |
| TTS | Google TTS Standard | $0 |
| TTS Premium | ElevenLabs Starter | $5 (optional) |
| WhatsApp | Baileys | $0 |
| Telegram | Bot API | $0 |
| **Total** | | **$3–13** |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | Claude API key (Haiku 3.5) |
| `GROQ_API_KEY` | Yes | Groq API key for Whisper STT |
| `GOOGLE_APPLICATION_CREDENTIALS` | Yes | GCP service account for TTS |
| `ELEVENLABS_API_KEY` | No* | ElevenLabs API key (*required if `TTS_PROVIDER=elevenlabs`) |
| `ELEVENLABS_VOICE_ID` | No* | ElevenLabs voice ID (*required if `TTS_PROVIDER=elevenlabs`) |
| `WHATSAPP_PHONE` | Yes* | Phone number for headless pairing (e.g. `491774124474`). Required for first auth. |
| `TELEGRAM_BOT_TOKEN` | No | Telegram bot token (if Telegram enabled) |
| `TTS_PROVIDER` | No | `google` (default) or `elevenlabs` |
| `GOOGLE_TTS_VOICE` | No | TTS voice name (default: `de-DE-Standard-B`) |
| `STT_LANGUAGE` | No | Whisper language hint (default: `de`) |

## Local Development

NanoClaw runs on the VM. Voice-middleware can be developed/tested locally:

```bash
cd nanoclaw-assistant/voice-middleware
npm install
npm run build
npm test          # Unit tests with mocked APIs
npm run dev       # Watch mode
```

## Security Review (02.03.2026)

Umfassende Sicherheitsprüfung durchgeführt. **Status: ALLE MASSNAHMEN UMGESETZT (02.03.2026)**

> Alle 5 kritischen und 6 hohen Schwachstellen wurden am 02.03.2026 behoben. Nächster Schritt: Deployment auf VM + WhatsApp-Pairing.

### Gute Befunde
- Keine hardcoded Secrets im Code (alle via `.env` / Secret Manager)
- `.gitignore` umfassend (`.env`, `gcp-service-account.json`, `store/`)
- TypeScript `strict: true` in allen 3 tsconfig-Dateien
- Docker Container läuft als `node` (non-root)
- Tests nutzen Mock-Keys
- Keine npm postinstall Scripts

### Kritische Schwachstellen (VOR WhatsApp-Pairing beheben)

#### K1: Keine Sender-Beschränkung bei WhatsApp
- NanoClaw prüft nur registrierte Gruppen, nicht einzelne Sender
- JEDER mit der Bot-Telefonnummer kann Nachrichten senden → Claude API wird aufgerufen → Kosten
- **Fix:** Telefonnummer-Allowlist in `src/channels/whatsapp.ts` (messages.upsert Handler)
- **Aufwand:** 1-2h

#### K2: SSH-Firewall offen für 0.0.0.0/0
- `deploy/create-gcp-project.sh` Zeile 40: `--source-ranges 0.0.0.0/0`
- **Fix:** Auf eigene IP beschränken oder GCP IAP (Identity-Aware Proxy) nutzen
- **Aufwand:** 5min

#### K3: VM Service Account mit `--scopes=cloud-platform`
- Volle GCP-Berechtigung — bei VM-Kompromittierung Zugriff auf ALLE Ressourcen
- **Fix:** Custom Role nur mit `texttospeech.client` + `secretmanager.secretAccessor`
- **Aufwand:** 15min

#### K4: WhatsApp-Session in Klartext (`store/auth/`)
- `creds.json` enthält Signal-Protokoll-Keys, von jeder Maschine replay-fähig
- WhatsApp bindet Sessions nicht an IP/Hardware
- **Fix:** Verzeichnis `chmod 700`, idealerweise Disk-Encryption oder Secret Manager
- **Aufwand:** 2-3h

#### K5: Secrets als .env auf VM statt Laufzeit-Abruf aus Secret Manager
- Secret Manager eingerichtet, aber Keys als Datei auf VM kopiert
- **Fix:** `gcloud secrets versions access latest` im systemd ExecStartPre
- **Aufwand:** 1h

### Hohe Schwachstellen (innerhalb 1 Woche nach Deployment)

#### H1: Prompt Injection über Voice
- `content = \`[Voice: ${transcript}]\`` — kein Escaping/Sanitizing
- **Fix:** Sonderzeichen escapen, Längenlimit (2000 chars), Structured Input
- **Aufwand:** 30min

#### H2: Keine Audio-Datei-Validierung
- Keine Größenbeschränkung, kein MIME-Check, kein Transkriptions-Timeout
- Groq Free Tier (28.800 sec/Tag) erschöpfbar mit ~100 großen Audio-Files
- **Fix:** Size limit (10MB), Timeout, MIME validation
- **Aufwand:** 30min

#### H3: Sensible Daten in Logs
- JIDs (Telefonnummern) und Transkript-Auszüge auf info-Level geloggt
- **Fix:** Nur Länge loggen, JIDs maskieren
- **Aufwand:** 30min

#### H4: systemd Service ungehärtet
- Fehlend: `NoNewPrivileges=true`, `ProtectHome=true`, `MemoryLimit=512M`, `CPUQuota=50%`
- **Fix:** Optionen in `nanoclaw.service` ergänzen
- **Aufwand:** 15min

#### H5: Baileys-Version nicht gepinnt
- `"^7.0.0-rc.9"` — Release Candidate mit Caret, jedes `npm install` kann neue Version einziehen
- **Fix:** `"7.0.0-rc.9"` (ohne ^)
- **Aufwand:** 5min

#### H6: Kein Rate Limiting
- Keine Begrenzung pro Sender oder pro API
- **Fix:** 10 msg/min pro Sender, API-Quota-Tracking
- **Aufwand:** 1-2h

### Baileys/WhatsApp — Inhärente Risiken (nicht behebbar)

Diese Risiken sind architekturbedingt und gelten für jede Baileys-basierte Lösung:

1. **Account-Sperre:** WhatsApp sperrt inoffizielle API-Nutzung ohne Vorwarnung
2. **Supply-Chain:** Im Dez 2025 wurde ein malicious Baileys-Fork ("lotusbail") auf npm entdeckt — 56k Downloads, stahl Credentials+Nachrichten. Quelle: [The Hacker News](https://thehackernews.com/2025/12/fake-whatsapp-api-package-on-npm-steals.html)
3. **Keine offizielle Sicherheitsgarantie:** Baileys implementiert Signal-Protokoll selbst, kein Patch-SLA
4. **Session-Hijacking:** Wer `store/auth/creds.json` hat, kann den Account von überall nutzen

**Empfehlung:** Für persönlichen Gebrauch akzeptabel mit Risikobewusstsein. Für produktiven/öffentlichen Einsatz: offizielle WhatsApp Business API verwenden.

### Umsetzungs-Checkliste

| # | Maßnahme | Prio | Aufwand | Status |
|---|----------|------|---------|--------|
| K1 | Telefonnummer-Allowlist | KRITISCH | 1-2h | DONE (02.03.2026) |
| K2 | SSH Firewall auf eigene IP | KRITISCH | 5min | DONE (02.03.2026) |
| K3 | VM-Scopes reduzieren | KRITISCH | 15min | DONE (02.03.2026) |
| K4 | Session-Dateien schützen | KRITISCH | 2-3h | DONE (02.03.2026) |
| K5 | Secrets Laufzeit-Abruf | KRITISCH | 1h | DONE (02.03.2026) |
| H1 | Voice-Input sanitizen | HOCH | 30min | DONE (02.03.2026) |
| H2 | Audio-Validierung | HOCH | 30min | DONE (02.03.2026) |
| H3 | Logs bereinigen | HOCH | 30min | DONE (02.03.2026) |
| H4 | systemd härten | HOCH | 15min | DONE (02.03.2026) |
| H5 | Baileys Version pinnen | HOCH | 5min | DONE (02.03.2026) |
| H6 | Rate Limiting | HOCH | 1-2h | DONE (02.03.2026) |

**Alle Security-Maßnahmen umgesetzt am 02.03.2026.**

### Implementierungsdetails (02.03.2026)

**K1 — Allowlist:** `ALLOWED_SENDERS` Env-Variable (Komma-getrennte Telefonnummern). Prüfung in `whatsapp.ts` messages.upsert vor jeder Verarbeitung. Ohne Wert = deaktiviert.

**K2 — SSH-Firewall:** `SSH_SOURCE_IP` Variable in `create-gcp-project.sh`. Default bleibt `0.0.0.0/0`, muss bei Deployment auf eigene IP gesetzt werden.

**K3 — VM-Scopes:** Dedizierter Service Account `nanoclaw-vm-sa` mit nur `secretmanager.secretAccessor` + `texttospeech.client` Rollen.

**K4 — Session-Schutz:** `setup-vm.sh` Step [9/9] setzt `chmod 700` auf `store/auth/`, `chmod 600` auf `.env`.

**K5 — Secrets Runtime:** `ExecStartPre` in `nanoclaw.service` lädt Secrets aus Secret Manager in `/run/nanoclaw/secrets.env` (transient, automatisch aufgeräumt).

**H1 — Sanitize:** `sanitizeTranscript()` in `whatsapp.ts` — max 2000 Zeichen, Control Characters entfernt.

**H2 — Audio-Validierung:** Max 10MB, MIME-Type-Check gegen Whitelist, Doppelprüfung nach Download.

**H3 — Log-Bereinigung:** `maskJid()` Funktion maskiert Telefonnummern in allen Logs (`491***78`). Keine Transkript-Inhalte mehr in Logs.

**H4 — systemd:** `NoNewPrivileges=true`, `ProtectHome=true`, `ProtectKernelTunables/Modules/ControlGroups=true`, `MemoryMax=512M`, `CPUQuota=80%`.

**H5 — Baileys Pin:** `"7.0.0-rc.9"` statt `"^7.0.0-rc.9"`.

**H6 — Rate Limiting:** Sliding-Window (1 Min), max 10 msg/min pro Sender (konfigurierbar via `RATE_LIMIT_MAX_PER_MIN`).

**Bonus-Fix:** `readEnvFile()` Aufrufe in `transcription.ts` und `voice-response.ts` korrigiert (fehlende `keys` Arrays).

## Integration Activation (05.03.2026)

All 5 integrations have setup scripts ready. After `deploy-update.sh` pulls the latest code, activate each one individually on the VM.

### Overview

| # | Integration | Type | Setup Script | Prerequisites |
|---|------------|------|-------------|---------------|
| 1 | Todoist | Token → Secret Manager | `setup-todoist.sh <TOKEN>` | Todoist API Token |
| 2 | Roam Research | Token → Secret Manager | `setup-roam.sh <TOKEN> <GRAPH>` | Roam API Token (read+edit) |
| 3 | Telegram | Token → Secret Manager | `setup-telegram.sh <BOT_TOKEN>` | BotFather → create bot |
| 4 | Gmail | OAuth (local browser flow) | `setup-gmail.sh --install-from-tmp` | Local OAuth + SCP to VM |
| 5 | Google Sheets | OAuth (local browser flow) | `setup-gsheets.sh --install-from-tmp` | Local OAuth + SCP to VM |

### ExecStartPre Robustness

`nanoclaw.service` now separates required vs. optional secrets:
- **Required** (service won't start without): `ANTHROPIC_API_KEY`, `GROQ_API_KEY`
- **Optional** (empty string if missing, service still starts): `TODOIST_API_TOKEN`, `ELEVENLABS_API_KEY`, `ROAM_API_TOKEN`, `ROAM_GRAPH_NAME`, `TELEGRAM_BOT_TOKEN`

Gmail + Google Sheets use file-based OAuth credentials at `~/.gmail-mcp/` and `~/.gsheets-mcp/` — not Secret Manager.

### Step-by-step: Deploy + Activate

```bash
# 0. SSH to VM
gcloud compute ssh nanoclaw-vm --zone=us-central1-a --project=nanoclaw-tnoll

# 1. Pull latest code + restart
sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/deploy-update.sh

# 2. Todoist
sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-todoist.sh <TODOIST_TOKEN>

# 3. Roam Research
sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-roam.sh <ROAM_API_TOKEN> <GRAPH_NAME>

# 4. Telegram (create bot via @BotFather first)
sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-telegram.sh <BOT_TOKEN>

# 5. Gmail (3-step: local OAuth → SCP → VM install)
#    Lokal:
mkdir %USERPROFILE%\.gmail-mcp
copy newsletter-agent\config\credentials.json %USERPROFILE%\.gmail-mcp\gcp-oauth.keys.json
cd nanoclaw-fork && python setup_gmail_oauth.py
#    SCP:
gcloud compute scp %USERPROFILE%\.gmail-mcp\credentials.json nanoclaw-vm:/tmp/gmail-credentials.json --zone=us-central1-a --project=nanoclaw-tnoll
gcloud compute scp %USERPROFILE%\.gmail-mcp\gcp-oauth.keys.json nanoclaw-vm:/tmp/gmail-oauth-keys.json --zone=us-central1-a --project=nanoclaw-tnoll
#    VM:
sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-gmail.sh --install-from-tmp

# 6. Google Sheets (same 3-step flow)
#    Lokal:
mkdir %USERPROFILE%\.gsheets-mcp
copy newsletter-agent\config\credentials.json %USERPROFILE%\.gsheets-mcp\gcp-oauth.keys.json
cd nanoclaw-fork && python setup_gsheets_oauth.py
#    SCP:
gcloud compute scp %USERPROFILE%\.gsheets-mcp\credentials.json nanoclaw-vm:/tmp/gsheets-credentials.json --zone=us-central1-a --project=nanoclaw-tnoll
gcloud compute scp %USERPROFILE%\.gsheets-mcp\gcp-oauth.keys.json nanoclaw-vm:/tmp/gsheets-oauth-keys.json --zone=us-central1-a --project=nanoclaw-tnoll
#    VM:
sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-gsheets.sh --install-from-tmp
```

### Smoke Tests (via WhatsApp)

| Integration | Test Message | Expected |
|---|---|---|
| Todoist | "Was steht auf meiner Todoist-Liste?" | Lists current tasks |
| Roam | "Such in Roam nach Einträgen mit Tag #erfasst" | Finds Roam blocks |
| Telegram | Direct message to bot in Telegram | Bot replies (text + voice) |
| Gmail | "Zeig mir meine letzten 3 E-Mails" | Shows inbox subjects |
| Gmail | "Schreib eine E-Mail an t.nolle@gmx.de: Testmail von Nano" | Sends email |
| Google Sheets | "Lies die erste Zeile aus Sheet \<ID\>" | Shows cell contents |
| Logs | `sudo journalctl -u nanoclaw -f` | MCP server registration visible |

### Future Integrations

- **Google Calendar:** Custom NanoClaw skill (Phase 3)
- **MCP Bridge:** Voice commands to trigger workspace projects (WBW-Radar, newsletter-agent, etc.)
