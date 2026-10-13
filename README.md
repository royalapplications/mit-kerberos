# MIT Kerberos

Contains scripts to build "Apple-Universal" static libraries of MIT Kerberos. Also packages everything up into an XCFramework for easy consumption with Swift packages or Xcode.
Release names use `<MIT Kerberos version>_openssl-<OpenSSL version>`, with an
optional `_r<N>` suffix for packaging revisions. For example,
`1.22.2_openssl-3.6.5_r1` is the first revision with the same upstream versions;
further packaging changes use `_r2`, `_r3`, etc. Existing names without a revision
remain supported.

## KDC Proxy over HTTPS

The macOS static library includes the OpenSSL-backed `k5tls` module. The build
requires `--with-tls-impl=openssl`, and `scripts/static_k5tls.patch` registers the
module as a built-in when MIT Kerberos is compiled with `STATIC_PLUGINS`.
Shared builds retain upstream's dynamic plugin loading.

`libMITKerberos.a` and the XCFramework include `libkrb5_k5tls.a`. Applications must
also link the matching OpenSSL libraries (`libssl` and `libcrypto`, or the combined
`libOpenSSL.a`), the macOS Kerberos framework, and `libresolv`. No separate `k5tls`
plugin file or application registration call is needed. Applications linking the
individual Kerberos archives must include `libkrb5_k5tls.a` themselves.

This supplies the HTTPS transport; the application still needs to configure the
Kerberos realm's KDC Proxy and certificate trust. For example, in the configuration
read by MIT Kerberos (`KRB5_CONFIG` can select an explicit file):

```ini
[libdefaults]
    default_realm = CORP.EXAMPLE.COM
    dns_lookup_kdc = false
    dns_uri_lookup = false

[realms]
    CORP.EXAMPLE.COM = {
        kdc = https://rdg.example.com/KdcProxy
        http_anchors = FILE:/absolute/path/trusted-ca.pem
    }
```

The proxy must be deployed on the server and able to reach the domain controllers.
The OpenSSL backend validates the proxy certificate and hostname; supply the
appropriate CA certificate or CA bundle rather than assuming macOS Keychain trust
is available. Both initial-ticket and service-ticket requests need access to the
proxy through the realm configuration.

## Verification

After building, run the same check used by CI:

```sh
python3 scripts/tests/test_kdc_proxy.py \
  build/mitkerberos-1.22.2_openssl-3.6.5_r1 \
  build/openssl-3.6.5/macosx
```

The check links both macOS slices from the final XCFramework, then runs the native
slice against a temporary HTTPS KDC Proxy fixture on loopback. It verifies a
Kerberos request and error response with no external plugins, rejection of an
untrusted certificate, and rejection of a hostname mismatch. It uses synthetic
credentials and does not require a domain controller. A real RD Gateway login
still needs an integration test in the customer's environment.
