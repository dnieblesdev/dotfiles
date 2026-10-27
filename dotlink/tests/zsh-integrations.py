#!/usr/bin/env python3
"""Isolated checks for optional Zsh integrations and prompt selection."""
import fcntl
import os
from pathlib import Path
import pty
import shutil
import struct
import subprocess
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
ZSH = shutil.which("zsh")
AUTOSUGGEST = Path("/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh")
HIGHLIGHT = Path("/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh")
P10K = Path("/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme")
READY = b"__DOTFILES_READY__"
DONE = b"__DOTFILES_DONE__"


class InteractiveZsh:
    def __init__(self, env, cwd, load_rc=False, ready=READY):
        self.master, slave = pty.openpty()
        attrs = termios.tcgetattr(slave)
        attrs[3] &= ~termios.ECHO
        termios.tcsetattr(slave, termios.TCSANOW, attrs)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

        def controlling_tty():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        args = [ZSH, "-d", "-i"] if load_rc else [ZSH, "-d", "-f", "-i"]
        self.proc = subprocess.Popen(args, cwd=cwd, env=env,
                                     stdin=slave, stdout=slave, stderr=slave,
                                     preexec_fn=controlling_tty, close_fds=True)
        os.close(slave)
        self.initial_output = self.read_until(ready)

    def send(self, data):
        os.write(self.master, data.encode() if isinstance(data, str) else data)

    def read_until(self, marker, timeout=10):
        import select
        import time
        output = bytearray()
        deadline = time.monotonic() + timeout
        while marker not in output:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"timed out waiting for {marker!r}; saw {bytes(output)!r}")
            ready, _, _ = select.select([self.master], [], [], remaining)
            if not ready:
                continue
            chunk = os.read(self.master, 65536)
            if not chunk:
                raise AssertionError(f"Zsh exited before {marker!r}: {bytes(output)!r}")
            output.extend(chunk)
        return bytes(output)

    def command(self, code):
        self.send(code + f'\nprint -r -- "{DONE.decode()}"\n')
        output = self.read_until(DONE)
        return output + self.read_until(READY)

    def close(self):
        if self.proc.poll() is None:
            self.send(b"\x04")
        try:
            self.proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait(timeout=3)
        os.close(self.master)


