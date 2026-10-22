# ATMA native iOS browser

This branch prepares the native browser for the existing Apple app `ru.atma.app`
(App Store Connect ID `6774934498`). The product name is **ATMA**. Its icon is the
owner's `atma.png`, copied into `assets/` and pinned by SHA-256.

`release/config.json` pins the native upstream source revision. Codemagic fetches
that source and its locked dependencies; `release/prepare.py` applies display
text, logos, icons, the ATMA user agent and Apple identity. Internal API/module
names, license notices and third-party URLs retain their original meanings.

The first browser build contains the main application. It does not claim the
upstream vendor's app groups, VPN extensions or default-browser entitlement.
Those capabilities require separate registration and verification for ATMA.
The legacy web-app sources in `ATMA/` are not built by this workflow.

The workflow runs a simulator scenario that opens an HTTPS website and Settings
and checks for old branding. Only a passing scenario proceeds to signing,
archive validation and TestFlight upload. Automatic push triggers are omitted.

Local verification: `python -m unittest discover -s tests -v`, followed by
`python release/validate.py --source <prepared-native-source>`.
Compilation, simulator behavior and App Store delivery require the macOS CI.
