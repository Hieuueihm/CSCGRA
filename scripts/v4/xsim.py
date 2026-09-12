"""Real Vivado simulator backend; no alternative simulator or synthesis fallback."""
from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import uuid


@dataclass
class Result:
    returncode: int
    stdout: str = ''
    stderr: str = ''
    commands: list = field(default_factory=list)


def tools():
    """Return {xvlog,xelab,xsim: absolute Path}; missing tools are fatal."""
    directory = Path(os.environ.get('VIVADO_BIN', 'C:/Xilinx/Vivado/2018.1/bin')).resolve()
    found = {name: directory / (name + '.bat') for name in ('xvlog', 'xelab', 'xsim')}
    missing = [str(path) for path in found.values() if not path.is_file()]
    if missing:
        raise FileNotFoundError('Vivado simulator tools are required: ' + ', '.join(missing))
    return found


def execute_process(command, *, cwd, timeout):
    """Bound one owned process tree, including batch-launcher descendants."""
    process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, errors='replace')
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        # Never select by executable name: other agents may own identical tools.
        cleanup = subprocess.run(['C:/Windows/System32/taskkill.exe', '/PID', str(process.pid),
                                  '/T', '/F'], capture_output=True, text=True, timeout=30)
        try:
            stdout, stderr = process.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate(timeout=30)
        if isinstance(error, subprocess.TimeoutExpired):
            raise subprocess.TimeoutExpired(command, timeout, output=stdout,
                stderr=stderr + '\nOwned process-tree cleanup: ' + cleanup.stdout + cleanup.stderr) from error
        raise
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def _invoke(tool, arguments, cwd, timeout):
    # A string command preserves cmd.exe's /s /c outer quoting for .bat paths.
    argv = [str(tool), *map(str, arguments)]
    if any(any(c in arg for c in '"%!&|<>^\r\n') for arg in argv):
        raise ValueError('unsupported cmd.exe metacharacter in Vivado argument')
    quoted = ' '.join('"' + arg + '"' for arg in argv)
    command = subprocess.list2cmdline([os.environ.get('COMSPEC', 'C:/Windows/System32/cmd.exe'),
                                      '/d', '/s', '/c']) + ' "' + quoted + '"'
    record = dict(command=command, argv=argv, cwd=str(cwd), timeout_seconds=timeout,
                  invocation_id=uuid.uuid4().hex, execution='executed',
                  started_utc=datetime.now(timezone.utc).isoformat())
    try:
        process = execute_process(command, cwd=cwd, timeout=timeout)
        record.update(returncode=process.returncode, stdout=process.stdout, stderr=process.stderr)
    except subprocess.TimeoutExpired as error:
        decode = lambda value: value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
        record.update(returncode=124, stdout=decode(error.stdout), stderr=decode(error.stderr), error='timeout')
    except OSError as error:
        record.update(returncode=127, stdout='', stderr=str(error), error=type(error).__name__)
    # Xsim can terminate on $fatal while its batch launcher still returns zero.
    log = Path(cwd) / (Path(tool).stem + '.log')
    record['logs'] = {log.name: log.read_text(errors='replace')} if log.is_file() else {}
    text = record['stdout'] + '\n' + record['stderr'] + '\n'.join(record['logs'].values())
    if re.search(r'(?im)^\s*(?:error|fatal)\s*(?:\[|:)|\$fatal\b', text):
        record['log_failure'] = True
        if not record['returncode']:
            record['returncode'] = 1
    return record


def tool_versions():
    """Return command records for real -help banner probes, including tool versions."""
    with tempfile.TemporaryDirectory(prefix='v4_vivado_version_') as cwd:
        return [_invoke(path, ['-help'], cwd, 60) for path in tools().values()]


def _filelist(root):
    root = Path(root).resolve()
    sources, includes, visited = [], [root / 'rtl/v4/include'], set()
    def parse(path):
        path = path.resolve()
        if path in visited:
            return
        visited.add(path)
        text = re.sub(r'/\*.*?\*/|//[^\n]*|#[^\n]*', '', path.read_text(), flags=re.S)
        tokens = shlex.split(text, posix=True)
        index = 0
        while index < len(tokens):
            item = tokens[index]
            if item.startswith('+incdir+'):
                includes.extend(root / name for name in item[len('+incdir+'):].split('+'))
            elif item == '-f':
                index += 1
                parse(root / tokens[index])
            elif item.endswith(('.sv', '.v')):
                sources.append((root / item).resolve())
            else:
                raise ValueError(f'unsupported Vivado file-list directive: {item}')
            index += 1
    parse(root / 'rtl/v4/files.f')
    return list(dict.fromkeys(sources)), list(dict.fromkeys(path.resolve() for path in includes))


