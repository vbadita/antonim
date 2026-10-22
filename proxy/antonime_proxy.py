"""Signing proxy: the only door from nginx to the OCI Function.

OCI API Gateway was the first design but has no free band, so nginx does the
public part (TLS, per-IP rate limit, cache) and this process does the rest:

  GET /antonime?cuvant=...   validate -> global invocation cap -> signed invoke
  GET /healthz               liveness only, never invokes

Auth is the VM's instance principal (dynamic group antonime-invokers, policy
"use fn-invocation" in the antonime compartment): no key file on disk.

The global cap is the hard limit that keeps OCI Functions inside its free
allowance: every invocation goes through here, and nothing else may invoke.
"""

from __future__ import annotations

import json
import os
import re
import sys
import threading
import time
from collections import deque
from collections.abc import Callable
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

# Same rule as function/func.py (kept in sync by tests/test_proxy.py): reject
# garbage here so it never costs an invocation or a slot in the global cap.
WORD_RE = re.compile(r"[a-zA-ZăâîșțĂÂÎȘȚşţŞŢ-]{1,40}")

ERR_INVALID = {"eroare": "Cuvânt invalid"}
ERR_BUSY = {"eroare": "Prea multe cereri. Încearcă din nou peste un minut."}
ERR_UNAVAILABLE = {"eroare": "Serviciul nu a răspuns"}
ERR_NOT_FOUND = {"eroare": "Nu există"}


def log(event: str, **fields: object) -> None:
    print(json.dumps({"event": event, **fields}, ensure_ascii=False), file=sys.stdout, flush=True)


class MinuteCap:
    """Sliding window: at most `limit` invocations in any `window` seconds."""

    def __init__(self, limit: int, window: float = 60.0, clock=time.monotonic) -> None:
        self.limit = limit
        self.window = window
        self.clock = clock
        self._calls: deque[float] = deque()
        self._lock = threading.Lock()

    def acquire(self) -> bool:
        with self._lock:
            now = self.clock()
            while self._calls and now - self._calls[0] >= self.window:
                self._calls.popleft()
            if len(self._calls) >= self.limit:
                return False
            self._calls.append(now)
            return True


def valid_word(raw: str | None) -> bool:
    return bool(raw) and WORD_RE.fullmatch(raw.strip()) is not None


# An invoker takes the raw word and returns
# (status, json_body_bytes, cache_control, function_version).
Invoker = Callable[[str], tuple[int, bytes, str, str]]


class OciInvoker:
    """Signed InvokeFunction calls with the instance principal.
    One client per thread (the SDK client is not documented as thread-safe)."""

    def __init__(self, function_id: str, endpoint: str) -> None:
        self.function_id = function_id
        self.endpoint = endpoint
        self._local = threading.local()
        self._signer = None
        self._signer_lock = threading.Lock()

    def _client(self):
        import oci  # heavy import, only in the real service

        with self._signer_lock:
            if self._signer is None:  # refreshes its own token before expiry
                self._signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        if not hasattr(self._local, "client"):
            self._local.client = oci.functions.FunctionsInvokeClient(
                config={},
                signer=self._signer,
                service_endpoint=self.endpoint,
                # A cold start took 44 s: allow it. No retries: each one is a
                # billable invocation, and the caller can simply ask again.
                timeout=(5, 60),
                retry_strategy=oci.retry.NoneRetryStrategy(),
            )
        return self._local.client

    def __call__(self, word: str) -> tuple[int, bytes, str, str]:
        resp = self._client().invoke_function(
            self.function_id,
            invoke_function_body=json.dumps({"cuvant": word}, ensure_ascii=False),
        )
        # The function answers 200 on direct invokes; the real status is here.
        status = int(resp.headers.get("X-Antonime-Status", "502"))
        return (
            status,
            resp.data.content,
            resp.headers.get("Cache-Control", "no-store"),
            resp.headers.get("X-Antonime-Version", ""),
        )


def make_handler(invoke: Invoker, cap: MinuteCap) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "antonime-proxy"
        sys_version = ""

        def _send(
            self, status: int, body: bytes | dict, cache: str = "no-store", version: str = ""
        ) -> None:
            if isinstance(body, dict):
                body = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", cache)
            self.send_header("Content-Length", str(len(body)))
            if version:  # which function image answered (CI smoke test checks it)
                self.send_header("X-Antonime-Version", version)
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802 (http.server API)
            started = time.monotonic()
            url = urlsplit(self.path)
            if url.path == "/healthz":
                self._send(200, {"status": "ok"})
                return
            if url.path != "/antonime":
                self._send(404, ERR_NOT_FOUND)
                return
            word = (parse_qs(url.query).get("cuvant") or [None])[0]
            invoked, version = False, ""
            if not valid_word(word):
                status, body, cache = 400, ERR_INVALID, "no-store"
            elif not cap.acquire():
                status, body, cache = 429, ERR_BUSY, "no-store"
            else:
                invoked = True
                try:
                    status, body, cache, version = invoke(word.strip())
                except Exception as exc:  # OCI error, timeout, network: never a traceback
                    log("invoke_failed", error=type(exc).__name__, detail=str(exc)[:200])
                    status, body, cache = 502, ERR_UNAVAILABLE, "no-store"
            self._send(status, body, cache, version)
            log(
                "request",
                status=status,
                invoked=invoked,
                ms=round((time.monotonic() - started) * 1000),
                client_ip=self.headers.get("X-Real-IP"),
            )

        def log_message(self, *args) -> None:  # replaced by the JSON log above
            pass

    return Handler


def main() -> None:
    function_id = os.environ["ANTONIME_FUNCTION_ID"]
    endpoint = os.environ["ANTONIME_INVOKE_ENDPOINT"]
    port = int(os.environ.get("PORT", "8091"))
    per_minute = int(os.environ.get("ANTONIME_MAX_INVOCATIONS_PER_MINUTE", "6"))
    server = ThreadingHTTPServer(
        ("127.0.0.1", port),  # loopback only: nginx is the public side
        make_handler(OciInvoker(function_id, endpoint), MinuteCap(per_minute)),
    )
    log("started", port=port, max_invocations_per_minute=per_minute)
    server.serve_forever()


if __name__ == "__main__":
    main()
