#!/usr/bin/env python3
import configparser
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONFIG = Path('/etc/linux-devops-homework/app.conf')
STATE_DIR = Path('/var/lib/linux-devops-homework')

cfg = configparser.ConfigParser()
if not CONFIG.exists():
    raise RuntimeError(f'configuration file not found: {CONFIG}')
cfg.read(CONFIG)
host = cfg.get('server', 'host')
port = cfg.getint('server', 'port')

# Deliberately requires write access for the service account.
with (STATE_DIR / 'startup.log').open('a', encoding='utf-8') as f:
    f.write(f'starting on {host}:{port}\n')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            body = json.dumps({'status': 'ok'}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

print(f'homework-app: listening on {host}:{port}', flush=True)
ThreadingHTTPServer((host, port), Handler).serve_forever()
