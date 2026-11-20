"""Standalone read-only HTTP + SSE leaderboard server for Shapes & Beams."""

from __future__ import annotations

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import queue
import signal
import socket
import socketserver
import sys
import threading
from typing import Any
from urllib.parse import unquote, urlsplit

try:
    from .watcher import SaveWatcher
except ImportError:
    from watcher import SaveWatcher

_CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
}


class RecordsHTTPServer(ThreadingHTTPServer):
    """Multi-threaded HTTP server carrying shared watcher and static directory state."""

    allow_reuse_address = True
    daemon_threads = True

    def __init__(
        self,
        server_address: tuple[str, int],
        watcher: SaveWatcher,
        static_dir: Path,
        *,
        quiet: bool = False,
        keepalive_interval: float = 15.0,
    ) -> None:
        self.watcher = watcher
        self.static_dir = static_dir.resolve()
        self.quiet = quiet
        self.keepalive_interval = max(0.5, float(keepalive_interval))
        self.shutdown_event = threading.Event()
        super().__init__(server_address, RecordsRequestHandler)

    def server_bind(self) -> None:
        """Bind listening socket without blocking on reverse DNS (`socket.getfqdn`)."""
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host) or "localhost"
        self.server_port = int(port)

    def shutdown(self) -> None:
        """Signal active SSE streams to close before stopping the serve loop."""
        self.shutdown_event.set()
        super().shutdown()


class RecordsRequestHandler(BaseHTTPRequestHandler):
    """Strictly read-only HTTP + SSE request handler."""

    protocol_version = "HTTP/1.1"

    @property
    def _srv(self) -> RecordsHTTPServer:
        return self.server  # type: ignore[return-value]

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        if self._srv.quiet:
            return
        super().log_message(format, *args)

    def do_GET(self) -> None:
        self._handle_read(send_body=True)

    def do_HEAD(self) -> None:
        self._handle_read(send_body=False)

    def do_POST(self) -> None:
        self._send_method_not_allowed()

    def do_PUT(self) -> None:
        self._send_method_not_allowed()

    def do_PATCH(self) -> None:
        self._send_method_not_allowed()

    def do_DELETE(self) -> None:
        self._send_method_not_allowed()

    def do_OPTIONS(self) -> None:
        self._send_method_not_allowed()

    def _send_method_not_allowed(self) -> None:
        self.close_connection = True
        body = json.dumps(
            {"error": "Method not allowed; this server is strictly read-only."},
            separators=(",", ":"),
        ).encode("utf-8")
        self.send_response(405)
        self.send_header("Allow", "GET, HEAD")
        self.send_header("Connection", "close")
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _send_bytes(
        self,
        status: int,
        body: bytes,
        content_type: str,
        *,
        cache_control: str,
        send_body: bool,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache_control)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def _send_not_found(self, send_body: bool) -> None:
        body = b'{"error":"Not found"}'
        self._send_bytes(
            404,
            body,
            "application/json; charset=utf-8",
            cache_control="no-store",
            send_body=send_body,
        )

    def _handle_read(self, *, send_body: bool) -> None:
        path = unquote(urlsplit(self.path).path)

        if path in ("/", "/index.html"):
            self._serve_file(self._srv.static_dir / "index.html", send_body=send_body)
            return

        if path == "/favicon.ico":
            self.send_response(204)
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            return

        if path.startswith("/static/"):
            rel_path = path[len("/static/") :]
            self._serve_static(rel_path, send_body=send_body)
            return

        if path == "/api/records":
            payload = self._srv.watcher.get_snapshot_json().encode("utf-8")
            self._send_bytes(
                200,
                payload,
                "application/json; charset=utf-8",
                cache_control="no-store",
                send_body=send_body,
            )
            return

        if path == "/health":
            snap = self._srv.watcher.get_snapshot()
            health = {
                "status": "ok",
                "read_only": True,
                "source_file": snap.get("source_file", ""),
                "source_exists": bool(snap.get("source_exists", False)),
                "total_players": int(snap.get("total_players", 0)),
            }
            payload = json.dumps(health, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self._send_bytes(
                200,
                payload,
                "application/json; charset=utf-8",
                cache_control="no-store",
                send_body=send_body,
            )
            return

        if path == "/events":
            self._serve_sse(send_body=send_body)
            return

        self._send_not_found(send_body=send_body)

    def _serve_static(self, rel_path: str, *, send_body: bool) -> None:
        if not rel_path or "\x00" in rel_path or rel_path.startswith("/") or "\\" in rel_path:
            self._send_not_found(send_body=send_body)
            return
        static_root = self._srv.static_dir
        try:
            target = (static_root / rel_path).resolve()
        except (OSError, ValueError):
            self._send_not_found(send_body=send_body)
            return
        if not target.is_relative_to(static_root) or target == static_root or not target.is_file():
            self._send_not_found(send_body=send_body)
            return
        self._serve_file(target, send_body=send_body)

    def _serve_file(self, target: Path, *, send_body: bool) -> None:
        try:
            data = target.read_bytes()
        except OSError:
            self._send_not_found(send_body=send_body)
            return
        content_type = _CONTENT_TYPES.get(target.suffix.lower(), "application/octet-stream")
        self._send_bytes(
            200,
            data,
            content_type,
            cache_control="no-cache",
            send_body=send_body,
        )

    def _serve_sse(self, *, send_body: bool) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if not send_body:
            return

        self.close_connection = True
        watcher = self._srv.watcher
        sub_q = watcher.subscribe()
        try:
            initial_json = watcher.get_snapshot_json()
            initial_frame = f"retry: 2000\nevent: records\ndata: {initial_json}\n\n".encode("utf-8")
            self.wfile.write(initial_frame)
            self.wfile.flush()

            while not self._srv.shutdown_event.is_set():
                try:
                    payload = sub_q.get(timeout=self._srv.keepalive_interval)
                except queue.Empty:
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
                    continue

                if payload is None:
                    break

                frame = f"event: records\ndata: {payload}\n\n".encode("utf-8")
                self.wfile.write(frame)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError, ValueError):
            pass
        finally:
            watcher.unsubscribe(sub_q)