class ZshIntegrations(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dotfiles-zsh-integrations-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.env = {
            "HOME": str(self.home), "ZDOTDIR": str(self.home),
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "TERM": "xterm",
            "HISTFILE": "/dev/null", "TMPDIR": str(self.base),
            "PS1": READY.decode() + " ", "PROMPT": READY.decode() + " ", "RPROMPT": "",
            "XDG_CONFIG_HOME": str(self.base / "config"),
            "XDG_DATA_HOME": str(self.base / "data"),
            "XDG_CACHE_HOME": str(self.base / "cache"),
            "XDG_STATE_HOME": str(self.base / "state"),
        }
        self.rc = ROOT / "zsh/.zshrc"

    def run_zsh(self, code, extra=None, path=None):
        env = dict(self.env)
        env.update(extra or {})
        if path is not None:
            env["PATH"] = path
        return subprocess.run([ZSH, "-d", "-f", "-i", "-c", f'source "{self.rc}"; {code}'],
                              cwd=self.home, env=env, text=True, capture_output=True, timeout=15)

    def run_pty(self, code, extra=None):
        env = dict(self.env, **(extra or {}))
        master, slave = pty.openpty()

        def controlling_tty():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        proc = subprocess.Popen([ZSH, "-d", "-f", "-i", "-c", code],
                                cwd=self.home, env=env, stdin=slave, stdout=slave, stderr=slave,
                                preexec_fn=controlling_tty, close_fds=True)
        os.close(slave)
        try:
            status = proc.wait(timeout=20)
            output = bytearray()
            while True:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
        finally:
            os.close(master)
        return status, bytes(output)

    def test_missing_integrations_are_silent_and_reload_is_idempotent(self):
        no_tools = self.base / "empty-path"
        no_tools.mkdir()
        for name in ("uname", "grep", "mkdir", "readlink", "dirname", "sort", "find", "dircolors",
                     "cat", "sed", "tr", "rm", "mv", "chmod", "touch", "pwd", "cut", "head", "tail"):
            tool = shutil.which(name)
            if tool:
                (no_tools / name).symlink_to(tool)
        result = self.run_zsh(
            f'source "{self.rc}"; print -r -- "state:$+functions[_dotfiles_autosuggestions_loaded]:$+functions[_dotfiles_fzf_loaded]:$+functions[_dotfiles_syntax_highlighting_loaded]:$+functions[_dotfiles_zsh_prompt_selected]:$+functions[prompt_starship_precmd]"',
            extra={"DOTFILES_ZSH_PROMPT": "invalid", "ZSH_AUTOSUGGEST_SCRIPT": "/missing/auto",
                   "ZSH_SYNTAX_HIGHLIGHTING_SCRIPT": "/missing/syntax", "FZF_ZSH_SCRIPT": "/missing/fzf"},
            path=str(no_tools))
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "state:0:0:0:1:0\n", ""))

    def test_explicit_sources_once_order_invalid_override_and_generic_discovery(self):
        data = self.base / "data/zsh/plugins"
        auto_dir, syntax_dir = data / "zsh-autosuggestions", data / "zsh-syntax-highlighting"
        auto_dir.mkdir(parents=True)
        syntax_dir.mkdir(parents=True)
        auto, syntax, fzf = self.base / "auto.zsh", self.base / "syntax.zsh", self.base / "fzf.zsh"
        auto.write_text('typeset -g DOTFILES_LOAD_ORDER="${DOTFILES_LOAD_ORDER}auto,"; typeset -g DOTFILES_AUTO_LOADS=$((${DOTFILES_AUTO_LOADS:-0}+1)); autosuggest_test() { :; }\n')
        syntax.write_text('typeset -g DOTFILES_LOAD_ORDER="${DOTFILES_LOAD_ORDER}syntax,"; typeset -g DOTFILES_HIGHLIGHT_LOADS=$((${DOTFILES_HIGHLIGHT_LOADS:-0}+1)); syntax_test() { :; }\n')
        fzf.write_text('typeset -g DOTFILES_LOAD_ORDER="${DOTFILES_LOAD_ORDER}fzf,"; typeset -g DOTFILES_FZF_LOADS=$((${DOTFILES_FZF_LOADS:-0}+1)); fzf_test() { :; }\n')
        (auto_dir / "zsh-autosuggestions.zsh").symlink_to(auto)
        (syntax_dir / "zsh-syntax-highlighting.zsh").symlink_to(syntax)
        result = self.run_zsh(
            f'source "{self.rc}"; source "{self.rc}"; print -r -- "$DOTFILES_LOAD_ORDER|$DOTFILES_AUTO_LOADS:$DOTFILES_HIGHLIGHT_LOADS:$DOTFILES_FZF_LOADS"',
            extra={"FZF_ZSH_SCRIPT": str(fzf), "DOTFILES_ZSH_PROMPT": "none"})
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "auto,fzf,syntax,|1:1:1\n", ""))

        result = self.run_zsh(
            f'source "{self.rc}"; print -r -- "invalid:$+functions[autosuggest_test]:$+functions[syntax_test]"',
            extra={"ZSH_AUTOSUGGEST_SCRIPT": "/missing/auto", "ZSH_SYNTAX_HIGHLIGHTING_SCRIPT": "",
                   "DOTFILES_ZSH_PROMPT": "none"})
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "invalid:0:0\n", ""))

    def test_powerlevel10k_is_quiet_and_active_on_first_prompt(self):
        if not P10K.is_file():
            self.skipTest("real Powerlevel10k unavailable")
        isolated_p10k = self.home / "installed-p10k"
        shutil.copytree(P10K.parent, isolated_p10k)
        test_p10k = isolated_p10k / P10K.name
        self.assertNotIn("POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD", self.env)
        (self.home / ".zshrc").write_text(
            f'source "{self.rc}"\n'
            'autoload -Uz add-zsh-hook\n'
            'dotfiles_prompt_ready() { print -r -- __DOTFILES_PROMPT_READY__:$+functions[p10k]:$+functions[_p9k_precmd] }\n'
            'add-zsh-hook precmd dotfiles_prompt_ready\n')
        prompt_env = dict(self.env, DOTFILES_ZSH_PROMPT="powerlevel10k",
                          POWERLEVEL10K_ZSH_THEME_FILE=str(test_p10k))
        shell = InteractiveZsh(prompt_env, self.home, load_rc=True, ready=b"__DOTFILES_PROMPT_READY__")
        self.addCleanup(shell.close)
        self.assertIn(b"__DOTFILES_PROMPT_READY__:1:1", shell.initial_output)
        self.assertNotIn(b"configuration wizard", shell.initial_output.lower())
        shell.send("print -r -- COMMAND_AFTER_PROMPT\n")
        command_output = shell.read_until(b"__DOTFILES_PROMPT_READY__")
        self.assertIn(b"COMMAND_AFTER_PROMPT", command_output)
        self.assertNotIn(b"configuration wizard", command_output.lower())
        self.assertFalse((self.home / ".p10k.zsh").exists())
        self.assertIsNone(prompt_env.get("POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD"))

    def test_real_widgets_perform_suggestions_highlighting_and_fzf_selection(self):
        if not AUTOSUGGEST.is_file() or not HIGHLIGHT.is_file() or not shutil.which("fzf"):
            self.skipTest("real autosuggestions, syntax highlighting, and fzf are required")
        env = dict(self.env, ZSH_AUTOSUGGEST_SCRIPT=str(AUTOSUGGEST),
                   ZSH_SYNTAX_HIGHLIGHTING_SCRIPT=str(HIGHLIGHT), DOTFILES_ZSH_PROMPT="none",
                   ZSH_AUTOSUGGEST_STRATEGY="history",
                   FZF_CTRL_T_COMMAND="find . -maxdepth 1 -name dotfiles-fzf-selection-target -print")
        shell = InteractiveZsh(env, self.home)
        self.addCleanup(shell.close)
        shell.command(f'source "{self.rc}"; ghost_accept() {{ _zsh_autosuggest_suggest "${{BUFFER}}-target"; zle autosuggest-accept; }}; zle -N ghost_accept; bindkey "^X^A" ghost_accept')
        shell.send("print -r -- ghost-suggestion")
        time.sleep(0.1)
        shell.send(b"\x18\x01\r")
        suggestion_output = shell.read_until(READY)
        self.assertIn(b"ghost-suggestion-target", suggestion_output)

        shell.send("command_that_does_not_exist_dotfiles")
        time.sleep(0.1)
        shell.send(b"\x07")
        highlight_output = shell.read_until(READY)
        self.assertIn(b"\x1b[31m", highlight_output)

        target = self.home / "dotfiles-fzf-selection-target"
        target.write_text("fixture\\n")
        shell.command('bindkey "^X^F" fzf-file-widget')
        shell.send(b"\x18\x06")
        fzf_list = shell.read_until(b"dotfiles-fzf", timeout=5)
        shell.send(b"\r")
        fzf_output = fzf_list + shell.read_until(READY, timeout=15)
        self.assertIn(b"dotfiles-fzf-selection-target", fzf_output)

    def test_real_plugins_fzf_and_prompt_exclusivity_in_pty(self):
        for name, path in (("zsh-autosuggestions", AUTOSUGGEST), ("zsh-syntax-highlighting", HIGHLIGHT),
                           ("fzf", Path(shutil.which("fzf") or ""))):
            if not path.is_file():
                self.skipTest(f"real {name} unavailable")
        status, output = self.run_pty(
            f'source "{self.rc}"; print -r -- "REAL:$+functions[_zsh_autosuggest_start]:$+functions[_zsh_highlight]:$+widgets[fzf-file-widget]:$+widgets[autosuggest-accept]"; exit',
            {"ZSH_AUTOSUGGEST_SCRIPT": str(AUTOSUGGEST),
             "ZSH_SYNTAX_HIGHLIGHTING_SCRIPT": str(HIGHLIGHT), "DOTFILES_ZSH_PROMPT": "none"})
        self.assertEqual(status, 0, output)
        self.assertIn(b"REAL:1:1:1:1", output)
        self.assertNotIn(b"can't change option: zle", output)

        starship = shutil.which("starship")
        if not starship:
            self.skipTest("real Starship unavailable")
        trace = self.base / "highlight-trace.zsh"
        trace.write_text(f'source "{HIGHLIGHT}"; typeset -g DOTFILES_HIGHLIGHT_SAW_STARSHIP=$+functions[starship_zle-keymap-select]\n')
        status, output = self.run_pty(
            f'source "{self.rc}"; print -r -- "STARSHIP:$+functions[prompt_starship_precmd]:$+functions[p10k]:$DOTFILES_HIGHLIGHT_SAW_STARSHIP"; exit',
            {"DOTFILES_ZSH_PROMPT": "starship", "ZSH_SYNTAX_HIGHLIGHTING_SCRIPT": str(trace)})
        self.assertEqual(status, 0, output)
        self.assertIn(b"STARSHIP:1:0:1", output)

        if not P10K.is_file():
            self.skipTest("real Powerlevel10k unavailable")
        isolated_p10k = self.home / "installed-p10k"
        shutil.copytree(P10K.parent, isolated_p10k)
        test_p10k = isolated_p10k / P10K.name
        status, output = self.run_pty(
            f'source "{test_p10k}"; source "{self.rc}"; print -r -- "P10K:$+functions[prompt_starship_precmd]:$+functions[p10k]"; exit',
            {"DOTFILES_ZSH_PROMPT": "starship"})
        self.assertEqual(status, 0, output)
        self.assertIn(b"P10K:0:1", output)

        status, output = self.run_pty(
            f'source "{self.rc}"; DOTFILES_ZSH_PROMPT=powerlevel10k; POWERLEVEL10K_ZSH_THEME_FILE="{P10K}"; source "$DOTFILES_ROOT/zsh/prompt"; print -r -- "NO_SWITCH:$+functions[prompt_starship_precmd]:$+functions[p10k]"; exit',
            {"DOTFILES_ZSH_PROMPT": "starship"})
        self.assertEqual(status, 0, output)
        self.assertIn(b"NO_SWITCH:1:0", output)

        status, output = self.run_pty(
            f'source "{self.rc}"; print -r -- "UNCHANGED:$+functions[prompt_starship_precmd]:$+functions[p10k]"; exit',
            {"DOTFILES_ZSH_PROMPT": "starship"})
        self.assertEqual(status, 0, output)
        self.assertIn(b"UNCHANGED:1:0", output)


if __name__ == "__main__":
    if ZSH is None:
        raise SystemExit("zsh is required")
    unittest.main(verbosity=2)
