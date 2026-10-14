"""Reviewed Codex sources remain consistent without probing deployed hosts."""

import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
POLICIES = ROOT / 'dotfiles/.codex'
SOURCES = {
    'mac': 'AGENTS.md',
    'linux': 'AGENTS.linux.md',
    'cerpacnas': 'AGENTS.cerpacnas.md',
    'driehuisnas': 'AGENTS.driehuisnas.md',
}


class AgentInstructionSources(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / 'setup-scripts/agent-instructions/manifest.json').read_text())

    def policy_parts(self, filename):
        content = (POLICIES / filename).read_bytes()
        shared = self.manifest['shared_block']
        start = shared['start_marker'].encode()
        end = shared['end_marker'].encode()
        self.assertEqual(content.count(start), 1, filename)
        self.assertEqual(content.count(end), 1, filename)
        self.assertTrue(content.startswith(start + b'\n'), filename)
        boundary = content.index(end) + len(end)
        self.assertEqual(content[boundary:boundary + 1], b'\n', filename)
        return content[:boundary + 1], content[boundary + 1:]

    def test_all_four_sources_share_the_reviewed_block(self):
        blocks = []
        for filename in SOURCES.values():
            with self.subTest(source=filename):
                block, _ = self.policy_parts(filename)
                blocks.append(block)
                self.assertEqual(hashlib.sha256(block).hexdigest(), self.manifest['shared_block']['sha256'])
                self.assertNotIn(b'macOS Keychain', block)
        self.assertEqual(len(set(blocks)), 1)
        self.assertTrue(self.manifest['shared_block']['includes_end_marker_newline'])

    def test_deployed_codex_hashes_match_the_reviewed_sources(self):
        for host in ('mac', 'cerpacnas', 'driehuisnas'):
            with self.subTest(host=host):
                entry = next(e for e in self.manifest['hosts'][host]['entries'] if e['id'] == host + '-codex')
                filename = SOURCES[host]
                self.assertTrue(entry['source']['path'].endswith('/dotfiles/.codex/' + filename))
                self.assertTrue(entry['shared_block_required'])
                digest = hashlib.sha256((POLICIES / filename).read_bytes()).hexdigest()
                self.assertEqual(entry['source']['sha256'], digest)
                self.assertEqual(entry['target']['sha256'], digest)

    def test_host_notes_keep_platform_and_project_ownership(self):
        tails = {host: self.policy_parts(filename)[1] for host, filename in SOURCES.items()}
        self.assertEqual(tails['linux'].strip(), b'')
        self.assertIn(b'## Mac host notes', tails['mac'])
        self.assertIn(b'macOS Keychain', tails['mac'])
        self.assertIn(b'macOS Keychain', tails['driehuisnas'])
        self.assertNotIn(b'macOS Keychain', tails['cerpacnas'])
        for host, heading in (('cerpacnas', b'## CerpacNAS host notes'),
                              ('driehuisnas', b'## Driehuis NAS host notes')):
            with self.subTest(host=host):
                tail = tails[host]
                self.assertIn(heading, tail)
                self.assertIn(b'personal-concierge:apple-reminders', tail)
                self.assertIn(b'Thesis execution on the NAS is retired', tail)
                self.assertIn(b'Current thesis implementation and acceptance belong to the existing Mac owner', tail)
                self.assertIn(b'Other authorized NAS projects may use their established native remote host', tail)
                self.assertIn(b'In Code Mode, minimize unnecessary outer model round trips', tail)
                self.assertIn(b'issue comments, pull-request comments or descriptions, review summaries', tail)
                self.assertIn(b'discussion posts', tail)
                self.assertIn(b'verified-model disclosure in the shared policy', tail)
                self.assertNotIn(b'<model (', tail)

    def test_repository_instructions_retain_the_cloud_nas_runbook(self):
        self.assertIn('[Cloud NAS access](docs/cloud-nas-access.md)', (ROOT / 'AGENTS.md').read_text())
        self.assertTrue((ROOT / 'docs/cloud-nas-access.md').is_file())


if __name__ == '__main__':
    unittest.main()
