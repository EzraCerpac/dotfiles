import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from prompt_toolkit.application import run_in_terminal
from prompt_toolkit.completion import FuzzyCompleter
from prompt_toolkit.document import Document
from prompt_toolkit.filters import EmacsInsertMode, ViInsertMode
from prompt_toolkit.keys import Keys
from xonsh.built_ins import XSH
from xonsh.platform import ON_DARWIN, ON_LINUX

env = XSH.env
aliases = XSH.aliases

env["UPDATE_OS_ENVIRON"] = True
env["VI_MODE"] = True
env["XONSH_PROMPT_CURSOR_SHAPE"] = "modal"

if env.get("XONSH_INTERACTIVE") and env.get("TERM") == "dumb":
    env["TERM"] = "xterm-256color"
    env["SHELL_TYPE"] = "prompt_toolkit"


def _have(command):
    return shutil.which(command, path=env.detype().get("PATH")) is not None


def _prepend_path(*paths):
    current = [str(path) for path in env.get("PATH", [])]
    for raw_path in reversed(paths):
        path = os.path.expanduser(raw_path)
        if path and os.path.isdir(path) and path not in current:
            current.insert(0, path)
    env["PATH"] = current


def _sync_process_env(*names):
    detyped = env.detype()
    for name in names:
        value = detyped.get(name)
        if value is None:
            continue
        os.environ[name] = str(value)


if ON_DARWIN:
    _prepend_path("/opt/homebrew/bin", "/opt/homebrew/sbin")
elif ON_LINUX and os.path.isdir("/home/linuxbrew/.linuxbrew/bin"):
    _prepend_path("/home/linuxbrew/.linuxbrew/bin")

_prepend_path("~/.local/bin", "~/bin", "~/.cargo/bin")

if ON_DARWIN:
    _prepend_path("/opt/homebrew/opt/uutils-coreutils/libexec/uubin")
    _prepend_path("~/.orbstack/bin")

env["EDITOR"] = shutil.which("nvim") or "nvim"
env["VISUAL"] = env["EDITOR"]
env["GIT_EDITOR"] = env["EDITOR"]
env["XDG_CONFIG_HOME"] = str(Path.home() / ".config")
_sync_process_env("PATH", "EDITOR", "VISUAL", "GIT_EDITOR", "XDG_CONFIG_HOME")

aliases["ls"] = "eza --icons=auto --group-directories-first --git"
aliases["la"] = "eza -a --icons=auto --group-directories-first --git"
aliases["ll"] = "eza -la --icons=auto --group-directories-first --git"
aliases["tree"] = "eza --tree --level=2 --icons=auto --git"

aliases[".."] = "cd .."
aliases["..."] = "cd ../.."
aliases["...."] = "cd ../../.."
aliases["....."] = "cd ../../../.."
aliases["......"] = "cd ../../../../.."

aliases["v"] = "nvim"
aliases["ca"] = "chezmoi-smart-apply"
aliases["pluto"] = "julia --banner=no -e 'using Pluto; Pluto.run(auto_reload_from_file=true, require_secret_for_access=false, require_secret_for_open_links=false)'"
aliases["lss"] = 'julia -e "import LiveServer as LS; LS.serve(launch_browser=true)"'

if ON_DARWIN:
    aliases["tailscale"] = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    if env.get("DBUS_LAUNCHD_SESSION_BUS_SOCKET"):
        env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={env['DBUS_LAUNCHD_SESSION_BUS_SOCKET']}"
    aliases["grealpath"] = "realpath"


def _run_streamed(command, extra_env=None):
    run_env = env.detype()
    if extra_env:
        run_env.update(extra_env)
    return subprocess.run(command, env=run_env).returncode


def _nvim_local(args):
    """Launch nvim with local-root mode."""
    return _run_streamed(["nvim", *args], extra_env={"NVIM_LOCAL_ROOT": "1"})


aliases["nvim-local"] = _nvim_local
aliases["vl"] = _nvim_local

_JJ_AGENT_CONFIG = f"{Path.home()}/.config/jj/config.toml:{Path.home()}/.config/jj/claude-config.toml"


