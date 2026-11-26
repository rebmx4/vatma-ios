import argparse
import hashlib
import json
import re
import ssl
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

parser=argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("certificate", type=Path)
parser.add_argument("key", type=Path)
parser.add_argument("--v2-downloads", action="store_true")
arguments=parser.parse_args()
output=arguments.output
staged={}
downloads=b"PhoneDisk download fixture\n"
range_file = bytes(150 * 64 * 1024)
range_file_sha = hashlib.sha256(range_file).hexdigest()
range_file_etag = f'"{range_file_sha}"'
test_token = "fixture-download-device"
slow_requests = 0
slow_requests_lock = threading.Lock()

class Fixture(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"

    def log_message(self,*args):
        pass

    def reply(self, status, data=b"",kind="application/json",**headers):
        print(f"{self.command} {self.path} -> {status}", flush=True)
        self.send_response(status)
        self.send_header("Content-Type",kind)
        self.send_header("Content-Length",str(len(data)))
        for name,value in headers.items():
            self.send_header(name.replace("_","-"),value)
        self.end_headers()
        self.wfile.write(data)

    def logged_in(self):
        if "fixture=allowed" not in self.headers.get("Cookie",""):
            self.reply(401)
            return False
        return True

    def range_file_allowed(self, params):
        if self.headers.get("Authorization") != "Bearer " + test_token:
            self.reply(401)
            return False
        if params.get("source") != ["photos-c"] or params.get("path") != ["/slow file +.bin"]:
            self.reply(404)
            return False
        return True

    def do_HEAD(self):
        url = urlsplit(self.path)
        if not arguments.v2_downloads or url.path != "/api/v2/file":
            self.reply(404)
        elif self.range_file_allowed(parse_qs(url.query)):
            self.reply(200, kind="application/octet-stream", ETag=range_file_etag,
                       X_File_SHA256=range_file_sha, X_File_Size=str(len(range_file)))

    def stream_test_file(self, start=0, stop=len(range_file), partial=False):
        global slow_requests
        with slow_requests_lock:
            slow_requests += 1
            attempt = slow_requests
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(stop - start))
        if partial:
            self.send_header("ETag", range_file_etag)
            self.send_header("Content-Range", f"bytes {start}-{stop-1}/{len(range_file)}")
        self.end_headers()
        print(f"Fixture download attempt {attempt}: bytes {start}-{stop-1}", flush=True)
        chunk = 64 * 1024
        try:
            for offset in range(start, stop, chunk):
                self.wfile.write(range_file[offset:min(offset+chunk, stop)])
                self.wfile.flush()
                if attempt == 1:
                    # Keep the first transfer active through the tab switch on slower CI runners.
                    time.sleep(1.5)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass

    def do_GET(self):
        url=urlsplit(self.path)
        params=parse_qs(url.query)
        if url.path=="/":
            html = (
                '<meta name="viewport" content="width=device-width">'
                '<section id="fixture-files">'
                '<a href="/api/resources/download?source=photos-c&amp;file=%2Fci-download.txt">Скачать пробный файл</a>'
                '<p><a href="/api/resources/download?source=photos-c&amp;file=%2Fslow+file+%2B.bin">Скачать файл для остановки</a></p>'
                '</section><p id="fixture-backup" hidden>Настройки автокопий</p>'
                '<nav class="bottom-tabs" aria-label="Разделы">'
                '<button type="button" data-tab="files">Файлы</button>'
                '<button type="button" data-tab="backup">Автокопии</button>'
                '<button type="button" data-tab="transfers">Передача</button>'
                '</nav>'
                """
                <script>
                document.querySelector('.bottom-tabs').addEventListener('click', event => {
                    const tab = event.target.dataset.tab;
                    if (tab !== 'files' && tab !== 'backup') return;
                    document.getElementById('fixture-files').hidden = tab !== 'files';
                    document.getElementById('fixture-backup').hidden = tab !== 'backup';
                });
                </script>
                """
            )
            if arguments.v2_downloads:
                html += "<p>Fixture v2</p>"
            self.reply(200,html.encode(),"text/html; charset=utf-8",
                       Set_Cookie="fixture=allowed; Path=/; Max-Age=3600; HttpOnly")
            return
        if url.path == "/api/v2/capabilities":
            if arguments.v2_downloads:
                self.reply(200, json.dumps({"version":2,"serverId":"f"*32,"lan":False}).encode())
            else:
                self.reply(404)
            return
        if arguments.v2_downloads and url.path == "/api/v2/file":
            if not self.range_file_allowed(params):
                return
            bounds = re.fullmatch(r"bytes=([0-9]+)-([0-9]+)", self.headers.get("Range", ""))
            if bounds is None or self.headers.get("If-Range") != range_file_etag:
                self.reply(416)
                return
            start, end = map(int, bounds.groups())
            if not 0 <= start <= end < len(range_file):
                self.reply(416)
                return
            self.stream_test_file(start, end + 1, partial=True)
            return
        if not self.logged_in(): return
        if params.get("source")==["settings"] and params.get("file")==["/drives.json"]:
            info={"schema":1,"drives":[{"id":"C","available":True,"registered":True,"root":{"source":"photos-c"}}]}
            self.reply(200,json.dumps(info).encode())
        elif params.get("source")==["photos-c"] and params.get("file")==["/ci-download.txt"]:
            self.reply(200,downloads,"application/octet-stream",Content_Disposition='attachment; filename="ci-download.txt"')
        elif params.get("source")==["photos-c"] and params.get("file")==["/slow file +.bin"]:
            self.stream_test_file()
        elif params.get("path",[None])[0] in staged:
            self.reply(200,b'{}')
        else:
            self.reply(404)

    def do_POST(self):
        if not self.logged_in(): return
        url=urlsplit(self.path)
        if arguments.v2_downloads and url.path == "/api/v2/device":
            self.rfile.read(int(self.headers["Content-Length"]))
            self.reply(200,json.dumps({"token":test_token,"expires":time.time()+3600}).encode())
            return
        params=parse_qs(url.query)
        path=params.get("path",[""])[0]
        if params.get("source")!=["photos-c"] or not path.startswith("/.phone-disk-incoming"):
            self.reply(409)
            return
        if params.get("isDir")==["true"]:
            self.reply(200,b'{}')
            return
        data=self.rfile.read(int(self.headers["Content-Length"]))
        time.sleep(2)
        staged[path]=data
        self.reply(200,b'{}')

    def do_PATCH(self):
        if not self.logged_in(): return
        payload=json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        item=payload["items"][0]
        if item["fromSource"]!="photos-c" or item["toSource"]!="photos-c" or item["toPath"]!="/fixture-data.txt":
            self.reply(409)
            return
        data=staged.pop(item["fromPath"])
        output.write_bytes(data)
        self.reply(200,json.dumps({"succeeded":[item]}).encode())

server=ThreadingHTTPServer(("127.0.0.1",18878),Fixture)
tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
tls.load_cert_chain(arguments.certificate,arguments.key)
server.socket=tls.wrap_socket(server.socket,server_side=True)
server.serve_forever()
