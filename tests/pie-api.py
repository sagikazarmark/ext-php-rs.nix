# A stand-in for the part of GitHub's REST API that PIE downloads pre-packaged binaries with
# (src/Downloading/GithubPackageReleaseAssets.php), serving the archives in /assets over TLS
# with /tls/cert.pem and /tls/key.pem, for tests/pie.sh:
#
# - GET /repos/<owner>/<repository>/releases/tags/<tag>: the release of <tag>, whose assets are
#   the archives named php_<repository>-<tag>_…
# - GET /assets/<name>: an archive.
import http.server
import json
import os
import ssl
import urllib.parse

ASSETS = "/assets"
BASE = "https://api.github.com"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parts = urllib.parse.urlparse(self.path).path.strip("/").split("/")
        if len(parts) == 6 and parts[0] == "repos" and parts[3:5] == ["releases", "tags"]:
            repository, tag = parts[2], parts[5]
            prefix = f"php_{repository}-{tag}_"
            assets = [
                {"name": name, "url": f"{BASE}/assets/{name}"}
                for name in sorted(os.listdir(ASSETS))
                if name.startswith(prefix) and name.endswith((".tgz", ".zip"))
            ]
            if assets:
                return self.respond(200, json.dumps({"tag_name": tag, "assets": assets}).encode())
        elif len(parts) == 2 and parts[0] == "assets":
            path = os.path.join(ASSETS, parts[1])
            if os.path.isfile(path):
                with open(path, "rb") as asset:
                    return self.respond(200, asset.read(), "application/octet-stream")
        self.respond(404, b'{"message": "Not Found"}')

    def respond(self, status, body, content_type="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain("/tls/cert.pem", "/tls/key.pem")
server = http.server.ThreadingHTTPServer(("", 443), Handler)
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
