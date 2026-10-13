#!/usr/bin/env python3
"""Link both Mac slices and exercise the packaged library against local HTTPS.

Usage: test_kdc_proxy.py <packaged build directory> <OpenSSL macosx directory>
No domain controller, real credentials, or installed Kerberos plugins are used.
"""

import argparse
import datetime
import http.server
import os
from pathlib import Path
import platform
import plistlib
import ssl
import subprocess
import tempfile
import threading


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs)


def der(tag, value):
    length = len(value)
    encoded_length = bytes([length]) if length < 128 else bytes([0x81, length])
    return bytes([tag]) + encoded_length + value


def kdc_error_reply():
    # RFC 4120 KRB-ERROR: the fixture deliberately has no account named probe.
    realm = der(0x1B, b"KDC-PROXY.TEST")
    service = der(0x30, der(0xA0, der(0x02, b"\x02")) +
                  der(0xA1, der(0x30, der(0x1B, b"krbtgt") + realm)))
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%SZ")
    error = der(0x7E, der(0x30,
        der(0xA0, der(0x02, b"\x05")) +
        der(0xA1, der(0x02, b"\x1e")) +
        der(0xA4, der(0x18, now.encode("ascii"))) +
        der(0xA5, der(0x02, b"\x00")) +
        der(0xA6, der(0x02, b"\x06")) +
        der(0xA9, realm) + der(0xAA, service)))
    # MS-KKDCP KDC-PROXY-MESSAGE contains the TCP length prefix as well.
    return der(0x30, der(0xA0, der(0x04, len(error).to_bytes(4, "big") + error)))


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.server.requests.append((self.path, body))
        reply = kdc_error_reply()
        self.send_response(200)
        self.send_header("Content-Type", "application/kerberos")
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    def log_message(self, *args):
        pass


def create_certificate(directory, name):
    config = directory / (name + ".cnf")
    cert = directory / (name + ".pem")
    key = directory / (name + ".key")
    config.write_text("""[req]
prompt = no
distinguished_name = dn
x509_extensions = extensions
[dn]
CN = localhost
[extensions]
subjectAltName = DNS:localhost
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyEncipherment,keyCertSign
""")
    run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
        "-config", str(config), "-keyout", str(key), "-out", str(cert))
    return cert, key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("openssl", type=Path)
    args = parser.parse_args()
    package = args.package.resolve()
    openssl = args.openssl.resolve()
    framework = package / "MITKerberos.xcframework"
    with (framework / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    library = next(entry for entry in info["AvailableLibraries"]
                   if entry["SupportedPlatform"] == "macos")
    archive = framework / library["LibraryIdentifier"] / library["LibraryPath"]
    sdk = run("xcrun", "--sdk", "macosx", "--show-sdk-path").stdout.strip()

    with tempfile.TemporaryDirectory(prefix="mitkerberos-kdc-proxy-") as temp:
        directory = Path(temp)
        binaries = {}
        for arch in ("arm64", "x86_64"):
            binary = directory / ("probe-" + arch)
            run("xcrun", "clang", "-arch", arch, "-isysroot", sdk,
                "-mmacosx-version-min=11.0", "-Werror",
                "-I", str(package / "macosx/include"),
                str(Path(__file__).with_name("kdc_proxy_probe.c")), str(archive),
                str(openssl / "lib/libssl.a"), str(openssl / "lib/libcrypto.a"),
                "-framework", "Kerberos", "-lresolv", "-o", str(binary))
            binaries[arch] = binary
            print(f"PASS: packaged {arch} library links with OpenSSL", flush=True)

        cert, key = create_certificate(directory, "trusted")
        other_cert, _ = create_certificate(directory, "untrusted")
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(cert, key)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ProxyHandler)
        server.requests = []
        server.socket = tls.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for label, hostname, anchors, success in (
                ("trusted HTTPS proxy", "localhost", cert, True),
                ("untrusted certificate rejected", "localhost", other_cert, False),
                ("wrong hostname rejected", "127.0.0.1", cert, False),
            ):
                config = directory / "krb5.conf"
                config.write_text(f"""[libdefaults]
    default_realm = KDC-PROXY.TEST
    dns_lookup_kdc = false
    dns_uri_lookup = false
    plugin_base_dir = {directory}/no-plugins
    request_timeout = 3s
[realms]
    KDC-PROXY.TEST = {{
        kdc = https://{hostname}:{server.server_port}/KdcProxy
        http_anchors = FILE:{anchors}
    }}
""")
                server.requests.clear()
                env = dict(os.environ, KRB5_CONFIG=str(config), KRB5_TRACE="/dev/stderr")
                result = subprocess.run([str(binaries[platform.machine()])], env=env,
                                        text=True, capture_output=True, timeout=15)
                if success:
                    valid = (result.returncode == 0 and len(server.requests) > 0 and
                             all(path == "/KdcProxy" and body.startswith(b"\x30")
                                 for path, body in server.requests))
                else:
                    valid = result.returncode == 1 and not server.requests
                if not valid:
                    raise RuntimeError(f"{label} failed:\n{result.stdout}\n{result.stderr}")
                print(f"PASS: {label}", flush=True)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(f"Command failed: {error.cmd}\n{error.stdout}\n{error.stderr}")
