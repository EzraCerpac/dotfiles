#!/usr/bin/env python3
"""Resolve uploaded GitHub release assets to native mise tools and publish app bundles."""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

REPO = re.compile(r"https://github\.com/([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9_.-]+?)(?:\.git)?/?\Z")
ARCHIVES = (".zip", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz", ".tbz2", ".tar")
MAX_DOWNLOAD = 512 * 1024 * 1024


def repository(url):
    match = REPO.fullmatch(url)
    if not match or match[2] in {".", ".."}:
        raise ValueError("use an HTTPS GitHub repository URL: https://github.com/OWNER/REPO")
    return f"{match[1]}/{match[2]}".casefold()


def fetch_release(repo):
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/latest",
                                     headers={"Accept": "application/vnd.github+json", "User-Agent": "dots"})
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise ValueError(f"{repo} has no accessible stable GitHub release; source builds are not supported") from exc
        raise ValueError(f"GitHub release lookup failed ({exc.code}); check access or GITHUB_TOKEN") from exc
    if not isinstance(result, dict) or result.get("draft") or result.get("prerelease"):
        raise ValueError(f"{repo} has no accessible stable GitHub release")
    if not result.get("assets"):
        raise ValueError(f"{repo} publishes no downloadable release assets; source builds are not supported")
    return result


def asset_score(name, system, machine):
    name = name.lower()
    words = set(re.split(r"[^a-z0-9]+", name))
    families = {"darwin": {"macos", "darwin", "osx", "mac"},
                "linux": {"linux", "ubuntu", "debian", "alpine", "fedora", "centos", "rhel", "archlinux", "opensuse", "suse", "nixos", "gentoo", "rockylinux", "almalinux"},
                "windows": {"windows", "win", "win32", "win64"},
                "freebsd": {"freebsd"}, "netbsd": {"netbsd"}, "openbsd": {"openbsd"}, "android": {"android"}}
    current = families.get(system, {system})
    if any(words & tokens for key, tokens in families.items() if key != system):
        return None
    arm = machine in {"arm64", "aarch64"}
    x64 = machine in {"x86_64", "amd64", "x64"}
    arm32_tokens = {"arm", "armv6", "armv6l", "armv7", "armv7l", "armhf"}
    x86_tokens = {"x86", "i386", "i486", "i586", "i686", "386"}
    foreign_arch_tokens = {"riscv64", "ppc64", "ppc64le", "powerpc64", "powerpc64le", "s390x", "loongarch64", "mips", "mipsel", "mips64", "mips64el", "sparc", "sparc64"}
    if (arm or x64) and words & foreign_arch_tokens:
        return None
    # x86_64 and x86-64 split into x86/64, so exclude those spellings first.
    has_x86_64 = bool(re.search(r"(?:^|[^a-z0-9])x86[_-]64(?:$|[^a-z0-9])", name))
    if (arm or x64) and (words & arm32_tokens or words & (x86_tokens - {"x86"}) or ("x86" in words and not has_x86_64)):
        return None
    arm_tokens = {"arm64", "aarch64"}
    x64_tokens = {"x64", "amd64"}
    has_x64 = bool(words & x64_tokens) or has_x86_64
    universal = "universal" in words and (arm or x64)
    if ((not x64 and has_x64) or (not arm and words & arm_tokens)) and not universal:
        return None
    if words & {"source", "sources", "checksum", "checksums", "sha256", "sha512", "debug", "symbols", "sbom", "intoto", "provenance"} or name.endswith((".sig", ".asc")):
        return None
    if name.endswith((".dmg", ".pkg")) and system != "darwin":
        return None
    if name.endswith(".exe") and system != "windows":
        return None
    if name.endswith((".msi", ".deb", ".rpm", ".apk", ".pkg")):
        return None
    score = 20 if words & current else 0
    score += 10 if (arm and words & arm_tokens) or (x64 and has_x64) else 0
    return score


