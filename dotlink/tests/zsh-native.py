#!/usr/bin/env python3
"""Isolated public-interface tests for native Zsh history and ZLE."""
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
ZSH = shutil.which("zsh")
READY = b"__DOTFILES_READY__"


class InteractiveZsh:
    """A real interactive Zsh process attached to a private pseudo-terminal."""
    def __init__(self, env, cwd):
        self.env = dict(env, PS1=READY.decode() + " ", PROMPT=READY.decode() + " ", RPROMPT="", PS2="__DOTFILES_CONT__")
        self.cwd = cwd
        self.master, slave = pty.openpty()
        attrs = termios.tcgetattr(slave)
        attrs[3] &= ~termios.ECHO
        termios.tcsetattr(slave, termios.TCSANOW, attrs)

        def controlling_tty():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        self._closed = False
        self.proc = subprocess.Popen([ZSH, "-d", "-i"], env=self.env, cwd=cwd,
                                      stdin=slave, stdout=slave, stderr=subprocess.PIPE,
                                      preexec_fn=controlling_tty, close_fds=True)
        os.close(slave)
        self._read_until(READY)

    def send(self, data):
        os.write(self.master, data.encode() if isinstance(data, str) else data)

    def _read_until(self, marker, timeout=5):
        deadline = time.monotonic() + timeout
        data = bytearray()
        while marker not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"timeout waiting for {marker!r}; received {bytes(data)!r}")
            ready, _, _ = select.select([self.master], [], [], remaining)
            if not ready:
                continue
            chunk = os.read(self.master, 65536)
            if not chunk:
                raise AssertionError(f"Zsh exited while waiting for {marker!r}: {bytes(data)!r}")
            data.extend(chunk)
        return bytes(data[:data.index(marker)])

    def command(self, line, timeout=5):
        self.send(line + "\n")
        output = self._read_until(b"__DOTFILES_DONE__", timeout)
        return output + self._read_until(READY, timeout)

    def key(self, data, timeout=5):
        self.send(data)
        if data == b"\r":
            output = self._read_until(b"__DOTFILES_DONE__", timeout)
            return output + self._read_until(READY, timeout)
        deadline = time.monotonic() + timeout
        output = bytearray()
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"timeout draining ZLE key output: {bytes(output)!r}")
            ready, _, _ = select.select([self.master], [], [], min(remaining, 0.15))
            if not ready:
                return bytes(output)
            chunk = os.read(self.master, 65536)
            if not chunk:
                raise AssertionError(f"Zsh exited during ZLE key input: {bytes(output)!r}")
            output.extend(chunk)

    def close(self):
        if self._closed:
            return
        self._closed = True
        if self.proc.poll() is None:
            try:
                self.send(b"\x04")
            except OSError:
                pass
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait(timeout=2)
        stderr = self.proc.stderr.read()
        self.proc.stderr.close()
        os.close(self.master)
        if self.proc.returncode != 0:
            raise AssertionError(f"interactive Zsh exited {self.proc.returncode}; stderr={stderr!r}")
        if stderr:
            raise AssertionError(f"unexpected Zsh stderr: {stderr!r}")


