from __future__ import annotations

import importlib.util
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import Mock


SCRIPT = Path(__file__).parents[1] / "pod" / "hf_preflight.py"
SPEC = importlib.util.spec_from_file_location("hf_preflight", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeResponse:
    def __init__(self, status_code: int) -> None:
        self.status_code = status_code


class FakeHubError(Exception):
    def __init__(self, status_code: int) -> None:
        super().__init__(f"HTTP {status_code}")
        self.response = FakeResponse(status_code)


class HuggingFacePreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        self.download = Mock(return_value="/cache/config.json")
        self.hub_module = types.ModuleType("huggingface_hub")
        self.hub_module.hf_hub_download = self.download
        self.previous = sys.modules.get("huggingface_hub")
        sys.modules["huggingface_hub"] = self.hub_module

    def tearDown(self) -> None:
        if self.previous is None:
            sys.modules.pop("huggingface_hub", None)
        else:
            sys.modules["huggingface_hub"] = self.previous

    def test_downloads_config_with_token_without_printing_it(self) -> None:
        result = MODULE.verify_model_access("owner/model", "hf_secret", cache_dir="/cache")
        self.assertEqual(result, 0)
        self.download.assert_called_once_with(
            repo_id="owner/model",
            filename="config.json",
            token="hf_secret",
            cache_dir="/cache",
        )

    def test_returns_configuration_error_for_forbidden_model(self) -> None:
        self.download.side_effect = FakeHubError(403)
        self.assertEqual(MODULE.verify_model_access("owner/model", "hf_secret"), 77)

    def test_skips_hub_for_local_model_directory(self) -> None:
        with tempfile.TemporaryDirectory() as model_dir:
            self.assertEqual(MODULE.verify_model_access(model_dir, "hf_secret"), 0)
        self.download.assert_not_called()


if __name__ == "__main__":
    unittest.main()
