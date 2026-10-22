"""Static checks on frontend/index.html (no browser needed)."""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PAGE = (ROOT / "frontend" / "index.html").read_text(encoding="utf-8")
sys.path.insert(0, str(ROOT / "scripts"))
from csp import InlineCode  # noqa: E402  (a real HTML parser: skips comments)

_parser = InlineCode()
_parser.feed(PAGE)
(SCRIPT,) = _parser.blocks["script"]  # exactly one inline script


def test_csp_hashes_match_the_inline_code():
    result = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts" / "csp.py"),
            "--check",
            str(ROOT / "frontend" / "index.html"),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def test_csp_is_strict():
    csp = re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', PAGE).group(1)
    assert "default-src 'none'" in csp
    assert "connect-src 'self'" in csp  # only our own API
    assert "unsafe-inline" not in csp and "unsafe-eval" not in csp


def test_no_html_injection_sinks():
    """Network data must only reach the DOM through textContent / createElement."""
    for sink in (
        "innerHTML",
        "outerHTML",
        "insertAdjacentHTML",
        "document.write",
        "eval(",
        "new Function",
    ):
        assert sink not in SCRIPT, sink
    assert "textContent" in SCRIPT


def test_messages_for_every_error_the_api_returns():
    for status in ("400", "429", "502"):
        assert re.search(rf"\b{status}:", SCRIPT), status


def test_word_rule_matches_the_function():
    func_src = (ROOT / "function" / "func.py").read_text(encoding="utf-8")
    func_chars = re.search(r'WORD_RE = re\.compile\(r"([^"]+)"\)', func_src).group(1)
    page_rule = re.search(r"const WORD_RE = /\^(.+)\$/;", SCRIPT).group(1)
    assert page_rule == func_chars


def test_api_is_same_origin():
    assert 'const API = "/antonim/api/antonime";' in SCRIPT


def test_version_placeholder_present():
    """frontend-sync.sh replaces it with the deployed commit."""
    assert PAGE.count("__VERSION__") == 2


def test_romanian_ui():
    assert '<html lang="ro">' in PAGE
    assert ">Caută</button>" in PAGE
    assert 'name="viewport"' in PAGE  # mobile
