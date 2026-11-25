import argparse
import json
import ssl
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

parser=argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("certificate", type=Path)
parser.add_argument("key", type=Path)
arguments=parser.parse_args()
output=arguments.output
staged={}
downloads=b"PhoneDisk download fixture\n"

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

    def do_GET(self):
        url=urlsplit(self.path)
        params=parse_qs(url.query)
        if url.path=="/":
            html = (
                '<meta name="viewport" content="width=device-width">'
                '<a href="/api/resources/download?source=photos-c&amp;file=%2Fci-download.txt">Скачать пробный файл</a>'
                '<p><a href="/api/resources/download?source=photos-c&amp;file=%2Fslow+file+%2B.bin">Скачать файл для остановки</a></p>'
                '<button data-tab="transfers">Передача</button>'
            )
            self.reply(200,html.encode(),"text/html; charset=utf-8",
                       Set_Cookie="fixture=allowed; Path=/; Max-Age=3600; HttpOnly")
            return
        if not self.logged_in(): return
        if params.get("source")==["settings"] and params.get("file")==["/drives.json"]:
            info={"schema":1,"drives":[{"id":"C","available":True,"registered":True,"root":{"source":"photos-c"}}]}
            self.reply(200,json.dumps(info).encode())
        elif params.get("source")==["photos-c"] and params.get("file")==["/ci-download.txt"]:
            self.reply(200,downloads,"application/octet-stream",Content_Disposition='attachment; filename="ci-download.txt"')
        elif params.get("source")==["photos-c"] and params.get("file")==["/slow file +.bin"]:
            part = bytes(64 * 1024)
            parts = 36
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(part) * parts))
            self.end_headers()
            try:
                for _ in range(parts):
                    self.wfile.write(part)
                    self.wfile.flush()
                    time.sleep(0.5)
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                pass
        elif params.get("path",[None])[0] in staged:
            self.reply(200,b'{}')
        else:
            self.reply(404)

    def do_POST(self):
        if not self.logged_in(): return
        params=parse_qs(urlsplit(self.path).query)
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
