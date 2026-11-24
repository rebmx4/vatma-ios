import argparse
import json
import ssl
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

parser=argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("certificate", nargs="?")
parser.add_argument("private_key", nargs="?")
options=parser.parse_args()
output=options.output
staged={}
backup=output.parent/"autocopy-results"
backup.mkdir()
backup_enabled=False
downloads=b"PhoneDisk download fixture\n"

class Fixture(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.0"

    def log_message(self,*args):
        pass

    def reply(self, status, data=b"",kind="application/json",**headers):
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
            html="""<meta name="viewport" content="width=device-width">
<a href="/api/resources/download?source=photos-c&amp;file=%2Fci-download.txt">Скачать пробный файл</a>
<button type="button" data-tab="transfers">Передача</button>
<button type="button" id="backup" onclick="saveSettings('video', {enabled:true})" disabled>Тестовая автовыгрузка</button>
<script>
async function saveSettings(type, patch) {
  const response = await fetch('/fixture/settings', {
    method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify(patch)
  });
  if (!response.ok) throw new Error('Could not save preference');
}
const check = setInterval(() => {
  if (!window.phoneDiskBackupInstalled) return;
  document.getElementById('backup').disabled = false;
  clearInterval(check);
}, 50);
</script>"""
            self.reply(200,html.encode(),"text/html; charset=utf-8",
                       Set_Cookie="fixture=allowed; Path=/; Max-Age=3600; HttpOnly")
            return
        if not self.logged_in(): return
        if params.get("source")==["settings"] and params.get("file")==["/drives.json"]:
            info={"schema":1,"drives":[{
                "id":"C","available":True,"registered":True,
                "root":{"source":"photos-c"},"backup":{"source":"backup-c"},
            }]}
            self.reply(200,json.dumps(info).encode())
        elif params.get("source")==["settings"] and params.get("file")==["/autocopies.json"]:
            self.reply(200,json.dumps({
                "photo":{"enabled":False,"disk":"C"},
                "video":{"enabled":backup_enabled,"disk":"C"},
            }).encode())
        elif params.get("source")==["photos-c"] and params.get("file")==["/ci-download.txt"]:
            self.reply(200,downloads,"application/octet-stream",Content_Disposition='attachment; filename="ci-download.txt"')
        elif (params.get("source",[""])[0], params.get("path",[""])[0]) in staged:
            self.reply(200,b'{}')
        elif params.get("source")==["backup-c"] and params.get("path",[""])[0].startswith("/Видео/"):
            path=backup/Path(params["path"][0]).name
            self.reply(200 if path.is_file() else 404,b'{}')
        else:
            self.reply(404)

    def do_PUT(self):
        global backup_enabled
        if not self.logged_in(): return
        if self.path != "/fixture/settings":
            self.reply(404)
            return
        body=json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        backup_enabled=body.get("enabled") is True
        self.reply(200,b'{}')

    def do_POST(self):
        if not self.logged_in(): return
        params=parse_qs(urlsplit(self.path).query)
        path=params.get("path",[""])[0]
        source=params.get("source",[""])[0]
        if source=="backup-c" and path=="/Видео" and params.get("isDir")==["true"]:
            self.reply(200,b'{}')
            return
        if source not in ("photos-c","backup-c") or not path.startswith("/.phone-disk-incoming"):
            self.reply(409)
            return
        if params.get("isDir")==["true"]:
            self.reply(200,b'{}')
            return
        data=self.rfile.read(int(self.headers["Content-Length"]))
        time.sleep(2)
        staged[source,path]=data
        self.reply(200,b'{}')

    def do_PATCH(self):
        if not self.logged_in(): return
        payload=json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        item=payload["items"][0]
        source=item["fromSource"]
        path=item["toPath"]
        if source!=item["toSource"]:
            self.reply(409)
            return
        if source=="photos-c" and path=="/fixture-data.txt":
            target=output
        elif source=="backup-c" and path.startswith("/Видео/"):
            target=backup/Path(path).name
        else:
            self.reply(409)
            return
        data=staged.pop((source,item["fromPath"]),None)
        if data is None or target.exists():
            self.reply(409)
            return
        target.write_bytes(data)
        self.reply(200,json.dumps({"succeeded":[item]}).encode())

server=ThreadingHTTPServer(("127.0.0.1",18878),Fixture)
if options.certificate and options.private_key:
    tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain(options.certificate,options.private_key)
    server.socket=tls.wrap_socket(server.socket,server_side=True)
server.serve_forever()