def create_server(
    host: str,
    port: int,
    watcher: SaveWatcher,
    static_dir: Path | None = None,
    *,
    quiet: bool = False,
    keepalive_interval: float = 15.0,
) -> RecordsHTTPServer:
    """Create a configured `RecordsHTTPServer` instance."""
    resolved_static = static_dir or (Path(__file__).resolve().parent / "static")
    return RecordsHTTPServer(
        (host, port),
        watcher=watcher,
        static_dir=resolved_static,
        quiet=quiet,
        keepalive_interval=keepalive_interval,
    )


def detect_lan_ip() -> str | None:
    """Best-effort LAN IP detection via instant kernel route probe (no DNS, no packets sent)."""
    for target in (("10.255.255.255", 1), ("192.168.0.1", 80), ("8.8.8.8", 80)):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.connect(target)
            ip = sock.getsockname()[0]
            if ip and not ip.startswith("127.") and ip != "0.0.0.0":
                return ip
        except OSError:
            pass
        finally:
            sock.close()
    return None


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments with `RECORDS_*` environment fallbacks."""
    parser = argparse.ArgumentParser(
        description="Read-only live HTTP + SSE records screen server for Shapes & Beams."
    )
    parser.add_argument(
        "--host",
        default=os.environ.get("RECORDS_HOST", "0.0.0.0"),
        help="Bind address (default: 0.0.0.0 / RECORDS_HOST).",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("RECORDS_PORT", "8080")),
        help="Listen port (default: 8080 / RECORDS_PORT).",
    )
    parser.add_argument(
        "--save-file",
        default=os.environ.get("RECORDS_SAVE_FILE") or None,
        help="Explicit path to save_data.tres (default: auto-detect Godot user:// or juego/data/).",
    )
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=float(os.environ.get("RECORDS_POLL_INTERVAL", "0.4")),
        help="File poll interval in seconds (default: 0.4).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint."""
    args = parse_args(argv)
    explicit_save = Path(args.save_file) if args.save_file else None
    repo_root = Path(__file__).resolve().parent.parent

    watcher = SaveWatcher(
        explicit_save_file=explicit_save,
        repo_root=repo_root,
        poll_interval=args.poll_interval,
    )
    watcher.start()

    server = create_server(args.host, args.port, watcher=watcher)
    bound_port = server.server_address[1]
    snap = watcher.get_snapshot()

    print("Shapes & Beams — Live Records Server (read-only)", flush=True)
    if args.host in ("0.0.0.0", "::", ""):
        print(f"  Local:    http://localhost:{bound_port}", flush=True)
        lan_ip = detect_lan_ip()
        if lan_ip:
            print(f"  Network:  http://{lan_ip}:{bound_port}", flush=True)
    else:
        print(f"  URL:      http://{args.host}:{bound_port}", flush=True)

    status_suffix = "" if snap.get("source_exists") else " (waiting for file...)"
    print(f"  Watching: {snap.get('source_file', '')}{status_suffix}", flush=True)
    print("  Press Ctrl+C to stop.", flush=True)

    def _request_shutdown(_signum: int, _frame: Any) -> None:
        server.shutdown_event.set()
        watcher.stop()
        threading.Thread(target=server.shutdown, daemon=True).start()

    previous_sigterm = signal.getsignal(signal.SIGTERM)
    signal.signal(signal.SIGTERM, _request_shutdown)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server...", flush=True)
    finally:
        server.shutdown_event.set()
        watcher.stop()
        server.server_close()
        signal.signal(signal.SIGTERM, previous_sigterm)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
