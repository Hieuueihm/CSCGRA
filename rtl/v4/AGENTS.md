# RTL v4 implementation instructions

Latest user request, 2026-09-09: Astra Ultra plans carefully, coordinates and
reviews; GPT-5.6 Terra agents at high reasoning effort implement code. This
supersedes the earlier Astra Medium and Luna/Spark coding preferences. First
review existing RTL and testbenches and run the applicable checks; preserve
implementations that pass. Continue the missing work from its verified state.
Use short, meaningful names and a clean functional module hierarchy. Follow V4
documents as the design authority; do not infer a V4 design from older versions.
Latest performance steering: use actual V2/V3 cycle reports and schedules as
comparison anchors, with matched dimensions, iteration counts, quality and
measurement boundaries. Read CYCLE_BASELINE_CONTRACT.md before optimization;
do not use the slow V4 baseline alone as the acceptance target.

Naming: v4 is only the project directory/version label. Module identifiers,
internal signal/type identifiers, generated macro names and include guards must
not contain V4/v4. Use functional module names and CSR_* macro namespaces.
The planned system wrapper is csr_top. Apply this rule to existing RTL as well;
the user-requested naming migration supersedes byte-for-byte preservation of
old identifiers, while arithmetic and interface semantics must remain unchanged.

Current verification rule: use Vivado xsim only for RTL tests, through xvlog,
xelab and xsim. Do not run Icarus/vvp or Verilator for current acceptance.
Python may generate stimuli and compare integer golden results. Keep earlier
simulator reports as historical evidence; rerun the required checks in xsim.

Current native RTL is recovery_engine with loaded program_sequencer,
stream_kernel, live_operator_memory, arithmetic_service and result_store.
The kernel owns one vector pool and exactly two stream_array instances.
Native generic-program integration and result publication have source-bound
Vivado evidence; complete algorithm programs and QR are separate gates.
Round-two active-program scope is MP, OMP, GOMP, CoSaMP, SP, IHT, HTP, GP,
FISTA and PDHG. ADMM is historical reference-only here: its round-two quality
work is `STOPPED_BY_SCOPE`, so neither it nor warm-start work is a new PASS.
Current arrays are independent lanes. Terminal ACC uses existing PEACC and
fixed registered reduction links; do not claim an added terminal arithmetic
block, general programmable mesh routing, or a full-mesh CGRA from the 4x4
array shape alone.

The earlier resident tile64/control256 and bounded lsqr_engine compositions
are independently elaborated historical references. Their passing behavior
is preserved; they do not select the current solver or add arrays to the
target. Check source-bound evidence before claiming acceptance of changes.
Diagrams, model tests and packed images are not RTL qualification.

Current target correction: support least squares uses QR, initially a
Householder numerical candidate. Read QR_SOLVER.md and STREAM_SYSTEM_CONTRACT.md.
The existing lsqr_engine is a separately elaborated historical reference,
never an implicit fallback in new recovery programs. csr_top now plans
recovery_engine/stream_kernel with exactly two streaming arrays. Live Phi/B,
R1/R4 and generic commands have separate source-bound xsim evidence; QR and
full recovery are not qualified by those tests.

Before creating a module, read its entry in `../../config/v4_modules.json` and
the relevant contract under `../../docs/v4/architecture/`. Read the current v4
status and architecture specification. Keep v3 untouched.

- Use the functional module paths from the catalog; no M1/M8/M13 milestone names.
- Use synthesizable SystemVerilog, one clock `clk`, synchronous active-high
  internal reset `rst`; adapt board resets at the boundary.
- Observe the published latency/valid-ready/tag/reset contracts. On stall, hold
  payload, tags and owned state until the transaction is accepted.
- Generate width/opcode definitions from the selected contracts; do not copy
  private constants or algorithm-specific classifiers into PE/dispatcher RTL.
- Numeric/profile and context ABI are still candidates. Do not silently freeze
  them or relax certificates to make a test pass.
- Add meaningful module/phase tests including tails, stalls, reset and faults;
  compare against the agreed integer oracle. Model tests are not RTL tests.
- Do not run synthesis or implementation before the required v4 correctness
  gates pass. Record actual source hashes and tool/test results.
- Do not add empty RTL stubs to make the catalog appear implemented.