def choose_asset(assets, override=None, system=None, machine=None):
    system = system or platform.system().lower()
    machine = machine or platform.machine().lower()
    if override:
        candidates = [asset for asset in assets if fnmatch.fnmatchcase(asset["name"], override)]
    else:
        scores = [(asset_score(asset["name"], system, machine), asset) for asset in assets]
        scores = [(score, asset) for score, asset in scores if score is not None]
        candidates = [asset for score, asset in scores if score == max((s for s, _ in scores), default=-1)]
        # ZIP and DMG of the same app are alternative packaging, not ambiguity.
        zip_stems = {a["name"][:-4].lower() for a in candidates if a["name"].lower().endswith(".zip")}
        candidates = [a for a in candidates if not (a["name"].lower().endswith(".dmg") and a["name"][:-4].lower() in zip_stems)]
    if len(candidates) != 1:
        names = ", ".join(a["name"] for a in (candidates or assets))
        raise ValueError(f"cannot choose one release asset; use --asset NAME or GLOB. Available: {names}")
    asset = candidates[0]
    if not re.fullmatch(r"[A-Za-z0-9_.+ -]+", asset["name"]):
        raise ValueError("release asset name contains unsupported characters")
    if asset["name"].lower().endswith((".tar.zst", ".tzst")):
        raise ValueError("Zstandard tar archives cannot be inspected safely by this installer; select a ZIP or gzip/bzip2/xz tar asset with --asset")
    if asset["name"].lower().endswith((".dmg", ".pkg", ".msi", ".deb", ".rpm", ".apk")):
        raise ValueError("this installer format is not supported; select a ZIP/tar app bundle or prebuilt CLI asset with --asset")
    return asset


def safe_name(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or ".." in path.parts or "\\" in name or "\x00" in name:
        raise ValueError(f"unsafe archive path: {name!r}")
    return str(path)


def safe_link(name, target, hard=False):
    if not target or target.startswith("/") or "\\" in target or "\x00" in target:
        raise ValueError(f"unsafe archive link: {name!r}")
    combined = target if hard else str(PurePosixPath(name).parent / target)
    depth = 0
    for component in PurePosixPath(combined).parts:
        depth += -1 if component == ".." else 0 if component == "." else 1
        if depth < 0:
            raise ValueError(f"archive link escapes its root: {name!r}")


def archive_app(archive):
    """Inspect before native mise extraction. No archive entry is executed."""
    entries, links = {}, set()
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as contents:
            for info in contents.infolist():
                name = safe_name(info.filename)
                mode = info.external_attr >> 16
                kind = stat.S_IFMT(mode)
                if kind not in {0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK}:
                    raise ValueError(f"unsupported archive entry: {name}")
                if kind == stat.S_IFLNK:
                    if info.file_size > 4096:
                        raise ValueError("archive symlink is too large")
                    safe_link(name, contents.read(info).decode("utf-8"))
                    links.add(name)
                add_entry(entries, name, info.file_size)
    else:
        with tarfile.open(archive) as contents:
            for info in contents:
                name = safe_name(info.name)
                if not (info.isfile() or info.isdir() or info.issym() or info.islnk()):
                    raise ValueError(f"unsupported archive entry: {name}")
                if info.issym() or info.islnk():
                    safe_link(name, info.linkname, info.islnk())
                    links.add(name)
                add_entry(entries, name, info.size)
    if sum(entries.values()) > 4 * 1024**3:
        raise ValueError("archive exceeds inspection limits")
    for name in entries:
        if any(str(parent) in links for parent in PurePosixPath(name).parents):
            raise ValueError(f"archive entry traverses a link: {name}")
    apps = {name[:-len("/Contents/Info.plist")] for name in entries if name.endswith(".app/Contents/Info.plist") and not name.startswith("__MACOSX/")}
    # Nested helper apps are part of their containing application.
    apps = {app for app in apps if not any(app.startswith(other + "/") for other in apps if other != app)}
    if len(apps) > 1:
        raise ValueError("release contains multiple apps; automatic app installation is ambiguous")
    return next(iter(apps), None)


def add_entry(entries, name, size):
    if name in entries:
        raise ValueError(f"duplicate archive path: {name}")
    entries[name] = size
    if len(entries) > 100000:
        raise ValueError("archive exceeds inspection limits")


def download_asset(asset, repo, destination):
    url = asset.get("browser_download_url", "")
    parsed = urllib.parse.urlsplit(url)
    path = parsed.path.split("/", 4)
    if (parsed.scheme != "https" or parsed.netloc.lower() != "github.com"
            or len(path) != 5 or "/".join(path[1:3]).casefold() != repo.casefold()
            or path[3] != "releases" or not path[4].startswith("download/")):
        raise ValueError("asset is not an official GitHub release download")
    if asset.get("size", 0) > MAX_DOWNLOAD:
        raise ValueError("release archive is too large to inspect (limit 512 MiB)")
    request = urllib.request.Request(url, headers={"User-Agent": "dots"})
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        asset_id = asset.get("id")
        if type(asset_id) is not int or asset_id <= 0:
            raise ValueError("release asset lacks a valid GitHub asset ID")
        request = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/assets/{asset_id}",
                                         headers={"User-Agent": "dots", "Accept": "application/octet-stream"})
        # GitHub redirects to a signed storage URL. urllib must not forward the token.
        request.add_unredirected_header("Authorization", f"Bearer {token}")
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(request, timeout=60) as response, destination.open("wb") as stream:
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_DOWNLOAD:
                raise ValueError("release archive is too large to inspect (limit 512 MiB)")
            digest.update(chunk)
            stream.write(chunk)
    expected = asset.get("digest")
    if expected and expected.startswith("sha256:") and expected != "sha256:" + digest.hexdigest():
        raise ValueError("GitHub release asset checksum mismatch")


