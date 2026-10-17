import json
import os
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer


class RequestHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        if self.path != "/":
            self.send_error(404, "Not Found")
            return

        response = {
            "message": os.environ.get(
                "BACKEND_MESSAGE",
                "Hello from IDTECH Academy!"
            ),
            "hostname": socket.gethostname()
        }

        body = json.dumps(response).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    host = os.environ.get("BACKEND_HOST", "127.0.0.1")
    port = int(os.environ.get("BACKEND_PORT", "8080"))

    server = HTTPServer((host, port), RequestHandler)
    server.serve_forever()