def _cc(args):
    """Launch Claude with the agent jj config."""
    return _run_streamed(
        ["claude", "--dangerously-skip-permissions", *args],
        extra_env={"JJ_CONFIG": _JJ_AGENT_CONFIG},
    )


aliases["cc"] = _cc


def _oc(args):
    """Launch OpenCode with the agent jj config."""
    return _run_streamed(["opencode", *args], extra_env={"JJ_CONFIG": _JJ_AGENT_CONFIG})


aliases["oc"] = _oc


def _wto(args, stderr=None):
    """Create or switch a worktree and launch OpenCode."""
    if not args:
        print("usage: wto <branch> [prompt...]", file=stderr or sys.stderr)
        return 1

    branch = args[0]
    prompt = args[1:]
    if prompt:
        return _run_streamed(["wt", "switch", "-c", branch, "-x", "opencode", "--", *prompt])
    return _run_streamed(["wt", "switch", "-c", "-x", "opencode", branch])


aliases["wto"] = _wto


def _prdiff(args):
    """Review a pull request diff in diffnav."""
    return _run_streamed(["bash", "-lc", 'gh pr diff "$@" | diffnav --side-by-side', "prdiff", *args])


aliases["prdiff"] = _prdiff


def _glf(args):
    """Browse commits and launch gitlogue on selection."""
    script = r'''
commit="$(git log --oneline --color=always "$@" |
    fzf --ansi --no-sort \
        --preview 'git show --stat --color=always {1}' \
        --preview-window=right:60% |
    awk '{print $1}')"
test -n "$commit" && gitlogue --commit "$commit"
'''
    return _run_streamed(["bash", "-lc", script, "glf", *args])


aliases["glf"] = _glf


def _gitlogue_menu(args):
    """Interactive gitlogue menu."""
    script = r'''
choice="$(printf '%s\n' "Random commits" "Specific commit" "By author" "By date range" "Theme selection" |
    fzf --prompt="gitlogue> " --height=40% --reverse)"
case "$choice" in
    "Random commits")
        gitlogue
        ;;
    "Specific commit")
        commit="$(git log --oneline | fzf --prompt="Select commit> " | awk '{print $1}')"
        test -n "$commit" && gitlogue --commit "$commit"
        ;;
    "By author")
        author="$(git log --format='%an' | sort -u | fzf --prompt="Select author> ")"
        test -n "$author" && gitlogue --author "$author"
        ;;
    "By date range")
        after="$(printf '%s\n' "1 day ago" "1 week ago" "2 weeks ago" "1 month ago" |
            fzf --prompt="After> ")"
        test -n "$after" && gitlogue --after "$after"
        ;;
    "Theme selection")
        theme="$(gitlogue theme list | tail -n +2 | sed 's/^  - //' | fzf --prompt="Select theme> ")"
        test -n "$theme" && gitlogue --theme "$theme"
        ;;
esac
'''
    return _run_streamed(["bash", "-lc", script, "gitlogue-menu", *args])


aliases["gitlogue-menu"] = _gitlogue_menu