def resolve(url, override=None):
    repo = repository(url)
    release = fetch_release(repo)
    # GitHub redirects old repository names after a rename or ownership transfer.
    if "url" in release:
        canonical_url = release["url"]
        canonical = re.fullmatch(r"https://api\.github\.com/repos/([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9_.-]+)/releases/[1-9][0-9]*", canonical_url) if isinstance(canonical_url, str) else None
        if not canonical:
            raise ValueError("release metadata lacks an official GitHub release API URL")
        repo = repository(f"https://github.com/{canonical[1]}/{canonical[2]}")
    asset = choose_asset(release["assets"], override)
    app = None
    if asset["name"].lower().endswith(ARCHIVES):
        with tempfile.TemporaryDirectory(prefix="dots-github-") as temporary:
            path = Path(temporary) / asset["name"]
            download_asset(asset, repo, path)
            app = archive_app(path)
    pattern = override or asset["name"]
    tag = release["tag_name"]
    numeric_version = re.search(r"(?<![\d.])\d+(?:\.\d+)*(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$", tag)
    if not override:
        versions = {tag, tag.removeprefix("v")}
        if numeric_version:
            versions.add(numeric_version[0])
        for version in sorted(versions, key=len, reverse=True):
            version_pattern = r"(?<![\d.])" + re.escape(version) + r"(?!\d|\.\d)"
            if version and re.search(version_pattern, pattern):
                pattern = re.sub(version_pattern, "*", pattern)
                break
    system = {"Darwin": "macos", "Windows": "windows"}.get(platform.system(), platform.system().lower())
    machine = {"aarch64": "arm64", "x86_64": "x64", "amd64": "x64"}.get(platform.machine().lower(), platform.machine().lower())
    options = {"asset_pattern": override} if override else {f"platform_{system}_{machine}_asset_pattern": pattern}
    if app:
        if platform.system() != "Darwin":
            raise ValueError("this release contains a macOS app; install it on a Mac")
        if override:
            options.pop("asset_pattern")
            options[f"platform_{system}_{machine}_asset_pattern"] = override
        hook = 'uv run --no-project python "${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/setup-scripts/lib/dots-github.py" install-app ' + shlex.quote(repo)
        options.update(strip_components=0, bin_path=".dots-no-bin", os=["macos"], postinstall={"run": hook, "when": "always"})
    if numeric_version and tag[:numeric_version.start()] not in {"", "v"}:
        options["version_prefix"] = tag[:numeric_version.start()]
    def toml_value(value):
        if isinstance(value, dict):
            return "{" + ",".join(f"{key}={toml_value(item)}" for key, item in value.items()) + "}"
        return json.dumps(value)

    encoded = ",".join(f"{key}={toml_value(value)}" for key, value in options.items())
    return f"github:{repo}" + (f"[{encoded}]" if encoded else "")