def filelist_sources(root):
    """Resolve listed RTL sources; compile_rtl also consumes its +incdir entries."""
    return _filelist(root)[0]


def compile_rtl(output, top, sources, *, root, includes=(), parameters=None, timeout=180,
                debug='typical', optimization=None):
    if debug not in ('typical','off'):
        raise ValueError('debug must be typical or off')
    if optimization is not None and (type(optimization) is not int or not 0<=optimization<=3):
        raise ValueError('optimization must be None or integer0..3')
    output, root = Path(output).resolve(), Path(root).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    executables = tools()
    inputs = [(root / path).resolve() for path in sources]
    if not inputs or any(path.suffix not in ('.sv', '.v') or not path.is_file() for path in inputs):
        raise ValueError('compile_rtl requires existing RTL/TB source files only')
    include_dirs = list(dict.fromkeys([*_filelist(root)[1], *[(root / path).resolve() for path in includes]]))
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    for directory in include_dirs:
        for path in sorted(directory.rglob('*')):
            if path.is_file() and path.suffix in ('.vh', '.svh'):
                hashes[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    identity = dict(metadata_schema=2, top=top, sources=[str(path) for path in inputs], hashes=hashes,
                    includes=[str(path) for path in include_dirs], parameters=parameters or {},
                    tools={name: str(path) for name, path in executables.items()}, timescale='1ns/1ps')
    # Keep the existing default signature; nondefault elaborations must never
    # reuse a binary built with another debug/optimization configuration.
    if debug!='typical' or optimization is not None:
        identity['elaboration']=dict(debug=debug,optimization=optimization)
    signature = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    if output.is_file():
        previous = json.loads(output.read_text())
        if previous.get('signature') == signature and (Path(previous['cwd']) / 'xsim.dir' / previous['snapshot']).is_dir():
            return Result(0, 'Reused source-identical Vivado elaboration.\n',
                          commands=[dict(record, execution='reused') for record in previous['commands']])
    cwd = Path(tempfile.mkdtemp(prefix=output.stem + '_', dir=output.parent))
    snapshot = 'sim_' + signature[:16]
    arguments = ['-sv']
    for directory in include_dirs:
        arguments.extend(['-i', str(directory)])
    commands = [_invoke(executables['xvlog'], [*arguments, *inputs], cwd, timeout)]
    if not commands[-1]['returncode']:
        elaborate = [top, '-s', snapshot, '--timescale', '1ns/1ps', '--debug', debug]
        if optimization is not None:elaborate.append(f'--O{optimization}')
        for name, value in (parameters or {}).items():
            if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
                raise ValueError(f'invalid top-level parameter name {name}')
            elaborate.extend(['--generic_top', f'{name}={value}'])
        commands.append(_invoke(executables['xelab'], elaborate, cwd, timeout))
    for record in commands:
        record['source_identity'] = identity
        record['compile_signature'] = signature
    result = Result(commands[-1]['returncode'], ''.join(row['stdout'] for row in commands),
                    ''.join(row['stderr'] for row in commands), commands)
    if not result.returncode:
        output.write_text(json.dumps(dict(cwd=str(cwd), snapshot=snapshot, signature=signature,
                                         identity=identity, commands=commands), indent=2) + '\n')
    return result


def run_rtl(output, plusargs, *, root, timeout=180):
    descriptor = json.loads(Path(output).read_text())
    cwd = Path(descriptor['cwd'])
    arguments = [descriptor['snapshot'], '-runall', '-onerror', 'quit']
    for argument in plusargs:
        arguments.extend(['-testplusarg', str(argument).removeprefix('+')])
    command = _invoke(tools()['xsim'], arguments, cwd, timeout)
    command['compile_signature'] = descriptor['signature']
    return Result(command['returncode'], command['stdout'], command['stderr'], [command])
