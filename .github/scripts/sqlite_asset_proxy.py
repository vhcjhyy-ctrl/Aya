#!/usr/bin/env python3
"""Serve checksum-verified sqlite3 release assets to Dart's native asset hook.

The GitHub Actions runner has intermittent failures when downloading GitHub
release assets via browser_download_url. This proxy obtains the same public
release asset through the GitHub REST API, validates GitHub's SHA-256 digest,
and serves only the verified bytes to the local build hook.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPOSITORY = "simolus3/sqlite3.dart"
TAG_PATTERN = re.compile(r"^sqlite3-3\\.5\\.2$")
FILENAME_PATTERN = re.compile(
    r"^libsqlite3\\.(?:arm64|x64)\\.(?:android|linux)\\.so$"
)
API_ROOT = f"https://api.github.com/repos/{REPOSITORY}"
RELEASE_CACHE: dict[str, dict] = {}
ASSET_CACHE: dict[tuple[str, str], bytes] = {}
CACHE_LOCK = threading.Lock()


def github_get(url: str, accept: str) -> bytes:
    headers = {
        "Accept": accept,
        "User-Agent": "qalam-muslim-verified-sqlite-proxy",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    request = urllib.request.Request(url, headers=headers, method="GET")
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def load_release(tag: str) -> dict:
    with CACHE_LOCK:
        cached = RELEASE_CACHE.get(tag)
    if cached is not None:
        return cached

    raw = github_get(f"{API_ROOT}/releases/tags/{tag}", "application/vnd.github+json")
    release = json.loads(raw.decode("utf-8"))
    if release.get("tag_name") != tag:
        raise RuntimeError(f"Unexpected release tag returned for {tag}")
    with CACHE_LOCK:
        RELEASE_CACHE[tag] = release
    return release


def load_asset(tag: str, filename: str) -> bytes:
    key = (tag, filename)
    with CACHE_LOCK:
        cached = ASSET_CACHE.get(key)
    if cached is not None:
        return cached

    release = load_release(tag)
    asset = next((item for item in release.get("assets", []) if item.get("name") == filename), None)
    if asset is None:
        raise FileNotFoundError(f"{filename} is not attached to release {tag}")

    expected_digest = asset.get("digest", "")
    if not expected_digest.startswith("sha256:"):
        raise RuntimeError(f"GitHub did not publish a SHA-256 digest for {filename}")

    # GitHub's release-asset API streams the binary when requested with this
    # Accept header; urllib follows the temporary redirect to the asset host.
    data = github_get(asset["url"], "application/octet-stream")
    actual_digest = hashlib.sha256(data).hexdigest()
    expected_sha = expected_digest.split(":", 1)[1].lower()

    if len(data) != int(asset["size"]):
        raise RuntimeError(
            f"Size mismatch for {filename}: got {len(data)}, expected {asset['size']}"
        )
    if actual_digest != expected_sha:
        raise RuntimeError(
            f"SHA-256 mismatch for {filename}: got {actual_digest}, expected {expected_sha}"
        )

    with CACHE_LOCK:
        ASSET_CACHE[key] = data
    print(
        f"Verified {filename}: {len(data)} bytes, sha256={actual_digest}",
        flush=True,
    )
    return data


class Handler(BaseHTTPRequestHandler):
    server_version = "QalamSQLiteAssetProxy/1.0"

    def do_HEAD(self) -> None:
        self._serve(send_body=False)

    def do_GET(self) -> None:
        self._serve(send_body=True)

    def _serve(self, send_body: bool) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/health":
            body = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if send_body:
                self.wfile.write(body)
            return

        parts = [urllib.parse.unquote(part) for part in parsed.path.split("/") if part]
        if len(parts) != 2:
            self.send_error(404, "Expected /<release-tag>/<asset-filename>")
            return

        tag, filename = parts
        if not TAG_PATTERN.fullmatch(tag) or not FILENAME_PATTERN.fullmatch(filename):
            self.send_error(404, "Asset is not in the allowlist")
            return

        try:
            body = load_asset(tag, filename)
        except Exception as error:
            print(f"SQLite asset proxy error for {filename}: {error}", file=sys.stderr, flush=True)
            self.send_error(502, "Could not retrieve and verify the official SQLite asset")
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def log_message(self, format_string: str, *args) -> None:
        print(f"sqlite-proxy: {format_string % args}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Verified SQLite asset proxy listening on {args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