def _jw(args, stderr=None):
    """Run jw and cd after workspace-switching commands."""
    if not args:
        return _run_streamed(["jw"])

    should_cd = args[0] in ("switch", "s", "^", "-")
    passthrough = any(arg in ("-x", "--execute", "-h", "--help") for arg in args)
    if not should_cd or passthrough:
        return _run_streamed(["jw", *args])

    result = subprocess.run(
        ["jw", *args, "--print-path"],
        env=env.detype(),
        stdout=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        return result.returncode

    target = result.stdout.strip()
    if not target:
        print("jw: no target path returned", file=stderr or sys.stderr)
        return 1
    os.chdir(os.path.expanduser(target))
    return 0


if Path.home().joinpath(".local/bin/jw").exists():
    aliases["jw"] = _jw


def _wt(args, stderr=None):
    """Run wt and apply shell cd/source directives in xonsh."""
    worktrunk_bin = env.get("WORKTRUNK_BIN") or shutil.which("wt")
    if not worktrunk_bin:
        print("wt: command not found", file=stderr or sys.stderr)
        return 127

    filtered_args = [arg for arg in args if arg != "--source"]
    use_source = len(filtered_args) != len(args)

    cd_file = tempfile.NamedTemporaryFile(delete=False)
    exec_file = tempfile.NamedTemporaryFile(delete=False)
    cd_file.close()
    exec_file.close()

    try:
        extra_env = {
            "WORKTRUNK_DIRECTIVE_CD_FILE": cd_file.name,
            "WORKTRUNK_DIRECTIVE_EXEC_FILE": exec_file.name,
        }
        if use_source:
            command = ["cargo", "run", "--bin", "wt", "--quiet", "--", *filtered_args]
        else:
            command = [worktrunk_bin, *filtered_args]

        exit_code = _run_streamed(command, extra_env=extra_env)

        if os.path.getsize(cd_file.name) > 0:
            target = Path(cd_file.name).read_text().strip()
            if target:
                os.chdir(os.path.expanduser(target))

        if os.path.getsize(exec_file.name) > 0:
            execx(Path(exec_file.name).read_text())

        return exit_code
    finally:
        for path in (cd_file.name, exec_file.name):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


if _have("wt"):
    aliases["wt"] = _wt


def _open_buffer_in_neovim(buffer):
    editor = env.get("VISUAL") or env.get("EDITOR") or shutil.which("nvim") or "nvim"
    fd, path = tempfile.mkstemp(suffix=".xsh", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(buffer.text)

        exit_code = subprocess.call([str(editor), path], env=env.detype())
        if exit_code == 0:
            text = Path(path).read_text(encoding="utf-8")
            if text.endswith("\n"):
                text = text[:-1]
            buffer.document = Document(text=text, cursor_position=len(text))
    finally:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def _start_fuzzy_completion(buffer):
    if buffer.complete_state:
        buffer.complete_next()
        return

    original_completer = buffer.completer
    fuzzy_completer = FuzzyCompleter(original_completer, WORD=True)

    def _restore_completer(_buffer):
        buffer.on_completions_changed -= _restore_completer
        buffer.completer = original_completer

    buffer.completer = fuzzy_completer
    buffer.on_completions_changed += _restore_completer
    try:
        buffer.start_completion(select_first=False)
    except Exception:
        buffer.on_completions_changed -= _restore_completer
        buffer.completer = original_completer
        raise


if $XONSH_INTERACTIVE:
    from xonsh.events import events

    @events.on_ptk_create
    def _bind_prompt_keys(bindings, **_kwargs):
        @bindings.add("c-e")
        def _open_editor(event):
            run_in_terminal(lambda: _open_buffer_in_neovim(event.current_buffer))

        @bindings.add(
            Keys.BackTab,
            filter=ViInsertMode() | EmacsInsertMode(),
            eager=True,
        )
        def _open_fuzzy_completion(event):
            _start_fuzzy_completion(event.current_buffer)

    if _have("mise"):
        execx($(mise activate xonsh))
        env["EDITOR"] = shutil.which("nvim") or env["EDITOR"]
        env["VISUAL"] = env["EDITOR"]
        env["GIT_EDITOR"] = env["EDITOR"]
        _sync_process_env("PATH", "EDITOR", "VISUAL", "GIT_EDITOR")

    if _have("atuin"):
        execx($(atuin init xonsh))

    television_bin = Path.home() / "Projects/television/target/debug/tv"
    if television_bin.exists():
        television_init = subprocess.run(
            [str(television_bin), "init", "xonsh"],
            stdout=subprocess.PIPE,
            text=True,
            check=False,
        )
        if television_init.returncode == 0:
            television_script = television_init.stdout.replace('"tv"', repr(str(television_bin)))
            television_script = television_script.replace(
                '''        @bindings.add("c-r", eager=True)
        def _tv_shell_history(event):
            tv_shell_history(event)
''',
                "",
            )
            execx(television_script, "exec", __xonsh__.ctx, filename="television")

    if _have("zoxide"):
        execx($(zoxide init xonsh --cmd cd), "exec", __xonsh__.ctx, filename="zoxide")

    if _have("starship"):
        execx($(starship init xonsh --print-full-init))

    if _have("carapace"):
        env["CARAPACE_BRIDGES"] = "zsh,fish,bash,inshellisense"
        env["COMPLETIONS_CONFIRM"] = True
        exec($(carapace _carapace xonsh))
