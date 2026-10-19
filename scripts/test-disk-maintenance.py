#!/usr/bin/env python3
"""Testa a fronteira destrutiva em home isolado, sem acessar o store real."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'dot_local/bin/executable_disk-maintenance'


class MaintenanceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.log = self.home / 'calls'
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        XDG_CACHE_HOME=str(self.home / '.cache'),
                        XDG_STATE_HOME=str(self.home / '.local/state'),
                        XDG_CONFIG_HOME=str(self.home / '.config'),
                        TEST_LOG=str(self.log), TEST_USED='30', TEST_FREE='100000000',
                        TEST_FAIL='0', TEST_BUSY='1')
        self.fake('podman', '''if [[ $1 == info ]]; then echo "$HOME/store"; exit; fi
printf 'podman %s\\n' "$*" >> "$TEST_LOG"
exit "$TEST_FAIL"''')
        self.fake('df', '''printf 'Filesystem 1024-blocks Used Available Capacity Mounted\\n'
printf 'test 100000000 1 %s %s%% /\\n' "$TEST_FREE" "$TEST_USED"''')
        self.fake('uv', 'printf "uv %s\\n" "$*" >> "$TEST_LOG"')
        self.fake('notify-send', 'echo notify >> "$TEST_LOG"')
        self.fake('pgrep', 'exit "$TEST_BUSY"')
        (self.home / 'store').mkdir()

    def fake(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\nset -euo pipefail\n' + body + '\n')
        path.chmod(0o755)

    def file(self, name, days):
        path = self.home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('preserve or regenerate')
        stamp = time.time() - days * 86400
        os.utime(path, (stamp, stamp))
        return path

    def run_script(self, *args):
        return subprocess.run(['bash', str(SCRIPT), *args], env=self.env,
                              text=True, capture_output=True, timeout=15)

    def calls(self):
        return self.log.read_text() if self.log.exists() else ''

    def test_dry_run_never_changes_data_or_state(self):
        old = self.file('.cache/go-build/old', 10)
        result = self.run_script('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(old.exists())
        self.assertFalse((self.home / '.local/state').exists())
        self.assertEqual(self.calls(), '')
        self.assertIn('until=72h', result.stdout)

    def test_regular_cleanup_preserves_data_and_hot_files(self):
        old = self.file('.cache/go-build/old', 10)
        protected = [self.file(name, days) for name, days in [
            ('.cache/go-build/recent', 2), ('.cache/claude-t3/state.sqlite', 100),
            ('.cache/codex-runtimes/runtime', 100), ('Backups/archive.zip', 100),
            ('.codex/sessions/history', 100), ('Repos/app/source', 100)]]
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(old.exists())
        self.assertTrue(all(p.exists() for p in protected))
        self.assertIn('image prune --all --force --filter until=72h', self.calls())
        self.assertIn('label!=disk-maintenance.keep=true', self.calls())
        for forbidden in ['volume prune', 'container prune', 'system prune', '--external', '--build-cache']:
            self.assertNotIn(forbidden, self.calls())
        self.assertIn('uv cache prune --ci', self.calls())
        # A segunda execução não repete a limpeza diária.
        self.log.unlink()
        self.assertEqual(self.run_script().returncode, 0)
        self.assertNotIn('uv ', self.calls())

    def test_pressure_overrides_daily_marker(self):
        for used, free in [('75', '100000000'), ('30', '40000000')]:
            with self.subTest(used=used, free=free):
                self.env.update(TEST_USED=used, TEST_FREE=free)
                old = self.file('.cache/pip/old', 2)
                hot = self.file('.cache/pip/hot', 0)
                self.file('.local/state/disk-maintenance/last-cache', 0).write_text(str(int(time.time())) + '\n')
                result = self.run_script()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(old.exists())
                self.assertTrue(hot.exists())
                self.assertIn('until=24h', self.calls())
                self.assertIn('notify', self.calls())

    def test_prune_failure_does_not_skip_cache_cleanup(self):
        self.env['TEST_FAIL'] = '1'
        old = self.file('.cache/go-build/old', 10)
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertFalse(old.exists())
        self.assertIn('uv cache prune', self.calls())
        self.assertIn('notify', self.calls())

    def test_symlinks_and_active_package_builds_are_preserved(self):
        outside = self.file('outside/old', 100)
        cache = self.home / '.cache'
        cache.mkdir()
        (cache / 'pip').symlink_to(outside.parent)
        clone = self.file('.cache/paru/clone/package/source', 100)
        self.env['TEST_BUSY'] = '0'
        self.assertEqual(self.run_script().returncode, 0)
        self.assertTrue(outside.exists())
        self.assertTrue(clone.exists())

    def test_invalid_markers_do_not_block_cache_cleanup(self):
        for value in ['', 'invalid\n', '9999999999\n', '999999999999999999999\n', '123']:
            with self.subTest(value=value):
                marker = self.file('.local/state/disk-maintenance/last-cache', 0)
                marker.write_text(value)
                old = self.file('.cache/pip/old', 10)
                result = self.run_script()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(old.exists())
                self.assertLess(abs(int(marker.read_text()) - time.time()), 15)
                self.assertEqual(marker.stat().st_mode & 0o777, 0o600)
                self.assertEqual(list(marker.parent.glob('last-cache.*')), [])

    def test_paru_scan_failure_preserves_clone_and_reports_error(self):
        old = self.file('.cache/paru/clone/package/source', 100)
        self.fake('find', '''if [[ $1 == "$HOME/.cache/paru/clone/package" ]]; then
    echo 'simulated I/O error' >&2
    exit 1
fi
exec /usr/bin/find "$@"''')
        result = self.run_script()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertTrue(old.exists())
        self.assertIn('preservado', result.stderr)
        self.assertIn('notify', self.calls())
        self.assertFalse((self.home / '.local/state/disk-maintenance/last-cache').exists())

    def test_marker_publish_failure_keeps_previous_marker(self):
        marker = self.file('.local/state/disk-maintenance/last-cache', 10)
        previous = str(int(time.time()) - 10 * 86400) + '\n'
        marker.write_text(previous)
        self.fake('mv', 'exit 1')
        result = self.run_script()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(marker.read_text(), previous)
        self.assertEqual(list(marker.parent.glob('last-cache.*')), [])
        self.assertIn('notify', self.calls())

    def test_old_paru_clone_is_pruned_only_after_successful_scan(self):
        old = self.file('.cache/paru/clone/old/source', 100)
        recent = self.file('.cache/paru/clone/recent/source', 0)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(old.exists())
        self.assertTrue(recent.exists())

    def test_lock_prevents_concurrent_cleanup(self):
        import fcntl
        state = self.home / '.local/state/disk-maintenance'
        state.mkdir(parents=True)
        with (state / 'lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_script()
            self.assertEqual(result.returncode, 0)
            self.assertEqual(self.calls(), '')
            self.assertIn('já em execução', result.stdout)


if __name__ == '__main__':
    unittest.main()
