"""Source-only caller for HouseAtlas's existing MaintenanceOwner.call interface.

No transport is installed. The CLI reports unavailable without reading stdin.
Only a trusted future host may inject an already-qualified MaintenanceOwner;
caller arguments/environment never select an owner, endpoint or executable.
"""

import json
import sys
import threading
import uuid


FORMATS = {
    'check': 'houseatlas.updater.check.v1',
    'apply': 'houseatlas.updater.apply.v1',
    'status': 'houseatlas.updater.status-request.v1',
}
TOOLS = {command: 'houseatlas_update_' + command for command in FORMATS}


class Unavailable(Exception):
    """No owner-qualified HouseAtlas binding is present."""


class InvalidRequest(Exception):
    """Caller framing is invalid; the owner retains full protocol validation."""


class StatusRequired(Exception):
    """After an apply attempt, only status of that operation is allowed."""

    def __init__(self, operation_id):
        self.operation_id = operation_id
        super().__init__('consult status of the original operation; do not repeat apply')


class OutcomeUnknown(StatusRequired):
    """Dispatch returned no usable result; this does not cancel the operation."""


def frame(command, raw_request):
    """Frame existing owner input without normalizing or rebuilding its bytes.

    This is only a bounded format/correlation check. HouseAtlas's closed parser
    validates the release, expected-installed revision and remaining fields.
    """
    if (type(command) is not str or command not in FORMATS or
            type(raw_request) is not bytes or len(raw_request) > 4096):
        raise InvalidRequest('invalid HouseAtlas request')

    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate field')
            result[key] = value
        return result

    def reject_constant(_):
        raise ValueError('non-JSON constant')

    try:
        text = raw_request.decode('utf-8')
        packet = json.loads(text, object_pairs_hook=unique, parse_constant=reject_constant)
        if type(packet) is not dict or packet.get('format') != FORMATS[command]:
            raise ValueError('format mismatch')
        operation_id = packet['operationId']
        if operation_id is None and command == 'status':
            pass
        elif type(operation_id) is not str or str(uuid.UUID(operation_id)) != operation_id:
            raise ValueError('invalid operation')
    except (ValueError, UnicodeError, KeyError, RecursionError, AttributeError):
        raise InvalidRequest('invalid HouseAtlas request') from None
    return operation_id, {'requestJson': text}


class MaintenanceCaller:
    """One apply attempt per caller; no retry, new ID, installer or journal.

    The supplied owner is HouseAtlas's existing MaintenanceOwner with separate
    action-time authorization. It alone owns transactions and durable status.
    Reconstructing this object cannot establish permission to re-apply: a future
    installed host must reconcile its durable operation before enabling apply.
    """

    def __init__(self, owner=None):
        self._owner = owner
        self._apply_operation = None
        self._lock = threading.Lock()

    def call(self, command, raw_request):
        operation_id, arguments = frame(command, raw_request)
        with self._lock:
            if self._owner is None:
                raise Unavailable('HouseAtlas binding is unqualified')
            if self._apply_operation is not None:
                if command != 'status' or operation_id != self._apply_operation:
                    raise StatusRequired(self._apply_operation)
            if command == 'apply':
                # Mark before handing off, even if a response is subsequently
                # lost. A check result and handled=true never clear this fence.
                self._apply_operation = operation_id
        try:
            result = self._owner.call(TOOLS[command], arguments)
            if type(result) is not dict or result.get('format') != 'houseatlas.updater.result.v1':
                raise ValueError('missing updater result')
            # Keep phase/code/health/recovery/operation identity exactly as the
            # existing sanitized owner returned them. ok means handled only.
            return result
        except Exception:
            if self._apply_operation is not None:
                raise OutcomeUnknown(self._apply_operation) from None
            raise Unavailable('HouseAtlas result unavailable') from None


def main(args):
    if len(args) != 1 or args[0] not in FORMATS:
        print('dots: unsupported HouseAtlas action; use check, apply or status', file=sys.stderr)
        return 2
    # No installed transport/owner exists under HouseAtlas #284/#290. Do not
    # read stdin, discover hosts, import adapters or execute any updater here.
    print(json.dumps({'format': 'dots.houseatlas.caller.v1',
                      'availability': 'unavailable',
                      'reason': 'houseatlas-binding-unqualified'}))
    print('dots: HouseAtlas unavailable: qualified maintenance binding required; '
          'no request was sent', file=sys.stderr)
    return 3


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
