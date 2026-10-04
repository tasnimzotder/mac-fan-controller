import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('metadata', Path(__file__).resolve().parents[1] / 'tools/release-metadata.py')
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class ReleaseMetadataTests(unittest.TestCase):
    def test_tag_mismatch_fails(self):
        with self.assertRaises(ValueError):
            metadata.version_for('v999.0.0')

    def test_cask_and_checksums_use_exact_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            dist = Path(directory)
            version = metadata.version_for()
            name = f'MacFanController_v{version}_aarch64.dmg'
            payload = b'release fixture, not a real DMG'
            (dist / name).write_bytes(payload)
            result = metadata.render('tasnimzotder/mac-fan-controller', dist, f'v{version}')
            digest = hashlib.sha256(payload).hexdigest()
            self.assertEqual(result['sha256'], digest)
            self.assertEqual((dist / 'SHA256SUMS').read_text(), f'{digest}  {name}\n')
            cask = (dist / 'mac-fan-controller.rb').read_text()
            self.assertIn(f'sha256 "{digest}"', cask)
            self.assertIn('github.com/tasnimzotder/mac-fan-controller', cask)
            self.assertNotIn('{{', cask.replace('{{appdir}}', ''))
            self.assertIn('["-r", "-d", "com.apple.quarantine", "{{appdir}}/Mac Fan Controller.app"]', cask)
            self.assertEqual(result['prerelease'], '-' in version)

    def test_missing_or_empty_artifact_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            dist = Path(directory)
            with self.assertRaises(ValueError):
                metadata.render('owner/repo', dist)
            (dist / f'MacFanController_v{metadata.version_for()}_aarch64.dmg').touch()
            with self.assertRaises(ValueError):
                metadata.render('owner/repo', dist)

    def test_repository_cannot_inject_ruby_or_urls(self):
        for repository in ['owner/repo"; system("oops")', '../repo', 'owner/repo/other']:
            with self.assertRaises(ValueError):
                metadata.render(repository, Path('/unused'))


if __name__ == '__main__':
    unittest.main()
