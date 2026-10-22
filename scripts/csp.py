#!/usr/bin/env python3
"""Keep the page's Content-Security-Policy in sync with its inline code.

The CSP allows inline <script>/<style> only by SHA-256 hash, so ANY edit to
them changes the hash. Run after editing frontend/index.html:

    scripts/csp.py --write frontend/index.html   # update the meta tag
    scripts/csp.py --check frontend/index.html   # CI: fail if out of date
"""

import base64
import hashlib
import re
import sys
from html.parser import HTMLParser

META_RE = re.compile(r'(<meta http-equiv="Content-Security-Policy" content=")([^"]*)(">)')


class InlineCode(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.blocks: dict[str, list[str]] = {"script": [], "style": []}
        self._current: str | None = None

    def handle_starttag(self, tag, attrs):
        if tag in self.blocks and not dict(attrs).get("src"):
            self._current = tag
            self.blocks[tag].append("")

    def handle_endtag(self, tag):
        if tag == self._current:
            self._current = None

    def handle_data(self, data):
        if self._current:
            self.blocks[self._current][-1] += data


def sha(text: str) -> str:
    return "'sha256-" + base64.b64encode(hashlib.sha256(text.encode()).digest()).decode() + "'"


def policy(html: str) -> str:
    parser = InlineCode()
    parser.feed(html)
    scripts = " ".join(sha(b) for b in parser.blocks["script"])
    styles = " ".join(sha(b) for b in parser.blocks["style"])
    return (
        f"default-src 'none'; script-src {scripts}; style-src {styles}; "
        "connect-src 'self'; img-src data:; base-uri 'none'; form-action 'self'"
    )


def main() -> int:
    mode, path = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as fh:
        html = fh.read()
    match = META_RE.search(html)
    if not match:
        print(f"{path}: no CSP meta tag", file=sys.stderr)
        return 1
    expected = policy(html)
    if mode == "--check":
        if match.group(2) != expected:
            print(
                f"{path}: CSP is out of date, run scripts/csp.py --write {path}",
                file=sys.stderr,
            )
            return 1
        print(f"{path}: CSP matches the inline code")
        return 0
    if mode == "--write":
        new = META_RE.sub(lambda m: m.group(1) + expected + m.group(3), html, count=1)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new)
        print(f"{path}: CSP updated\n  {expected}")
        return 0
    print("usage: csp.py --check|--write <file>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
