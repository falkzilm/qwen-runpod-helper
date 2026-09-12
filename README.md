# Sicherer Qwen-Pod mit Open WebUI

[![Container image](https://github.com/falkzilm/qwen-runpod-helper/actions/workflows/container.yml/badge.svg)](https://github.com/falkzilm/qwen-runpod-helper/actions/workflows/container.yml)
[![GHCR](https://img.shields.io/badge/GHCR-qwen--runpod--helper-blue?logo=github)](https://github.com/falkzilm/qwen-runpod-helper/pkgs/container/qwen-runpod-helper)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Ein einzelner RunPod-Pod betreibt das Modell über vLLM und Open WebUI. Nur
Open WebUI ist öffentlich erreichbar; vLLM lauscht ausschließlich auf
`127.0.0.1` innerhalb des Containers.

Das Repository ist als Community-Vorlage gedacht: Das fertige Image kann direkt
verwendet werden, während Modell, Kontextgröße und GPU-Profil über
Umgebungsvariablen austauschbar bleiben. Pull Requests und nachvollziehbare
Modellprofile sind willkommen.

```text
Browser / OpenCode / Cline
          │ HTTPS + WebUI-Login bzw. eigener API-Key
          ▼
https://POD_ID-8080.proxy.runpod.net
          │
       Nginx :8080                    öffentlich
──────────── Sicherheitsgrenze ────────────────────
          ├── Open WebUI :8081         nur 127.0.0.1
          ├── vLLM :8000               nur 127.0.0.1
          └── SearXNG :8888            optional, nur 127.0.0.1
          │
 Qwen3.8-27B-Uncensored-FP8
```

## Gewähltes Profil

- Image-Basis: `vllm/vllm-openai:v0.28.0`
- Open WebUI: `0.11.3` in einer getrennten Python-3.11-Umgebung
- Modell: `orcarouter/Qwen3.8-27B-Uncensored-FP8`
- GPU: eine H100 80 GB
- Kontext: 131072 Token, FP8-KV-Cache
- maximal vier parallele Sequenzen
- Text-only, Qwen-Reasoning, native Tool Calls und MTP aktiviert
- RunPod HTTP-Proxy: ausschließlich Port `8080/http`
- keine öffentlichen TCP-Ports und kein öffentlicher vLLM-Port
- Nginx begrenzt Login-Versuche und parallele Verbindungen, setzt
  Sicherheitsheader und unterstützt WebSockets/Streaming
- optionales, internes SearXNG mit drei vorkonfigurierten Suchmaschinen

Das Modell ist ein abliterierter Community-Umbau ohne verlässliche Guardrails.
Zugriffsregeln, Tool-Freigaben und Kostenlimits dürfen niemals dem Modell selbst
überlassen werden.

## Schnellstart mit dem fertigen Community-Image

Für RunPod wird kein lokaler Docker-Build benötigt. Verwende im privaten
RunPod-Template das versionierte Image:

```text
ghcr.io/falkzilm/qwen-runpod-helper:0.1.1
```

Release-Tags sind reproduzierbarer als `latest`. Noch strenger ist ein in GHCR
angezeigter Digest wie `ghcr.io/falkzilm/qwen-runpod-helper@sha256:...`.
`edge` wird aus dem aktuellen Stand von `main` gebaut und ist für Tests gedacht.

Danach:

1. Repository klonen und mit `make init` die privaten Werte erzeugen.
2. In RunPod ein **privates** Template mit dem Image, `8080/http`, 80 GB
   Container Disk und 10 GB Volume Disk unter `/workspace` anlegen.
3. Die Werte aus `pod/template.env` als Environment Variables übertragen.
4. Eine H100 80 GB starten und die WebUI über
   `https://POD_ID-8080.proxy.runpod.net` öffnen.
5. Nach der Sitzung den Pod mit **Stop**, nicht mit **Terminate**, anhalten.

Die folgenden Kapitel erklären jede Entscheidung und alle Schritte ausführlich.

## Voraussetzungen

Du brauchst:

- einen RunPod-Account mit Guthaben,
- einen Hugging-Face-Account und einen read-only Access Token,
- `bash`, `openssl` und `rg` für die lokalen Hilfsskripte.

Docker mit Buildx und eine eigene Registry brauchst du nur, wenn du das Image
selbst verändern und veröffentlichen willst. Es wird keine lokale NVIDIA-GPU
zum Bauen benötigt. Secrets werden erst im privaten RunPod-Template gesetzt und
gelangen nicht in das öffentliche Image oder in GitHub Actions.

## Speicherstrategie und echte Kosten

Die günstige Standardkonfiguration trennt Daten und Modellcache:

| Daten | Pfad | Verhalten beim Stoppen |
|---|---|---|
| Chats, Accounts, Einstellungen | `/workspace/open-webui` | bleiben erhalten |
| Hugging-Face-Modellcache | `/root/.cache/huggingface` | wird gelöscht |
| Container/Image | Container Disk | wird beim Neustart wiederhergestellt |

Empfohlen sind zunächst **80 GB Container Disk** und **10 GB Volume Disk** mit
Mountpoint `/workspace`. Die Container Disk kostet nur während der Pod läuft.
Die 10-GB-Volume-Disk kostet beim gestoppten Pod nach aktuellem Tarif ungefähr
2 USD/Monat. Dafür muss das etwa 31 GB große Modell nach jedem Stop erneut
geladen werden.

Wenn du sehr häufig startest, ist ein persistenter Modellcache bequemer:

1. Volume Disk auf mindestens 50–60 GB erhöhen.
2. Im Template `MODEL_CACHE_DIR=/workspace/huggingface` setzen.

Das kostet gestoppt ungefähr 10–12 USD/Monat, spart aber die wiederholten
Downloads und verkürzt Starts. Volumes können nur vergrößert, nicht verkleinert
werden; deshalb mit dem günstigen 10-GB-Profil beginnen.

Kein Network Volume verwenden, wenn du den Pod mit **Stop/Start** betreiben
willst: Pods mit Network Volume können bei RunPod nur terminiert und neu
bereitgestellt werden. Eine normale Volume Disk bleibt dagegen beim Stoppen
erhalten.

## 1. Secrets erzeugen

1. Öffne die
   [Modellseite](https://huggingface.co/orcarouter/Qwen3.8-27B-Uncensored-FP8),
   melde dich an und akzeptiere beziehungsweise beantrage den Zugriff. Das ist
   nur im Browser möglich; ein Token akzeptiert die Bedingungen nicht für dich.
2. Warte, bis die Modellseite den Zugriff tatsächlich als freigegeben anzeigt.
   Bei manueller Freigabe genügt das Absenden des Antrags noch nicht.
3. Erstelle unter **Settings → Access Tokens** mit genau demselben
   Hugging-Face-Konto einen Fine-grained Token. Er braucht entweder Leserechte
   für genau dieses Repository oder die Berechtigung **Read access to contents
   of all public gated repositories you can access**. Ein alter Token muss nach
   einer Rechteänderung gegebenenfalls bearbeitet oder neu erstellt werden.
4. Übernimm den Token in das aktive Pod-Deployment und in das private
   RunPod-Template. Bei einer Pod-Migration können sonst alte Environment
   Variables weiterverwendet werden.
5. Führe im Projektverzeichnis aus:

```bash
make init
```

Das erzeugt die ignorierte Datei `pod/template.env` mit Modelltoken,
WebUI-Secret, internem vLLM-Key und einem starken einmaligen Admin-Passwort.
Die Datei erhält Modus 600. Sichere das ausgegebene Passwort im Passwortmanager.
Kontrollieren kannst du die lokale Konfiguration mit `make validate`.

Ab Image `0.1.1` prüft der Container vor dem Start der Dienste den Zugriff auf
`MODEL_NAME/config.json`. Bei 401/403 bricht er mit einer kurzen Anleitung ab,
ohne den Token auszugeben. Im Pod lässt sich dieselbe Prüfung manuell ausführen:

```bash
/opt/open-webui/bin/python /opt/qwen-pod/hf_preflight.py
```

## 2. Fertiges Image nutzen oder selbst bauen

### Community-Image

Trage in RunPod direkt Folgendes ein:

```text
ghcr.io/falkzilm/qwen-runpod-helper:0.1.1
```

Das Image enthält die Laufzeit, aber weder Modellgewichte noch Secrets. Das
Modell wird beim Pod-Start mit deinem eigenen Hugging-Face-Token geladen.

### Eigenes Image

Nach Änderungen kannst du lokal bauen und in eine eigene Registry pushen:

```bash
make image IMAGE=ghcr.io/DEIN-BENUTZER/qwen-runpod-helper:MEINE-VERSION
make push  IMAGE=ghcr.io/DEIN-BENUTZER/qwen-runpod-helper:MEINE-VERSION
```

Das Image selbst enthält keine Secrets und darf für minimale Registry-Kosten
öffentlich sein; das RunPod-Template bleibt privat. Bei einem privaten Registry-
Repository hinterlegst du dessen Zugangsdaten in RunPod. Verwende kein
`latest`-Tag; neue Versionen erhalten einen neuen Tag.

Vor dem Push zu GHCR einmal anmelden:

```bash
docker login ghcr.io
```

Der Build ist erfolgreich, wenn beide Installationen abgeschlossen werden und
Docker das finale Image taggt. Ein lokaler Funktionstest ohne NVIDIA-GPU kann
den vollständigen vLLM-Start nicht prüfen.

### Automatische GitHub-Releases

Der Workflow [`.github/workflows/container.yml`](.github/workflows/container.yml)
prüft Pull Requests durch einen Build und veröffentlicht bei Pushes:

| Git-Referenz | GHCR-Tags |
|---|---|
| `main` | `edge`, `sha-...` |
| `v1.2.3` | `1.2.3`, `1.2`, `latest`, `sha-...` |

Alle verwendeten Actions sind auf vollständige Commit-SHAs gepinnt. Der Build
erzeugt eine SBOM und Provenance und darf nur Repository-Inhalte lesen sowie in
GitHub Packages schreiben. Ein Release wird so erstellt:

```bash
git tag -a v1.2.3 -m 'Release v1.2.3'
git push origin v1.2.3
```

GHCR legt ein neu veröffentlichtes Paket zunächst möglicherweise privat an.
Der Repository-Besitzer muss dann einmal unter **Packages → Package settings →
Change visibility → Public** die Sichtbarkeit ändern. Erst danach kann RunPod
das Image ohne Registry-Zugangsdaten ziehen. Ein privates Image funktioniert
ebenfalls, benötigt aber passende Registry Credentials in RunPod.

## 3. Privates RunPod-Template anlegen

Unter **Templates → New Template**:

| Einstellung | Wert |
|---|---|
| Template visibility | Private |
| Container Image | `ghcr.io/falkzilm/qwen-runpod-helper:0.1.1` oder eigener Tag |
| Container Disk | 80 GB |
| Volume Disk | 10 GB |
| Volume Mount Path | `/workspace` |
| Expose HTTP Ports | `8080` |
| Expose TCP Ports | leer |
| Docker Entrypoint/Command | leer lassen |

Übertrage anschließend alle Werte aus `pod/template.env` in die Environment
Variables des privaten Templates. Secrets niemals in das Image einbauen.

Besonders wichtig:

- `DATA_DIR` muss unter `/workspace` liegen, sonst verschwinden Chats.
- `MODEL_CACHE_DIR=/root/.cache/huggingface` ist bewusst flüchtig und günstig.
- Nur `8080/http` exponieren. Weder `8000` noch `8081` hinzufügen.
- Das Feld **Docker Command** leer lassen, weil das Image seinen eigenen
  Entrypoint besitzt.
- Jupyter und SSH nicht aktivieren, wenn du sie nicht wirklich benötigst.

## 4. Pod starten

1. Das private Template auswählen.
2. H100 80 GB wählen.
3. Für sensible Chats **Secure Cloud** verwenden. Community Cloud ist günstiger,
   läuft aber auf Infrastruktur von Community-Hosts.
4. On-Demand starten, nicht Spot: Eine Unterbrechung mitten in einer Antwort ist
   für interaktive Nutzung wenig sinnvoll.
5. Warten, bis beide Healthchecks bereit sind. Beim ersten Start kann der
   Modelldownload mehrere Minuten dauern.

Danach ist die Oberfläche erreichbar unter:

```text
https://POD_ID-8080.proxy.runpod.net
```

Nach dem ersten Login das Admin-Passwort in Open WebUI ändern. Registrierung
bleibt deaktiviert. Open-WebUI-Tools, Functions, MCP und Code Interpreter nur
gezielt aktivieren.

### Start kontrollieren

Öffne während des ersten Starts in RunPod die Container-Logs. Die wesentlichen
Phasen sind:

1. Der Preflight bestätigt den Hugging-Face-Zugriff.
2. Open WebUI migriert seine Datenbank und startet intern auf Port 8081.
3. Hugging Face lädt die Modell-Shards; vLLM reserviert Gewichtsspeicher und
   KV-Cache.
4. Nginx veröffentlicht Port 8080. `/health` wird erst mit vLLM bereit.

Die öffentliche `/health`-Route wird erst erfolgreich, wenn Open WebUI und vLLM
beide bereit sind:

```bash
curl --fail https://POD_ID-8080.proxy.runpod.net/health
```

## 5. API-Keys für Coding-Clients

Open WebUI ist das API-Gateway. Der interne vLLM-Key wird niemals an Clients
gegeben.

1. Für jedes Gerät bzw. jeden Client einen separaten Nicht-Admin-Benutzer in
   Open WebUI erstellen.
2. Diesem Benutzer nur Modellzugriff und die API-Key-Berechtigung geben.
3. Unter **Settings → Account → API Keys** dessen `sk-...`-Key erzeugen.

Die API-Key-Allowlist ist im Container auf genau diese Routen beschränkt:

```text
GET  /api/models
POST /api/chat/completions
```

Client-Konfiguration:

- Base URL: `https://POD_ID-8080.proxy.runpod.net/api`
- API Key: der eigene Open-WebUI-Key
- Modell: `qwen3.8-27b-uncensored`
- Timeout: mindestens 900 Sekunden

Vorlagen befinden sich unter
[clients/openai-compatible.env.example](clients/openai-compatible.env.example)
und [clients/opencode.example.json](clients/opencode.example.json).

Ein direkter Funktionstest sieht so aus:

```bash
export OPEN_WEBUI_API_KEY='sk-DEIN-CLIENT-KEY'

curl --fail --show-error \
  https://POD_ID-8080.proxy.runpod.net/api/chat/completions \
  -H "Authorization: Bearer ${OPEN_WEBUI_API_KEY}" \
  -H 'Content-Type: application/json' \
  --data '{
    "model": "qwen3.8-27b-uncensored",
    "messages": [{"role": "user", "content": "Antworte nur mit: bereit"}],
    "stream": false,
    "max_tokens": 32
  }'
```

Der Browserzugriff und die API verwenden dieselbe HTTPS-Adresse. Der API-Key
ersetzt lediglich den Browser-Login und erbt die Rechte seines WebUI-Benutzers.

## Tool Calls und optionale Websuche

Native Tool Calls sind bereits auf beiden Ebenen vorbereitet: vLLM verwendet
den Qwen-Tool-Parser mit automatischer Tool-Wahl, und Open WebUI nutzt seit
Version 0.10 standardmäßig den Native/Agentic-Modus. Ein Tool muss dem Benutzer
beziehungsweise Chat trotzdem ausdrücklich zur Verfügung stehen; das Modell
kann nicht von selbst beliebige Programme auf dem Pod starten.

Die Websuche ist aus Datenschutz- und Kostenkontrollgründen zunächst
ausgeschaltet. Das Image enthält ein vorbereitetes SearXNG, das nur intern auf
`127.0.0.1:8888` lauscht. RunPod veröffentlicht diesen Port nicht. Aktivierung:

1. Im privaten RunPod-Template `ENABLE_SEARXNG=true` setzen. Der von `make init`
   erzeugte Wert `SEARXNG_SECRET` muss ebenfalls vorhanden sein. Anschließend
   den Pod zu einem passenden Zeitpunkt neu starten.
2. Bei einer bereits vorhandenen Open-WebUI-Datenbank **Settings → Admin →
   Tools → Web Search** öffnen und diese Werte speichern:

   | Feld | Wert |
   |---|---|
   | Enable Web Search | an |
   | Web Search Engine | `searxng` |
   | SearXNG Query URL | `http://127.0.0.1:8888/search?q=<query>` |
   | Search Result Count | `5` |
   | Concurrent Requests | `2` |

   Es wird kein SearXNG-API-Key benötigt. `Trust Proxy Environment` bleibt aus,
   solange im Pod kein ausgehender HTTP-Proxy konfiguriert ist. Bei einer
   frischen Datenbank setzt das Startskript die zentralen Werte automatisch.
3. Unter **Settings → Admin → Models** das Qwen-Modell bearbeiten: Capability
   **Web Search** aktivieren, unter **Default Features** ebenfalls **Web Search**
   markieren und unter **Advanced Parameters → Function Calling** den Wert
   **Native** beibehalten. Danach speichern.
4. Falls Web Search nicht als Default Feature gesetzt wurde, im jeweiligen Chat
   über das Plus-/Tools-Menü die Websuche einschalten.
5. Mit einer Frage wie „Suche im Web nach … und nenne die Quellen“ testen.

SearXNG nutzt in dieser Vorlage Brave, DuckDuckGo und Wikipedia, unterstützt die
für Open WebUI erforderliche JSON-Ausgabe und benötigt keinen externen
API-Schlüssel. Anpassungen sind in `pod/searxng-settings.yml` möglich und
erfordern einen neuen Image-Build. `SEARXNG_LANGUAGE` und
`WEB_SEARCH_RESULT_COUNT` können dagegen im privaten Template gesetzt werden.

Im Native-Modus darf das Modell dann selbst entscheiden, `search_web`
aufzurufen und Ergebnisse weiterzuverarbeiten. Suchanfragen und abgerufene
Webseiten verlassen dabei den Pod und sind nicht mehr vollständig lokal. Keine
internen Quelltexte, Tokens oder vertraulichen Chatdaten in Suchanfragen geben.

`SAFE_MODE=true` und `ENABLE_PLUGINS=false` blockieren weiterhin hochriskante
Workspace-Tools und Python-Functions; die eingebaute Websuche bleibt nutzbar.
Community-Tools niemals ungeprüft importieren: Sie laufen serverseitig mit den
Rechten des Open-WebUI-Prozesses.

Bei Coding-Clients ist ein weiterer Unterschied wichtig: Ein normaler
OpenAI-kompatibler Aufruf an `/api/chat/completions` kann strukturierte
`tool_calls` zurückgeben, führt aber nicht automatisch jede mehrstufige
Agent-Schleife aus. Entweder führt der Client die angebotenen Tools selbst aus,
oder er muss Open WebUIs serverseitigen Tool-Calling-Ablauf mit Chat- und
Message-ID verwenden.

SearXNG ist hier technisch ein Begleitprozess im selben Container. RunPod-Pod-
Templates starten nur ein Container-Image und bieten kein Docker-Compose-
Sidecar-Modell. Die Sicherheitsgrenze bleibt dennoch klar: eigener
unprivilegierter Benutzer, bereinigte Prozessumgebung, Loopback-Bindung und kein
Nginx-/RunPod-Port für 8888.

### Funktionsprofile

Die Voreinstellungen bilden ein sicheres, breit nutzbares Kernprofil:

| Funktion | Voreinstellung | Begründung |
|---|---|---|
| Native Tool Calls | aktiv | strukturiert, mehrstufig und KV-Cache-freundlich |
| Notes | aktiv | persistente, manuell kontrollierbare Arbeitsnotizen |
| Memory | aktiv, nur per Tool | Erinnerungen werden nicht pauschal in jeden System-Prompt kopiert |
| automatische Memory-Auswertung | aus | keine unerwarteten Hintergrundaufrufe |
| SearXNG | vorbereitet, aus | bewusste Freigabe externer Suchanfragen |
| Automations | aus | der gestoppte Pod kann ohnehin nichts ausführen; vermeidet Kostenläufe |
| Sub-Agents | aus | jeder Sub-Agent erzeugt weitere Modellaufrufe und kann Kontext vervielfachen |
| Python-Functions/Workspace-Tools | aus | laufen sonst mit Rechten des WebUI-Prozesses |
| Remote Shell/Code-Ausführung | nicht enthalten | gehört in eine getrennte Sandbox |

Für Entwicklung ist OpenCode oder Cline auf dem lokalen Rechner die bevorzugte
Tool-Schicht. Dort können Dateizugriff, Git und Shell auf das konkrete Projekt
begrenzt und jede Aktion sichtbar bestätigt werden, während der RunPod nur
Inference bereitstellt.

Open Terminal kann das Browser-Erlebnis später um eine echte Remote-
Entwicklungsumgebung ergänzen, sollte aber als eigener Container mit separatem
Volume, starkem API-Key, CPU-/RAM-Limits und eingeschränktem Egress laufen. Es
darf weder den Docker-Socket noch die Secrets dieses Modell-Pods erhalten. Das
ist mit einem einfachen RunPod-Single-Container-Template nicht sauber isoliert
und deshalb bewusst kein Bestandteil des Standardimages.

## 6. Nach der Nutzung sicher stoppen

Im RunPod-Dashboard auf **Stop** drücken, nicht **Terminate**. Stop gibt die GPU
frei und behält `/workspace`; Terminate löscht die lokale Volume Disk.

Optional kann das vom lokalen Rechner erfolgen:

```bash
cp .env.control.example .env.control
chmod 600 .env.control
# Pod-ID und einen minimal berechtigten RunPod-Key eintragen

make status
make start
make stop
```

Der Management-Key liegt ausschließlich lokal und wird nie in den Pod kopiert.
Wenn nach dem Stop keine H100 auf derselben Maschine verfügbar ist, kann RunPod
den Pod vorübergehend mit null GPUs anbieten. Dann warten oder die Daten sichern
und später neu deployen; genau deshalb dürfen wichtige Chats nicht die einzige
Kopie bleiben.

### Kostenkontrolle

- Nach jeder Sitzung im Dashboard prüfen, dass der Status wirklich **Stopped**
  lautet.
- RunPod Billing Alerts beziehungsweise ein persönliches Ausgabenlimit setzen.
- Keinen Spot-Pod verwenden, nur um wenige Cent zu sparen, wenn längere Coding-
  Antworten nicht unterbrochen werden dürfen.
- Die GPU niemals über einen API-Key automatisch durch das Modell stoppen
  lassen. Der dafür erforderliche Management-Key gehört nicht in den Pod.

## Backups

Vor wichtigen Änderungen im laufenden Pod mindestens sichern:

```text
/workspace/open-webui
```

Open WebUI verwendet dort unter anderem seine SQLite-Datenbank. Für einzelne
Chats eignet sich der Export in Open WebUI. Für ein vollständiges Backup den
Pod kurz starten, keine Chats mehr schreiben und RunPods Cloud-Sync bzw. einen
konsistenten SQLite-Backupmechanismus verwenden. Kritische Daten zusätzlich
außerhalb von RunPod aufbewahren.

## Fehlerdiagnose

### Die Proxy-URL zeigt 502 oder „Bad Gateway“

Der Container oder Nginx ist noch nicht bereit. Logs öffnen und warten, bis der
Modelldownload und die vLLM-Initialisierung abgeschlossen sind. Prüfen, dass im
Template ausschließlich `8080/http` und kein überschreibender Docker Command
gesetzt ist.

`connect() failed (111: Connection refused) while connecting to upstream` ist
dabei meist nur das Nginx-Symptom. Die eigentliche Ursache steht einige Zeilen
danach bei Open WebUI oder vLLM.

### Hugging Face meldet 401/403

Die Modellbedingungen wurden nicht mit demselben Account akzeptiert, der den
`HF_TOKEN` erstellt hat, der Zugriffsantrag ist noch nicht genehmigt oder dem
Fine-grained Token fehlt die Repository-Berechtigung. Auf der Modellseite den
Status prüfen, anschließend einen passend berechtigten Token desselben Kontos
erstellen und **sowohl den aktiven Pod als auch das private Template**
aktualisieren. Danach den Pod neu starten. `make init` speichert den Wert nur in
der lokalen, ignorierten Datei; es ändert kein bestehendes RunPod-Template.

### Open WebUI 0.11.2 meldet `ENABLE_LOCAL_WEB_FETCH` oder `no such table: config`

Das ist ein Fehler der Open-WebUI-0.11.2-Migration bei einer frischen
Datenbank. Image `0.1.1` verwendet Open WebUI 0.11.3. Wenn ein **erster, noch
ungenutzter** Start mit Image `0.1.0` bereits eine unvollständige Datenbank
angelegt hat:

1. Im privaten Template auf Image `0.1.1` wechseln.
2. Einmalig `RECOVER_OPEN_WEBUI_0112=true` setzen und den Pod starten.
3. Nach erfolgreichem Start die Variable wieder entfernen.

Der Recovery-Schritt löscht das Verzeichnis nicht, sondern verschiebt es nach
`/workspace/open-webui.broken-0112-ZEITSTEMPEL`. Ein Marker verhindert eine
zweite Ausführung. Bei einem bereits benutzten WebUI mit wichtigen Chats zuerst
ein Backup erstellen und die Recovery-Option nicht blind setzen.

### Ein API-Key ist in vLLM-Logs sichtbar

Image `0.1.0` übergab den internen Schlüssel als Kommandozeilenargument. Image
`0.1.1` verwendet stattdessen die offizielle vLLM-Variable `VLLM_API_KEY` und
protokolliert den Wert nicht als Startargument. Einen bereits sichtbaren
Schlüssel als kompromittiert behandeln: `INTERNAL_VLLM_API_KEY` im Template neu
erzeugen und den Pod neu starten. Dieser interne Schlüssel ist nicht mit den
pro Benutzer erzeugten Open-WebUI-API-Keys identisch.

### CUDA Out of Memory

In dieser Reihenfolge reduzieren:

1. `MAX_MODEL_LEN` von `131072` auf `65536`,
2. `MAX_NUM_SEQS` von `4` auf `2` oder `1`,
3. `GPU_MEMORY_UTILIZATION` von `0.90` auf `0.88`.

Danach den Pod vollständig neu starten. Nicht auf eine 48-GB-GPU wechseln; das
31-GB-Modell benötigt zusätzlich Runtime-, Aktivierungs- und KV-Cache-Speicher.

### Open WebUI zeigt keine Modelle

Zuerst `/health` testen und die vLLM-Logs prüfen. Danach kontrollieren, ob
`OPENAI_API_BASE_URL` intern auf `http://127.0.0.1:8000/v1` gesetzt wurde und
`INTERNAL_VLLM_API_KEY` unverändert im Template vorhanden ist. Beides setzt das
Startskript automatisch.

### Pod lässt sich nach dem Stop nicht mit GPU starten

Die zuvor verwendete GPU wurde anderweitig vergeben. Warten und erneut starten.
Da eine lokale Volume Disk an die Maschine gebunden ist, kann ein sofortiges
Verschieben auf einen anderen Host nicht garantiert werden. Bei längerer
Knappheit Daten sichern, Pod terminieren und aus demselben Template neu anlegen.

### Login oder WebSockets funktionieren nicht

Nur die exakte RunPod-Proxy-Adresse benutzen. Das Startskript bildet daraus
automatisch `WEBUI_URL` und `CORS_ALLOW_ORIGIN`. Ein zusätzlicher eigener Domain-
Proxy benötigt passende explizite Werte für beide Variablen.

## Sicherheitscheck vor der ersten echten Nutzung

- Template ist privat und enthält keine unnötigen Management-Rechte.
- Öffentlich exponiert ist ausschließlich `8080/http`.
- Freie Registrierung ist deaktiviert.
- Admin-Passwort wurde nach dem Erstlogin geändert.
- Coding-Clients verwenden Nicht-Admin-Konten mit getrennten API-Keys.
- API-Keys dürfen nur `/api/models` und `/api/chat/completions` aufrufen.
- Tools, MCP, Functions, Websuche und Code Interpreter sind deaktiviert, bis sie
  bewusst benötigt und geprüft wurden.
- RunPod-Ausgabenlimit und Billing Alert sind aktiv.
- Chats mit sensiblen Daten werden regelmäßig extern gesichert.

## Modell wechseln

Für ein anderes Hugging-Face-Modell im Template mindestens `MODEL_NAME`,
`SERVED_MODEL_NAME`, GPU, `MAX_MODEL_LEN`, Quantisierung sowie Reasoning- und
Tool-Parser prüfen. Die Defaults in `pod/start.sh` sind Qwen-3.8-spezifisch.
Qwen-Parser niemals blind für andere Modellfamilien übernehmen.

## Community und Lizenz

Der Helper steht unter der [MIT-Lizenz](LICENSE). Die eingebundenen Projekte,
Container-Basisimages und Modelle behalten ihre jeweils eigenen Lizenzen und
Nutzungsbedingungen. Vor öffentlicher oder kommerzieller Nutzung insbesondere
die Model Card des gewählten Modells prüfen.

Beiträge sind in [CONTRIBUTING.md](CONTRIBUTING.md) beschrieben. Ausnutzbare
Schwachstellen bitte nicht als öffentliches Issue melden, sondern nach
[SECURITY.md](SECURITY.md) vertraulich einreichen. Niemals echte Tokens,
Passwörter, Chat-Inhalte oder Pod-Adressen in Issues und Build-Logs posten.

## Prüfung

```bash
make test
```

Geprüft werden Shell-Syntax, der Hugging-Face-Preflight und, sofern vorhanden,
die Rechte und Platzhalter der lokalen Secret-Datei. Ein Image-Build benötigt
Docker und Internetzugriff; ein Modelltest benötigt eine passende NVIDIA-GPU.

## Primärquellen

- [RunPod: Pods starten, stoppen und verwalten](https://docs.runpod.io/pods/manage-pods)
- [RunPod: Pod- und Storage-Preise](https://docs.runpod.io/pods/pricing)
- [RunPod: Storage-Arten](https://docs.runpod.io/pods/storage/types)
- [RunPod: HTTP-Ports und Sicherheitsanforderungen](https://docs.runpod.io/pods/configuration/expose-ports)
- [Open WebUI: Hardening](https://docs.openwebui.com/getting-started/advanced-topics/hardening/)
- [Open WebUI: API-Keys](https://docs.openwebui.com/features/authentication-access/api-keys/)
- [Open WebUI: Native Tools und Tool-Calling-Modi](https://docs.openwebui.com/features/extensibility/plugin/tools/)
- [Open WebUI: Server-side Tool Calling über die API](https://docs.openwebui.com/reference/server-side-tool-calling/)
- [Open WebUI: Web-Search-Konfiguration](https://docs.openwebui.com/troubleshooting/web-search/)
- [Open WebUI: SearXNG anbinden](https://docs.openwebui.com/features/chat-conversations/web-search/providers/searxng/)
- [Open WebUI: Notes](https://docs.openwebui.com/features/notes/)
- [Open WebUI: Open-Terminal-Sicherheitsmodell](https://docs.openwebui.com/features/open-terminal/advanced/security/)
- [Open WebUI 0.11.2: Fehlerhafte Migration bei frischer Datenbank](https://github.com/open-webui/open-webui/issues/29280)
- [Open WebUI: Releases](https://github.com/open-webui/open-webui/releases)
- [Hugging Face: Zugriff auf gated Models](https://huggingface.co/docs/hub/models-gated)
- [Hugging Face: User Access Tokens und Fine-grained Rechte](https://huggingface.co/docs/hub/security-tokens)
- [vLLM: API-Key über `VLLM_API_KEY` setzen](https://docs.vllm.ai/en/v0.28.0/cli/serve/)
- [SearXNG: Container-Installation](https://docs.searxng.org/admin/installation-docker)
- [SearXNG: Server nur an Loopback binden](https://docs.searxng.org/admin/settings/settings_server.html)
- [Qwen3.8 Uncensored FP8: Model Card](https://huggingface.co/orcarouter/Qwen3.8-27B-Uncensored-FP8)
- [GitHub: Container-Images mit Actions veröffentlichen](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images)
- [GitHub: Container Registry verwenden](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