class NativeZsh(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dotfiles-zsh-native-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.hist = self.home / ".zsh_history"
        self.env = {
            "HOME": str(self.home), "ZDOTDIR": str(self.home),
            "PATH": os.environ["PATH"], "TERM": "xterm",
            "HISTFILE": str(self.hist),
            "XDG_CONFIG_HOME": str(self.base / "config"),
            "XDG_DATA_HOME": str(self.base / "data"),
            "XDG_CACHE_HOME": str(self.base / "cache"),
            "XDG_STATE_HOME": str(self.base / "state"),
            "TMPDIR": str(self.base),
        }
        self.rc = ROOT / "zsh/.zshrc"
        (self.home / ".zshrc").write_text(
            f'setopt HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS HIST_EXPIRE_DUPS_FIRST INC_APPEND_HISTORY_TIME\n'
            f'source "{self.rc}"\nPROMPT="{READY.decode()} "; PS1=$PROMPT; RPROMPT=""; PS2="__DOTFILES_CONT__"; precmd() {{ print -rn -- "__DOTFILES_DONE__"; }}\n')

    def shell(self, command, interactive=False, timeout=15):
        args = [ZSH, "-d", "-f"] + (["-i"] if interactive else []) + ["-c", command]
        return subprocess.run(args, env=self.env, cwd=self.home, capture_output=True,
                              text=True, timeout=timeout)

    def run_rc(self, command, **kwargs):
        kwargs.setdefault("interactive", True)
        return self.shell(f'source "{self.rc}"; {command}', **kwargs)

    def start_tty(self):
        session = InteractiveZsh(self.env, self.home)
        self.addCleanup(session.close)
        return session

    def test_history_defaults_and_preserves_existing_file_and_limits(self):
        self.hist.write_text(": 1:0;old-command\n")
        result = self.run_rc('print -r -- "$HISTFILE|$HISTSIZE|$SAVEHIST|$options[incappendhistory]|$options[sharehistory]"')
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, f'{self.hist}|10001|10001|on|off\n', ""))
        self.assertEqual(self.hist.read_text(), ": 1:0;old-command\n")
        self.env.update(HISTSIZE="25000", SAVEHIST="30000")
        result = self.run_rc('print -r -- "$HISTSIZE|$SAVEHIST"')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "30000|30000\n", ""))

    def test_custom_history_filename_and_invalid_destination_fallback(self):
        custom = self.home / "custom history"
        custom.write_text(": 1:0;keep\n")
        self.env["HISTFILE"] = str(custom)
        result = self.run_rc('print -r -- "$HISTFILE"')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, f"{custom}\n", ""))
        self.assertEqual(custom.read_text(), ": 1:0;keep\n")
        bad = self.home / "not-a-history-file"
        bad.mkdir()
        sentinel = bad / "preserve-this"
        sentinel.write_text("foreign fixture data\n")
        self.env["HISTFILE"] = str(bad)
        result = self.run_rc('print -r -- "$HISTFILE"')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, f"{self.hist}\n", ""))
        self.assertTrue(bad.is_dir())
        self.assertEqual(sentinel.read_text(), "foreign fixture data\n")
        self.assertEqual([path.name for path in bad.iterdir()], ["preserve-this"])

    def test_noninteractive_does_not_create_or_mutate_history(self):
        self.hist.write_text(": 1:0;preserve-noninteractive\n")
        before = self.hist.read_bytes()
        result = self.run_rc('print -r -- ready', interactive=False)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "ready\n", ""))
        self.assertEqual(self.hist.read_bytes(), before)

    def test_conservative_options_override_inherited_pruning_options(self):
        command = (f'setopt HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS HIST_EXPIRE_DUPS_FIRST '
                   f'INC_APPEND_HISTORY_TIME; source "{self.rc}"; '
                   'print -r -- "$options[incappendhistory]|$options[incappendhistorytime]|$options[sharehistory]|$options[hist_ignore_all_dups]|$options[hist_save_no_dups]|$options[hist_expire_dups_first]"')
        result = self.shell(command, interactive=True)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "on|off|off|off|off|off\n", ""))

    def test_unset_empty_and_devnull_history_destinations(self):
        result = self.shell(f'unset HISTFILE; source "{self.rc}"; print -r -- "$HISTFILE"', interactive=True)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, f"{self.hist}" + "\n", ""))
        self.env["HISTFILE"] = ""
        result = self.run_rc('print -r -- "$HISTFILE"')
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, f"{self.hist}" + "\n", ""))

        self.env["HISTFILE"] = "/dev/null"
        session = self.start_tty()
        output = session.command('print -r -- "$HISTFILE"')
        self.assertIn(b"/dev/null" + bytes((13, 10)), output)
        self.assertIn(b"natural-null-optout" + bytes((13, 10)), session.command('print -r -- natural-null-optout'))
        session.close()
        self.assertFalse(self.hist.exists(), "explicit /dev/null opt-out must not write the default file")

    def test_large_existing_history_survives_natural_capture_with_headroom(self):
        count = 12050
        old_commands = [f"preexisting-{index:05d};retain-delimiter" for index in range(count)]
        old_lines = [f": {index + 1}:0;{command}" for index, command in enumerate(old_commands)]
        self.hist.write_text(chr(10).join(old_lines) + chr(10))
        session = self.start_tty()
        limits_file = self.home / "limits"
        session.command(f'print -r -- "$HISTSIZE|$SAVEHIST" > "{limits_file}"')
        hist_size, save_hist = map(int, limits_file.read_text().strip().split("|"))
        self.assertGreaterEqual(hist_size, save_hist)
        self.assertGreaterEqual(save_hist, count + 5)
        for index in range(5):
            marker = f"naturally-added-{index}"
            self.assertIn(marker.encode() + bytes((13, 10)), session.command(f"print -r -- {marker}"))
        session.close()
        written = self.hist.read_text().splitlines()
        for command in old_commands:
            self.assertIn(command, written)
        for index in range(5):
            self.assertEqual(sum(f"naturally-added-{index}" in line for line in written), 1)

    def test_real_interactive_history_is_incremental_private_and_duplicate_safe(self):
        self.hist.write_text(": 1:0;older-marker\n")
        first = self.start_tty()
        second = self.start_tty()
        self.assertIn(b"concurrent-first-marker\r\n", first.command('print -r -- concurrent-first-marker'))
        self.assertTrue(self.hist.exists(), "INC_APPEND_HISTORY did not persist before shell exit")
        live_listing = second.command("fc -l 1 99")
        self.assertNotIn(b"concurrent-first-marker", live_listing)

        # Native capture suppresses adjacent duplicates but not older entries.
        self.assertIn(b"repeated-marker\r\n", first.command('print -r -- repeated-marker'))
        self.assertIn(b"repeated-marker\r\n", first.command('print -r -- repeated-marker'))

        # Adjacent A is suppressed, but A after B retains the older A.
        for command in ("A;keep", "A;keep", "B;keep", "A;keep"):
            self.assertIn(command.encode() + bytes((13, 10)),
                          first.command(f"print -r -- '{command}'"))
        first.close()
        first = None
        saved = self.hist.read_text()
        self.assertIn("older-marker", saved)
        self.assertEqual(saved.count("repeated-marker"), 1)
        self.assertEqual(saved.count("concurrent-first-marker"), 1)
        self.assertEqual(saved.count("A;keep"), 2)
        self.assertEqual(saved.count("B;keep"), 1)

        later = self.start_tty()
        persisted_listing = later.command("fc -l 1 99")
        self.assertIn(b"concurrent-first-marker", persisted_listing)
        later.close()
        first = None
        later = None
        second.close()
        second = None

    def test_zle_prefix_navigation_no_match_cursor_multiline_and_reload(self):
        session = self.start_tty()
        self.assertIn(b"prefix-one\r\n", session.command('print -r -- prefix-one'))
        self.assertIn(b"prefix-two\r\n", session.command('print -r -- prefix-two'))
        session.send(b"print -r -- prefix")
        session.key(b"\x1b[A")
        session.key(b"\x1b[A")
        session.key(b"\x1b[B")
        self.assertIn(b"prefix-two\r\n", session.key(b"\r"))

        # With no matching history, Up leaves the buffer and cursor untouched.
        session.send(b"print -r -- unmatchedXYZ")
        session.send(b"\x1b[D\x1b[D\x1b[D")
        session.key(b"\x1b[A")
        session.send(b"Q")
        self.assertIn(b"unmatchedQXYZ\r\n", session.key(b"\r"))

        # An open quoted command remains multiline-editable across Up/Down.
        session.send(b"print -r -- 'line-one\n")
        session._read_until(b"__DOTFILES_CONT__")
        session.send(b"line-two'")
        session.key(b"\x1b[A")
        session.key(b"\x1b[B")
        self.assertIn(b"line-one\r\nline-two\r\n", session.key(b"\r"))

        # Re-sourcing preserves a widget reconfigured after the initial load.
        session.command('zle -N external-up up-line-or-history; bindkey -M emacs "^[[A" external-up; source "$DOTFILES_ROOT/zsh/.zshrc"')
        self.assertIn(b'"^[[A" external-up\r\n', session.command('print -r -- "$(bindkey -M emacs \'^[[A\')"'))
        session.close()


if __name__ == "__main__":
    if ZSH is None:
        raise SystemExit("zsh is required")
    unittest.main()
