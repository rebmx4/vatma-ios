"""A LAN-only CONNECT listener for PhoneDisk's existing HTTPS origin."""

import argparse
import ctypes
from ctypes import wintypes
from contextlib import contextmanager, nullcontext, suppress
from ipaddress import IPv4Address, IPv4Network
import logging
import socket
from socketserver import BaseRequestHandler, ThreadingTCPServer
import threading


AUTHORITY = b"files.rynpro.ru:443"
TAILNET = IPv4Network("100.64.0.0/10")
LOG = logging.getLogger("phone-disk.lan")


class Gateway(ThreadingTCPServer):
    daemon_threads = True

    def __init__(self, address, network, upstream):
        self.network = network
        self.upstream = upstream
        self.slots = threading.BoundedSemaphore(24)
        super().__init__(address, Tunnel)

    def verify_request(self, request, client_address):
        return IPv4Address(client_address[0]) in self.network


class Tunnel(BaseRequestHandler):
    @staticmethod
    def copy(source, destination):
        try:
            while data := source.recv(131072):
                destination.sendall(data)
        except OSError:
            pass
        finally:
            with suppress(OSError):
                destination.shutdown(socket.SHUT_WR)

    def handle(self):
        if not self.server.slots.acquire(blocking=False):
            return
        try:
            self.forward()
        except OSError:
            pass
        finally:
            self.server.slots.release()

    def forward(self):
        client = self.request
        client.settimeout(4)
        header = bytearray()
        while b"\r\n\r\n" not in header and len(header) < 8192:
            packet = client.recv(8192 - len(header))
            if not packet:
                return
            header.extend(packet)
        end = header.find(b"\r\n\r\n")
        line = bytes(header).split(b"\r\n", 1)[0]
        if end >= 0 and line in (b"GET /phonedisk-check HTTP/1.1", b"GET /phonedisk-check HTTP/1.0"):
            body = "Локальный шлюз «Моего диска» доступен.".encode("utf-8")
            client.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n"
                           + f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode("ascii") + body)
            if self.client_address[0] != self.server.server_address[0]:
                LOG.info("A LAN device reached the PhoneDisk test page")
            return
        if end < 0 or line not in (b"CONNECT " + AUTHORITY + b" HTTP/1.1", b"CONNECT " + AUTHORITY + b" HTTP/1.0"):
            client.sendall(b"HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
            return
        source = None if self.server.upstream[0] == "127.0.0.1" else (self.server.server_address[0], 0)
        with socket.create_connection(self.server.upstream, 4, source_address=source) as upstream:
            for connection in (client, upstream):
                connection.settimeout(90)
                connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            if header[end + 4:]:
                upstream.sendall(header[end + 4:])
            reader = threading.Thread(target=self.copy, args=(upstream, client), daemon=True)
            reader.start()
            self.copy(client, upstream)
            reader.join()


@contextmanager
def advertise(address, port, index):
    dns = ctypes.WinDLL("dnsapi")
    pointer = ctypes.c_void_p
    callback_type = ctypes.WINFUNCTYPE(None, wintypes.DWORD, pointer, pointer)

    class Registration(ctypes.Structure):
        _fields_ = [("version", wintypes.ULONG), ("interface", wintypes.ULONG),
                    ("instance", pointer), ("callback", callback_type),
                    ("context", pointer), ("credentials", wintypes.HANDLE),
                    ("unicast", wintypes.BOOL)]

    dns.DnsServiceConstructInstance.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR, pointer, pointer,
        wintypes.WORD, wintypes.WORD, wintypes.WORD, wintypes.DWORD, pointer, pointer]
    dns.DnsServiceConstructInstance.restype = pointer
    dns.DnsServiceFreeInstance.argtypes = [pointer]
    for function in (dns.DnsServiceRegister, dns.DnsServiceDeRegister):
        function.argtypes = [ctypes.POINTER(Registration), pointer]
        function.restype = wintypes.DWORD

    ipv4 = ctypes.create_string_buffer(IPv4Address(address).packed)
    host = "phonedisk-" + address.replace(".", "-")
    keys = (wintypes.LPCWSTR * 2)("address", "port")
    values = (wintypes.LPCWSTR * 2)(address, str(port))
    instance = dns.DnsServiceConstructInstance(host + "._phonedisk._tcp.local", host + ".local",
                                               ipv4, None, port, 0, 0, 2, keys, values)
    if not instance:
        raise OSError("Cannot create DNS-SD instance")
    event = threading.Event()
    result = []

    @callback_type
    def completed(status, context, returned):
        if returned and returned != instance:
            dns.DnsServiceFreeInstance(returned)
        result.append(status)
        event.set()

    request = Registration(1, index, instance, completed, None, None, False)
    status = dns.DnsServiceRegister(ctypes.byref(request), None)
    if status != 9506:  # DNS_REQUEST_PENDING
        dns.DnsServiceFreeInstance(instance)
        raise OSError(f"DNS-SD register status {status}")
    # Keep callback and instance alive until this process exits, including if a
    # Windows completion arrives after a timeout.
    if not event.wait(5) or not result or result[0] != 0:
        LOG.warning("DNS-SD registration could not be confirmed")
    else:
        LOG.info("PhoneDisk DNS-SD registration confirmed")
    try:
        yield
    finally:
        event.clear()
        if dns.DnsServiceDeRegister(ctypes.byref(request), None) == 9506 and event.wait(5):
            dns.DnsServiceFreeInstance(instance)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--address", required=True)
    parser.add_argument("--network", required=True)
    parser.add_argument("--interface", type=int)
    parser.add_argument("--tailnet", action="store_true")
    parser.add_argument("--port", type=int, default=18113)
    parser.add_argument("--loopback-origin-port", type=int)
    args = parser.parse_args()
    address = IPv4Address(args.address)
    network = IPv4Network(args.network)
    if args.tailnet:
        if address not in TAILNET or network != TAILNET or args.interface or args.loopback_origin_port:
            parser.error("A Tailscale IPv4 address and Tailscale-only network are required")
        origin = (args.address, 18117)
        announcement = nullcontext()
    else:
        if address not in network or not network.is_private or network.prefixlen < 16 or not args.interface or args.interface < 1:
            parser.error("A specific private LAN interface is required")
        origin = ("127.0.0.1", args.loopback_origin_port) if args.loopback_origin_port else (args.address, 443)
        announcement = advertise(args.address, args.port, args.interface)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    with Gateway((args.address, args.port), network, origin) as gateway, announcement:
        gateway.serve_forever()


if __name__ == "__main__":
    main()
