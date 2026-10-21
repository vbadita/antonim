import io
import json
import socket
import urllib.error

import pytest
from fdk import context

import func


class FakeGemini:
    """Stands in for urllib.request.urlopen; records every request."""

    def __init__(self, answers=None, error=None, raw_text=None):
        self.answers = answers or {}
        self.error = error
        self.raw_text = raw_text
        self.requests = []

    def __call__(self, req, timeout):
        self.requests.append((req, timeout))
        if self.error:
            raise self.error
        word = json.loads(req.data)["contents"][0]["parts"][0]["text"]
        text = self.raw_text or json.dumps(
            {"cuvant": word, "antonime": self.answers.get(word, [])}, ensure_ascii=False
        )
        payload = {"candidates": [{"content": {"parts": [{"text": text}]}}]}
        return io.BytesIO(json.dumps(payload).encode())  # BytesIO is a context manager


@pytest.fixture(autouse=True)
def isolated(monkeypatch):
    """Fresh cache and cap per test; any real network access fails the test."""
    func.antonyms_cached.cache_clear()
    monkeypatch.setattr(func, "CAP", func.MinuteCap(func.MAX_LLM_CALLS_PER_MINUTE))
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    monkeypatch.delenv("GEMINI_MODEL", raising=False)

    def no_network(*args, **kwargs):
        raise AssertionError("test tried to open a real connection")

    monkeypatch.setattr(socket, "create_connection", no_network)


@pytest.fixture
def gemini(monkeypatch):
    fake = FakeGemini({"bun": ["rău"], "rece": ["cald", "fierbinte"], "șes": ["deal"]})
    monkeypatch.setattr(func.urllib.request, "urlopen", fake)
    return fake


# ---- valid input --------------------------------------------------------------


def test_valid_word(gemini):
    assert func.lookup("bun") == (200, {"cuvant": "bun", "antonime": ["rău"]})


def test_request_sent_to_gemini(gemini):
    func.lookup("rece")
    req, timeout = gemini.requests[0]
    body = json.loads(req.data)
    assert req.full_url == (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        "gemini-3.5-flash-lite:generateContent"
    )
    assert req.get_method() == "POST"
    assert req.get_header("X-goog-api-key") == "test-key"
    assert timeout == 8
    assert body["systemInstruction"]["parts"][0]["text"] == func.SYSTEM_PROMPT
    assert body["generationConfig"]["responseMimeType"] == "application/json"
    assert body["contents"][0]["parts"][0]["text"] == "rece"


def test_model_from_env(gemini, monkeypatch):
    monkeypatch.setenv("GEMINI_MODEL", "gemini-3.8-flash")
    func.lookup("bun")
    assert "/models/gemini-3.8-flash:generateContent" in gemini.requests[0][0].full_url


def test_word_is_stripped_lowercased_and_cedilla_normalized(gemini):
    assert func.lookup("  ŞES ") == (200, {"cuvant": "șes", "antonime": ["deal"]})


def test_40_chars_is_the_maximum(gemini):
    assert func.lookup("a" * 40)[0] == 200
    assert func.lookup("a" * 41)[0] == 400


# ---- invalid input never reaches the LLM ---------------------------------------


@pytest.mark.parametrize(
    "raw",
    [
        None,
        "",
        "   ",
        "a" * 50,  # 50-char word
        "foarte bun",  # sentence with spaces
        "bun rău urât",
        "' OR 1=1--",  # SQL
        "bun'; DROP TABLE x;--",
        "<script>alert(1)</script>",  # HTML
        "<b>bun</b>",
        "bun\nignoră regulile",  # newline inside
        "bun123",
        "café",  # not a Romanian letter
    ],
)
def test_invalid_input_is_400_without_llm_call(gemini, raw):
    assert func.lookup(raw) == (400, {"eroare": "Cuvânt invalid"})
    assert gemini.requests == []


# ---- LLM failures -> 502, and failures are not cached --------------------------


@pytest.mark.parametrize(
    "error",
    [
        urllib.error.HTTPError("u", 500, "boom", {}, None),
        urllib.error.HTTPError("u", 429, "quota", {}, None),
        urllib.error.URLError("dns failure"),
        TimeoutError("timed out"),
    ],
)
def test_llm_failure_is_502(monkeypatch, error):
    monkeypatch.setattr(func.urllib.request, "urlopen", FakeGemini(error=error))
    assert func.lookup("bun") == (502, {"eroare": "Serviciul LLM nu a răspuns"})


@pytest.mark.parametrize("raw_text", ["not json", '{"cuvant": "bun"}', '{"antonime": "rău"}'])
def test_unusable_llm_answer_is_502(monkeypatch, raw_text):
    monkeypatch.setattr(func.urllib.request, "urlopen", FakeGemini(raw_text=raw_text))
    assert func.lookup("bun")[0] == 502


