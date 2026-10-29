#!/usr/bin/env python3
"""Isolated public-entrypoint regression tests; no user startup is executed."""
import fcntl
import os
from pathlib import Path
import pty
import shutil
import subprocess
import tempfile
import termios
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ShellStartup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dotfiles-shells-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.repo = self.base / "checkout with spaces"
        self.repo.mkdir()
        for name in ("bash", "zsh", "env", "linux", "wsl"):
            shutil.copytree(ROOT / name, self.repo / name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        # An allowlist, not /usr/bin: absence cases cannot accidentally find mise.
        for name in ("uname", "grep", "mkdir", "readlink", "dirname", "sort", "find", "dircolors", "cat", "sed", "tr", "rm", "mv", "chmod"):
            target = shutil.which(name)
            if target:
                (self.bin / name).symlink_to(target)
        self.env = {
            "HOME": str(self.home), "PATH": str(self.bin), "TERM": "dumb",
            "ZDOTDIR": str(self.home), "HISTFILE": "/dev/null",
            "XDG_CONFIG_HOME": str(self.base / "config"),
            "XDG_DATA_HOME": str(self.base / "data"),
            "XDG_CACHE_HOME": str(self.base / "cache"),
            "XDG_STATE_HOME": str(self.base / "state"),
            "TMPDIR": str(self.base),
        }
        for shell in ("bash", "zsh"):
            (self.home / f".{shell}rc").symlink_to(self.repo / shell / f".{shell}rc")

    def run_shell(self, shell, code, interactive=True, login=False):
        executable = shutil.which(shell)
        self.assertIsNotNone(executable, f"required test shell unavailable: {shell}")
        args = [executable] + (["--noprofile", "--norc"] if shell == "bash" else ["-d", "-f"])
        if login:
            args.append("-l")
        args += ["-ic" if interactive else "-c", code]
        master, slave = pty.openpty()
        def tty():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        try:
            result = subprocess.run(args, env=self.env, cwd=self.home, stdin=slave,
                                    capture_output=True, text=True, timeout=15, preexec_fn=tty)
        finally:
            os.close(slave)
            os.close(master)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout

    def test_startup_context_matrix_and_user_owned_bash_profile(self):
        # The entrypoint tests suppress automatic startup to avoid host config.
        # Bash --noprofile also suppresses login profiles; model that boundary
        # explicitly, then source a disposable user-owned profile when desired.
        for shell in ("bash", "zsh"):
            for login in (False, True):
                for interactive in (False, True):
                    with self.subTest(shell=shell, login=login, interactive=interactive):
                        marker = self.base / f"{shell}-{login}-{interactive}.marker"
                        code = (f'. "$HOME/.{shell}rc"; printf "loaded\\n" > "{marker}"; '
                                'printf "interactive:%s\\n" "$([[ $- == *i* ]] && echo yes || echo no)"')
                        out = self.run_shell(shell, code, interactive=interactive, login=login)
                        self.assertTrue(marker.exists())
                        self.assertEqual(out, f"interactive:{'yes' if interactive else 'no'}\n")

        profile = self.home / ".bash_profile"
        profile.write_text('printf "profile\\n" > "$HOME/profile.marker"; source "$HOME/.bashrc"\n')
        out = self.run_shell("bash", '. "$HOME/.bash_profile"; printf "%s\\n" "${DOTFILES_ROOT-unset}"', login=True)
        self.assertIn(str(self.repo), out)
        self.assertTrue((self.home / "profile.marker").exists())
        profile.unlink()
        (self.home / "profile.marker").unlink()
        out = self.run_shell("bash", 'printf "%s\\n" "${DOTFILES_ROOT-unset}"', login=True)
        self.assertEqual(out, "unset\n")
        self.assertFalse((self.home / "profile.marker").exists())

    def test_noninteractive_rc_is_inert_and_reload_is_stable(self):
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                rc = f"$HOME/.{shell}rc"
                code = (f'before="$PATH"; . "{rc}"; middle="$PATH"; '
                        f'. "{rc}"; test "$before" = "$PATH" -a "$middle" = "$PATH"; '
                        'printf "%s|%s|%s\\n" "$PATH" "$(type -t dev 2>/dev/null || echo absent)" '
                        '"${DOTFILES_ROOT-unset}"')
                # Noninteractive mode returns before integrations and PATH changes.
                out = self.run_shell(shell, code, interactive=False)
                fields = out.rstrip("\n").split("|")
                self.assertEqual(fields[0], self.env["PATH"])
                self.assertEqual(fields[1], "absent")
                self.assertEqual(fields[2], "unset")
                self.assertFalse(Path(self.env["XDG_CACHE_HOME"]).exists())

    def test_simulated_wsl_detection_preserves_explicit_workspace(self):
        workspace = str(self.base / "mnt" / "c" / "workspace")
        grep = self.bin / "grep"
        grep.unlink()
        real_grep = shutil.which("grep")
        grep.write_text(f'''#!/bin/sh
last=
for arg do last=$arg; done
if [ "$last" = /proc/version ]; then
    case "$*" in *microsoft*) exit 0;; esac
fi
exec '{real_grep}' "$@"
''')
        grep.chmod(0o755)
        self.env.update(WORKSPACE=workspace)
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                out = self.run_shell(shell, f'. "$HOME/.{shell}rc"; printf "%s|%s|%s\\n" "$WORKSPACE" "$(is_wsl && echo wsl || echo other)" "$PATH"')
                fields = out.rstrip("\n").split("|")
                self.assertEqual(fields[:2], [workspace, "wsl"])
                if shell == "bash":
                    self.assertIn("/mnt/c/Windows/System32", fields[2].split(":"))

    def test_zsh_conflict_is_preserved_by_public_dotlink(self):
        target = self.home / ".zshrc"
        target.unlink()
        target.write_text("user-owned zsh configuration\n")
        protected = [target]
        for name in (".bash_profile", ".profile", ".zprofile", ".zshenv"):
            fixture = self.home / name
            fixture.write_text(f"# user-owned {name}\n")
            protected.append(fixture)
        before = {path: path.read_bytes() for path in protected}
        env = dict(self.env, DOTLINK_HOME=str(self.home), PATH=os.environ["PATH"])
        result = subprocess.run([str(ROOT / "bin/dotlink"), "link", "zsh"], env=env,
                                cwd=ROOT, capture_output=True, text=True, timeout=15)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (1, "dotlink: summary: created=0 unchanged=0 failed=1\n",
                          f"dotlink: conflict: refusing to replace {target}\n"))
        self.assertEqual({path: path.read_bytes() for path in protected}, before)

    def test_relocated_checkout_without_optional_tools(self):
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                out = self.run_shell(shell, f'. "$HOME/.{shell}rc"; printf "%s\\n" "$DOTFILES_ROOT"; type dev >/dev/null; printf "ready\\n"')
                self.assertEqual(out, f"{self.repo}\nready\n")

    def test_machine_environment_is_explicit(self):
        self.env.update(WORKSPACE=str(self.base / "projects"), JAVA_HOME=str(self.base / "jdk"), FLUTTER_HOME=str(self.base / "flutter"), ANDROID_HOME=str(self.base / "android"))
        for path in ("jdk/bin", "flutter/bin", "android/platform-tools", "android/cmdline-tools/latest/bin"):
            (self.base / path).mkdir(parents=True)
        # Source-only baseline also exercises standalone shared environment use.
        (self.home / ".dotfiles").symlink_to(self.repo)
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                out = self.run_shell(shell, f'. "$HOME/.{shell}rc"; printf "%s\\n%s\\n%s\\n" "$WORKSPACE" "$JAVA_HOME" "$PATH"')
                workspace, java, path = out.splitlines()
                self.assertEqual(workspace, self.env["WORKSPACE"])
                self.assertEqual(java, self.env["JAVA_HOME"])
                self.assertNotIn("/home/dniebles", path)
                for suffix in ("jdk/bin", "flutter/bin", "android/platform-tools"):
                    self.assertIn(str(self.base / suffix), path.split(":"))

    def test_existing_go_and_user_integrations(self):
        go = self.home / ".local/go/bin/go"
        go.parent.mkdir(parents=True)
        go.write_text('#!/bin/sh\nprintf "local-go\\n"\n')
        go.chmod(0o755)
        for name, variable in ((".cargo/env", "CARGO_SEEN"), (".nvm/nvm.sh", "NVM_SEEN")):
            target = self.home / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(f"export {variable}=yes\n")
        for shell in ("bash", "zsh"):
            out = self.run_shell(shell, f'. "$HOME/.{shell}rc"; go; printf "%s|%s\\n" "$CARGO_SEEN" "$NVM_SEEN"; alias ll')
            self.assertEqual(out, "local-go\nyes|yes\nll='ls -alF'\n" if shell == "zsh" else "local-go\nyes|yes\nalias ll='ls -alF'\n")
        (self.bin / "go").write_text('#!/bin/sh\nprintf "existing-go\\n"\n')
        (self.bin / "go").chmod(0o755)
        for shell in ("bash", "zsh"):
            self.assertEqual(self.run_shell(shell, f'. "$HOME/.{shell}rc"; go; printf "%s\\n" "${{GOROOT-unset}}"'), "existing-go\nunset\n")

    def test_no_personal_defaults(self):
        (self.home / ".dotfiles").symlink_to(self.repo)
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                out = self.run_shell(shell, f'. "$HOME/.{shell}rc"; printf "%s|%s|%s\\n" "${{WORKSPACE-unset}}" "${{JAVA_HOME-unset}}" "$PATH"')
                workspace, java, path = out.strip().split("|")
                self.assertEqual((workspace, java), ("unset", "unset"))
                self.assertNotIn("/home/dniebles", path)
                self.assertNotIn("/mnt/", path)


if __name__ == "__main__":
    unittest.main()
