"""A different editor must fail before importing or executing the project."""
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def expected_cache_paths(repo_root: Path, version: str):
    if platform.system() == "Darwin":
        plat = "macos.universal"
        rel = Path("Godot.app/Contents/MacOS/Godot")
    else:
        plat = "linux.x86_64" if platform.machine() == "x86_64" else "linux.arm64"
        rel = Path(f"Godot_v{version}-stable_{plat}")
    godot_dir = repo_root / ".cache" / "godot" / version / plat
    return godot_dir, godot_dir / rel


def make_executable(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\nexit 0\n")
    path.chmod(0o755)


class GodotVersionTests(unittest.TestCase):
    def test_wrong_engine_never_runs_project(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            log = root / "calls"
            binary.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALL_LOG"\necho 4.8.stable.official.fixture\n')
            binary.chmod(0o755)
            result = subprocess.run(["bash", "scripts/check_godot.sh"], cwd=ROOT,
                                    env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(log)),
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Godot mismatch", result.stderr)
            self.assertEqual(log.read_text().splitlines(), ["--version"])


class GodotEnvironmentTests(unittest.TestCase):
    def clean_env(self):
        env = dict(os.environ)
        for var in ("GODOT_DIR", "RUNNER_TEMP", "GODOT_CONFIG", "GITHUB_OUTPUT",
                    "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE"):
            env.pop(var, None)
        return env

    def create_worktree_fixture(self, tmp_root: Path):
        main_repo = tmp_root / "main"
        worktree = tmp_root / "wt"
        main_repo.mkdir()
        git_env = self.clean_env()
        subprocess.run(["git", "init", "-q"], cwd=main_repo, env=git_env, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=main_repo, env=git_env, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=main_repo, env=git_env, check=True)
        (main_repo / "README.md").write_text("fixture\n")
        subprocess.run(["git", "add", "README.md"], cwd=main_repo, env=git_env, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=main_repo, env=git_env, check=True)
        subprocess.run(["git", "worktree", "add", "-q", "-b", "wt-branch", str(worktree)],
                       cwd=main_repo, env=git_env, check=True)
        return main_repo.resolve(), worktree.resolve()

    def source_environment(self, cwd: Path, extra_env=None):
        env = self.clean_env()
        env["GODOT_CONFIG"] = str(ROOT / "scripts" / "godot.env")
        if extra_env:
            env.update(extra_env)
        script = (
            'set -euo pipefail\n'
            f'source "{ROOT / "scripts" / "godot_environment.sh"}"\n'
            'printf "%s\\n%s\\n%s\\n" "$GODOT_VERSION" "$GODOT_DIR" "$GODOT_BINARY"\n'
        )
        result = subprocess.run(["bash", "-c", script], cwd=cwd, env=env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        version, godot_dir, godot_binary = result.stdout.splitlines()
        return version, Path(godot_dir), Path(godot_binary)

    def test_worktree_reuses_common_cache_when_local_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            main_repo, worktree = self.create_worktree_fixture(Path(directory).resolve())
            version, _, _ = self.source_environment(worktree)
            common_dir, common_binary = expected_cache_paths(main_repo, version)
            make_executable(common_binary)
            _, godot_dir, godot_binary = self.source_environment(worktree)
            self.assertEqual(godot_dir, common_dir)
            self.assertEqual(godot_binary, common_binary)

    def test_worktree_prefers_local_cache_over_common_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            main_repo, worktree = self.create_worktree_fixture(Path(directory).resolve())
            version, _, _ = self.source_environment(worktree)
            _, common_binary = expected_cache_paths(main_repo, version)
            local_dir, local_binary = expected_cache_paths(worktree, version)
            make_executable(common_binary)
            make_executable(local_binary)
            _, godot_dir, godot_binary = self.source_environment(worktree)
            self.assertEqual(godot_dir, local_dir)
            self.assertEqual(godot_binary, local_binary)

    def test_worktree_keeps_local_default_when_common_binary_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            _, worktree = self.create_worktree_fixture(Path(directory).resolve())
            version, godot_dir, godot_binary = self.source_environment(worktree)
            local_dir, local_binary = expected_cache_paths(worktree, version)
            self.assertEqual(godot_dir, local_dir)
            self.assertEqual(godot_binary, local_binary)

    def test_explicit_godot_dir_or_runner_temp_overrides_common_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            tmp_root = Path(directory).resolve()
            main_repo, worktree = self.create_worktree_fixture(tmp_root)
            version, _, _ = self.source_environment(worktree)
            _, common_binary = expected_cache_paths(main_repo, version)
            make_executable(common_binary)

            custom_dir = tmp_root / "custom-godot"
            _, godot_dir, _ = self.source_environment(worktree, {"GODOT_DIR": str(custom_dir)})
            self.assertEqual(godot_dir, custom_dir)

            runner_temp = tmp_root / "runner-temp"
            _, godot_dir, _ = self.source_environment(worktree, {"RUNNER_TEMP": str(runner_temp)})
            self.assertEqual(godot_dir, runner_temp)

    def test_non_git_directory_falls_back_to_local_default(self):
        with tempfile.TemporaryDirectory() as directory:
            plain_dir = Path(directory).resolve()
            version, godot_dir, godot_binary = self.source_environment(plain_dir)
            local_dir, local_binary = expected_cache_paths(plain_dir, version)
            self.assertEqual(godot_dir, local_dir)
            self.assertEqual(godot_binary, local_binary)


if __name__ == "__main__":
    unittest.main()
