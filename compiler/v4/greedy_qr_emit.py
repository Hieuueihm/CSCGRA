"""Greedy outer programs using the explicit Householder QR subroutine.

The immutable sign-Phi operator gives every column the same norm, so OMP's
normalized ranking is exactly the ordinary stable magnitude ranking here.
No support truncation or alternative least-squares backend is introduced.
"""
from fractions import Fraction
from compiler.v4.recovery_emit import Program
from compiler.v4.recovery_program import ABI


ALGORITHMS = ('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP')


def compile_greedy_qr(algorithm, matrix, policy, *, r4=None, max_refinements=2,
                     qr_cache_entries=None, qr_schedule_compact=None, qr_scalar_template=None,
                     qr_profile='reference', qr_panel_min_columns=8, operand_chains=False,
                     factor_range_template=False, factor_energy_tap=False, outer_fusion=False):
    if algorithm not in ALGORITHMS:
        raise ValueError('a QR-calling greedy algorithm is required')
    if not isinstance(max_refinements, int) or not 0 <= max_refinements <= 2:
        raise ValueError('max_refinements must be 0..2')
    if not isinstance(operand_chains, bool):
        raise ValueError('operand_chains must be boolean')
    if type(outer_fusion) is not bool:
        raise ValueError('outer_fusion must be boolean')
    if not isinstance(factor_range_template, bool):
        raise ValueError('factor_range_template must be boolean')
    if not isinstance(factor_energy_tap, bool):
        raise ValueError('factor_energy_tap must be boolean')
    p = Program(algorithm, matrix, policy, r4, outer_fusion)
    a = p.a
    if qr_profile not in ('reference', 'balanced', 'panel', 'reuse', 'resident', 'compact', 'streamed', 'view'):
        raise ValueError('QR profile must be reference, balanced, panel, reuse, resident, compact, streamed or view')
    if (qr_profile in ('reuse', 'resident', 'compact', 'streamed', 'view') and algorithm in ('OMP', 'GOMP') and
            qr_cache_entries not in (None, 0)):
        raise ValueError('reuse OMP/GOMP requires qr_cache_entries=0')
    if type(qr_panel_min_columns) is not int or not 1<=qr_panel_min_columns<=96:
        raise ValueError('QR panel minimum must be1..96')
    balanced = qr_profile in ('balanced', 'panel', 'reuse', 'resident', 'compact', 'streamed', 'view')
    if qr_cache_entries is None:
        qr_cache_entries = {'OMP': 0, 'GOMP': 0, 'CoSaMP': 2, 'SP': 2, 'HTP': 1}[algorithm] if balanced else 0
    if qr_schedule_compact is None:
        qr_schedule_compact = balanced
    if qr_scalar_template is None:
        qr_scalar_template = balanced
    if type(qr_cache_entries) is not int or qr_cache_entries not in (0, 1, 2):
        raise ValueError('QR result cache supports zero, one or two entries')
    if type(qr_schedule_compact) is not bool:
        raise ValueError('QR compact schedule is a boolean')
    if type(qr_scalar_template) is not bool:
        raise ValueError('QR scalar-template selection is a boolean')
    if not isinstance(policy.sparsity, int) or not 1 <= policy.sparsity <= p.n:
        raise ValueError('sparsity must be 1..N')
    if policy.residual_atol < 0 or not 0 < policy.ls_normal_rtol < 1:
        raise ValueError('invalid residual or stored-X certificate tolerance')
    if not isinstance(policy.group_size, int) or policy.group_size < 1:
        raise ValueError('group_size must be positive')

    limit = policy.max_iterations
    exhausted = 'MAX_ITERATIONS'
    if algorithm == 'GOMP':
        paper_limit = min(policy.sparsity, p.m // policy.group_size)
        limit = min(limit, paper_limit)
        if limit == paper_limit:
            exhausted = 'PAPER_ITERATION_LIMIT'
        maximum_support = min(p.n, limit * policy.group_size)
    elif algorithm == 'OMP':
        maximum_support = min(p.n, limit)
    elif algorithm == 'CoSaMP':
        maximum_support = min(p.n, 3 * policy.sparsity)
    elif algorithm == 'SP':
        maximum_support = min(p.n, 2 * policy.sparsity)
    else:
        maximum_support = policy.sparsity
    if maximum_support > min(p.m, 96):
        raise ValueError('policy can request a restricted solve beyond min(M,96); choose an explicit supported policy')
    # Capacity derives only from the selected algorithm and policy.  No panel
    # instruction or Q descriptor is emitted when it cannot be reached.
    panel_min_columns = (qr_panel_min_columns if qr_profile in ('panel', 'reuse', 'resident', 'compact', 'streamed', 'view') and
                         maximum_support > qr_panel_min_columns else 0)
    panel_disabled_reason = (None if panel_min_columns else
                             'profile_not_panel_or_reuse' if qr_profile not in ('panel', 'reuse', 'resident', 'compact', 'streamed', 'view') else
                             'maximum_support_not_wider_than_threshold')
    reuse_enabled = qr_profile in ('reuse', 'resident', 'compact', 'streamed', 'view') and algorithm in ('OMP', 'GOMP')
    resident_project = qr_profile in ('resident', 'compact', 'streamed', 'view') and panel_min_columns != 0
    scalar_insert = qr_profile in ('compact', 'streamed', 'view')
    stream_scalar_insert = qr_profile in ('streamed', 'view')
    range_template = qr_profile == 'view'
    if factor_range_template and not range_template:
        raise ValueError('factor_range_template requires qr_profile=view')
    if factor_energy_tap and not range_template:
        raise ValueError('factor_energy_tap requires qr_profile=view')

    for name in ('G', 'C'):
        p.vec(name)
    if algorithm == 'HTP':
        p.vec('T')
    for name in ('NR', 'M'):
        p.vec(name, p.m)
    for name in ('NS', 'CH', 'PX'):
        p.vec(name, 96)
    # OMP/GOMP reuse only retains ordered support, tau and the *initial* Q^T
    # RHS.  The mutable factor image stays exclusively in factor_store.
    if reuse_enabled:
        for name, capacity in (('RU_S', 96), ('RU_T', 96), ('RU_QTY', p.m)):
            p.vec(name, capacity)
        p.set(23, 0)  # invalid until a certified QR return publishes all state
        p.set(24, 0)
    # Entries are scoped to this complete program invocation. Resetting these
    # count registers before any lookup rejects all RAM left by prior jobs.
    cache = []
    for entry in range(qr_cache_entries):
        names = (f'QC{entry}_S', f'QC{entry}_X', f'QC{entry}_R')
        for name, capacity in zip(names, (96, 96, p.m)):
            p.vec(name, capacity)
        count, steps = (23, 27) if entry == 0 else (24, 31)
        p.set(count, 0)
        cache.append((names, count, steps))

    # The QR helper preserves R16..R31 except R25 (returned solve count).
    p.set(16, min(p.m, 96))
    p.set(17, policy.sparsity)
    if algorithm == 'HTP':
        p.set(18, p.scalar(policy.step_size, True))
    selection_count = (policy.group_size if algorithm == 'GOMP' else
                       min(p.n, 2 * policy.sparsity) if algorithm == 'CoSaMP' else
                       policy.sparsity if algorithm == 'SP' else 1)
    p.set(19, selection_count)
    p.set(20, 1)
    p.set(30, limit)
    tolerance = Fraction(str(policy.residual_atol)) * 2**22
    numerator = a.constant(tolerance.denominator**2)
    denominator = a.constant(tolerance.numerator**2)

    def residual_test(label):
        p.energy('R', 21, p.m)
        a.emit('CERT', dst_s=1, a_s=21, b_s=20,
               immediate=numerator | (denominator << 10))
        p.branch('BR_NONZERO', label, a_s=1)

    def solve():
        if reuse_enabled:
            p.branch('CALL', 'qr_reuse_dispatch')
        elif cache:
            p.branch('CALL', 'qr_cached')
        else:
            a.emit('BUILD_B', a_v=p.v['NS'], a_s=28)
            p.branch('CALL', 'qr')
        p.call('SCATTER', 'C', 'PX', support_v=p.v['NS'], support_length_s=28)

    def accept(increment=True):
        p.op('copy', 'X', 'C')
        p.op('copy', 'R', 'NR', length=p.m)
        p.op('copy', 'S', 'NS', length=(28,))
        a.emit('MOV', dst_s=29, a_s=28)
        if increment:
            p.inc(26)

    # SP has a genuine initial solve before its counted outer iterations.
    if algorithm == 'SP':
        residual_test('residual_done')
        p.mv('G', 'R', True)
        p.call('TOPK', 'NS', 'G', k_s=17, flags=2, flag=28, count=True)
        solve()
        accept(increment=False)

    a.label('outer')
    residual_test('residual_done')
    p.branch('BR_GE', 'max_done', a_s=26, b_s=30)
    p.mv('G', 'R', True)
    if algorithm in ('OMP', 'GOMP'):
        p.call('TOPK', 'CH', 'G', k_s=19, flags=1, flag=8, count=True,
               support_v=p.v['S'], support_length_s=29)
        p.branch('BR_COMPARE', 'no_new_atom', a_s=8, b_s=19,
                 immediate=ABI['comparisons']['LT'])
        p.call('UNION', 'NS', k_s=16, flags=1, flag=28, count=True,
               support_v=p.v['S'], support_length_s=29,
               aux_v=p.v['CH'], aux_length_s=8)
        solve()
    elif algorithm in ('CoSaMP', 'SP'):
        p.call('TOPK', 'CH', 'G', k_s=19, flag=8, count=True)
        p.call('UNION', 'NS', k_s=16, flag=28, count=True,
               support_v=p.v['S'], support_length_s=29,
               aux_v=p.v['CH'], aux_length_s=8)
        solve()
        p.call('TOPK', 'NS', 'C', k_s=17, flags=2, flag=28, count=True)
        if algorithm == 'SP':
            solve()
        else:
            p.call('APPLY_SUPPORT', 'C', 'C', support_v=p.v['NS'], support_length_s=28)
    else:
        if outer_fusion:
            p.affine('T', 'X', 'G', scalar=18)
        else:
            p.scale_op('T', 'G', 18)
            p.op('add', 'T', 'X', 'T')
        p.call('TOPK', 'NS', 'T', k_s=17, flags=2, flag=28, count=True)
        solve()

    p.store('C', 'C')
    # QR returns the residual of its final stored candidate. CoSaMP changes
    # that candidate after the solve, so only its prune needs a fresh GEMV.
    if algorithm == 'CoSaMP':
        p.residual('NR', 'C', 'M')
    if algorithm == 'SP' and policy.sp_stop_on_non_decrease:
        p.energy('NR', 22, p.m)
        p.branch('BR_GE', 'rollback', a_s=22, b_s=21)
    accept()
    p.branch('JUMP', 'outer')

    for label, status in (
        ('residual_done', 'RESIDUAL_TOLERANCE'), ('max_done', exhausted),
        ('no_new_atom', 'NO_NEW_ATOM'), ('rollback', 'RESIDUAL_NOT_DECREASED'),
        ('qr_failure', 'LS_NOT_CONVERGED'), ('qr_rank', 'NUMERIC_FAULT'),
    ):
        a.label(label)
        p.halt(status)

    from compiler.v4.qr_program import emit_qr, emit_qr_reuse
    if cache:
        a.label('qr_cached')
        for entry, (names, count, steps) in enumerate(cache):
            next_label = f'qr_cache_next_{entry}'
            p.branch('BR_COMPARE', next_label, a_s=28, b_s=count,
                     immediate=ABI['comparisons']['NE'])
            # Full ordered equality: indices are exact small integers and the
            # squared difference sum fits ACC64. CH is dead after NS creation.
            p.op('sub', 'CH', 'NS', names[0], length=(28,))
            p.energy('CH', 11, (28,))
            p.branch('BR_ZERO', f'qr_cache_hit_{entry}', a_s=11)
            a.label(next_label)
        a.label('qr_cache_miss')
        a.emit('BUILD_B', a_v=p.v['NS'], a_s=28)
        p.branch('CALL', 'qr')
        # Only a successful stored-X certificate returns here. Never cache a
        # failed solve. Cache publication occurs after all three vector copies.
        if len(cache) == 2:
            old, old_count, old_steps = cache[0]
            new, new_count, new_steps = cache[1]
            p.branch('BR_ZERO', 'qr_cache_insert', a_s=old_count)
            p.set(new_count, 0)
            for dst, src, length in zip(new, old, ((old_count,), (old_count,), p.m)):
                p.op('copy', dst, src, length=length)
            a.emit('MOV', dst_s=new_steps, a_s=old_steps)
            a.emit('MOV', dst_s=new_count, a_s=old_count)
        a.label('qr_cache_insert')
        names, count, steps = cache[0]
        p.set(count, 0)
        for dst, src, length in zip(names, ('NS', 'PX', 'NR'), ((28,), (28,), p.m)):
            p.op('copy', dst, src, length=length)
        a.emit('MOV', dst_s=steps, a_s=25)
        a.emit('MOV', dst_s=count, a_s=28)
        a.emit('RET')
        for entry, (names, count, steps) in enumerate(cache):
            a.label(f'qr_cache_hit_{entry}')
            p.op('copy', 'PX', names[1], length=(28,))
            p.op('copy', 'NR', names[2], length=p.m)
            a.emit('MOV', dst_s=25, a_s=steps)
            p.set(15, 1)
            a.emit('RET')
    emit_qr(p, 'qr', rhs_vector='Y', result_vector='PX', support_register=28,
            residual_vector='NR',
            failure_label='qr_failure', rank_label='qr_rank',
            max_refinements=max_refinements, schedule_compact=qr_schedule_compact,
            scalar_template=qr_scalar_template, panel_min_columns=panel_min_columns,
            resident_project=resident_project, scalar_insert=scalar_insert, stream_scalar_insert=stream_scalar_insert, range_template=range_template,
            factor_range_template=factor_range_template, factor_energy_tap=factor_energy_tap,
            initial_qty_vector='RU_QTY' if reuse_enabled else None)
    if reuse_enabled:
        # Op19 is pure factor-store transport: descriptor0 and all-zero
        # contexts prove it cannot consume or publish a vector-pool operand.
        p.t['factor_extend'] = len(a.templates)
        a.templates.append(dict(name='factor_extend', descriptor=0, bind_a=0,
                                bind_b=0, contexts=[0] * 32))
        a.label('qr_reuse_dispatch')
        # Never trust count alone.  Prefix mismatch, shrink/reorder or a
        # cleared job cache falls through to the ordinary BUILD_B+INIT path.
        p.branch('BR_ZERO', 'qr_reuse_fallback', a_s=23)
        p.branch('BR_COMPARE', 'qr_reuse_fallback', a_s=28, b_s=23,
                 immediate=ABI['comparisons']['LE'])
        p.op('sub', 'CH', 'NS', 'RU_S', length=(23,))
        p.energy('CH', 27, (23,))
        p.branch('BR_NONZERO', 'qr_reuse_fallback', a_s=27)
        a.emit('MOV', dst_s=24, a_s=23)
        p.set(23, 0)  # invalidate before extension/certificate work
        # BUILD_B publishes the new selected B image; rev4 keeps the old
        # private factors until FACTOR_EXTEND validates and appends the suffix.
        a.emit('BUILD_B', a_v=p.v['NS'], a_s=28)
        p.call('FACTOR_EXTEND', 'X', 'X', 'X', length=p.m,
               template='factor_extend', dense=1, support_length_s=28,
               index_s=24)
        p.branch('CALL', 'qr_reuse')
        p.branch('JUMP', 'qr_reuse_publish')
        a.label('qr_reuse_fallback')
        p.set(23, 0)
        a.emit('BUILD_B', a_v=p.v['NS'], a_s=28)
        p.branch('CALL', 'qr')
        a.label('qr_reuse_publish')
        # Publish only after the QR subroutine returned from its stored-X
        # certificate.  RU_QTY was captured before any correction solve.
        p.op('copy', 'RU_S', 'NS', length=(28,))
        p.op('copy', 'RU_T', 'qr_T', length=(28,))
        a.emit('MOV', dst_s=23, a_s=28)
        a.emit('RET')
        emit_qr_reuse(p, 'qr_reuse', rhs_vector='Y', result_vector='PX',
                      support_register=28, old_count_register=24,
                      tau_vector='RU_T', qty_vector='RU_QTY',
                      residual_vector='NR', failure_label='qr_failure',
                      rank_label='qr_rank', max_refinements=max_refinements,
                      schedule_compact=qr_schedule_compact,
                      scalar_template=qr_scalar_template, panel_min_columns=panel_min_columns,
                      resident_project=resident_project, scalar_insert=scalar_insert, stream_scalar_insert=stream_scalar_insert, range_template=range_template,
                      factor_range_template=factor_range_template, factor_energy_tap=factor_energy_tap, workspace_prefix='qr')
    package = p.finish()
    package.update(
        scope='Complete greedy outer candidate plus explicit Householder QR; numerical and RTL qualification are separate',
        least_squares='Householder QR; no fallback', qr_max_refinements=max_refinements,
        restricted_support_bound=maximum_support,
        residual_policy='Reuse exact final stored-X QR certificate residual; CoSaMP recomputes after pruning',
        policy_capacity='Reject potential restricted support beyond min(M,96); never truncate',
        qr_result_cache_entries=qr_cache_entries,
        qr_result_cache_scope='Per-invocation exact ordered support/count under immutable Phi/Y/scale/format/certificate policy; only certified stored X and its exact residual are cached',
        qr_schedule_compact=qr_schedule_compact,
        qr_scalar_template=qr_scalar_template,
        qr_execution_profile=qr_profile,
        qr_reuse_enabled=reuse_enabled,
        qr_resident_project_enabled=resident_project,
        qr_scalar_insert_enabled=scalar_insert,
        qr_stream_scalar_insert_enabled=stream_scalar_insert,
        qr_range_template_enabled=range_template,
        qr_factor_range_template_enabled=factor_range_template,
        qr_factor_range_template_scope=('QTy full patched column tap and backsolve L>=2 row head tap; L1 stays FACTOR_READ' if factor_range_template else 'disabled'),
        qr_factor_energy_tap_enabled=factor_energy_tap,
        qr_factor_energy_tap_scope=('QR reflector construction uses full unpatched factor taps, raw factor-square energy and a tail-nonzero response; QTy, backsolve, certificate and corrections stay unchanged' if factor_energy_tap else 'disabled'),
        operand_chains=operand_chains,
        operand_chains_emitted=False,
        operand_chain_scope=('legacy suite flag does not select QR outer fusion; use outer_fusion explicitly' if operand_chains else 'disabled'),
        outer_fusion=outer_fusion,
        outer_fusion_emitted=p.affine_emitted,
        outer_fusion_scope='Opt-in outer SCALE then ADD lowering only; inner QR and its certificates unchanged',
        qr_factor_project_update_transport=('FACTOR_PROJECT_UPDATE replaces FACTOR_MATVEC/SCALE/FACTOR_RANK1 only for reachable panel rectangles' if resident_project else 'not_emitted'),
        qr_reuse_algorithms=['OMP', 'GOMP'],
        qr_reuse_scope=('Per-invocation O(M+S) RU_S/RU_T/RU_QTY after certified stored-X only; exact ordered prefix plus immutable job/Phi/RHS are required; mismatch/shrink/reorder falls back to BUILD_B+FACTOR_INIT'),
        qr_reuse_b_epoch_scope=('Every INIT or EXTEND is preceded by BUILD_B. BUILD_B advances the live B epoch; '
                                'EXTEND accepts exactly the next owned B epoch with immutable Phi identity, job, format and rows, '
                                'then rebases factor ownership only after suffix commit'),
        qr_factor_init_transport='BUILD_B plus FACTOR_INIT on initial/nonprefix paths',
        qr_factor_extend_transport='BUILD_B plus FACTOR_EXTEND only after ordered-prefix proof' if reuse_enabled else 'not_emitted',
        qr_panel_min_columns=panel_min_columns,
        qr_panel_requested_min_columns=qr_panel_min_columns,
        qr_panel_maximum_working_support=maximum_support,
        qr_panel_disabled_reason=panel_disabled_reason,
        required_kernel_revision=(10 if factor_energy_tap else 9 if factor_range_template else 7 if qr_profile == 'view' else 6 if qr_profile in ('compact', 'streamed') else 5 if qr_profile == 'resident' else 4 if reuse_enabled else 3 if panel_min_columns else 2 if qr_scalar_template else 1),
        required_kernel_features=((['SCALAR_TEMPLATE', 'FACTOR_PANEL', 'FACTOR_EXTEND', 'FACTOR_PROJECT_UPDATE', 'SCALAR_INSERT', 'RANGE_TEMPLATE'] +
                                  (['FACTOR_RANGE_TEMPLATE'] if factor_range_template else []) + ['FACTOR_ENERGY_TAP']) if factor_energy_tap else
                                  ['SCALAR_TEMPLATE', 'FACTOR_PANEL', 'FACTOR_EXTEND', 'FACTOR_PROJECT_UPDATE', 'SCALAR_INSERT', 'RANGE_TEMPLATE', 'FACTOR_RANGE_TEMPLATE'] if factor_range_template else
                                  ['SCALAR_TEMPLATE', 'FACTOR_PANEL', 'FACTOR_EXTEND', 'FACTOR_PROJECT_UPDATE', 'SCALAR_INSERT', 'RANGE_TEMPLATE'] if qr_profile == 'view' else
                                  ['SCALAR_TEMPLATE', 'FACTOR_PANEL', 'FACTOR_EXTEND', 'FACTOR_PROJECT_UPDATE', 'SCALAR_INSERT'] if qr_profile in ('compact', 'streamed') else
                                  ['SCALAR_TEMPLATE', 'FACTOR_PANEL', 'FACTOR_EXTEND', 'FACTOR_PROJECT_UPDATE'] if qr_profile == 'resident' else
                                  ['SCALAR_TEMPLATE', 'FACTOR_PANEL', 'FACTOR_EXTEND'] if reuse_enabled else
                                  ['SCALAR_TEMPLATE', 'FACTOR_PANEL'] if panel_min_columns else
                                  ['SCALAR_TEMPLATE'] if qr_scalar_template else []),
    )
    if p.affine_emitted:
        package['required_kernel_revision'] = max(8, package['required_kernel_revision'])
        package['required_kernel_features'].append('ROUNDED_AFFINE')
    return package