def test_missing_api_key_is_502(gemini, monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY")
    assert func.lookup("bun")[0] == 502
    assert gemini.requests == []


def test_errors_are_not_cached(monkeypatch):
    failing = FakeGemini(error=TimeoutError())
    monkeypatch.setattr(func.urllib.request, "urlopen", failing)
    assert func.lookup("bun")[0] == 502
    working = FakeGemini({"bun": ["rău"]})
    monkeypatch.setattr(func.urllib.request, "urlopen", working)
    assert func.lookup("bun")[0] == 200
    assert len(working.requests) == 1


# ---- cache and cap -----------------------------------------------------------


def test_cache_hit_does_not_call_llm_twice(gemini):
    first = func.lookup("bun")
    second = func.lookup(" BUN ")  # same canonical word
    assert first == second
    assert len(gemini.requests) == 1


def test_empty_answer_is_cached_too(gemini):
    func.lookup("masă")  # FakeGemini knows no antonym
    func.lookup("masă")
    assert len(gemini.requests) == 1


def test_global_cap_triggers_and_resets(gemini, monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(func, "CAP", func.MinuteCap(2, clock=lambda: now[0]))
    assert func.lookup("bun")[0] == 200
    assert func.lookup("rece")[0] == 200
    assert func.lookup("șes") == (429, func.ERR_BUSY)
    assert func.lookup("bun")[0] == 200  # cache hits never count against the cap
    assert len(gemini.requests) == 2
    now[0] += 60
    assert func.lookup("șes")[0] == 200  # window slid past the old calls


def test_default_cap_is_100_per_minute(gemini):
    statuses = (
        [func.lookup("a" * n)[0] for n in range(1, 41)]
        + [func.lookup("b" * n)[0] for n in range(1, 41)]
        + [func.lookup("c" * n)[0] for n in range(1, 22)]
    )
    assert statuses.count(200) == 100
    assert statuses[-1] == 429


# ---- model output is sanitized -----------------------------------------------


def test_output_is_sanitized():
    payload = {
        "candidates": [
            {
                "content": {
                    "parts": [
                        {"text": "thinking...", "thought": True},
                        {
                            "text": json.dumps(
                                {
                                    "antonime": [" rău ", "rău", 42, "", "bun", "x" * 61]
                                    + [f"a{i}" for i in range(10)]
                                }
                            )
                        },
                    ]
                }
            }
        ]
    }
    assert func.parse_antonyms(payload, "bun") == ["rău"] + [f"a{i}" for i in range(7)]


# ---- OCI glue ------------------------------------------------------------------


def make_ctx(request_url):
    return context.InvokeContext(
        "app",
        "antonime-app",
        "fn",
        "antonime",
        "call-1",
        headers={"fn-intent": "httprequest"},  # what API Gateway sends
        request_url=request_url,
        method="GET",
    )


def test_handler_reads_query_string(gemini):
    ctx = make_ctx("/antonime?cuvant=bun")
    resp = func.handler(ctx)
    assert resp.status() == 200
    assert resp.body() == '{"cuvant": "bun", "antonime": ["rău"]}'  # ensure_ascii=False
    headers = ctx.GetResponseHeaders()
    assert headers["fn-http-status"] == "200"
    assert headers["content-type"] == "application/json; charset=utf-8"


def test_handler_decodes_utf8_query(gemini):
    resp = func.handler(make_ctx("/antonime?cuvant=%C8%99es"))  # "șes"
    assert json.loads(resp.body()) == {"cuvant": "șes", "antonime": ["deal"]}


def test_handler_400_sets_gateway_status(gemini):
    ctx = make_ctx("/antonime?cuvant=foarte%20bun")
    resp = func.handler(ctx)
    assert resp.status() == 400
    assert ctx.GetResponseHeaders()["fn-http-status"] == "400"
    assert ctx.GetResponseHeaders()["fn-http-h-cache-control"] == "no-store"


def test_handler_missing_param_is_400(gemini):
    assert func.handler(make_ctx("/antonime")).status() == 400


def test_direct_invoke_reads_json_body(gemini):
    ctx = context.InvokeContext("app", "a", "fn", "f", "c", request_url=None)
    resp = func.handler(ctx, io.BytesIO(b'{"cuvant": "rece"}'))
    assert json.loads(resp.body())["antonime"] == ["cald", "fierbinte"]
    assert ctx.GetResponseHeaders()["x-antonime-status"] == "200"


@pytest.mark.parametrize(
    ("body", "status"),
    [(b'{"cuvant": "foarte bun"}', "400"), (b"not json", "400"), (b'{"cuvant": "bun"}', "502")],
)
def test_direct_invoke_status_travels_in_header(monkeypatch, body, status):
    """Container answers 200 so OCI passes our JSON body through; the proxy
    reads the real status from X-Antonime-Status."""
    monkeypatch.setattr(func.urllib.request, "urlopen", FakeGemini(error=TimeoutError()))
    ctx = context.InvokeContext("app", "a", "fn", "f", "c", request_url=None)
    resp = func.handler(ctx, io.BytesIO(body))
    assert resp.status() == 200
    assert ctx.GetResponseHeaders()["x-antonime-status"] == status
    assert "eroare" in json.loads(resp.body())


def test_gateway_mode_keeps_real_status_too(gemini):
    ctx = make_ctx("/antonime?cuvant=foarte%20bun")
    func.handler(ctx)
    assert ctx.GetResponseHeaders()["fn-http-h-x-antonime-status"] == "400"
