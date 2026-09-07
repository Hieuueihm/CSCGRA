"""Transaction-level cycle simulator for the complete v3 architecture.

The functional path comes from :mod:`models.v3.hardware`.  This module maps the
resulting phase trace onto the six locked macroblocks and a deterministic
resource-reservation scheduler.  It is a pre-RTL architecture estimate, not an
RTL timing measurement.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from math import ceil
from typing import Any, Iterable, Sequence

from compiler.v3 import architecture_configuration
from models.v3 import hardware


MACROBLOCKS = (
    "reconstruction_control",
    "context_programmed_cgra",
    "generated_phi_stream",
    "reconstruction_memory",
    "sparse_selection_support",
    "reconstruction_result_writer",
)


@dataclass(frozen=True)
class TimingContract:
    revision: int
    architecture_hash: str
    reduction_latency_cycles: int
    reduction_initiation_interval: int
    threefry_first_word_latency_cycles: int
    threefry_request_initiation_interval: int
    phi_normalize_latency_cycles: int
    phi_normalize_initiation_interval: int
    shared_vector_dot_latency_cycles: int
    shared_vector_dot_initiation_interval: int
    shared_vector_norm_latency_cycles: int
    shared_vector_norm_initiation_interval: int
    shared_vector_scale_latency_cycles: int
    shared_vector_scale_initiation_interval: int
    shared_vector_axpy_latency_cycles: int
    shared_vector_axpy_initiation_interval: int
    shared_vector_copy_latency_cycles: int
    shared_vector_copy_initiation_interval: int
    scalar_divide_cycles: int
    scalar_divide_initiation_interval: int
    topk_push_latency_cycles: int
    topk_push_initiation_interval: int
    topk_commit_cycles: int
    clock_hz: int = 150_000_000
    pe_lanes: int = 32
    phi_accumulate_cycles_per_term: int = 1
    shared_vector_lanes: int = 16
    axi_data_width: int = 128
    external_element_width: int = 32
    phase_dispatch_cycles: int = 1
    context_dispatch_cycles: int = 1
    array_fill_drain_cycles: int = 5
    phi_cache_fill_drain_cycles: int = 21
    candidate_symbol_capture: bool = True
    scalar_compare_cycles: int = 2
    support_item_cycles: int = 1
    dma_setup_cycles: int = 6
    run_configuration_words: int = 16
    run_configuration_words_per_axi_beat: int = 4
    run_configuration_validation_cycles: int = 16
    result_writer_lanes: int = 1
    terminal_cycles: int = 2
    external_axi_wait_cycles_per_beat: int = 0


def _timing_record(timing: dict[str, dict[str, Any]], name: str, *,
                   require_measured: bool) -> dict[str, Any]:
    if name not in timing:
        raise ValueError(f"architecture timing authority is missing {name}")
    record = timing[name]
    if require_measured:
        if record["status"] != "implemented" or record["timing_status"] != "measured":
            raise ValueError(f"{name} must be implemented with measured timing")
        if not record["timing_evidence"]:
            raise ValueError(f"{name} measured timing has no evidence")
    elif record["status"] not in {"implemented", "planned"}:
        raise ValueError(f"{name} is unavailable in the timing authority")
    return record


def timing_contract_from_architecture_configuration(
        configuration: dict[str, Any] | None = None) -> TimingContract:
    configuration = configuration or architecture_configuration.load()
    timing = architecture_configuration.operation_timing(configuration)
    measured_names = (
        "REDUCE_SUM", "PHI_SIGN_WORD", "PHI_NORMALIZE", "SCALAR_DIVIDE",
        "SHARED_VECTOR_DOT", "SHARED_VECTOR_NORM_SQ", "SHARED_VECTOR_SCALE",
        "SHARED_VECTOR_AXPY", "SHARED_VECTOR_COPY",
    )
    measured = {name: _timing_record(timing, name, require_measured=True)
                for name in measured_names}
    topk_push = _timing_record(timing, "TOPK_PUSH", require_measured=False)
    topk_commit = _timing_record(timing, "TOPK_COMMIT", require_measured=False)
    return TimingContract(
        revision=4,
        architecture_hash=architecture_configuration.configuration_hash(configuration),
        reduction_latency_cycles=measured["REDUCE_SUM"]["latency"],
        reduction_initiation_interval=measured["REDUCE_SUM"]["initiation_interval"],
        threefry_first_word_latency_cycles=measured["PHI_SIGN_WORD"]["latency"],
        threefry_request_initiation_interval=measured["PHI_SIGN_WORD"]["initiation_interval"],
        phi_normalize_latency_cycles=measured["PHI_NORMALIZE"]["latency"],
        phi_normalize_initiation_interval=measured["PHI_NORMALIZE"]["initiation_interval"],
        shared_vector_dot_latency_cycles=measured["SHARED_VECTOR_DOT"]["latency"],
        shared_vector_dot_initiation_interval=measured["SHARED_VECTOR_DOT"]["initiation_interval"],
        shared_vector_norm_latency_cycles=measured["SHARED_VECTOR_NORM_SQ"]["latency"],
        shared_vector_norm_initiation_interval=measured["SHARED_VECTOR_NORM_SQ"]["initiation_interval"],
        shared_vector_scale_latency_cycles=measured["SHARED_VECTOR_SCALE"]["latency"],
        shared_vector_scale_initiation_interval=measured["SHARED_VECTOR_SCALE"]["initiation_interval"],
        shared_vector_axpy_latency_cycles=measured["SHARED_VECTOR_AXPY"]["latency"],
        shared_vector_axpy_initiation_interval=measured["SHARED_VECTOR_AXPY"]["initiation_interval"],
        shared_vector_copy_latency_cycles=measured["SHARED_VECTOR_COPY"]["latency"],
        shared_vector_copy_initiation_interval=measured["SHARED_VECTOR_COPY"]["initiation_interval"],
        scalar_divide_cycles=measured["SCALAR_DIVIDE"]["latency"],
        scalar_divide_initiation_interval=measured["SCALAR_DIVIDE"]["initiation_interval"],
        topk_push_latency_cycles=topk_push["latency"],
        topk_push_initiation_interval=topk_push["initiation_interval"],
        topk_commit_cycles=topk_commit["latency"],
    )

@dataclass(frozen=True)
class TransactionSpec:
    name: str
    phase_seq: int
    iteration: int
    phase_name: str
    category: str
    macroblock: str
    duration: int
    resources: tuple[str, ...]
    dependencies: tuple[int, ...] = ()
    detail: dict[str, int | str | bool] = field(default_factory=dict)


@dataclass(frozen=True)
class ScheduledTransaction:
    transaction_id: int
    start_cycle: int
    end_cycle: int
    wait_cycles: int
    spec: TransactionSpec

    @property
    def duration(self) -> int:
        return self.end_cycle - self.start_cycle


class ResourceScheduler:
    """Earliest-start scheduler with exclusive multi-resource reservations."""

    def __init__(self) -> None:
        self.resource_free: dict[str, int] = {}
        self.scheduled: list[ScheduledTransaction] = []

    def schedule(self, spec: TransactionSpec) -> int:
        if spec.duration <= 0:
            raise ValueError("transaction duration must be positive")
        if spec.macroblock not in MACROBLOCKS:
            raise ValueError(f"unknown macroblock {spec.macroblock}")
        dependency_end = max(
            (self.scheduled[item].end_cycle for item in spec.dependencies),
            default=0,
        )
        resource_start = max(
            (self.resource_free.get(resource, 0) for resource in spec.resources),
            default=0,
        )
        start = max(dependency_end, resource_start)
        end = start + spec.duration
        item = ScheduledTransaction(
            transaction_id=len(self.scheduled),
            start_cycle=start,
            end_cycle=end,
            wait_cycles=start - dependency_end,
            spec=spec,
        )
        self.scheduled.append(item)
        for resource in spec.resources:
            self.resource_free[resource] = end
        return item.transaction_id


@dataclass(frozen=True)
class SimulationResult:
    algorithm: str
    case_name: str
    profile: str
    dimensions: dict[str, int]
    total_cycles: int
    ingress_cycles: int
    compute_cycles: int
    egress_cycles: int
    estimated_seconds: float
    estimated_microseconds: float
    category_cycles: dict[str, int]
    phase_cycles: dict[str, int]
    macroblock_busy_cycles: dict[str, int]
    resource_busy_cycles: dict[str, int]
    resource_utilization: dict[str, float]
    phase_invocations: dict[str, int]
    functional_stop_reason: str
    final_support_count: int
    numeric_events: dict[str, int]
    assumptions: dict[str, int | str | bool]
    transactions: tuple[ScheduledTransaction, ...]

    def payload(self, include_transactions: bool = True) -> dict:
        value = asdict(self)
        if not include_transactions:
            value.pop("transactions")
        return value


class ArchitectureSimulator:
    def __init__(self, timing: TimingContract | None = None,
                 result_mode: str = "both") -> None:
        self.t = timing or timing_contract_from_architecture_configuration()
        if result_mode not in {"dense", "sparse", "both"}:
            raise ValueError("result_mode must be dense, sparse or both")
        self.result_mode = result_mode
        self.scheduler = ResourceScheduler()
        self.frontier: tuple[int, ...] = ()

    @staticmethod
    def _div_up(value: int, lanes: int) -> int:
        return (value + lanes - 1) // lanes

    def _add(self, name: str, duration: int, *, phase_seq: int = -1,
             iteration: int = -1, phase_name: str = "RUN_BOUNDARY",
             category: str, macroblock: str, resources: Iterable[str],
             detail: dict[str, int | str | bool] | None = None,
             dependencies: Sequence[int] | None = None,
             chain: bool = True) -> int:
        deps = tuple(dependencies) if dependencies is not None else self.frontier
        transaction_id = self.scheduler.schedule(TransactionSpec(
            name=name, phase_seq=phase_seq, iteration=iteration,
            phase_name=phase_name, category=category, macroblock=macroblock,
            duration=max(1, int(duration)), resources=tuple(resources),
            dependencies=deps, detail=detail or {},
        ))
        if chain:
            self.frontier = (transaction_id,)
        return transaction_id

    def _axi_cycles(self, beats: int) -> int:
        return (self.t.dma_setup_cycles + beats
                * (1 + self.t.external_axi_wait_cycles_per_beat))

    @staticmethod
    def _pipeline_cycles(request_count: int, latency: int,
                         initiation_interval: int) -> int:
        if request_count <= 0 or latency <= 0 or initiation_interval <= 0:
            raise ValueError("pipeline timing values must be positive")
        return latency + (request_count - 1) * initiation_interval

    def _vector_cycles(self, length: int, operation: str) -> int:
        request_count = self._div_up(max(1, length), self.t.shared_vector_lanes)
        timing = {
            "DOT": (self.t.shared_vector_dot_latency_cycles,
                    self.t.shared_vector_dot_initiation_interval),
            "NORM_SQ": (self.t.shared_vector_norm_latency_cycles,
                        self.t.shared_vector_norm_initiation_interval),
            "SCALE": (self.t.shared_vector_scale_latency_cycles,
                      self.t.shared_vector_scale_initiation_interval),
            "AXPY": (self.t.shared_vector_axpy_latency_cycles,
                     self.t.shared_vector_axpy_initiation_interval),
            "COPY": (self.t.shared_vector_copy_latency_cycles,
                     self.t.shared_vector_copy_initiation_interval),
        }
        if operation not in timing:
            raise ValueError(f"unknown shared-vector operation {operation}")
        latency, initiation_interval = timing[operation]
        return self._pipeline_cycles(request_count, latency, initiation_interval)

    def _topk_cycles(self, candidate_count: int) -> int:
        return (self._pipeline_cycles(
            max(1, candidate_count), self.t.topk_push_latency_cycles,
            self.t.topk_push_initiation_interval) + self.t.topk_commit_cycles)

    def _array_operator_cycles(self, m: int, support_count: int) -> int:
        return (self._div_up(m * max(1, support_count), self.t.pe_lanes)
                * self.t.phi_accumulate_cycles_per_term
                + self.t.array_fill_drain_cycles)

    def _correlation_cycles(self, m: int, n: int) -> int:
        return (self._div_up(m * n, self.t.pe_lanes)
                * self.t.phi_accumulate_cycles_per_term
                + self.t.threefry_first_word_latency_cycles
                + self.t.reduction_latency_cycles
                + self.t.phi_normalize_latency_cycles)

    def _phase_add(self, phase: hardware.Phase, name: str, duration: int,
                   category: str, macroblock: str,
                   resources: Iterable[str], **detail: int | str | bool) -> int:
        return self._add(
            name, duration, phase_seq=phase.seq, iteration=phase.iteration,
            phase_name=phase.name, category=category, macroblock=macroblock,
            resources=resources, detail=detail,
        )

    def _schedule_ingress(self, m: int) -> tuple[int, int]:
        start = 0
        configuration_beats = self._div_up(
            self.t.run_configuration_words,
            self.t.run_configuration_words_per_axi_beat)
        self._add("run_configuration_fetch", self._axi_cycles(configuration_beats),
                  category="ingress", macroblock="reconstruction_control",
                  resources=("axi_read", "reconstruction_control"),
                  detail={"axi_beats": configuration_beats})
        self._add("run_configuration_validate",
                  self.t.run_configuration_validation_cycles,
                  category="ingress", macroblock="reconstruction_control",
                  resources=("reconstruction_control",))
        values_per_beat = self.t.axi_data_width // self.t.external_element_width
        measurement_beats = self._div_up(m, values_per_beat)
        self._add("measurement_preload", self._axi_cycles(measurement_beats),
                  category="ingress", macroblock="reconstruction_memory",
                  resources=("axi_read", "scratchpad_write"),
                  detail={"axi_beats": measurement_beats, "elements": m})
        self._add("context_activate", 2 * self.t.context_dispatch_cycles,
                  category="ingress", macroblock="reconstruction_control",
                  resources=("reconstruction_control", "context_store"))
        end = self.scheduler.scheduled[self.frontier[0]].end_cycle
        return start, end

    def _schedule_refinement_begin(self, phase: hardware.Phase, m: int) -> None:
        support_count = len(phase.support)
        cache_words = self._div_up(m * max(1, support_count), self.t.pe_lanes)
        if self.t.candidate_symbol_capture:
            self._phase_add(
                phase, "active_support_phi_cache_promote",
                self.t.phi_cache_fill_drain_cycles,
                "refinement", "generated_phi_stream",
                ("phi_cache_read", "phi_cache_write", "support_read"),
                support_count=support_count, captured_words=cache_words,
                eliminated_generator_words=cache_words)
        else:
            self._phase_add(
                phase, "active_support_phi_cache_fill",
                cache_words + self.t.phi_cache_fill_drain_cycles,
                "refinement", "generated_phi_stream",
                ("phi_generator", "phi_cache_write", "support_read"),
                support_count=support_count, cache_words=cache_words)
        proxy_reused = bool(phase.scalars.get("proxy_reused", False))
        if proxy_reused:
            self._phase_add(
                phase, "refinement_warm_start_gather",
                self._vector_cycles(support_count, "COPY"), "refinement",
                "sparse_selection_support",
                ("scratchpad_read", "shared_vector", "support_read"),
                support_count=support_count, proxy_reused=True)
        else:
            self._phase_add(
                phase, "initial_normal_residual",
                self._array_operator_cycles(m, support_count), "refinement",
                "context_programmed_cgra",
                ("cgra_array", "phi_cache_read", "scratchpad_read",
                 "cluster_reduction"), support_count=support_count)
        self._phase_add(
            phase, "refinement_initialize_vectors",
            self._vector_cycles(support_count, "COPY"), "refinement",
            "context_programmed_cgra",
            ("shared_vector", "scratchpad_read", "scratchpad_write"),
            support_count=support_count)

    def _schedule_refinement_step(self, phase: hardware.Phase, m: int) -> None:
        support_count = len(phase.support)
        self._phase_add(
            phase, "refinement_forward_Ap",
            self._array_operator_cycles(m, support_count), "refinement",
            "context_programmed_cgra",
            ("cgra_array", "phi_cache_read", "scratchpad_read",
             "scratchpad_write", "cluster_reduction"),
            support_count=support_count)
        self._phase_add(
            phase, "refinement_delta_norm",
            self._vector_cycles(m, "NORM_SQ"), "refinement",
            "context_programmed_cgra",
            ("shared_vector", "scratchpad_read", "global_reduction"),
            vector_length=m)
        self._phase_add(
            phase, "refinement_alpha_divide", self.t.scalar_divide_cycles,
            "refinement", "context_programmed_cgra", ("scalar_function",))
        self._phase_add(
            phase, "refinement_update_x",
            self._vector_cycles(support_count, "AXPY"), "refinement",
            "context_programmed_cgra",
            ("shared_vector", "scratchpad_read", "scratchpad_write"),
            vector_length=support_count)
        self._phase_add(
            phase, "refinement_update_r", self._vector_cycles(m, "AXPY"),
            "refinement", "context_programmed_cgra",
            ("shared_vector", "scratchpad_read", "scratchpad_write"),
            vector_length=m)
        self._phase_add(
            phase, "recurrence_solver_transpose",
            self._array_operator_cycles(m, support_count), "refinement",
            "context_programmed_cgra",
            ("cgra_array", "phi_cache_read", "scratchpad_read",
             "scratchpad_write", "cluster_reduction"),
            support_count=support_count)
        self._phase_add(
            phase, "recurrence_gamma_norm",
            self._vector_cycles(support_count, "NORM_SQ"), "refinement",
            "context_programmed_cgra",
            ("shared_vector", "scratchpad_read", "global_reduction"),
            vector_length=support_count)
        if bool(phase.scalars.get("recurrence_update", False)):
            self._phase_add(
                phase, "recurrence_beta_divide", self.t.scalar_divide_cycles,
                "refinement", "context_programmed_cgra", ("scalar_function",))
            self._phase_add(
                phase, "recurrence_update_p",
                self._vector_cycles(support_count, "AXPY"), "refinement",
                "context_programmed_cgra",
                ("shared_vector", "scratchpad_read", "scratchpad_write"),
                vector_length=support_count)

    def _schedule_refinement_certificate(self, phase: hardware.Phase, m: int) -> None:
        support_count = len(phase.support)
        self._phase_add(
            phase, "certificate_true_residual",
            self._array_operator_cycles(m, support_count)
            + self._vector_cycles(m, "AXPY"), "certificate",
            "context_programmed_cgra",
            ("cgra_array", "phi_cache_read", "scratchpad_read",
             "scratchpad_write", "shared_vector", "cluster_reduction"),
            support_count=support_count, post_d18=True)
        self._phase_add(
            phase, "certificate_normal_residual",
            self._array_operator_cycles(m, support_count)
            + self._vector_cycles(support_count, "NORM_SQ"), "certificate",
            "context_programmed_cgra",
            ("cgra_array", "phi_cache_read", "scratchpad_read",
             "shared_vector", "cluster_reduction", "global_reduction"),
            support_count=support_count, post_d18=True)
        self._phase_add(
            phase, "certificate_compare", self.t.scalar_compare_cycles,
            "certificate", "sparse_selection_support",
            ("refinement_checker",),
            passed=bool(phase.scalars.get("passed", False)))

    def _schedule_phase(self, trace: hardware.Trace, phase_index: int,
                        m: int, n: int, k: int) -> None:
        phase = trace.phases[phase_index]
        name = phase.name
        self._phase_add(
            phase, "phase_dispatch", self.t.phase_dispatch_cycles,
            "control", "reconstruction_control", ("control_sequencer",))

        if name in {"PROXY", "INIT_PROXY"}:
            self._phase_add(
                phase, "full_correlation_and_candidate_capture",
                self._correlation_cycles(m, n), "correlation",
                "context_programmed_cgra",
                ("cgra_array", "phi_generator", "scratchpad_read",
                 "cluster_reduction", "global_reduction", "topk"),
                measurement_count=m, signal_length=n)
        elif name == "REFINEMENT_BEGIN":
            self._schedule_refinement_begin(phase, m)
        elif name == "REFINEMENT_STEP":
            self._schedule_refinement_step(phase, m)
        elif name == "REFINEMENT_CERTIFICATE":
            self._schedule_refinement_certificate(phase, m)
        elif name == "REFINEMENT_RESTART":
            self._phase_add(
                phase, "refinement_restart_copy",
                self._vector_cycles(len(phase.support), "COPY"), "refinement",
                "sparse_selection_support",
                ("shared_vector", "scratchpad_read", "scratchpad_write",
                 "refinement_checker"), support_count=len(phase.support))
        elif name in {"REFINEMENT_COMMIT", "REFINEMENT_ROLLBACK"}:
            self._phase_add(
                phase, "refinement_atomic_commit" if name.endswith("COMMIT")
                else "refinement_atomic_rollback",
                self._vector_cycles(len(phase.support), "COPY"), "refinement",
                "sparse_selection_support",
                ("support_write", "scratchpad_write", "refinement_checker"),
                support_count=len(phase.support))
        elif (name in {"SELECT", "SELECT_GROUP", "IDENTIFY", "INIT_SELECT"}
              and not (name == "SELECT" and trace.algorithm == "HTP")):
            candidate_count = max(1, len(phase.candidates) or len(phase.support))
            self._phase_add(
                phase, "selection_finalize",
                self._topk_cycles(candidate_count), "selection_support",
                "sparse_selection_support", ("topk", "support_write"),
                candidate_count=candidate_count)
        elif name in {"MERGE"}:
            work_count = max(1, len(phase.support))
            self._phase_add(
                phase, "support_union",
                work_count * self.t.support_item_cycles + 2,
                "selection_support", "sparse_selection_support",
                ("support_read", "support_write"), work_count=work_count)
        elif name == "PRUNE" and trace.algorithm == "IHT":
            self._phase_add(
                phase, "iht_dense_topk",
                self._topk_cycles(n), "selection_support",
                "sparse_selection_support",
                ("topk", "scratchpad_read", "support_write"),
                source_count=n)
        elif name == "SELECT" and trace.algorithm == "HTP":
            self._phase_add(
                phase, "htp_dense_topk",
                self._topk_cycles(n), "selection_support",
                "sparse_selection_support",
                ("topk", "scratchpad_read", "support_write"),
                source_count=n)
        elif name == "PRUNE":
            prior_refinement_count = next(
                (len(item.support) for item in reversed(trace.phases[:phase_index])
                 if item.name == "REFINEMENT_COMMIT"), 0)
            source_count = max(k, prior_refinement_count,
                               len(phase.vectors.get("estimate", ())),
                               len(phase.support))
            self._phase_add(
                phase, "coefficient_topk",
                self._topk_cycles(source_count), "selection_support",
                "sparse_selection_support",
                ("topk", "scratchpad_read", "support_write"),
                source_count=source_count)
        elif name == "UPDATE" and trace.algorithm == "IHT":
            self._phase_add(
                phase, "iht_dense_gradient_update", self._vector_cycles(n, "AXPY"),
                "vector_update", "context_programmed_cgra",
                ("shared_vector", "scratchpad_read", "scratchpad_write"),
                vector_length=n)
        elif name == "DIRECTION" and trace.algorithm == "GP":
            support_count = max(1, len(phase.support))
            self._phase_add(
                phase, "gp_projected_direction",
                self._array_operator_cycles(m, support_count), "matrix_operator",
                "context_programmed_cgra",
                ("cgra_array", "phi_generator", "scratchpad_read",
                 "scratchpad_write", "cluster_reduction"),
                support_count=support_count)
            self._phase_add(
                phase, "gp_line_search_dots", 2 * self._vector_cycles(m, "DOT"),
                "vector_update", "context_programmed_cgra",
                ("shared_vector", "scratchpad_read", "global_reduction"),
                vector_length=m)
            self._phase_add(
                phase, "gp_line_search_divide", self.t.scalar_divide_cycles,
                "vector_update", "context_programmed_cgra",
                ("scalar_function",))
        elif name == "UPDATE" and trace.algorithm == "GP":
            self._phase_add(
                phase, "gp_active_update", self._vector_cycles(len(phase.support), "AXPY"),
                "vector_update", "context_programmed_cgra",
                ("shared_vector", "scratchpad_read", "scratchpad_write"),
                support_count=len(phase.support))
        elif name == "UPDATE" and trace.algorithm == "MP":
            self._phase_add(
                phase, "mp_rank1_coefficient_update", self.t.scalar_divide_cycles + 2,
                "vector_update", "context_programmed_cgra",
                ("scalar_function", "support_write"))
        elif name in {"RESIDUAL", "INIT_RESIDUAL", "RESIDUAL_CHECK"}:
            if trace.algorithm in {"OMP", "CoSaMP", "HTP", "SP", "GOMP"}:
                self._phase_add(
                    phase, "residual_commit_projection", 1, "control",
                    "sparse_selection_support", ("refinement_checker",))
            elif trace.algorithm == "MP":
                self._phase_add(
                    phase, "mp_rank1_residual_projection",
                    self._div_up(m, self.t.pe_lanes)
                    + self.t.array_fill_drain_cycles,
                    "residual", "context_programmed_cgra",
                    ("cgra_array", "phi_generator", "scratchpad_read",
                     "scratchpad_write"), support_count=1)
            else:
                support_count = max(1, len(phase.support))
                self._phase_add(
                    phase, "residual_recompute",
                    self._array_operator_cycles(m, support_count)
                    + self._vector_cycles(m, "AXPY"), "residual",
                    "context_programmed_cgra",
                    ("cgra_array", "phi_generator", "scratchpad_read",
                     "scratchpad_write", "shared_vector", "cluster_reduction"),
                    support_count=support_count)
        elif name in {"LS", "LS_WORK", "LS_FINAL", "INIT_LS"}:
            self._phase_add(
                phase, "ls_macro_commit_boundary", 1, "control",
                "reconstruction_control", ("control_sequencer",))
        elif name == "ROLLBACK":
            self._phase_add(
                phase, "sp_outer_rollback", 2, "selection_support",
                "sparse_selection_support", ("support_write", "scratchpad_write"))
        else:
            self._phase_add(
                phase, "phase_scalar_or_support_operation", 2, "control",
                "reconstruction_control", ("control_sequencer",))

    def _schedule_egress(self, n: int, support_count: int) -> tuple[int, int]:
        start = self.scheduler.scheduled[self.frontier[0]].end_cycle
        if self.result_mode in {"dense", "both"}:
            beats = self._div_up(n * self.t.external_element_width,
                                 self.t.axi_data_width)
            duration = (self._div_up(n, self.t.result_writer_lanes)
                        + self._axi_cycles(beats))
            self._add("dense_result_expand_and_drain", duration,
                      category="egress",
                      macroblock="reconstruction_result_writer",
                      resources=("result_writer", "support_read", "axi_write"),
                      detail={"elements": n, "axi_beats": beats})
        if self.result_mode in {"sparse", "both"}:
            beats = self._div_up(max(1, support_count) * 64,
                                 self.t.axi_data_width)
            self._add("sparse_result_drain",
                      max(1, support_count) + self._axi_cycles(beats),
                      category="egress",
                      macroblock="reconstruction_result_writer",
                      resources=("result_writer", "support_read", "axi_write"),
                      detail={"records": support_count, "axi_beats": beats})
        self._add("terminal_completion", self.t.terminal_cycles,
                  category="egress", macroblock="reconstruction_control",
                  resources=("reconstruction_control",))
        end = self.scheduler.scheduled[self.frontier[0]].end_cycle
        return start, end

    @staticmethod
    def _sum_by(items: Sequence[ScheduledTransaction], key) -> dict[str, int]:
        result: dict[str, int] = {}
        for item in items:
            name = str(key(item))
            result[name] = result.get(name, 0) + item.duration
        return dict(sorted(result.items()))

    def run(self, trace: hardware.Trace, *, case_name: str,
            measurement_count: int, signal_length: int, sparsity: int,
            profile: str) -> SimulationResult:
        if self.scheduler.scheduled:
            raise RuntimeError("ArchitectureSimulator instances are single-use")
        _, ingress_end = self._schedule_ingress(measurement_count)
        for index in range(len(trace.phases)):
            self._schedule_phase(trace, index, measurement_count,
                                 signal_length, sparsity)
        compute_end = self.scheduler.scheduled[self.frontier[0]].end_cycle
        _, total_end = self._schedule_egress(signal_length, len(trace.support))
        items = tuple(self.scheduler.scheduled)
        category = self._sum_by(items, lambda item: item.spec.category)
        phase = self._sum_by(
            [item for item in items if item.spec.phase_seq >= 0],
            lambda item: item.spec.phase_name)
        macroblock = self._sum_by(items, lambda item: item.spec.macroblock)
        resource_busy: dict[str, int] = {}
        invocations: dict[str, int] = {}
        for item in items:
            for resource in item.spec.resources:
                resource_busy[resource] = resource_busy.get(resource, 0) + item.duration
            if item.spec.phase_seq >= 0 and item.spec.name == "phase_dispatch":
                key = item.spec.phase_name
                invocations[key] = invocations.get(key, 0) + 1
        utilization = {key: value / total_end for key, value in sorted(resource_busy.items())}
        ingress_cycles = ingress_end
        compute_cycles = compute_end - ingress_end
        egress_cycles = total_end - compute_end
        return SimulationResult(
            algorithm=trace.algorithm, case_name=case_name, profile=profile,
            dimensions={"M": measurement_count, "N": signal_length, "K": sparsity},
            total_cycles=total_end, ingress_cycles=ingress_cycles,
            compute_cycles=compute_cycles, egress_cycles=egress_cycles,
            estimated_seconds=total_end / self.t.clock_hz,
            estimated_microseconds=total_end * 1_000_000 / self.t.clock_hz,
            category_cycles=category, phase_cycles=phase,
            macroblock_busy_cycles=macroblock,
            resource_busy_cycles=dict(sorted(resource_busy.items())),
            resource_utilization=utilization,
            phase_invocations=dict(sorted(invocations.items())),
            functional_stop_reason=trace.stop_reason,
            final_support_count=len(trace.support),
            numeric_events=asdict(trace.events),
            assumptions={**asdict(self.t), "result_mode": self.result_mode,
                         "external_axi_backpressure": False,
                         "cycle_status": "pre_rtl_architecture_estimate"},
            transactions=items,
        )


def simulate(trace: hardware.Trace, *, case_name: str, measurement_count: int,
             signal_length: int, sparsity: int, profile: str,
             timing: TimingContract | None = None,
             result_mode: str = "both") -> SimulationResult:
    return ArchitectureSimulator(timing, result_mode).run(
        trace, case_name=case_name, measurement_count=measurement_count,
        signal_length=signal_length, sparsity=sparsity, profile=profile)
