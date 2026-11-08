#!/usr/bin/env python3
"""Copy non-system runtime libraries into an app bundle and rewrite their load paths."""
import pathlib
import shutil
import re
import plistlib
import subprocess
import sys

def deployment_floors(commands):
    result = []
    for command in commands.split('Load command'):
        if re.search(r'cmd LC_BUILD_VERSION\s', command):
            version = re.search(r'\n\s*minos (\d+\.\d+(?:\.\d+)?)', command)
        elif re.search(r'cmd LC_VERSION_MIN_MACOSX\s', command):
            version = re.search(r'\n\s*version (\d+\.\d+(?:\.\d+)?)', command)
        else:
            continue
        if version:
            result.append(tuple(map(int, version.group(1).split('.'))))
    return result

assert deployment_floors('Load command 1\n cmd LC_SOURCE_VERSION\n version 27106.1\nLoad command 2\n cmd LC_BUILD_VERSION\n minos 27.0\n') == [(27, 0)]
assert deployment_floors('Load command 1\n cmd LC_VERSION_MIN_MACOSX\n version 14.0\n') == [(14, 0)]

bundle = pathlib.Path(sys.argv[1])
binaries = pathlib.Path(sys.argv[2])
frameworks = bundle / 'Contents' / 'Frameworks'
frameworks.mkdir(parents=True, exist_ok=True)
executable = bundle / 'Contents' / 'MacOS' / 'ConnectionWorkbench'
swift_compiler = pathlib.Path(subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip())
swift_runtimes = list((swift_compiler.parent.parent / 'lib').glob('swift*/macosx'))
queue = [executable]
copied = {}

def run(*args):
    return subprocess.check_output(args, text=True)

while queue:
    target = queue.pop(0)
    lines = run('otool', '-L', str(target)).splitlines()[1:]
    for line in lines:
        dependency = line.strip().split(' (', 1)[0]
        if dependency.startswith(('/System/', '/usr/lib/')):
            continue
        if target != executable and dependency == run('otool', '-D', str(target)).splitlines()[-1].strip():
            continue
        source = pathlib.Path(dependency)
        if dependency.startswith('@rpath/'):
            source = binaries / pathlib.Path(dependency).name
            if not source.is_file():
                source = next((path / pathlib.Path(dependency).name for path in swift_runtimes if (path / pathlib.Path(dependency).name).is_file()), source)
        elif dependency.startswith('@loader_path/'):
            source = target.parent / dependency[len('@loader_path/'):]
        elif not dependency.startswith(('/opt/homebrew/', '/usr/local/')):
            raise SystemExit('Unresolved runtime library: ' + dependency)
        if not source.is_file():
            raise SystemExit('Missing runtime library: ' + dependency)
        name = source.name
        destination = frameworks / name
        resolved = source.resolve()
        if name in copied and copied[name] != resolved:
            raise SystemExit('Conflicting runtime library basename: ' + name)
        if name not in copied:
            copied[name] = resolved
            destination.write_bytes(source.read_bytes())
            destination.chmod(0o755)
            subprocess.run(['install_name_tool', '-id', '@rpath/' + name, str(destination)], check=True)
            queue.append(destination)
        subprocess.run(['install_name_tool', '-change', dependency, '@rpath/' + name, str(target)], check=True)
for binary in [executable] + list(frameworks.glob('*.dylib')):
    commands = run('otool', '-l', str(binary))
    paths = re.findall(r'cmd LC_RPATH\n\s*cmdsize[^\n]*\n\s*path (.*?) \(offset \d+\)', commands)
    for path in set(paths):
        if path.startswith('/') and path != '/usr/lib/swift':
            subprocess.run(['install_name_tool', '-delete_rpath', path, str(binary)], check=True)
load_commands = run('otool', '-l', str(executable))
if 'path @executable_path/../Frameworks ' not in load_commands:
    subprocess.run(['install_name_tool', '-add_rpath', '@executable_path/../Frameworks', str(executable)], check=True)
floors = []
for binary in [executable] + list(frameworks.glob('*.dylib')):
    commands = run('otool', '-l', str(binary))
    floors += deployment_floors(commands)
info_path = bundle / 'Contents' / 'Info.plist'
info = plistlib.loads(info_path.read_bytes())
original_floor = tuple(map(int, info['LSMinimumSystemVersion'].split('.')))
info['LSMinimumSystemVersion'] = '.'.join(map(str, max([original_floor] + floors)))
info_path.write_bytes(plistlib.dumps(info))
print('Local bundle minimum macOS: ' + info['LSMinimumSystemVersion'])
for resource in binaries.glob('*.bundle'):
    destination = bundle / 'Contents' / 'Resources' / resource.name
    if destination.exists(): shutil.rmtree(destination)
    shutil.copytree(resource, destination)
for library in frameworks.glob('*.dylib'):
    subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(library)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(bundle)], check=True)
