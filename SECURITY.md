# Security Policy

Report vulnerabilities privately through GitHub Security Advisories. Do not
open a public issue containing credentials, private keys, hostnames, command
output, or app-server traffic.

The supported release line is the latest published version. Security-sensitive
invariants include SSH host-key verification, encrypted credential storage,
loopback-only tunneling, the namespaced remote app-server directory, and
read-only handling of externally owned running tasks.

The project never requests OpenAI credentials. Authentication is performed by
Codex on the remote host.

