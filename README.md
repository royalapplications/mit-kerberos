# MIT Kerberos

Contains scripts to build "Apple-Universal" static libraries of MIT Kerberos. Also packages everything up into an XCFramework for easy consumption with Swift packages or Xcode.
Release names use `<MIT Kerberos version>_openssl-<OpenSSL version>`, with an
optional `_r<N>` suffix for packaging revisions. For example,
`1.22.2_openssl-3.6.5_r1` is the first revision with the same upstream versions;
further packaging changes use `_r2`, `_r3`, etc. Existing names without a revision
remain supported.
