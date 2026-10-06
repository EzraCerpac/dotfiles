#!/usr/bin/env python3
"""Read-only check of six reviewed instruction routes and the shared Codex block."""
import argparse
import json
import shlex
import subprocess
import sys
from pathlib import Path

HOMES = {"mac": "/Users/ezracerpac", "cerpacnas": "/root", "driehuisnas": "/Users/server"}
ROUTES = {
    "mac-codex": (".config/mise/dotfiles/.codex/AGENTS.md", ".codex/AGENTS.md"),
    "mac-opencode": (".config/mise/dotfiles/.config/opencode/AGENTS.md", ".config/opencode/AGENTS.md"),
    "mac-claude": (".claude/CLAUDE.md", ".claude/CLAUDE.md"),
    "cerpacnas-codex": (".config/mise/dotfiles/.codex/AGENTS.cerpacnas.md", ".codex/AGENTS.md"),
    "cerpacnas-opencode": (".config/opencode/AGENTS.md", ".config/opencode/AGENTS.md"),
    "driehuisnas-codex": (".config/mise/dotfiles/.codex/AGENTS.driehuisnas.md", ".codex/AGENTS.md"),
}

PROBE = '''import hashlib,json,os,sys
from pathlib import Path
j=json.loads(sys.argv[1]);rows=[]
if os.path.expanduser("~")!=j["home"]:
 print(json.dumps({"error":"host_home_mismatch","expected_home":j["home"]}));sys.exit(2)
for spec in j["entries"]:
 r={"id":spec["id"],"host":j["id"],"paths":[]}
 for key in ("source","target"):
  expected=spec[key];p=Path(expected["path"])
  a={"role":key,"path":str(p),"exists":p.is_file(),"is_symlink":p.is_symlink(),"realpath":str(p.resolve())}
  a["link_mode_matches"]=a["is_symlink"]==expected["is_symlink"]
  a["link_target_matches"]=a["realpath"]==expected["realpath"]
  if a["exists"] and a["link_target_matches"]:
   b=p.read_bytes();a["sha256"]=hashlib.sha256(b).hexdigest();a["hash_matches"]=a["sha256"]==expected["sha256"]
   if spec.get("shared_block_required"):
    sb=j["shared_block"];start=sb["start_marker"].encode();end=sb["end_marker"].encode()
    ok=b.count(start)==1 and b.count(end)==1
    if ok:
     first=b.index(start);last=b.index(end)+len(end)
     ok=first<last and b[last:last+1]==b"\\n"
    if ok:
     a["shared_block_sha256"]=hashlib.sha256(b[first:last+1]).hexdigest()
     a["shared_block_matches"]=a["shared_block_sha256"]==sb["sha256"]
    else:a["shared_block_matches"]=False
  elif a["exists"]:a["content_read_skipped"]="unexpected_link_target"
  a["matches"]=a["exists"] and a["link_mode_matches"] and a["link_target_matches"] and a.get("hash_matches",False) and a.get("shared_block_matches",True)
  r["paths"].append(a)
 r["matches"]=all(a["matches"] for a in r["paths"]);rows.append(r)
ok=all(r["matches"] for r in rows)
print(json.dumps({"host":j["id"],"entries":rows,"all_match":ok},indent=2))
sys.exit(0 if ok else 1)
'''


def validate(manifest):
    if set(manifest["hosts"]) != set(HOMES):
        raise ValueError("Unexpected host set")
    seen = set()
    for host, h in manifest["hosts"].items():
        if h["id"] != host or h["home"] != HOMES[host]:
            raise ValueError("Unexpected host identity")
        if host != "mac" and h.get("ssh_alias") != host:
            raise ValueError("Unexpected SSH alias")
        for e in h["entries"]:
            route = ROUTES.get(e["id"])
            if not route or e["id"] in seen or not e["id"].startswith(host + "-"):
                raise ValueError("Unexpected instruction route")
            seen.add(e["id"])
            for key, relative in zip(("source", "target"), route):
                f = e[key]
                if f["path"] != HOMES[host] + "/" + relative:
                    raise ValueError("Unexpected instruction path")
                allowed_realpaths = {HOMES[host] + "/" + v for v in route}
                if f["realpath"] not in allowed_realpaths:
                    raise ValueError("Unexpected resolved instruction path")
                if len(f["sha256"]) != 64 or any(c not in "0123456789abcdef" for c in f["sha256"]):
                    raise ValueError("Malformed instruction hash")
            if e.get("shared_block_required", False) != e["id"].endswith("-codex"):
                raise ValueError("Missing or unexpected shared-block check")
    if seen != set(ROUTES):
        raise ValueError("Missing instruction route")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", default=str(Path(__file__).with_name("manifest.json")))
    p.add_argument("--host", choices=tuple(HOMES), default="mac")
    p.add_argument("--ssh", action="store_true", help="Read the exact verified NAS alias; copy no files")
    a = p.parse_args()
    m = json.loads(Path(a.manifest).read_text())
    validate(m)
    h = dict(m["hosts"][a.host], shared_block=m["shared_block"])
    payload = json.dumps(h, separators=(",", ":"))
    if a.ssh:
        if a.host == "mac":
            p.error("--ssh is only for an explicitly selected NAS")
        command = "python3 -c " + shlex.quote(PROBE) + " " + shlex.quote(payload)
        args = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=8", a.host, command]
    else:
        if a.host != "mac":
            p.error("NAS checks require --ssh; local execution cannot inspect a different native host")
        args = [sys.executable, "-c", PROBE, payload]
    return subprocess.run(args, timeout=30).returncode


if __name__ == "__main__":
    sys.exit(main())