def validate_bundle(source, verify_signature=True):
    source = source.resolve()
    info_file = source / "Contents/Info.plist"
    try:
        with info_file.open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as exc:
        raise ValueError(f"invalid app bundle: {source}") from exc
    if not isinstance(info, dict):
        raise ValueError("app Info.plist must be a dictionary")
    executable = info.get("CFBundleExecutable", "")
    identifier = info.get("CFBundleIdentifier", "")
    if not isinstance(executable, str) or not executable or Path(executable).name != executable or not isinstance(identifier, str) or not identifier:
        raise ValueError("app bundle lacks a valid executable or identifier")
    binary = source / "Contents/MacOS" / executable
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise ValueError("app bundle executable is missing or not executable")
    for directory, dirs, files in os.walk(source, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            if not (path.is_symlink() or path.is_file() or path.is_dir()):
                raise ValueError(f"unsupported app entry: {path}")
            if path.is_symlink() and not path.resolve().is_relative_to(source):
                raise ValueError(f"app symlink escapes bundle: {path}")
    if verify_signature and (source / "Contents/_CodeSignature").exists():
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(source)], check=True)
    return identifier


def publish_app(source, repo, applications=Path("/Applications"), state=None):
    """Replace only a bundle previously installed by dots from this repository."""
    source = Path(source)
    repo = repo.casefold()
    identifier = validate_bundle(source, verify_signature=False)
    if not source.name.endswith(".app") or source.name in {".app", "..app"}:
        raise ValueError("invalid app bundle name")
    state = state or Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "dots/github-apps"
    state.mkdir(parents=True, exist_ok=True)
    marker = state / (hashlib.sha256(source.name.encode()).hexdigest() + ".json")
    target = applications / source.name
    previous = marker.read_bytes() if marker.exists() else None
    old_target, old_marker = target, marker
    if not target.exists() or previous is None:
        # A release may rename its bundle while retaining its application identity.
        matches = []
        for candidate in state.glob("*.json"):
            if candidate == marker:
                continue
            try:
                owner = json.loads(candidate.read_bytes())
            except (ValueError, TypeError):
                continue
            if isinstance(owner, dict) and isinstance(owner.get("repo"), str):
                owner["repo"] = owner["repo"].casefold()
            if not isinstance(owner, dict) or owner.get("repo") != repo or owner.get("bundle_id") != identifier:
                continue
            if not isinstance(owner.get("path"), str):
                raise ValueError("invalid managed app ownership; refusing to migrate it")
            path = Path(owner["path"])
            expected_marker = hashlib.sha256(path.name.encode()).hexdigest() + ".json"
            if (path.parent != applications or not path.name.endswith(".app") or path.is_symlink()
                    or candidate.name != expected_marker
                    or owner != {"repo": repo, "path": str(path), "bundle_id": identifier}):
                raise ValueError("invalid managed app ownership; refusing to migrate it")
            if path.exists():
                if target.exists() and not path.samefile(target):
                    continue
                if validate_bundle(path) != identifier:
                    raise ValueError("installed app identity differs; refusing to replace it")
                matches.append((path, candidate))
        if len(matches) > 1:
            raise ValueError("multiple managed apps have this identity; migration is ambiguous")
        if matches:
            old_target, old_marker = matches[0]
    if target.exists() or target.is_symlink():
        try:
            owner = json.loads(old_marker.read_bytes() if old_marker.exists() else b"{}")
        except (ValueError, TypeError):
            owner = {}
        if isinstance(owner, dict) and isinstance(owner.get("repo"), str):
            owner["repo"] = owner["repo"].casefold()
        if target.is_symlink() or owner != {"repo": repo, "path": str(old_target), "bundle_id": identifier}:
            raise ValueError(f"{target} already exists and is not managed by dots for {repo}; keep or move it before installing")
        if validate_bundle(target) != identifier:
            raise ValueError("installed app identity differs; refusing to replace it")
    with tempfile.TemporaryDirectory(prefix=".dots-github-", dir=applications) as temporary:
        stage = Path(temporary) / source.name
        subprocess.run(["/usr/bin/ditto", "--rsrc", "--extattr", str(source), str(stage)], check=True)
        # Generic archive extraction can materialize AppleDouble metadata as ._*
        # resources. Merge them with native files before checking the sealed app.
        subprocess.run(["/usr/sbin/dot_clean", str(stage)], check=True)
        validate_bundle(stage)
        # Preserve Gatekeeper checks even when mise's downloader did not add quarantine.
        subprocess.run(["/usr/bin/xattr", "-w", "com.apple.quarantine", f"0081;{int(time.time()):08x};dots;", str(stage)], check=True)
        backup = Path(temporary) / "previous.app"
        had_target = old_target.exists()
        if had_target:
            old_target.rename(backup)
        marker_temp = None
        marker_written = False
        try:
            stage.rename(target)
            # State can live on a different filesystem.
            with tempfile.NamedTemporaryFile(dir=state, delete=False) as stream:
                marker_temp = Path(stream.name)
                stream.write(json.dumps({"repo": repo, "path": str(target), "bundle_id": identifier}).encode())
            os.replace(marker_temp, marker)
            marker_written = True
            if old_marker != marker:
                old_marker.unlink()
        except BaseException:
            if marker_temp:
                marker_temp.unlink(missing_ok=True)
            if target.exists():
                shutil.rmtree(target)
            if had_target:
                backup.rename(old_target)
            if marker_written:
                if previous is None:
                    marker.unlink(missing_ok=True)
                else:
                    marker.write_bytes(previous)
            raise
    print(f"dots: installed {target} from {repo}", file=sys.stderr)


def install_app(repo):
    if platform.system() != "Darwin":
        raise ValueError("app installation requires macOS")
    root = Path(os.environ["MISE_TOOL_INSTALL_PATH"])
    apps = [path for path in root.rglob("*.app") if (path / "Contents/Info.plist").is_file()]
    apps = [path for path in apps if not any(path.is_relative_to(other) for other in apps if path != other)]
    if len(apps) != 1:
        raise ValueError("installed release must contain exactly one app bundle")
    if not apps[0].resolve().is_relative_to(root.resolve()):
        raise ValueError("app bundle escapes its mise install directory")
    publish_app(apps[0], repo)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    resolver = commands.add_parser("resolve")
    resolver.add_argument("url")
    resolver.add_argument("--asset")
    installer = commands.add_parser("install-app")
    installer.add_argument("repo")
    args = parser.parse_args()
    try:
        if args.command == "resolve":
            print(resolve(args.url, args.asset))
        else:
            install_app(args.repo)
    except (OSError, ValueError, KeyError, urllib.error.URLError, subprocess.CalledProcessError, tarfile.TarError, zipfile.BadZipFile) as exc:
        print(f"dots: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
