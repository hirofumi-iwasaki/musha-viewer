# Leica C2PA root certificate

`leica-c2pa-root.pem` is the Leica C2PA Root CA retrieved on 2026-11-04 from <https://certs.leica.systems/cgi-bin/Leica_C2PA_Root_CA.crt> (the source is DER; this copy is PEM). Its SHA-256 certificate fingerprint is `C60F849915ACED77B2AC1D2B4A6D1B4BBEED6E2EBF29E1C759DBA555AFCAA31B`.

Verify the fingerprint from this directory with:

```sh
openssl x509 -in leica-c2pa-root.pem -noout -fingerprint -sha256
```

This anchor permits validation of Leica OCSP responder authorization. It is not a complete C2PA trust list and is not a claim that content is trusted; manifest trust verification remains disabled and the application reports trust as unknown.
