# Mitwirken

Issues und Pull Requests sind willkommen. Bitte halte Änderungen klein,
nachvollziehbar und für andere RunPod-Nutzer reproduzierbar.

## Lokale Prüfung

```bash
make validate
```

Wenn du das Container-Image änderst, baue es zusätzlich für `linux/amd64`:

```bash
make image IMAGE=qwen-runpod-helper:test
```

Ein vollständiger Modellstart benötigt eine kompatible NVIDIA-GPU und wird
nicht als Voraussetzung für einen Pull Request erwartet. Beschreibe deshalb,
was du tatsächlich getestet hast.

## Sicherheitsregeln

- Niemals Hugging-Face-, RunPod-, Registry- oder Open-WebUI-Tokens committen.
- Keine realen Pod-IDs, Chat-Daten oder generierten Passwörter in Logs posten.
- Neue öffentliche Ports und mächtige Open-WebUI-Funktionen müssen im Pull
  Request ausdrücklich begründet werden.
- Änderungen an Action-Versionen müssen auf einen vollständigen Commit-SHA
  gepinnt bleiben.

Sicherheitslücken bitte gemäß [SECURITY.md](SECURITY.md) vertraulich melden.
