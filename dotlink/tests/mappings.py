#!/usr/bin/env python3
"""Public-interface mapping and best-effort link contracts; no git-history fixtures."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MappingsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        shutil.copytree(ROOT, self.repo, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        self.home = self.root / "home"
        self.home.mkdir()
        self.config = self.repo / "dotlink/modules.conf"
        self.env = dict(os.environ, HOME=str(self.home), DOTLINK_HOME=str(self.home),
                        DOTLINK_REPO_ROOT=str(self.repo), XDG_CONFIG_HOME="")

    def run_cli(self, *args):
        return subprocess.run([str(self.repo / "bin/dotlink"), *args], env=self.env,
                              text=True, capture_output=True)

    def expect(self, args, code=0, out="", err=""):
        result = self.run_cli(*args)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (code, out, err))
        return result

    def snapshot(self, path=None):
        path = path or self.home
        return sorted((str(p.relative_to(path)), "link", os.readlink(p)) if p.is_symlink()
                      else (str(p.relative_to(path)), "dir", "") if p.is_dir()
                      else (str(p.relative_to(path)), "file", p.read_bytes())
                      for p in path.rglob("*"))

    def mapping(self, targets, sources=None, base=None):
        sources = sources or [".bashrc"] * len(targets)
        text = "[module bash]\n"
        for source, target in zip(sources, targets):
            text += f"[link]\nsource = {source}\ntarget = {target}\n"
            if base is not None:
                text += f"base = {base}\n"
        self.config.write_text(text)

    @staticmethod
    def summary(created=0, unchanged=0, failed=0):
        return f"dotlink: summary: created={created} unchanged={unchanged} failed={failed}\n"

    def linked(self, target, source=".bashrc", module="bash"):
        return f"dotlink: linked {self.home / target} -> {self.repo / module / source}\n"

    def assert_link(self, target, source=".bashrc", module="bash", base=None):
        target = (base or self.home) / target
        self.assertTrue(target.is_symlink(), str(target))
        self.assertEqual(os.readlink(target), str(self.repo / module / source))

    def test_bash_mapping_matches_legacy_lifecycle(self):
        original = self.config.read_text()
        self.assertIn("[module bash]", original)
        results = []
        for config in ("", original):
            self.config.write_text(config)
            run = []
            for args in (("status", "bash"), ("verify", "bash"), ("link", "bash"),
                         ("link", "bash"), ("status", "bash"), ("verify", "bash"),
                         ("unlink", "bash")):
                result = self.run_cli(*args)
                run.append((result.returncode, result.stdout, result.stderr, self.snapshot()))
            results.append(run)
        self.assertEqual(results[0], results[1])

    def test_config_mapping_matches_legacy_lifecycle_and_conflicts(self):
        original = self.config.read_text()
        self.assertIn("[module config]\n[link]\nsource = .config/starship.toml\ntarget = .config/starship.toml\n", original)
        self.env["XDG_CONFIG_HOME"] = str(self.root / "custom-xdg")
        runs = []
        for config in ("", original):
            self.config.write_text(config)
            run = []
            for args in (("list", "config"), ("status", "config"), ("verify", "config"),
                         ("link", "config"), ("link", "config"), ("status", "config"),
                         ("verify", "config"), ("unlink", "config")):
                result = self.run_cli(*args)
                run.append((result.returncode, result.stdout, result.stderr, self.snapshot()))
            target = self.home / ".config/starship.toml"
            target.write_text("foreign")
            for command in ("link", "status", "verify", "unlink"):
                result = self.run_cli(command, "config")
                run.append((result.returncode, result.stdout, result.stderr, self.snapshot()))
            target.unlink()
            target.parent.rmdir()
            runs.append(run)
        self.assertEqual(runs[0], runs[1])
        self.assertFalse((self.root / "custom-xdg").exists())

    def test_new_bash_dotfile_requires_explicit_mapping(self):
        (self.repo / "bash/.new-dotfile").write_text("fixture")
        target = self.home / ".new-dotfile"
        self.expect(("link", "bash"), out=self.linked(".bashrc") + self.summary(1))
        self.assertFalse(target.exists())
        self.expect(("status", "bash"), out=f"linked\tbash\t{self.home / '.bashrc'}\n")
        self.expect(("verify", "bash"))
        self.expect(("unlink", "bash"), out=f"dotlink: unlinked {self.home / '.bashrc'}\n")
        self.mapping([".bashrc", ".new-dotfile"], [".bashrc", ".new-dotfile"])
        self.expect(("link", "bash"), out=self.linked(".bashrc") + self.linked(".new-dotfile", ".new-dotfile") + self.summary(2))
        self.assert_link(".new-dotfile", ".new-dotfile")
        self.expect(("status", "bash"), out=f"linked\tbash\t{self.home / '.bashrc'}\nlinked\tbash\t{target}\n")
        self.expect(("verify", "bash"))
        self.expect(("unlink", "bash"), out=f"dotlink: unlinked {self.home / '.bashrc'}\ndotlink: unlinked {target}\n")
        self.assertEqual(self.snapshot(), [])

    def test_agents_full_lifecycle_and_profiles(self):
        parent = self.home / ".agents"
        parent.mkdir()
        (parent / "unmanaged").write_text("keep")
        target, source = parent / "skills", self.repo / "agents/skills"
        self.expect(("link", "agents"), out=self.linked(".agents/skills", "skills", "agents") + self.summary(1))
        self.assert_link(".agents/skills", "skills", "agents")
        self.expect(("link", "agents"), out=self.summary(unchanged=1))
        self.expect(("status", "agents"), out=f"linked\tagents\t{target}\n")
        self.expect(("verify", "agents"))
        self.expect(("list", "--profile", "base"), out="bash\ngit\n")
        self.expect(("list", "--profile", "interactive"), out="bash\ngit\nzsh\nconfig\n")
        self.expect(("unlink", "agents"), out=f"dotlink: unlinked {target}\n")
        self.assertFalse(target.exists())
        self.assertFalse(parent.is_symlink())
        self.assertEqual((parent / "unmanaged").read_text(), "keep")
        self.assertTrue(source.is_dir())

    def test_missing_empty_comment_config_and_absent_module_are_legacy(self):
        for content in (None, "", " \t# comment\r\n\n", "[module git]\n[link]\nsource=.gitconfig\ntarget=.gitconfig\n"):
            with self.subTest(content=content):
                self.config.unlink(missing_ok=True)
                if content is not None:
                    self.config.write_text(content)
                self.expect(("link", "bash"), out=self.linked(".bashrc") + self.summary(1))
                self.assert_link(".bashrc")
                self.expect(("unlink", "bash"), out=f"dotlink: unlinked {self.home / '.bashrc'}\n")
        self.assertEqual(self.snapshot(), [])

    def test_literals_whitespace_crlf_final_line_and_order(self):
        literal = "literal #$*=name"
        (self.repo / "bash" / literal).write_text("fixture")
        self.config.write_bytes((" \t# comment\r\n [module bash] \r\n [link]\r\n"
                                 f" source = {literal} \r\n target=first #$*=name\r\n"
                                 "[link]\r\nsource=.bashrc\r\ntarget=second").encode())
        self.expect(("link", "bash"), out=self.linked("first #$*=name", literal) + self.linked("second") + self.summary(2))
        self.assert_link("first #$*=name", literal)
        self.assert_link("second")

    def test_grammar_failures_are_atomic_even_for_unselected_modules(self):
        cases = [
            ("[link]\n", 1, "", "link outside module"),
            ("[module bash]\n", 1, "bash", "module requires at least one link"),
            ("[module bash]\n[link]\nsource=.bashrc\n", 3, "bash", "link requires source and target"),
            ("source=x\n", 1, "", "property outside link"),
            ("[module nope]\n", 1, "nope", "unknown module"),
            ("[module bash]\n[link]\nsource=.bashrc\ntarget=x\n[module bash]\n", 5, "bash", "duplicate module"),
            ("[module bash\n", 1, "", "malformed header or property"),
        ]
        for key in ("source", "target", "base"):
            cases.append((f"[module bash]\n[link]\n{key}={'home' if key == 'base' else 'x'}\n{key}=x\n", 4, "bash", f"duplicate {key}"))
        for key, value, cause in [
            ("foo", "x", "unknown property"), ("base", "", "invalid base"),
            ("base", "other", "invalid base"),
            *[(field, path, f"invalid {field} path") for field in ("source", "target")
              for path in ("", "/absolute", ".", "..", "./x", "../x", "a/./b", "a/../b", "a/.", "a/..", "a//b", "a/")],
            *[("target", f"x{char}y", "control byte in value") for char in ("\x01", "\t", "\x7f", "\r")],
        ]:
            cases.append((f"[module bash]\n[link]\n{key}={value}\n", 3, "bash", cause))
        for content, line, module, cause in cases:
            with self.subTest(content=content):
                self.config.write_text(content)
                result = self.run_cli("link", "--report=json", "git")
                self.assertEqual(result.returncode, 1)
                prefix = f"{module}: " if module else ""
                self.assertEqual(result.stderr, f"dotlink: {self.config}:{line}: {prefix}{cause}\n")
                report = json.loads(result.stdout)
                self.assertEqual(report, {"schema_version": 1, "modules": ["git"], "status": "failed", "entries": [],
                    "failure": {"module": None, "source": None, "target": None, "cause": {"code": "mapping_error", "message": "invalid mapping configuration"}},
                    "rollback": {"attempted": False, "completed": False, "removed_targets": [], "removed_directories": []}})
                self.assertEqual(self.snapshot(), [])

    def test_invalid_config_rejects_all_lifecycle_commands(self):
        self.config.write_text("[bad]\n")
        for command in ("link", "list", "status", "verify", "unlink"):
            self.expect((command, "bash"), 1, err=f"dotlink: {self.config}:1: malformed header or property\n")
        self.assertEqual(self.snapshot(), [])

    def test_config_type_and_nul_line_diagnostics(self):
        self.config.write_bytes(b"# first\n# bad\x00comment\n")
        self.expect(("link", "bash"), 1, err=f"dotlink: {self.config}:2: NUL byte in configuration\n")
        self.config.unlink()
        self.config.mkdir()
        message = f"dotlink: {self.config}:0: configuration must be a real readable regular file\n"
        self.expect(("link", "bash"), 1, err=message)
        self.config.rmdir()
        for destination in ("missing", str(self.repo / "profiles/base.sh")):
            self.config.symlink_to(destination)
            self.expect(("link", "bash"), 1, err=message)
            self.config.unlink()
        self.assertEqual(self.snapshot(), [])

    def test_unreadable_config(self):
        if os.geteuid() == 0:
            self.skipTest("root bypasses file read permissions")
        self.config.chmod(0)
        self.addCleanup(self.config.chmod, 0o644)
        self.expect(("link", "bash"), 1, err=f"dotlink: {self.config}:0: configuration must be a real readable regular file\n")
        self.assertEqual(self.snapshot(), [])

    def test_explicit_conflicts_continue_and_retain_first_failure(self):
        for failures in (("one",), ("two",), ("one", "three"), ("one", "two", "three")):
            with self.subTest(failures=failures):
                self.mapping(["one", "two", "three"])
                for target in self.home.iterdir():
                    target.unlink()
                for target in failures:
                    (self.home / target).write_text("foreign")
                result = self.run_cli("link", "--report=json", "bash")
                self.assertEqual(result.returncode, 1)
                report = json.loads(result.stdout)
                self.assertEqual(report["status"], "failed")
                self.assertEqual(report["failure"]["target"], str(self.home / failures[0]))
                expected_err = ""
                for target, entry in zip(("one", "two", "three"), report["entries"]):
                    path = self.home / target
                    if target in failures:
                        expected_err += f"dotlink: conflict: refusing to replace {path}\n"
                        self.assertEqual(entry["outcome"], "failed")
                        self.assertEqual(entry["cause"]["code"], "conflict")
                        self.assertEqual(path.read_text(), "foreign")
                    else:
                        expected_err += self.linked(target)
                        self.assertEqual(entry["outcome"], "changed")
                        self.assert_link(target)
                self.assertEqual(len(report["entries"]), 3)
                self.assertEqual(result.stderr, expected_err + self.summary(3-len(failures), failed=len(failures)))
                self.assertEqual(report["rollback"], {"attempted": False, "completed": False, "removed_targets": [], "removed_directories": []})
                before = self.snapshot()
                retry = self.run_cli("link", "--report=json", "bash")
                self.assertEqual(retry.returncode, 1)
                retry_report = json.loads(retry.stdout)
                self.assertEqual([e["outcome"] for e in retry_report["entries"]],
                                 ["failed" if target in failures else "unchanged" for target in ("one", "two", "three")])
                self.assertEqual(retry.stderr, "".join(f"dotlink: conflict: refusing to replace {self.home / target}\n" for target in failures) + self.summary(unchanged=3-len(failures), failed=len(failures)))
                self.assertEqual(self.snapshot(), before)

    def test_legacy_failure_continues_into_later_modules(self):
        (self.home / ".bashrc").write_text("foreign")
        self.expect(("link", "bash", "git", "zsh"), 1,
                    self.linked(".gitconfig", ".gitconfig", "git") + self.linked(".zshrc", ".zshrc", "zsh") + self.summary(2, failed=1),
                    f"dotlink: conflict: refusing to replace {self.home / '.bashrc'}\n")
        self.assertEqual((self.home / ".bashrc").read_text(), "foreign")
        self.assert_link(".gitconfig", ".gitconfig", "git")
        self.assert_link(".zshrc", ".zshrc", "zsh")

    def test_invalid_source_does_not_drop_following_entries(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "file").write_text("foreign")
        for source in ("absent", "alias", "escape/file", "inside/file"):
            with self.subTest(source=source):
                alias = self.repo / "bash/alias"
                if not alias.is_symlink():
                    alias.symlink_to(".bashrc")
                    (self.repo / "bash/escape").symlink_to(outside, target_is_directory=True)
                    (self.repo / "bash/inside").symlink_to("../git", target_is_directory=True)
                self.mapping(["bad", "good"], [source, ".bashrc"])
                self.expect(("link", "bash"), 1, self.linked("good") + self.summary(1, failed=1),
                            f"dotlink: {self.config}:2: bash: invalid source\n")
                self.assert_link("good")
                (self.home / "good").unlink()
                self.assertEqual(self.snapshot(), [])
                self.assertEqual((outside / "file").read_text(), "foreign")

    def test_xdg_base_defaults_and_selected_only_validation(self):
        self.mapping(["snippet"], base="xdg_config")
        self.env["XDG_CONFIG_HOME"] = "relative"
        self.expect(("link", "git"), out=self.linked(".gitconfig", ".gitconfig", "git") + self.summary(1))
        self.expect(("link", "bash"), 1, self.summary(failed=1), "dotlink: mapping base must be an absolute path: relative\n")
        self.env["XDG_CONFIG_HOME"] = ""
        self.expect(("link", "bash"), out=f"dotlink: linked {self.home / '.config/snippet'} -> {self.repo / 'bash/.bashrc'}\n" + self.summary(1))
        self.assert_link(".config/snippet")
        xdg = self.root / "external xdg"
        self.env["XDG_CONFIG_HOME"] = str(xdg)
        self.expect(("link", "bash"), out=f"dotlink: linked {xdg / 'snippet'} -> {self.repo / 'bash/.bashrc'}\n" + self.summary(1))
        self.assert_link("snippet", base=xdg)
        self.mapping(["home-default"])
        self.expect(("link", "bash"), out=self.linked("home-default") + self.summary(1))
        self.assert_link("home-default")

    def test_invalid_environment_roots_never_corrupt_inventory(self):
        for key, value in (("DOTLINK_HOME", "relative"), ("DOTLINK_HOME", str(self.home) + "\tbad"),
                           ("XDG_CONFIG_HOME", str(self.home) + "\nbad")):
            with self.subTest(key=key):
                self.mapping(["item"], base="xdg_config" if key == "XDG_CONFIG_HOME" else "home")
                env = self.env.copy()
                env[key] = value
                result = subprocess.run([str(self.repo / "bin/dotlink"), "link", "bash"], env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, self.summary(failed=1))
                expected = f"dotlink: mapping base must be an absolute path: {value}\n" if value == "relative" else "dotlink: mapping base contains control bytes\n"
                self.assertEqual(result.stderr, expected)
                self.assertEqual(self.snapshot(), [])

    def test_target_parents_are_real_and_read_only_commands_do_not_write(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.home / ".agents").symlink_to(outside, target_is_directory=True)
        target = self.home / ".agents/skills"
        before = self.snapshot()
        self.expect(("status", "agents"), 1, f"conflict\tagents\t{target}\n")
        self.expect(("verify", "agents"), 1, f"conflict\tagents\t{target}\n")
        self.expect(("unlink", "agents"), 1, err=f"dotlink: conflict: refusing to unlink {target}\n")
        self.expect(("link", "agents"), 1, self.summary(failed=1), f"dotlink: conflict: parent is not a real directory: {self.home / '.agents'}\n")
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.snapshot(outside), [])

    def test_duplicate_targets_inside_a_module_are_a_parse_error(self):
        # A present invalid file is rejected for every command, including modules
        # the command did not select, and the diagnostic names the parser cause.
        config = "[module agents]\n[link]\nsource=skills\ntarget=.agents/skills\n[link]\nsource=skills\ntarget=.agents/skills\n"
        self.config.write_text(config)
        for args in (("link", "git"), ("list",), ("list", "git"), ("link", "agents"),
                     ("status", "agents"), ("verify", "agents"), ("unlink", "agents")):
            with self.subTest(args=args):
                self.expect(args, 1, err=f"dotlink: {self.config}:7: agents: duplicate target\n")
                self.assertEqual(self.snapshot(), [])
        self.config.write_text(
            "[module agents]\n[link]\nsource=skills\ntarget=.agents\n[link]\nsource=skills\ntarget=.agents/skills\n")
        self.expect(("list",), 1, err=f"dotlink: {self.config}:7: agents: nested target\n")
        self.assertEqual(self.snapshot(), [])

    def test_duplicates_and_overlaps_across_explicit_and_legacy_are_atomic(self):
        for target in (".bashrc", ".bashrc/child"):
            self.config.write_text(f"[module git]\n[link]\nsource=.gitconfig\ntarget={target}\n")
            self.expect(("link", "bash", "git"), 1,
                        err=f"dotlink: overlapping targets: {self.home / '.bashrc'} and {self.home / target}\n")
            self.assertEqual(self.snapshot(), [])
        self.mapping(["same", "same"])
        self.expect(("link", "bash"), 1, err=f"dotlink: {self.config}:7: bash: duplicate target\n")
        self.assertEqual(self.snapshot(), [])

    def test_repeated_module_arguments_keep_legacy_behaviour(self):
        self.config.unlink()
        self.expect(("link", "bash", "bash"), out=self.linked(".bashrc") + self.summary(1))
        self.assert_link(".bashrc")
        self.expect(("status", "bash", "bash"), out=f"linked\tbash\t{self.home / '.bashrc'}\n" * 2)
        self.expect(("verify", "bash", "bash"))
        self.expect(("unlink", "bash", "bash"), out=f"dotlink: unlinked {self.home / '.bashrc'}\n")
        self.assertEqual(self.snapshot(), [])
        self.expect(("link", "bash", "git", "bash"), out=self.linked(".bashrc") + self.linked(".gitconfig", ".gitconfig", "git") + self.summary(2))
        self.assert_link(".bashrc")
        self.assert_link(".gitconfig", ".gitconfig", "git")

    def test_repeated_profile_and_explicit_module_are_not_ambiguous(self):
        self.mapping(["one", "two"])
        (self.repo / "profiles/repeated.sh").write_text('DOTLINK_PROFILE_MODULES=(bash git bash)\n')
        self.expect(("link", "--profile", "repeated"), out=self.linked("one") + self.linked("two") + self.linked(".gitconfig", ".gitconfig", "git") + self.summary(3))
        self.expect(("link", "bash", "bash"), out=self.summary(unchanged=2))
        for name in ("one", "two"):
            self.assert_link(name)

    def test_base_resolution_failure_does_not_abort_other_modules(self):
        self.config.unlink()
        self.env["XDG_CONFIG_HOME"] = "relative"
        self.expect(("link", "bash", "fish", "git"), 1,
                    self.linked(".bashrc") + self.linked(".gitconfig", ".gitconfig", "git") + self.summary(2, failed=1),
                    "dotlink: XDG_CONFIG_HOME must be an absolute path\n")
        self.assert_link(".bashrc")
        self.assert_link(".gitconfig", ".gitconfig", "git")
        self.expect(("status", "bash", "fish"), 1, f"linked\tbash\t{self.home / '.bashrc'}\n",
                    "dotlink: XDG_CONFIG_HOME must be an absolute path\n")
        self.expect(("verify", "bash", "fish"), 1, err="dotlink: XDG_CONFIG_HOME must be an absolute path\n")
        self.expect(("unlink", "bash", "fish"), 1, f"dotlink: unlinked {self.home / '.bashrc'}\n",
                    "dotlink: XDG_CONFIG_HOME must be an absolute path\n")
        self.assertFalse((self.home / ".bashrc").exists())

    def test_explicit_base_error_continues_same_module_and_json_reports_it(self):
        self.config.write_text('[module bash]\n[link]\nsource=.bashrc\ntarget=bad\nbase=xdg_config\n[link]\nsource=.bashrc\ntarget=good\n')
        self.env["XDG_CONFIG_HOME"] = "relative"
        result = self.run_cli("link", "--report=json", "bash", "git")
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertEqual(report["status"], "failed")
        self.assertEqual([entry["outcome"] for entry in report["entries"]], ["failed", "changed", "changed"])
        self.assertEqual(report["failure"]["cause"], {"code": "invalid_base", "message": "mapping base must be an absolute path: relative"})
        self.assertIsNone(report["failure"]["target"])
        self.assertEqual(result.stderr, "dotlink: mapping base must be an absolute path: relative\n" + self.linked("good") + self.linked(".gitconfig", ".gitconfig", "git") + self.summary(2, failed=1))
        self.assert_link("good")
        self.assert_link(".gitconfig", ".gitconfig", "git")

    def test_sibling_prefixes_are_not_overlaps(self):
        self.mapping(["ab", "abc", "a.b", "a"])
        self.expect(("link", "bash"), out="".join(self.linked(name) for name in ("ab", "abc", "a.b", "a")) + self.summary(4))
        for name in ("ab", "abc", "a.b", "a"):
            self.assert_link(name)

    def test_failed_entry_cleanup_preserves_successes_and_continues(self):
        self.mapping(["kept/item", "bad/item", "later/item"])
        stubs = self.root / "stubs"
        stubs.mkdir()
        real_ln = shlex.quote(shutil.which("ln"))
        stub = stubs / "ln"
        stub.write_text(f'#!/bin/sh\ncase "$3" in */bad/item) exit 1;; esac\nexec {real_ln} "$@"\n')
        stub.chmod(0o755)
        self.env["PATH"] = str(stubs) + os.pathsep + self.env["PATH"]
        result = self.run_cli("link", "--report=json", "bash")
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertEqual([e["outcome"] for e in report["entries"]], ["changed", "failed", "changed"])
        self.assertEqual(report["failure"]["cause"], {"code": "link_error", "message": f"unable to link {self.home / 'bad/item'} to {self.repo / 'bash/.bashrc'}"})
        self.assertEqual(report["rollback"], {"attempted": True, "completed": True, "removed_targets": [], "removed_directories": [str(self.home / "bad")]})
        self.assertEqual(result.stderr, self.linked("kept/item") + f"dotlink: unable to link {self.home / 'bad/item'} to {self.repo / 'bash/.bashrc'}\n" + self.linked("later/item") + self.summary(2, failed=1))
        self.assert_link("kept/item")
        self.assert_link("later/item")
        self.assertFalse((self.home / "bad").exists())


class UnlinkReachabilityTest(unittest.TestCase):
    """unlink must remove repository-owned symlinks it can prove it owns (#31)."""

    # Reuse the fixture without inheriting its tests, which unittest collects
    # from any TestCase subclass.
    setUp = MappingsTest.setUp
    run_cli = MappingsTest.run_cli
    expect = MappingsTest.expect
    snapshot = MappingsTest.snapshot
    mapping = MappingsTest.mapping
    summary = staticmethod(MappingsTest.summary)
    linked = MappingsTest.linked
    assert_link = MappingsTest.assert_link

    def test_status_verify_deleted_explicit_source_report_owned_orphan(self):
        self.mapping([".bashrc"])
        self.expect(("link", "bash"), out=self.linked(".bashrc") + self.summary(1))
        source = self.repo / "bash/.bashrc"
        source.rename(self.root / "moved-bashrc")
        before = self.snapshot()
        for command in ("status", "verify"):
            with self.subTest(command=command):
                self.expect((command, "bash"), 1,
                            f"drift\torphan\t{self.home / '.bashrc'}\n",
                            f"dotlink: {self.config}:2: bash: invalid source\n")
                self.assertEqual(self.snapshot(), before)

    def test_invalid_explicit_source_preserves_conflicts(self):
        self.mapping([".bashrc"], ["absent"])
        target = self.home / ".bashrc"
        for kind in ("file", "foreign-link"):
            with self.subTest(kind=kind):
                if kind == "file":
                    target.write_text("foreign")
                else:
                    target.symlink_to(self.root / "missing")
                before = self.snapshot()
                for command in ("status", "verify"):
                    self.expect((command, "bash"), 1,
                                f"conflict\tbash\t{target}\n",
                                f"dotlink: {self.config}:2: bash: invalid source\n")
                    self.assertEqual(self.snapshot(), before)
                target.unlink()

    def test_unlink_removes_link_after_source_disappears(self):
        self.expect(("link", "agents"), out=self.linked(".agents/skills", "skills", "agents") + self.summary(1))
        target = self.home / ".agents/skills"
        source = self.repo / "agents/skills"
        shutil.move(str(source), str(self.root / "moved-skills"))
        # Ownership, not source existence, authorizes removal.
        self.expect(("unlink", "agents"), out=f"dotlink: unlinked {target}\n")
        self.assertFalse(target.is_symlink())
        self.assertFalse(target.exists())

    def test_status_and_verify_fail_for_a_known_module_without_entries(self):
        self.config.unlink(missing_ok=True)
        for command in ("status", "verify"):
            with self.subTest(command=command):
                result = self.run_cli(command, "agents")
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr,
                                 f"dotlink: {self.repo}/agents: no entries discovered; declare explicit mappings or add dot entries\n")
        # link and unlink keep their historical best-effort behaviour.
        self.expect(("link", "agents"), out=self.summary())
        self.expect(("list", "agents"), out="agents\n")
        self.assertEqual(self.snapshot(), [])

    def test_unlink_removes_repo_owned_link_the_selection_cannot_describe(self):
        self.expect(("link", "agents"), out=self.linked(".agents/skills", "skills", "agents") + self.summary(1))
        target = self.home / ".agents/skills"
        # Dropping the declaration leaves a functional repository-owned link that
        # legacy discovery cannot describe; it must still be removable.
        self.config.unlink()
        self.expect(("unlink", "agents"), out=f"dotlink: unlinked orphaned {target}\n")
        self.assertFalse(target.is_symlink())
        self.assertEqual((self.home / ".agents").is_dir(), (self.home / ".agents").exists())

    def test_unlink_never_touches_foreign_links_or_files(self):
        foreign_target = self.root / "foreign.txt"
        foreign_target.write_text("keep")
        foreign_link = self.home / ".agents/skills"
        (self.home / ".agents").mkdir()
        foreign_link.symlink_to(foreign_target)
        plain_dir = self.home / ".plain"
        plain_dir.mkdir()

        def assert_untouched():
            self.assertTrue(foreign_link.is_symlink())
            self.assertEqual(os.readlink(foreign_link), str(foreign_target))
            self.assertTrue(plain_dir.is_dir())
            self.assertEqual(foreign_target.read_text(), "keep")

        # Declared but foreign: refuse and report, never remove.
        result = self.run_cli("unlink", "agents")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr,
                         f"dotlink: conflict: refusing to unlink {foreign_link}\n")
        assert_untouched()

        # Undeclared: dotlink has no claim on this path and stays silent.
        self.config.unlink()
        for args in (("unlink", "agents"), ("unlink",)):
            with self.subTest(args=args):
                result = self.run_cli(*args)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))
                assert_untouched()


if __name__ == "__main__":
    unittest.main()