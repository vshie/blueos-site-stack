#!/usr/bin/env python3
"""Status HTTP server for blueos-site-stack.

Serves the static status page plus BlueOS `/register_service` so the extension
appears in the sidebar (see
https://blueos.cloud/docs/latest/development/extensions/#web-interface-http-server).
"""

from __future__ import annotations

import json
import mimetypes
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WWW_DIR = Path(os.environ.get("WWW_DIR", "/www"))
STATUS_PORT = int(os.environ.get("STATUS_PORT", "80"))

REGISTER_SERVICE = {
    "name": "Site Stack",
    "description": (
        "Mosquitto MQTT broker + InfluxDB 1.8 + Telegraf — auto-ingests "
        "ESPHome and BlueOS extension telemetry."
    ),
    "icon": "mdi-database-cog",
    "company": "Community",
    "version": "0.2.1",
    "webpage": "https://github.com/vshie/blueos-site-stack",
    "api": "https://github.com/vshie/blueos-site-stack/blob/main/README.md",
    "new_page": False,
    "works_in_relative_paths": True,
}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WWW_DIR), **kwargs)

    def log_message(self, fmt, *args) -> None:
        print(f"[status] {self.address_string()} {fmt % args}")

    def _path_only(self) -> str:
        return (self.path or "/").split("?", 1)[0]

    def do_GET(self) -> None:  # noqa: N802
        if self._path_only().rstrip("/") == "/register_service":
            body = json.dumps(REGISTER_SERVICE).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        return super().do_GET()


def main() -> None:
    mimetypes.add_type("application/json", ".json")
    server = ThreadingHTTPServer(("0.0.0.0", STATUS_PORT), Handler)
    print(f"[status] listening on :{STATUS_PORT} (www={WWW_DIR})")
    server.serve_forever()


if __name__ == "__main__":
    main()
