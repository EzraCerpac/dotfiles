# Cloud NAS access

Use the cloud environment's configured VPN and inherited `HTTP_PROXY` /
`HTTPS_PROXY` settings for NAS web services. For HTTPS, keep CA trust and TLS
verification enabled; omit `--noproxy` and do not use `-k`. Plain HTTP entry
points below rely on the configured private VPN/proxy route. It can work while Ezra's
Mac is offline. A saved environment is not an always-running server: the cloud
task runtime must be available.

Tailscale can run in the platform sidecar. Missing executor-local Tailscale
binaries, VPN interfaces, or local DNS resolution do not establish that the
proxy route is unavailable. Current OpenAI documentation supports private IPv4,
MagicDNS, and split DNS through the configured VPN; use the fully qualified
service hostname. See [private networking](https://learn.chatgpt.com/docs/environments/cloud-environments#private-networking-vpn)
and [HTTP/HTTPS troubleshooting](https://learn.chatgpt.com/docs/environments/cloud-environments#vpn-connects-but-an-http-or-https-service-is-unreachable).

## Bounded read-only diagnosis

For an authorized web entry point, make one GET with inherited proxy settings:

```sh
curl --silent --show-error --connect-timeout 5 --max-time 20 \
  --output /dev/null --write-out 'HTTP %{http_code}\n' \
  http://cerpacnas.manatee-python.ts.net:8989/
```

Do not follow redirects automatically: inspect the destination first and avoid
login, logout, session creation, API/control endpoints, downloads, and writes.
If command networking is restricted, use the supported network permission for
the bounded request before interpreting a sandbox failure as a VPN failure.
This guide does not grant network permission or authorize bypassing a denial.

Keep proxy/auth values, tokens, cookies, full headers, and private response data
out of output. If service identity or an error needs inspection, capture the
response privately and report only status, safe headers, a minimal sanitized
excerpt, and redirect destinations without query strings. Preserve TLS checks.
An Envoy header alone does not distinguish a gateway response from a proxied
service. HTTP 200 with matching HTML confirms a web entry point, not authenticated
API access. A service-identifying 401/403 establishes a responding access guard,
not authorized application access; stop rather than trying an alternate route
to defeat it.

In the cloud executor tested below, `/etc/codex/network-policy.json` version 1
reported `vpn_configured: true`, unrestricted HTTP destinations, and no TCP
grants. This is a non-secret startup observation, not proof of current VPN health.
No environment status tool was exposed to this executor, so current sidecar
health and configuration/version mapping could not be verified. Generic SSH
support and NAS SSH authentication remain unconfirmed;
do not infer them from HTTP success or invent a port-specific grant UI.

## Service observations — 2026-10-08

These are dated checks from the selected dotfiles cloud environment, through its
inherited proxy with network permission enabled. They are not ongoing health
monitoring. CerpacNAS and DriehuisNAS are distinct hosts. No login or authenticated
application operation was tested, and redirects below were not followed.

| Host | Web entry point | Observed result |
| --- | --- | --- |
| CerpacNAS | [Sonarr](http://cerpacnas.manatee-python.ts.net:8989/) | 200, Sonarr HTML; supplied `/series/the-sopranos` entry also returned Sonarr HTML |
| CerpacNAS | [Radarr](http://cerpacnas.manatee-python.ts.net:7878/) | 200, matching HTML |
| CerpacNAS | [Lidarr](http://cerpacnas.manatee-python.ts.net:8686/) | 200, matching HTML |
| CerpacNAS | [Prowlarr](http://cerpacnas.manatee-python.ts.net:9696/) | 200, matching HTML |
| CerpacNAS | [Syncthing UI](http://cerpacnas.manatee-python.ts.net:8384/) | 200, matching HTML |
| CerpacNAS | [Deluge UI](http://cerpacnas.manatee-python.ts.net:8112/) | 200, matching HTML |
| CerpacNAS | [SABnzbd](http://cerpacnas.manatee-python.ts.net:8085/sabnzbd/) | Latest check: 200; body exceeded the 128 KiB check limit, so HTML identity was not confirmed |
| CerpacNAS | [Tautulli](http://cerpacnas.manatee-python.ts.net:8181/) | 303 to `/auth/logout` on the same private host/port |
| CerpacNAS | [Plex](http://cerpacnas.manatee-python.ts.net:32400/web) | 302 to `/web/index.html` on the same private host/port |
| CerpacNAS | [Music Assistant](http://cerpacnas.manatee-python.ts.net:8095/) | 200, matching HTML |
| CerpacNAS | [Home Assistant](http://cerpacnas.manatee-python.ts.net:8123/) | 200, matching HTML |
| CerpacNAS | [Heaper](http://cerpacnas.manatee-python.ts.net:4599/) | 200, matching HTML |
| CerpacNAS | [TSDProxy dashboard](http://cerpacnas.manatee-python.ts.net:8080/) | 200, matching HTML |
| CerpacNAS | [Portainer](http://cerpacnas.manatee-python.ts.net:9000/) | 200, matching HTML |
| DriehuisNAS | [HomeNetwork](https://driehuisnas.manatee-python.ts.net/) | 200, title “Driehuis · Home network” |
| DriehuisNAS | [Inventoried Capd endpoint](https://driehuisnas.manatee-python.ts.net:8443/) | 404 at `/`; HTTPS endpoint responds, Capd identity/function unverified |
| HouseAtlas | [Dedicated gateway](https://houseatlas.manatee-python.ts.net/) | 200, title “HouseAtlas”; TLS verification succeeded |

SABnzbd previously returned hostname rejection, then `403 External internet
access denied`. The NAS owner reported approved hostname and `100.64.0.0/10`
local-range changes; the latest cloud check above returned 200. This records the
result of separately authorized work, not an instruction to change access policy.

HouseAtlas's separately authorized read of
[`/api/atlas/auth/mode`](https://houseatlas.manatee-python.ts.net/api/atlas/auth/mode)
returned 200 with `{"mode":"trusted-proxy","schemaVersion":1}`. The NAS owner
reported native session/WhoIs, Home access, and autostart verification. Authenticated
cloud API access and acceptance of the actual `tag:codex` identity remain untested.
HouseAtlas now has a verified dedicated cloud HTTPS entry point; earlier
loopback/Mac-forward observations no longer describe its only available route.

Other DriehuisNAS Plex/concierge services, storage access, and generic SSH are
unverified from this cloud environment. Do not guess endpoints or scan ports.

## Discovery scope

The repository-root `AGENTS.md` routes NAS tasks to this reference when Codex
loads instructions for work inside this repository. See [instruction discovery](https://developers.openai.com/codex/agent-configuration/agents-md).
The current saved cloud environment starts at `/workspace`, outside the
`/workspace/dotfiles` repository, so not every task is guaranteed to auto-load
that file. Handoffs should explicitly link `/workspace/dotfiles/docs/cloud-nas-access.md`.
New tasks must receive a checkout containing this document; existing saved
snapshots do not necessarily acquire new repository commits. No environment
republish or setup/configuration change is part of this documentation update.
