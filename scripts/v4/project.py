"""Generate/check the v4 module catalog and diagram index from their sources."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]


def generated_files():
    manifest = json.loads((ROOT/'config/v4_modules.json').read_text(encoding='utf-8'))
    modules = manifest['modules']
    ids = [m['id'] for m in modules]
    if len(ids) != len(set(ids)) or len({m['rtl'] for m in modules}) != len(modules):
        raise ValueError('module names and source paths must be unique')
    known = set(ids)
    implemented = set(manifest.get('implemented_modules', []))
    if not implemented <= known:
        raise ValueError('implementation inventory contains unknown modules')
    for module in modules:
        if module['id'] in implemented and not (ROOT/module['rtl']).is_file():
            raise ValueError('implementation inventory refers to a missing source')
    children = {m['id']:m['children'] for m in modules}
    for m in modules:
        if not re.fullmatch(r'[a-z][a-z0-9_]*',m['id']) or 'v4' in m['id'].lower():
            raise ValueError('invalid module identifier')
        path = Path(m['rtl'])
        if '..' in path.parts or not m['rtl'].startswith('rtl/v4/') or path.suffix != '.sv':
            raise ValueError('module path outside the v4 SystemVerilog tree')
        if not isinstance(m['instances'],int) or m['instances'] < 1:
            raise ValueError('invalid system instance count')
        if not set(m['children']) <= known:
            raise ValueError('unknown child module')
    for source in (ROOT/'rtl/v4').rglob('*'):
        if source.suffix not in ('.sv', '.vh'):
            continue
        code = re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"', '',
                      source.read_text(encoding='utf-8'), flags=re.S)
        if re.search(r'\b\w*v4\w*\b', code, re.I):
            raise ValueError(f'version label in RTL identifier: {source.relative_to(ROOT)}')
    seen = set()
    def visit(node, stack):
        if node in stack:
            raise ValueError('module instantiation cycle')
        seen.add(node)
        for child in children[node]:
            visit(child, stack|{node})
    top = manifest['top']
    references = manifest.get('reference_roots', [])
    if top not in known or len(references) != len(set(references)) or not set(references) <= known:
        raise ValueError('invalid target or reference root')
    visit(top,set())
    target_nodes = seen.copy()
    if set(references) & target_nodes:
        raise ValueError('reference root must be outside the physical target hierarchy')
    for reference in references:
        visit(reference,set())
    if seen != known:
        raise ValueError('orphan module outside target and reference hierarchies')
    lines = ['# Module catalog v4','',
        'Generated from [v4_modules.json](../../../config/v4_modules.json).',
        'Edit that JSON, then run `py -3 scripts/v4/project.py generate`.','',
        '**Recovery RTL: the source-qualified five-step closure has matched active10 fixed-eight gates at M32/N64/K8 and M64/N256/K8; [five-step evidence](../../../reports/v4/five_optimizations_20260910/README.md), [A/B/C comparison](../../../reports/v4/resident_chain_comparison_20260910/resident_chain_comparison_vi.md), [scalar RTL gate](../../../reports/v4/scalar_insert_rtl_20260910/qualification.json), [numerical archive](../../../reports/v4/scalar_insert_numerical_20260910/archive_manifest.json), and [promotion manifest](../../../reports/v4/scalar_insert_promotion_20260910/before_after_manifest.json) are separate. PPA, timing, board and production bits remain unqualified. ADMM is historical reference-only.**','',
        'The implemented host path is csr_top -> host_command_bridge -> recovery_engine -> stream_kernel, with QR for support least squares.',
        'A loaded program PC drives generic kernels on exactly two 4x4 streaming PE arrays and one shared DIV/SQRT/RESCALE service.',
        'Live operator memory owns one Phi sign cache, one paired dense B cache and the Psi=I support builder.',
        'Native whole-result publication, factor storage, panel project update and scalar insertion have source-bound Vivado XSim evidence. The five final evidence links above separate matched whole-program, focused RTL, numerical, and installation scope. Held-out application workloads, synthesis, timing, PPA, board deployment and production bits remain unqualified; see current status for evidence boundaries.',
        'The bounded LSQR, tile64/control256 resident and revision-one stream wrappers are separate references. They add no arrays to the target.',
        'The host/AXI boundary is implemented by csr_top and host_command_bridge; see [AXI register map](AXI_REGISTER_MAP.md) and [CPU interface status](CPU_INTERFACE_STATUS.md). AXI protocol, real-core smoke, packaging, board, timing and PPA qualification remain separate or unqualified.','',
        'Current RTL acceptance uses Vivado xsim only. Earlier tool reports are historical evidence for their recorded source snapshots.',
        'See [current system contract](STREAM_SYSTEM_CONTRACT.md), [QR target](QR_SOLVER.md),',
        '[historical baseline](BASELINE.md), [resident contract](RESIDENT_RTL_CONTRACT.md),',
        '[LSQR integration](LSQR_INTEGRATION.md), [kernel contract](KERNEL_RTL_CONTRACT.md),',
        '[operator memory](OPERATOR_MEMORY_RTL_CONTRACT.md), [commit contract](COMMIT_RTL_CONTRACT.md),',
        'and [stream first-slice contract](STREAM_RTL_CONTRACT.md).','',
        manifest.get('streaming_candidate_note', ''),'',
        manifest.get('reader_hierarchy_note', ''),'',
        '## State ownership and interfaces','',
        '| Module | Target instances | Source | RTL scope/status | State ownership | Interface |',
        '|---|---:|---|---|---|---|']
    for m in modules:
        status = m.get('rtl_scope', 'RTL; see current evidence') if m['id'] in implemented else 'Planned'
        target_count = m['instances'] if m['id'] in target_nodes else 0
        lines.append(f"| `{m['id']}` | {target_count} | `{m['rtl']}` | {status} | {m['owns']} | {m['interface']} |")
    lines += ['', '## Instantiation hierarchy','', 'Counts above are physical target totals, not an elaborated full top; each array contains sixteen PEs. Auxiliary reference roots have zero target instances.',
              'The target keeps exactly two 4x4 streaming PE arrays (32 PEs total). QR factor-panel and command-local support transport reuse those existing PEs and bounded command state; terminal ACC uses existing PEACC and fixed registered reduction links. This adds no terminal arithmetic block, general programmable mesh routing, full mesh CGRA, PE or multiplier.','', '```mermaid','flowchart TB']
    for m in modules:
        if m['id'] not in target_nodes:
            continue
        lines.append(f"  {m['id']}[\"{m['id']}\"]")
        lines.extend(f"  {m['id']} --> {child}" for child in m['children'])
    lines += ['```','', '## Auxiliary/reference roots','',
              'These wrappers are elaborated separately and do not add feeder or PE resources to the target above.','']
    for reference in references:
        lines += [f'### `{reference}`','', '```mermaid','flowchart TB']
        reference_seen = set()
        def draw_reference(node):
            if node in reference_seen:
                return
            reference_seen.add(node)
            lines.append(f'  {node}["{node}"]')
            for child in children[node]:
                lines.append(f'  {node} --> {child}')
                draw_reference(child)
        draw_reference(reference)
        lines += ['```','']
    lines += ['## Common interface rules','',
        '- Clock `clk`; internal synchronous active-high reset `rst`.',
        '- Transfer only on `valid && ready`; hold payload/tags under backpressure.',
        '- `job_tag`, `op_tag`, `format_tag`, `lane_mask`, `last` travel with data.',
        '- Config/opcode/profile definitions are shared generated inputs, not per-module copies.',
        '- Native whole-result publication retains the selected X24 greedy or D18 proximal storage format and normalization metadata; kernel CALL publication is a distinct boundary.',
        '- QR uses loaded generic services on the shared 32 PEs and private factor storage. Consult [current status](../STATUS.md) and the source-bound evidence links above for the qualified source scope and its remaining boundaries; board, PPA and production-bit qualification remain unqualified. LSQR is reference only, with no implicit fallback.',
        '- Version labels belong to directory names. RTL identifiers use functional names and CSR_* macros.',
        '', '## Coding model preference','',
        'Current request: Astra Ultra coordinates and reviews; GPT-5.6 Terra agents at high reasoning effort implement code. Review existing RTL/TBs first and preserve implementations that pass.',
        'See [RTL instructions](../../../rtl/v4/AGENTS.md).']
    diagrams = ['# Sơ đồ v4','',
        'Generated from the `.mmd` sources in this directory; edit those sources and run',
        '`py -3 scripts/v4/project.py generate`. Each diagram identifies implemented, planned or reference scope.',
        'These are logical architecture/dataflow diagrams, not placed-and-routed layouts.','',
        'Source references: [system contract](../ARCHITECTURE_SPEC.md),',
        '[module catalog](../architecture/MODULES.md), [status](../STATUS.md).']
    titles = {'recovery':'Current recovery target: shared stream kernel, live operator and loaded programs',
              'operator_pipeline':'Queued Phi/B transport: four frames, shared cache and paired memory',
              'qr':'QR target: shared PEs, implicit reflectors and stored-X certificate',
              'stream':'Separately elaborated stream first slice: loadable programs and per-PE contexts',
              'lsqr':'Historical LSQR reference: shared operator, 32 PEs and certified commit',
              'resident':'Separately elaborated resident GEMV reference',
              'baseline':'Historical baseline: generated cache và LSQR',
              'numeric_contract':'Numerical: chuẩn hóa và nghiệm lưu X',
              'zcu106':'ZCU106: CPU, DDR và accelerator','system':'System reference và đường dữ liệu',
              'matrix':'Matrix image reference hai orientation','matrix_single':'Candidate một-copy đọc hai hướng',
              'generated_operator':'Candidate tự sinh: cache dấu, transform và LS',
              'context':'Compiler, context image và PE execution','solver':'CGLS reference và post-storage certificate',
              'context_stream_execution':'Context-stream execution: loaded QR commands, range transport and scalar insertion',
              'panel_mapping':'Factor-panel mapping: shared 32 PEs and private factor transport'}
    for stem,title in titles.items():
        source = ROOT/f'docs/v4/diagrams/{stem}.mmd'
        diagrams += ['',f'## {title}','',f'[Mermaid source]({stem}.mmd)','',
                     '```mermaid',source.read_text(encoding='utf-8').rstrip(),'```']
    return {ROOT/'docs/v4/architecture/MODULES.md':'\n'.join(lines)+'\n',
            ROOT/'docs/v4/diagrams/README.md':'\n'.join(diagrams)+'\n'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['generate','check'])
    args = parser.parse_args()
    stale = []
    for path,expected in generated_files().items():
        if args.action == 'generate':
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(expected,encoding='utf-8')
        elif not path.exists() or path.read_text(encoding='utf-8') != expected:
            stale.append(str(path.relative_to(ROOT)))
    if stale:
        print('Stale generated documents: '+', '.join(stale),file=sys.stderr)
        return 1
    if args.action == 'check':
        missing = []
        docs = list((ROOT/'docs/v4').rglob('*.md'))+[ROOT/'V4.md',ROOT/'rtl/v4/README.md']
        for path in docs:
            for target in re.findall(r'\]\(([^)]+)\)',path.read_text(encoding='utf-8')):
                if target.startswith(('http:','https:','#')):
                    continue
                if not (path.parent/target.split('#')[0]).exists():
                    missing.append((str(path.relative_to(ROOT)),target))
        if missing:
            print('Broken local document links: '+repr(missing),file=sys.stderr)
            return 1
    print(f'v4 project {args.action}: module hierarchy and generated documents OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

