# Probe for social notification feasibility

`probe.mjs` only creates a redacted evidence row. It does **not** verify that a website accepts ATMA's endpoint or that its counters are accurate. [Apple DTS](https://developer.apple.com/forums/thread/760767) confirms that Web Push does not work in `WKWebView`, so this probe is research tooling, not an implementation of background notifications in ATMA. An offline row can become `prototype` only for a separately proven transport; `verified` needs the device tests in the implementation plan.

Run with public or synthetic data, without saving an account session:

```powershell
node tools/notification-probe/probe.mjs --fixture vk
node tools/notification-probe/probe.mjs --fixture avito
```

The input schema has `provider`, `origins`, `endpointAccepted`, `encoding`, `messageOnly`, `eventID`, `unreadUnit`, `authoritativeCount`, `revisionOrder`, `remoteReadSync`, `logoutSignal`, `revocation`, and allowlisted `evidence` values. The output keeps exactly those fields plus a conservative `verdict`. It discards URL paths and query strings, arbitrary evidence text and extra fields, including message content or credentials. Do not feed real HAR files, cookies, tokens or messages into this tool. Any future native diagnostic probe must reduce events to these metadata fields on the iPhone before export.

The sample fixtures record **public source inspection only**. They do not establish a working VK/Avito subscription.
