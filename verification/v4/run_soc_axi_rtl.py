"""Run the vendor PS/AXI/interrupt-controller system test in Vivado XSim."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

from scripts.v4.xsim import _invoke, filelist_sources, tools
from verification.v4.soc_axi_fixtures import build_case, write_fixture

ROOT = Path(__file__).resolve().parents[2]
ALGORITHMS = ('MP', 'OMP', 'GOMP', 'CoSaMP', 'SP', 'IHT', 'HTP', 'GP', 'FISTA', 'PDHG')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--reuse-build', action='store_true')
    parser.add_argument('--algorithms', nargs='+', choices=ALGORITHMS, default=ALGORITHMS)
    args = parser.parse_args()
    directory = args.work.resolve() if args.work else Path(tempfile.mkdtemp(prefix='soc_axi_', dir=ROOT / 'work'))
    if directory.parent != ROOT / 'work' or not directory.name.startswith('soc_axi_'):
        parser.error('--work must be a direct child of work named soc_axi_*')
    directory.mkdir(exist_ok=True)
    paths = [*filelist_sources(ROOT), *sorted((ROOT / 'rtl/v4/include').glob('*.vh')),
             ROOT / 'verification/v4/host/tb_soc_axi.sv',
             ROOT / 'verification/v4/soc_axi_fixtures.py', Path(__file__).resolve(),
             ROOT / 'scripts/v4/build_soc_test.tcl', ROOT / 'scripts/v4/xsim.py',
             ROOT / 'verification/v4/recovery_program_vm.py']
    paths += sorted((ROOT / 'compiler/v4').glob('*.py'))
    paths += sorted((ROOT / 'models/v4').glob('*.py'))
    hashes = {str(path): digest(path) for path in paths}
    for path in paths:
        destination = directory / 'source_snapshot' / path.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() and digest(destination) != hashes[str(path)]:
            raise RuntimeError(f'Refusing to rewrite historical source snapshot: {destination}')
        if not destination.exists():
            shutil.copy2(path, destination)
    evidence = {'scope': 'PS VIP bus-functional SoC integration; not ARM instruction execution',
                'source_hashes_before': hashes, 'runs': [], 'commands': [], 'status': 'RUNNING'}
    evidence_path = directory / 'soc_evidence.json'
    if evidence_path.exists():
        raise RuntimeError('Use a fresh evidence directory; existing evidence is immutable')

    def save():
        evidence_path.write_text(json.dumps(evidence, indent=2) + '\n')

    def invoke(tool, arguments, cwd, timeout):
        record = _invoke(tool, arguments, cwd, timeout)
        evidence['commands'].append(record)
        save()
        if record['returncode']:
            raise RuntimeError(record['stdout'][-8000:] + record['stderr'][-8000:])
        return record

    try:
        vivado = tools()['xsim'].parent / 'vivado.bat'
        if not args.reuse_build:
            invoke(vivado, ['-mode', 'batch', '-log', str(directory / 'build.log'),
                           '-journal', str(directory / 'build.jou'), '-source',
                           str(ROOT / 'scripts/v4/build_soc_test.tcl'), '-tclargs', str(directory)], ROOT, 1200)
        simulation_dir = directory / 'project/soc_test.sim/sim_1/behav/xsim'
        invoke(simulation_dir / 'compile.bat', [], simulation_dir, 1200)
        invoke(simulation_dir / 'elaborate.bat', [], simulation_dir, 1200)
        for algorithm in args.algorithms:
            case = build_case(algorithm)
            fixture = directory / f'{algorithm}.fixture'
            trace = directory / f'{algorithm}.trace'
            write_fixture(case, fixture)
            (directory / f'{algorithm}.json').write_text(json.dumps(case, indent=2) + '\n')
            result = invoke(tools()['xsim'], ['tb_soc_axi_behav', '-runall', '-onerror', 'quit',
                            '-testplusarg', f'fixture={fixture.as_posix()}',
                            '-testplusarg', f'trace={trace.as_posix()}'], simulation_dir, 1800)
            text = trace.read_text() if trace.exists() else ''
            if 'PASS soc_axi' not in text or 'PASS soc_axi' not in result['stdout']:
                raise RuntimeError(f'{algorithm}: missing explicit testbench PASS')
            evidence['runs'].append({'algorithm': algorithm, 'fixture_sha256': digest(fixture),
                                     'golden_sha256': digest(directory / f'{algorithm}.json'),
                                     'trace_sha256': digest(trace), 'trace': text})
            save()
            print(f'{algorithm}: {text.strip()}', flush=True)
        evidence['status'] = 'PS_VIP_SOC_INTEGRATION_PASS'
    except BaseException as error:
        evidence['status'] = 'FAIL'
        evidence['error'] = repr(error)
        raise
    finally:
        evidence['source_hashes_after'] = {str(path): digest(path) for path in paths}
        evidence['source_unchanged'] = evidence['source_hashes_after'] == hashes
        if not evidence['source_unchanged']:
            evidence['status'] = 'FAIL_SOURCE_CHANGED'
        save()
    if evidence['status'] != 'PS_VIP_SOC_INTEGRATION_PASS':
        raise RuntimeError(evidence['status'])
    print(f'Evidence: {evidence_path}')


if __name__ == '__main__':
    main()
