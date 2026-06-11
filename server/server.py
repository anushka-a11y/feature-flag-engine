import http.server
import json
import os
from pathlib import Path

FLAGS_FILE = Path(__file__).parent / "flags.json"
PORT = 8080


def load_flags():
    with open(FLAGS_FILE, "r") as f:
        return json.load(f)


def save_flags(data):
    with open(FLAGS_FILE, "w") as f:
        json.dump(data, f, indent=2)


class FlagHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/flags":
            data = load_flags()
            body = json.dumps(data).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")  # allow Flutter web
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/flags":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            data = json.loads(body)
            save_flags(data)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # suppress noisy logs so Textual dashboard stays clean


def run_server():
    server = http.server.HTTPServer(("0.0.0.0", PORT), FlagHandler)
    print(f"[SERVER] Running on http://localhost:{PORT}/flags")
    server.serve_forever()


if __name__ == "__main__":
    run_server()