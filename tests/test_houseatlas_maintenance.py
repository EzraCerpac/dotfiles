"""Synthetic caller tests: no HouseAtlas runtime, transport, staging or apply."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest


SOURCE = Path(__file__).resolve().parents[1] / 'setup-scripts/lib/houseatlas-maintenance.py'
SPEC = importlib.util.spec_from_file_location('houseatlas_maintenance', SOURCE)
CALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CALLER)
OPERATION = '00000000-0000-4000-8000-000000000001'
OTHER_OPERATION = '00000000-0000-4000-8000-000000000002'


def request(command, operation=OPERATION):
    packet = {'format': CALLER.FORMATS[command], 'operationId': operation}
    if command != 'status':
        packet.update(expectedInstalledRevision='a' * 64, release={
            'version': '1.0.0', 'commit': 'b' * 40, 'tree': 'c' * 40,
            'releaseId': 1, 'assetId': 2, 'assetName': 'synthetic.tar',
            'archiveSha256': 'd' * 64, 'manifestSha256': 'e' * 64,
        })
    # Deliberate whitespace is part of the authorization bytes.
    return (' \n' + json.dumps(packet, indent=2) + '\n').encode()


class RecordingOwner:
    def __init__(self, result=None, fail=False):
        self.calls = []
        self.fail = fail
        self.result = result if result is not None else {
            'format': 'houseatlas.updater.result.v1', 'ok': True,
            'code': 'boundary-failed', 'status': {
                'operationId': OPERATION, 'phase': 'rejected',
                'healthVerified': False, 'recoveryNeeded': True,
            },
        }

    def call(self, name, arguments):
        self.calls.append((name, arguments))
        if self.fail:
            raise TimeoutError('private diagnostic must not escape')
        return self.result


class HouseAtlasMaintenanceTest(unittest.TestCase):
    def test_exact_owner_tools_bytes_identity_and_result_are_preserved(self):
        owner = RecordingOwner()
        caller = CALLER.MaintenanceCaller(owner)
        for command in ('check', 'apply', 'status'):
            raw = request(command)
            result = caller.call(command, raw)
            self.assertIs(result, owner.result)
            name, arguments = owner.calls[-1]
            self.assertEqual(name, 'houseatlas_update_' + command)
            self.assertEqual(set(arguments), {'requestJson'})
            self.assertEqual(arguments['requestJson'].encode(), raw)
        self.assertEqual(len(owner.calls), 3)

    def test_uncertain_apply_is_never_repeated_or_replaced(self):
        owner = RecordingOwner(fail=True)
        caller = CALLER.MaintenanceCaller(owner)
        with self.assertRaises(CALLER.OutcomeUnknown) as caught:
            caller.call('apply', request('apply'))
        self.assertEqual(caught.exception.operation_id, OPERATION)
        self.assertNotIn('private', str(caught.exception))
        for command, operation in [('apply', OPERATION), ('apply', OTHER_OPERATION),
                                   ('check', OPERATION), ('status', None),
                                   ('status', OTHER_OPERATION)]:
            with self.assertRaises(CALLER.StatusRequired):
                caller.call(command, request(command, operation))
        self.assertEqual(len(owner.calls), 1)
        owner.fail = False
        self.assertIs(caller.call('status', request('status')), owner.result)
        # Even a status response cannot authorize a second apply.
        with self.assertRaises(CALLER.StatusRequired):
            caller.call('apply', request('apply'))
        self.assertEqual([name for name, _ in owner.calls],
                         ['houseatlas_update_apply', 'houseatlas_update_status'])

    def test_successful_apply_also_requires_status_and_missing_result_is_uncertain(self):
        for result in (None, {'format': 'unexpected'}):
            owner = RecordingOwner()
            owner.result = result
            caller = CALLER.MaintenanceCaller(owner)
            with self.assertRaises(CALLER.OutcomeUnknown):
                caller.call('apply', request('apply'))
            with self.assertRaises(CALLER.StatusRequired):
                caller.call('apply', request('apply'))
            self.assertEqual(len(owner.calls), 1)
        caller = CALLER.MaintenanceCaller(RecordingOwner())
        caller.call('apply', request('apply'))
        with self.assertRaises(CALLER.StatusRequired):
            caller.call('apply', request('apply', OTHER_OPERATION))

    def test_framing_rejects_ambiguous_or_unbounded_input_before_owner(self):
        owner = RecordingOwner()
        caller = CALLER.MaintenanceCaller(owner)
        for command, raw in [('deploy', request('check')), ('apply', request('check')),
                             ('apply', request('apply', None)), ('apply', b'{}'),
                             ('status', b'\xff'), ('status', b'[]'),
                             ('status', b'{"format":0,"format":1}'),
                             ('status', b' ' * 4097),
                             ('status', (' ' * 4095 + '\u00e9').encode())]:
            with self.subTest(command=command, raw=raw[:30]):
                with self.assertRaises(CALLER.InvalidRequest):
                    caller.call(command, raw)
        self.assertEqual(owner.calls, [])
        with self.assertRaises(CALLER.Unavailable):
            CALLER.MaintenanceCaller().call('apply', request('apply'))

    def test_installed_cli_is_unavailable_without_reading_stdin(self):
        # Keep stdin open: an accidental protocol read would hang until timeout.
        with subprocess.Popen([sys.executable, '-I', str(SOURCE), 'apply'],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE) as child:
            try:
                self.assertEqual(child.wait(timeout=5), 3)
                self.assertEqual(json.loads(child.stdout.read())['availability'], 'unavailable')
                self.assertIn(b'no request was sent', child.stderr.read())
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()


if __name__ == '__main__':
    unittest.main()
