import json
import pathlib
import re
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import pytest

import antonime_proxy as proxy


class FakeInvoker:
    def __init__(self, result=None, error=None):
        self.result = result or (200, b'{"cuvant": "bun", "antonime": ["r\xc4\x83u"]}', "public")
        self.error = error
        self.words = []

    def __call__(self, word):
        self.words.append(word)
        if self.error:
            raise self.error
        return self.result


@pytest.fixture
def serve():
    servers = []

    def start(invoker, cap=None):
        cap = cap or proxy.MinuteCap(100)
        srv = ThreadingHTTPServer(("127.0.0.1", 0), proxy.make_handler(invoker, cap))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        servers.append(srv)
        return f"http://127.0.0.1:{srv.server_address[1]}"

    yield start
    for srv in servers:
        srv.shutdown()


def get(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            return r.status, json.loads(r.read()), r.headers
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read()), e.headers


def test_valid_word_is_invoked_and_passed_through(serve):
    inv = FakeInvoker()
    status, body, headers = get(serve(inv) + "/antonime?cuvant=%20bun%20")
    assert status == 200
    assert body == {"cuvant": "bun", "antonime": ["rău"]}
    assert headers["Content-Type"] == "application/json; charset=utf-8"
    assert headers["Cache-Control"] == "public"
    assert inv.words == ["bun"]  # stripped before invoking


def test_function_status_is_mapped(serve):
    inv = FakeInvoker(result=(502, b'{"eroare": "Serviciul LLM nu a r\xc4\x83spuns"}', "no-store"))
    status, body, _ = get(serve(inv) + "/antonime?cuvant=bun")
    assert (status, body) == (502, {"eroare": "Serviciul LLM nu a răspuns"})


@pytest.mark.parametrize(
    "query",
    ["", "?cuvant=", "?cuvant=foarte%20bun", "?cuvant=%3Cscript%3E", "?cuvant=" + "a" * 41],
)
def test_invalid_input_never_invokes(serve, query):
    inv = FakeInvoker()
    status, body, _ = get(serve(inv) + "/antonime" + query)
    assert (status, body) == (400, proxy.ERR_INVALID)
    assert inv.words == []


def test_global_cap_returns_429_without_invoking(serve):
    now = [0.0]
    inv = FakeInvoker()
    base = serve(inv, proxy.MinuteCap(2, clock=lambda: now[0]))
    assert get(base + "/antonime?cuvant=bun")[0] == 200
    assert get(base + "/antonime?cuvant=rece")[0] == 200
    assert get(base + "/antonime?cuvant=zi")[:2] == (429, proxy.ERR_BUSY)
    assert len(inv.words) == 2  # the 429 did not invoke
    now[0] += 60
    assert get(base + "/antonime?cuvant=zi")[0] == 200


def test_invalid_input_does_not_use_the_cap(serve):
    inv = FakeInvoker()
    base = serve(inv, proxy.MinuteCap(1))
    for _ in range(5):
        assert get(base + "/antonime?cuvant=%3Cx%3E")[0] == 400
    assert get(base + "/antonime?cuvant=bun")[0] == 200


def test_invoke_error_is_502_json(serve):
    status, body, _ = get(serve(FakeInvoker(error=TimeoutError("slow"))) + "/antonime?cuvant=bun")
    assert (status, body) == (502, proxy.ERR_UNAVAILABLE)


def test_healthz_never_invokes(serve):
    inv = FakeInvoker()
    assert get(serve(inv) + "/healthz")[:2] == (200, {"status": "ok"})
    assert inv.words == []


def test_unknown_path_is_404(serve):
    assert get(serve(FakeInvoker()) + "/admin")[0] == 404


def test_word_rule_matches_the_function():
    func_src = (pathlib.Path(__file__).parents[2] / "function" / "func.py").read_text()
    func_pattern = re.search(r'WORD_RE = re\.compile\(r"([^"]+)"\)', func_src).group(1)
    assert proxy.WORD_RE.pattern == func_pattern
