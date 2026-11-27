import hashlib
import ipaddress
import os
import shutil
import socket
import ssl
import subprocess
import sys
import threading
from datetime import datetime, timedelta, timezone

import ifaddr
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID
from zeroconf import IPVersion, ServiceInfo, Zeroconf


PRIVATE = tuple(ipaddress.ip_network(value) for value in ("192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"))
TAILNET = ipaddress.ip_network("100.64.0.0/10")
BONJOUR = "_phonedisk._tcp.local."


def identity(state, server_id):
    pem = state / "computer.pem"
    dns = server_id + ".phonedisk.local"
    if not pem.exists():
        key = ec.generate_private_key(ec.SECP256R1())
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, dns)])
        now = datetime.now(timezone.utc)
        certificate = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject).public_key(key.public_key())
                       .serial_number(x509.random_serial_number()).not_valid_before(now - timedelta(days=1))
                       .not_valid_after(now + timedelta(days=3650))
                       .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
                       .add_extension(x509.SubjectAlternativeName([x509.DNSName(dns)]), critical=False)
                       .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
                       .sign(key, hashes.SHA256()))
        temp = pem.with_suffix(".tmp")
        temp.write_bytes(certificate.public_bytes(serialization.Encoding.PEM) + key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        os.replace(temp, pem)
    certificate = x509.load_pem_x509_certificate(pem.read_bytes())
    fingerprint = hashlib.sha256(certificate.public_bytes(serialization.Encoding.DER)).hexdigest()
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.minimum_version = ssl.TLSVersion.TLSv1_2
    tls.load_cert_chain(pem)
    tls.set_alpn_protocols(["http/1.1"])
    return tls, fingerprint, dns


def macos_tailnet_address(candidates):
    binary = shutil.which("tailscale") or "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    if not os.path.isfile(binary):
        return None
    try:
        response = subprocess.run([binary, "ip", "-4"], capture_output=True, text=True, timeout=1)
    except (OSError, subprocess.TimeoutExpired):
        return None
    address = response.stdout.strip()
    return address if response.returncode == 0 and address in candidates else None


class Network:
    def __init__(self, loopback):
        self.loopback = loopback
        self.adapters = {}
        self.tailnet = None
        self.stop = threading.Event()
        self.refresh()

    def refresh(self):
        if self.loopback:
            self.adapters = {"127.0.0.1": ipaddress.ip_network("127.0.0.0/8")}
            return
        adapters, tailnet = {}, None
        tailnet_candidates = set()
        for adapter in ifaddr.get_adapters():
            for item in adapter.ips:
                if not item.is_IPv4 or item.network_prefix <= 0:
                    continue
                address = ipaddress.ip_address(item.ip)
                name = (str(adapter.name) + " " + str(adapter.nice_name) + " " + str(item.nice_name)).casefold()
                if address in TAILNET:
                    tailnet_candidates.add(str(address))
                    if "tailscale" in name:
                        tailnet = str(address)
                if any(address in network for network in PRIVATE):
                    adapters[str(address)] = ipaddress.ip_network(f"{address}/{item.network_prefix}", strict=False)
        # macOS can expose the Tailscale address on a generically named utun interface.
        if sys.platform == "darwin" and tailnet is None and tailnet_candidates:
            tailnet = macos_tailnet_address(tailnet_candidates)
        self.adapters, self.tailnet = adapters, tailnet

    @property
    def local(self):
        return list(self.adapters)

    def pairing_host(self):
        addresses = self.local
        if len(addresses) <= 1:
            return next(iter(addresses), None)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route:
                # Resolve the default IPv4 route without sending a datagram.
                route.connect(("192.0.2.1", 9))
                preferred = route.getsockname()[0]
        except OSError:
            return addresses[0]
        return preferred if preferred in addresses else addresses[0]

    def classify(self, target, peer):
        address = ipaddress.ip_address(peer)
        subnet = self.adapters.get(target)
        if subnet is not None and address in subnet and (self.loopback or any(address in net for net in PRIVATE)):
            return "lan"
        if self.tailnet == target and address in TAILNET:
            return "tailnet"
        return None

    def advertise(self, server_id, name, port, dns):
        if self.loopback:
            return

        def announce():
            mdns, announced = None, ()
            try:
                while not self.stop.is_set():
                    self.refresh()
                    addresses = tuple(sorted(self.local))
                    if addresses != announced:
                        if mdns:
                            mdns.close()
                            mdns = None
                        announced = ()
                        if addresses:
                            try:
                                mdns = Zeroconf(interfaces=list(addresses), ip_version=IPVersion.V4Only)
                                for index, address in enumerate(addresses):
                                    mdns.register_service(ServiceInfo(
                                        BONJOUR, f"{server_id}-{index}.{BONJOUR}", addresses=[socket.inet_aton(address)],
                                        port=port, server=dns + ".", properties={"id": server_id, "address": address,
                                                "port": str(port), "name": name.encode("utf-8")}),
                                        allow_name_change=False)
                                announced = addresses
                            except OSError:
                                if mdns:
                                    mdns.close()
                                    mdns = None
                    self.stop.wait(4)
            finally:
                if mdns:
                    mdns.close()

        threading.Thread(target=announce, daemon=True, name="PhoneDisk Bonjour").start()
