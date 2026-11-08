#!/usr/bin/env python3
"""Exercise transfers against an ephemeral, key-only OpenSSH server on loopback."""
import os
import pathlib
import pwd
import socket
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent
prefix = pathlib.Path(os.environ.get('SESSIONDOCK_LIBSSH2_PREFIX', '/opt/homebrew/opt/libssh2' if pathlib.Path('/opt/homebrew/opt/libssh2').exists() else '/usr/local/opt/libssh2'))
subprocess.run(['clang', '-I', str(root / 'Sources/CSFTP/include'), '-I', str(prefix / 'include'), str(root / 'Tests/NativeFixtures/sftp-transfer.c'), str(root / 'Sources/CSFTP/CSFTP.c'), '-L', str(prefix / 'lib'), '-lssh2', '-o', str(root / '.build/sftp-transfer')], check=True)
with tempfile.TemporaryDirectory(prefix='sessiondock-sftp-') as folder:
    temp = pathlib.Path(folder)
    for name in ['host', 'identity']:
        subprocess.run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(temp / name)], check=True)
    with socket.socket() as reserve:
        reserve.bind(('127.0.0.1', 0))
        port = reserve.getsockname()[1]
    user = pwd.getpwuid(os.getuid()).pw_name
    config = temp / 'sshd_config'
    config.write_text(f'''ListenAddress 127.0.0.1
Port {port}
HostKey {temp / 'host'}
AuthorizedKeysFile {temp / 'identity.pub'}
PidFile {temp / 'sshd.pid'}
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
AllowUsers {user}
AllowTcpForwarding no
X11Forwarding no
PermitTunnel no
Subsystem sftp internal-sftp -d {temp}
''')
    # Only the disposable identity is accepted; no user's SSH config or keys are read.
    public_host = (temp / 'host.pub').read_text().split()
    known = temp / 'known_hosts'
    known.write_text(f'[127.0.0.1]:{port} {public_host[0]} {public_host[1]}\n')
    environment = dict(os.environ, SSH_AUTH_SOCK=str(temp / 'socket'))
    children = []
    with (temp / 'sshd.log').open('w+') as log:
        try:
            children.append(subprocess.Popen(['/usr/bin/ssh-agent', '-D', '-a', environment['SSH_AUTH_SOCK']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            for _ in range(100):
                if (temp / 'socket').exists(): break
                time.sleep(0.02)
            subprocess.run(['/usr/bin/ssh-add', str(temp / 'identity')], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            server = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)], stdout=subprocess.DEVNULL, stderr=log)
            children.append(server)
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError('Loopback sshd could not start; check local OpenSSH permissions.')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=0.1): break
                except OSError: time.sleep(0.02)
            subprocess.run([str(root / '.build/sftp-transfer'), str(port), user, str(known), str(temp)], env=environment, check=True, timeout=30)
        finally:
            for child in reversed(children):
                if child.poll() is None: child.terminate()
            for child in children:
                try: child.wait(timeout=5)
                except subprocess.TimeoutExpired: child.kill(); child.wait()
