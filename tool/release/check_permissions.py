"""Check that a release APK declares no permission outside the allow-list.

Sonoglitch promises that it never touches the network, so a release APK must
not declare `android.permission.INTERNET` nor
`android.permission.ACCESS_NETWORK_STATE`. The permissions are read with
`aapt2 dump permissions` (or `aapt dump permissions`) from the Android SDK
build tools, and with the merged manifest of the build when the build tools
are not installed.

Usage:
    python tool/release/check_permissions.py build/app/outputs/flutter-apk/app-release.apk

The script exits with 0 when the APK only declares the allowed permissions,
with 1 when it declares one that the release does not allow, and with 2 when
the permissions could not be read at all: a check that cannot run must not
pass.
"""

import argparse
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

# The permissions that a release APK may declare.
#
# CAMERA takes the pictures and RECORD_AUDIO reads the level of the sound: the
# app never records, stores or sends any audio. Every other entry was found in
# the release APK of version 0.2.0 (build 25) and is justified here:
#
# - android.permission.INTERNET: forbidden, see FORBIDDEN_PERMISSIONS.
# - android.permission.ACCESS_NETWORK_STATE: forbidden, see
#   FORBIDDEN_PERMISSIONS.
# - android.permission.WRITE_EXTERNAL_STORAGE and
#   android.permission.READ_EXTERNAL_STORAGE: removed by the app manifest with
#   `tools:node="remove"`, because the app saves through the media store and
#   needs API 29.
# - es.sonoglitch.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION: a signature
#   permission that AndroidX Core declares for the app itself, so that its
#   runtime broadcast receivers cannot be reached by other apps. It grants
#   nothing and has no network effect.
ALLOWED_PERMISSIONS = frozenset(
    {
        'android.permission.CAMERA',
        'android.permission.RECORD_AUDIO',
        'es.sonoglitch.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
    }
)

# The permissions that break the promise of the app. They are checked apart
# from the allow-list so that the report names them as what they are.
FORBIDDEN_PERMISSIONS = frozenset(
    {
        'android.permission.INTERNET',
        'android.permission.ACCESS_NETWORK_STATE',
    }
)

ANDROID_NAME = '{http://schemas.android.com/apk/res/android}name'

# The lines that aapt and aapt2 print for a permission, for example
# "uses-permission: name='android.permission.CAMERA'".
AAPT_PERMISSION = re.compile(
    r"^uses-permission(?:-sdk-\d+)?:\s*name=['\"]([^'\"]+)['\"]",
    re.MULTILINE,
)


class CheckError(Exception):
    """The permissions of the APK could not be read."""


def android_sdk_roots():
    """The directories that may hold the Android SDK."""
    for variable in ('ANDROID_SDK_ROOT', 'ANDROID_HOME'):
        value = os.environ.get(variable)
        if value:
            yield Path(value)
    home = Path.home()
    yield home / 'Android' / 'Sdk'
    yield home / 'Library' / 'Android' / 'sdk'


def version_key(path):
    """Sort build-tools directories by their version numbers."""
    parts = []
    for part in path.name.split('.'):
        parts.append(int(part) if part.isdigit() else -1)
    return parts


def executable(path):
    """The executable file of a build tool, with the Windows suffix."""
    for name in (path.name, path.name + '.exe', path.name + '.bat'):
        candidate = path.with_name(name)
        if candidate.is_file():
            return candidate
    return None


def find_aapt():
    """The arguments that dump the permissions of an APK, or None."""
    for root in android_sdk_roots():
        build_tools = root / 'build-tools'
        if not build_tools.is_dir():
            continue
        versions = sorted(
            (directory for directory in build_tools.iterdir() if directory.is_dir()),
            key=version_key,
            reverse=True,
        )
        for version in versions:
            for name in ('aapt2', 'aapt'):
                tool = executable(version / name)
                if tool is not None:
                    return [str(tool), 'dump', 'permissions']
    return None


def parse_aapt_permissions(output):
    """The permissions of the output of `aapt dump permissions`."""
    return set(AAPT_PERMISSION.findall(output))


def manifest_permissions(path):
    """The permissions that a merged Android manifest declares."""
    try:
        tree = ElementTree.parse(path)
    except ElementTree.ParseError as error:
        raise CheckError(f'{path} is not a readable XML manifest: {error}')
    permissions = set()
    for element in tree.getroot():
        tag = element.tag.rsplit('}', 1)[-1]
        if tag in ('uses-permission', 'uses-permission-sdk-23'):
            name = element.get(ANDROID_NAME)
            if name:
                permissions.add(name)
    return permissions


def find_merged_manifest(apk):
    """The merged manifest of the build that produced the APK, or None."""
    app = apk.parent.parent.parent
    intermediates = app / 'intermediates'
    if not intermediates.is_dir():
        return None
    candidates = []
    for path in intermediates.rglob('AndroidManifest.xml'):
        parts = {part.lower() for part in path.parts}
        if parts & {'merged_manifest', 'merged_manifests', 'packaged_manifests'}:
            candidates.append(path)
    release = [path for path in candidates if 'release' in path.as_posix().lower()]
    pool = release or candidates
    return sorted(pool)[0] if pool else None


def run_command(command):
    """Run a command and return its exit code, its output and its errors."""
    result = subprocess.run(command, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def read_permissions(apk, manifest=None, runner=run_command):
    """The permissions that the APK declares, and where they were read."""
    command = find_aapt()
    if command is not None:
        code, output, errors = runner([*command, str(apk)])
        if code == 0:
            permissions = parse_aapt_permissions(output)
            if permissions:
                return permissions, 'aapt'
        detail = (errors or output).strip().splitlines()
        if detail:
            raise CheckError(
                f'{command[0]} could not read the permissions of {apk}: '
                + detail[0]
            )
    if manifest is None:
        manifest = find_merged_manifest(apk)
    if manifest is None or not Path(manifest).is_file():
        raise CheckError(
            f'no aapt in the Android SDK and no merged manifest for {apk}: '
            'the permissions cannot be checked'
        )
    return manifest_permissions(Path(manifest)), f'merged manifest {manifest}'


def check_permissions(permissions):
    """The problems that a set of permissions has, in a readable order."""
    problems = []
    for permission in sorted(permissions & FORBIDDEN_PERMISSIONS):
        problems.append(
            f'{permission}: the app promises never to touch the network'
        )
    for permission in sorted(permissions - ALLOWED_PERMISSIONS - FORBIDDEN_PERMISSIONS):
        problems.append(f'{permission}: not in the allow-list')
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Check that an APK declares no permission outside the '
        'allow-list of the app.',
    )
    parser.add_argument('apk', type=Path, help='the built APK to check')
    parser.add_argument(
        '--manifest',
        type=Path,
        default=None,
        help='the merged manifest to read when the build tools are missing',
    )
    args = parser.parse_args(argv)
    if not args.apk.is_file():
        print(f'error: there is no APK at {args.apk}', file=sys.stderr)
        return 2
    try:
        permissions, source = read_permissions(args.apk, args.manifest)
    except CheckError as error:
        print(f'error: {error}', file=sys.stderr)
        return 2
    problems = check_permissions(permissions)
    if problems:
        print(
            f'error: {args.apk} declares permissions that the app does not '
            'allow:',
            file=sys.stderr,
        )
        for problem in problems:
            print(f'  {problem}', file=sys.stderr)
        return 1
    print(f'OK: {args.apk} declares only allowed permissions (read with {source}).')
    for permission in sorted(permissions):
        print(f'  {permission}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
