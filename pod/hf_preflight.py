#!/usr/bin/env python3
"""Fail fast with an actionable message when a model cannot be downloaded."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def verify_model_access(
    model_name: str,
    token: str,
    filename: str = "config.json",
    cache_dir: str | None = None,
) -> int:
    if Path(model_name).is_dir():
        print(f"Lokales Modellverzeichnis gefunden: {model_name}", flush=True)
        return 0

    from huggingface_hub import hf_hub_download

    print(
        f"Pruefe Hugging-Face-Zugriff auf {model_name}/{filename} ...",
        flush=True,
    )
    try:
        hf_hub_download(
            repo_id=model_name,
            filename=filename,
            token=token,
            cache_dir=cache_dir,
        )
    except Exception as exc:  # huggingface_hub uses several HTTP exception types
        response = getattr(exc, "response", None)
        status_code = getattr(response, "status_code", None)
        gated = type(exc).__name__ == "GatedRepoError"
        if gated or status_code in (401, 403):
            print(
                "Fehler: Der aktive HF_TOKEN darf das Modell nicht herunterladen.\n"
                "1. Bedingungen im Browser mit demselben Hugging-Face-Konto "
                "akzeptieren und eine eventuelle Freigabe abwarten.\n"
                "2. Einen neuen Fine-grained Token erstellen und entweder genau "
                "dieses Modell oder 'public gated repositories' zum Lesen erlauben.\n"
                "3. HF_TOKEN im aktiven Pod UND im RunPod-Template ersetzen.\n"
                "Der Tokenwert wird aus Sicherheitsgruenden nicht ausgegeben.",
                file=sys.stderr,
                flush=True,
            )
            return 77

        print(
            f"Fehler beim Hugging-Face-Zugriff ({type(exc).__name__}): {exc}",
            file=sys.stderr,
            flush=True,
        )
        return 69

    print("Hugging-Face-Modellzugriff erfolgreich.", flush=True)
    return 0


def main() -> int:
    if os.environ.get("SKIP_HF_PREFLIGHT", "false").lower() == "true":
        print("Hugging-Face-Preflight wurde explizit deaktiviert.", flush=True)
        return 0

    return verify_model_access(
        model_name=os.environ["MODEL_NAME"],
        token=os.environ["HF_TOKEN"],
        filename=os.environ.get("HF_PREFLIGHT_FILE", "config.json"),
        cache_dir=os.environ.get("HF_HOME"),
    )


if __name__ == "__main__":
    raise SystemExit(main())
