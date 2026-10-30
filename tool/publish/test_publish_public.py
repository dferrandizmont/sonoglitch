"""Tests of publish_public.ps1: the public repository only ever sees one identity.

Each test builds a throw-away "private" repository (with a copy of the script),
an empty bare repository that plays the public one, and runs the real script
against them. The global git config of the test points at a Gmail identity, to
prove that the script never falls back to it.

Run from the repository root (Windows PowerShell or PowerShell 7 required):

    python -m unittest discover -s tool/publish
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / 'publish_public.ps1'
POWERSHELL = shutil.which('powershell') or shutil.which('pwsh')
PERSONAL = 'someone' + '@' + 'gmail.com'  # kept in pieces: this file is published too
PUBLIC = 'Daniel Mont Ferrandiz <dev@mainshai.com>'


@unittest.skipUnless(os.name == 'nt' and POWERSHELL, 'needs Windows and PowerShell')
class PublishPublicTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='publish-test-'))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        config = self.tmp / 'gitconfig'
        config.write_text(f'[user]\n\tname = Personal\n\temail = {PERSONAL}\n', encoding='utf8')
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=str(config), GIT_CONFIG_NOSYSTEM='1')
        for name in ('PUBLIC_AUTHOR_NAME', 'PUBLIC_AUTHOR_EMAIL'):
            self.env.pop(name, None)
        self.private = self.tmp / 'private'
        (self.private / 'tool' / 'publish').mkdir(parents=True)
        shutil.copy(SCRIPT, self.private / 'tool' / 'publish' / SCRIPT.name)
        (self.private / 'tool' / 'publish' / 'exclude.txt').write_text('# none\n', encoding='utf8')
        self.git('init', '-q', '-b', 'main', cwd=self.private)
        self.public = self.tmp / 'public.git'
        self.git('init', '-q', '--bare', '-b', 'main', str(self.public), cwd=self.tmp)
        self.work = self.tmp / 'work'

    def git(self, *args, cwd=None, check=True):
        result = subprocess.run(['git', *args], cwd=cwd or self.private, env=self.env,
                                capture_output=True, text=True)
        if check and result.returncode:
            self.fail(f'git {" ".join(args)} failed: {result.stderr}')
        return result.stdout.strip()

    def release(self, tag, files):
        for name, text in files.items():
            (self.private / name).write_text(text, encoding='utf8')
        self.git('add', '-A')
        self.git('commit', '-q', '-m', f'private {tag}')
        self.git('tag', tag)

    def publish(self, tag, **extra_env):
        return subprocess.run(
            [POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
             str(self.private / 'tool' / 'publish' / SCRIPT.name), '-Tag', tag,
             '-PublicUrl', str(self.public), '-WorkDir', str(self.work)],
            cwd=self.private, env=dict(self.env, **extra_env), capture_output=True, text=True)

    def public_log(self):
        return self.git('log', '--format=%an <%ae>|%cn <%ce>|%s', 'main', cwd=self.public).splitlines()

    def tagger(self, tag):
        return self.git('for-each-ref', '--format=%(objecttype) %(taggername) <%(taggeremail:trim)>',
                        f'refs/tags/{tag}', cwd=self.public)

    def test_default_identity_ignores_the_global_git_config(self):
        self.release('v0.0.1', {'README.md': 'one\n'})
        result = self.publish('v0.0.1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.public_log(), [f'{PUBLIC}|{PUBLIC}|Release v0.0.1'])
        self.assertEqual(self.tagger('v0.0.1'), 'tag Daniel Mont Ferrandiz <dev@mainshai.com>')

    def test_identity_can_be_changed_with_environment_variables(self):
        self.release('v0.0.1', {'README.md': 'one\n'})
        result = self.publish('v0.0.1', PUBLIC_AUTHOR_NAME='Public Name',
                              PUBLIC_AUTHOR_EMAIL='public@example.org')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        who = 'Public Name <public@example.org>'
        self.assertEqual(self.public_log(), [f'{who}|{who}|Release v0.0.1'])

    def test_a_kept_clone_with_a_personal_identity_is_still_published_as_the_public_one(self):
        self.release('v0.0.1', {'README.md': 'one\n'})
        self.assertEqual(self.publish('v0.0.1').returncode, 0)
        self.git('config', 'user.email', PERSONAL, cwd=self.work)
        self.git('config', 'user.name', 'Personal', cwd=self.work)
        self.release('v0.0.2', {'README.md': 'two\n'})
        result = self.publish('v0.0.2')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.public_log(), [f'{PUBLIC}|{PUBLIC}|Release v0.0.2',
                                             f'{PUBLIC}|{PUBLIC}|Release v0.0.1'])
        self.assertEqual(self.tagger('v0.0.2'), 'tag Daniel Mont Ferrandiz <dev@mainshai.com>')

    def test_a_gmail_address_in_a_file_stops_the_publication(self):
        self.release('v0.0.1', {'README.md': f'contact {PERSONAL}\n'})
        result = self.publish('v0.0.1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Possible secrets', result.stdout + result.stderr)
        self.assertEqual(self.git('for-each-ref', cwd=self.public), '')

    def test_a_gmail_address_as_the_public_identity_is_refused(self):
        self.release('v0.0.1', {'README.md': 'one\n'})
        result = self.publish('v0.0.1', PUBLIC_AUTHOR_EMAIL=PERSONAL)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Gmail', result.stdout + result.stderr)
        self.assertEqual(self.git('for-each-ref', cwd=self.public), '')

    def test_a_domain_that_only_starts_with_gmail_com_is_allowed(self):
        self.release('v0.0.1', {'README.md': 'see person@' + 'gmail.com.example.org\n'})
        result = self.publish('v0.0.1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
