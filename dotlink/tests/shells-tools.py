#!/usr/bin/env python3
"""Isolated Bash/Zsh integration tests using real optional tools."""
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
CORE_TOOLS = ("uname", "grep", "mkdir", "readlink", "dirname", "sort", "find", "dircolors",
              "cat", "sed", "tr", "rm", "mv", "chmod", "touch", "pwd", "cut", "head", "tail")


class ToolStartup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dotfiles-shell-tools-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.repo = self.base / "checkout"
        self.home.mkdir()
        for name in ("bash", "zsh", "env", "linux", "wsl"):
            shutil.copytree(ROOT / name, self.repo / name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.no_tools = self.base / "no-tools"
        self.no_tools.mkdir()
        self.available = {}
        for name in ("mise", "zoxide", "starship"):
            tool = shutil.which(name)
            self.available[name] = tool
            if tool:
                (self.bin / name).symlink_to(tool)
        for name in CORE_TOOLS:
            tool = shutil.which(name)
            if tool:
                (self.bin / name).symlink_to(tool)
                (self.no_tools / name).symlink_to(tool)
        self.home.joinpath(".bashrc").symlink_to(self.repo / "bash/.bashrc")
        self.home.joinpath(".zshrc").symlink_to(self.repo / "zsh/.zshrc")
        self.local_bin = self.home / ".local/bin"
        self.local_bin.mkdir(parents=True)
        self.competitor = self.local_bin / "node"
        self.competitor.write_text("#!/bin/sh\nprintf 'FOREIGN\\n'\n")
        self.competitor.chmod(0o755)
        self.proj_a, self.proj_b = self.base / "A", self.base / "B"
        for project, label in ((self.proj_a, "A"), (self.proj_b, "B")):
            toolbin = self.base / f"tool{label}" / "bin"
            toolbin.mkdir(parents=True)
            project.mkdir()
            node = toolbin / "node"
            node.write_text(f"#!/bin/sh\nprintf '{label}\\n'\n")
            node.chmod(0o755)
            (project / "mise.toml").write_text(
                f'[tools]\nnode = "path:{toolbin.parent}"\n[env]\nDIAG_PROJECT = "{label}"\n')
        self.nvm_bin = self.home / ".nvm/bin"
        self.nvm_bin.mkdir(parents=True)
        nvm_node = self.nvm_bin / "node"
        nvm_node.write_text("#!/bin/sh\nprintf 'NVM\\n'\n")
        nvm_node.chmod(0o755)
        (self.home / ".nvm/nvm.sh").write_text(
            'export NVM_LOADS=$(( ${NVM_LOADS:-0} + 1 ))\n'
            'PATH="$NVM_DIR/bin:$PATH"; export PATH\n'
            'nvm() { :; }\n')
        (self.home / ".nvm/bash_completion").write_text(
            'export NVM_COMPLETIONS=$(( ${NVM_COMPLETIONS:-0} + 1 ))\n'
            '__nvm() { :; }\n')
        self.base_env = {
            "HOME": str(self.home), "PATH": f"{self.bin}:/usr/bin:/bin", "TERM": "xterm-256color",
            "ZDOTDIR": str(self.home), "HISTFILE": "/dev/null", "TMPDIR": str(self.base),
            "XDG_CONFIG_HOME": str(self.base / "config"), "XDG_DATA_HOME": str(self.base / "data"),
            "XDG_CACHE_HOME": str(self.base / "cache"), "XDG_STATE_HOME": str(self.base / "state"),
            "MISE_CONFIG_FILE": str(self.base / "config/mise/config.toml"),
            "MISE_DATA_DIR": str(self.base / "data/mise"), "MISE_CACHE_DIR": str(self.base / "cache/mise"),
            "MISE_STATE_DIR": str(self.base / "state/mise"), "MISE_OFFLINE": "true", "MISE_AUTO_INSTALL": "false",
            "MISE_TRUSTED_CONFIG_PATHS": f"{self.proj_a}:{self.proj_b}", "_ZO_DOCTOR": "0",
            "_ZO_DATA_DIR": str(self.base / "zoxide"),
        }
        Path(self.base_env["MISE_CONFIG_FILE"]).parent.mkdir(parents=True)
        Path(self.base_env["MISE_CONFIG_FILE"]).touch()
        Path(self.base_env["_ZO_DATA_DIR"]).mkdir()

    def require_tools(self, *names):
        missing = [name for name in names if not self.available[name]]
        if missing:
            self.skipTest("required real tools unavailable: " + ", ".join(missing))

    def run_shell(self, shell, code, path=None):
        executable = shutil.which(shell)
        self.assertIsNotNone(executable, f"required test shell unavailable: {shell}")
        args = [executable, "--noprofile", "--norc"] if shell == "bash" else [executable, "-d", "-f"]
        args += ["-ic", code]
        env = dict(self.base_env)
        if path is not None:
            env["PATH"] = path
        master, slave = pty.openpty()
        def attach_tty():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        try:
            result = subprocess.run(args, cwd=self.home, env=env, text=True, capture_output=True,
                                    stdin=slave, timeout=20, preexec_fn=attach_tty)
        finally:
            os.close(slave)
            os.close(master)
        return result.returncode, result.stdout, result.stderr

    def assert_run(self, shell, code, expected, path=None):
        status, stdout, stderr = self.run_shell(shell, code, path)
        self.assertEqual((status, stdout, stderr), (0, expected, ""))

    def test_absent_tools_really_are_absent_from_allowlist_path(self):
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                rc = str(self.repo / ("bash/.bashrc" if shell == "bash" else "zsh/.zshrc"))
                checks = " ".join(f"command -v {name} >/dev/null && echo {name}-present || :;" for name in ("mise", "zoxide", "starship"))
                code = f"source '{rc}'; source '{rc}'; {checks} printf 'ready\\n'"
                self.assert_run(shell, code, "ready\n", path=str(self.no_tools))

    def test_real_mise_and_zoxide_reload_precedence_and_hook_counts(self):
        self.require_tools("mise", "zoxide")
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                rc = str(self.repo / ("bash/.bashrc" if shell == "bash" else "zsh/.zshrc"))
                if shell == "bash":
                    counts_before = "printf 'before:%s:%s\\n' \"$(declare -p PROMPT_COMMAND | grep -o '__zoxide_hook' | wc -l)\" \"$(declare -p PROMPT_COMMAND | grep -o '_mise_hook_prompt_command' | wc -l)\"; "
                    hooks = ("printf 'counts:%s:%s\\n' \"$(declare -p PROMPT_COMMAND | grep -o '__zoxide_hook' | wc -l)\" "
                             "\"$(declare -p PROMPT_COMMAND | grep -o '_mise_hook_prompt_command' | wc -l)\"; "
                             "if declare -p PROMPT_COMMAND | grep -q 'declare -a'; then "
                             "for h in \"${PROMPT_COMMAND[@]}\"; do \"$h\"; done; else eval \"$PROMPT_COMMAND\"; fi;")
                else:
                    counts_before = "printf 'before:%s:%s\\n' \"$(print -l -- $precmd_functions | grep -xc _mise_hook_precmd)\" \"$(print -l -- $chpwd_functions | grep -xc __zoxide_hook)\"; "
                    hooks = ("printf 'counts:%s:%s\\n' \"$(print -l -- $precmd_functions | grep -xc _mise_hook_precmd)\" "
                             "\"$(print -l -- $chpwd_functions | grep -xc __zoxide_hook)\"; "
                             "for h in $precmd_functions; do $h; done; ")
                code = (f"cd '{self.proj_a}'; source '{rc}'; "
                        f"printf 'first:%s:%s\\n' \"$(command node)\" \"$DIAG_PROJECT\"; {counts_before}"
                        f"path_prepend '{self.local_bin}'; cd '{self.proj_b}'; source '{rc}'; "
                        f"printf 'reload:%s:%s\\n' \"$(command node)\" \"$DIAG_PROJECT\"; {hooks} "
                        f"printf 'after:%s:%s\\n' \"$(command node)\" \"$DIAG_PROJECT\"; "
                        f"cd '{self.proj_a}'; printf 'back:%s:%s\\n' \"$(command node)\" \"$DIAG_PROJECT\"; "
                        f"printf 'zoxide:%s\\n' \"$(zoxide query --list | grep -Fx '{self.proj_b}' >/dev/null && echo learned || echo missing)\"")
                expected = "first:A:A\nbefore:1:1\nreload:B:B\ncounts:1:1\nafter:B:B\nback:A:A\nzoxide:learned\n"
                self.assert_run(shell, code, expected)

    def test_prior_activation_marker_prompt_and_real_starship_hooks(self):
        self.require_tools("mise", "zoxide", "starship")
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                rc = str(self.repo / ("bash/.bashrc" if shell == "bash" else "zsh/.zshrc"))
                if shell == "bash":
                    code = (f"MISE_SHELL=bash; export MISE_SHELL; source '{rc}'; "
                            "PS1='user-prompt> '; prior_count=0; prior_prompt() { prior_count=$((prior_count+1)); }; "
                            "PROMPT_COMMAND=prior_prompt; source \"" + rc + "\"; "
                            "eval \"$PROMPT_COMMAND\"; printf 'state:%s:%s:%s\\n' \"$PS1\" \"$prior_count\" \"$(declare -F _mise_hook >/dev/null && echo mise || echo absent)\"")
                    expected = "state:user-prompt> :1:mise\n"
                else:
                    code = (f"MISE_SHELL=zsh; export MISE_SHELL; source '{rc}'; "
                            "prior_count=0; prior_prompt() { (( prior_count++ )); }; "
                            "autoload -Uz add-zsh-hook; add-zsh-hook precmd prior_prompt; source \"" + rc + "\"; "
                            "for h in $precmd_functions; do $h; done; "
                            "printf 'state:%s:%s:%s:%s\\n' \"$prior_count\" "
                            "\"$(print -l -- $precmd_functions | grep -xc _mise_hook_precmd)\" "
                            "\"$(print -l -- $precmd_functions | grep -xc prompt_starship_precmd)\" "
                            "\"$(print -l -- $chpwd_functions | grep -xc __zoxide_hook)\"")
                    expected = "state:1:1:1:1\n"
                self.assert_run(shell, code, expected)

    def test_synthetic_nvm_and_completion_load_once_on_reload(self):
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                rc = str(self.repo / ("bash/.bashrc" if shell == "bash" else "zsh/.zshrc"))
                code = (f"source '{rc}'; source '{rc}'; "
                        "printf 'counts:%s:%s:%s\\n' \"$NVM_LOADS\" \"$NVM_COMPLETIONS\" "
                        "\"$(typeset -f __nvm >/dev/null && echo present || echo absent)\"")
                self.assert_run(shell, code, "counts:1:1:present\n")

    def test_actual_prior_mise_activation_is_reconciled_on_reload(self):
        self.require_tools("mise", "zoxide")
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                rc = str(self.repo / ("bash/.bashrc" if shell == "bash" else "zsh/.zshrc"))
                if shell == "bash":
                    prior = ("prior_count=0; prior_prompt() { prior_count=$((prior_count+1)); }; "
                             "PROMPT_COMMAND=prior_prompt; eval \"$(mise activate bash)\"; ")
                    cycle = ("if declare -p PROMPT_COMMAND | grep -q 'declare -a'; then "
                             "for h in \"${PROMPT_COMMAND[@]}\"; do \"$h\"; done; "
                             "else eval \"$PROMPT_COMMAND\"; fi; ")
                    prompt = "\"$prior_count\""
                    final_state = ("printf 'hooks:%s:%s:%s:%s:%s:%s\\n' "
                                   "\"$(declare -p PROMPT_COMMAND | grep -o '_mise_hook_prompt_command' | wc -l)\" "
                                   "\"$(declare -p PROMPT_COMMAND | grep -o '__zoxide_hook' | wc -l)\" "
                                   "\"$prior_count\" \"$(declare -F nvm >/dev/null && echo nvm || echo missing)\" "
                                   f"\"$(case \":$PATH:\" in *\":{self.local_bin}:\"*) echo local;; *) echo missing;; esac)\" "
                                   f"\"$(case \":$PATH:\" in *\":{self.nvm_bin}:\"*) echo nvm-path;; *) echo missing;; esac)\"")
                else:
                    prior = ("prior_count=0; prior_prompt() { (( prior_count++ )); }; "
                             "autoload -Uz add-zsh-hook; add-zsh-hook precmd prior_prompt; "
                             "eval \"$(mise activate zsh)\"; ")
                    cycle = "for h in $precmd_functions; do $h; done; "
                    prompt = "\"$prior_count\""
                    final_state = ("printf 'hooks:%s:%s:%s:%s:%s:%s\\n' "
                                   "\"$(print -l -- $precmd_functions | grep -xc _mise_hook_precmd)\" "
                                   "\"$(print -l -- $chpwd_functions | grep -xc __zoxide_hook)\" "
                                   "\"$prior_count\" \"$( (( $+functions[nvm] )) && print nvm || print missing )\" "
                                   f"\"$(case \":$PATH:\" in *\":{self.local_bin}:\"*) echo local;; *) echo missing;; esac)\" "
                                   f"\"$(case \":$PATH:\" in *\":{self.nvm_bin}:\"*) echo nvm-path;; *) echo missing;; esac)\"")
                nvm_init = f"source '{self.repo / 'env/nvm'}'; "
                competitor_path = f"PATH='{self.local_bin}:{self.nvm_bin}:'\"$PATH\"; export PATH; "
                code = (f"cd '{self.proj_a}'; {nvm_init}{prior}{competitor_path}"
                        f"printf 'prior:%s:%s\\n' \"$(command node)\" \"$DIAG_PROJECT\"; "
                        f"source '{rc}'; source '{rc}'; {cycle}"
                        f"printf 'A:%s:%s:%s:%s\\n' \"$(command node)\" \"$DIAG_PROJECT\" \"$NVM_LOADS\" {prompt}; "
                        f"cd '{self.proj_b}'; {competitor_path}source '{rc}'; source '{rc}'; {cycle}"
                        f"printf 'B:%s:%s:%s:%s\\n' \"$(command node)\" \"$DIAG_PROJECT\" \"$NVM_LOADS\" {prompt}; "
                        f"cd '{self.proj_a}'; {competitor_path}source '{rc}'; source '{rc}'; {cycle}"
                        f"printf 'A:%s:%s:%s:%s\\n' \"$(command node)\" \"$DIAG_PROJECT\" \"$NVM_LOADS\" {prompt}; "
                        f"{final_state}")
                expected = "prior:FOREIGN:A\nA:A:A:1:1\nB:B:B:1:2\nA:A:A:1:3\nhooks:1:1:3:nvm:local:nvm-path\n"
                self.assert_run(shell, code, expected)

    def test_synthetic_nvm_reload_does_not_win_over_project_mise(self):
        self.require_tools("mise")
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                rc = str(self.repo / ("bash/.bashrc" if shell == "bash" else "zsh/.zshrc"))
                code = (f"cd '{self.proj_a}'; source '{rc}'; "
                        f"path_prepend '{self.nvm_bin}'; source '{rc}'; "
                        "printf 'node:%s:%s loads:%s\\n' \"$(command node)\" \"$DIAG_PROJECT\" \"$NVM_LOADS\"")
                self.assert_run(shell, code, "node:A:A loads:1\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
