# Retire-time instruction fetch contract

`program_sequencer` has one 1024-word program store and one 128-bit current
instruction buffer (`word`).  It does not duplicate the program image or add
an instruction queue.  The initial instruction remains loaded by `FETCH`.

After an instruction has completed all of its validation and resolved a
successor PC, `retire(next_pc)` first checks that the successor is inside the
published program.  Only then it reads that word into the current-instruction
buffer and enters `EXEC` directly.  This is retire-time fetch, not speculative
lookahead: a branch, call, or return reads only its resolved target; a kernel,
scalar, builder, or certificate path reads only after its matching response
has been accepted and retired.

The retiring trace continues to report the old PC and old instruction word.
The watchdog continues to count retired instructions, and all RF, ACC,
service, load, idle, done-hold, reset, cancel, and fault rules are unchanged.
An invalid successor keeps the existing program-fault precedence and does not
read the store.  Reset, cancel, and a new start retain the existing initial
`FETCH` behavior; cancel still flushes executing state without exposing a
request or completion.

The implementation makes no clock-frequency, area, synthesis or board claim.
[The scalar/control increment](../../../reports/v4/context_stream_quick_20260910/README.md) measures the combined whole-program effect of retire-time fetch and expanded scalar insertion; it does not attribute the entire QR reduction to fetching.  The resolved target address is on the
retire-time read path and requires timing measurement before any margin claim.
Focused XSim compares the default design with the same RTL elaborated using
`RETIRE_TIME_FETCH=0`, exercising linear control, taken branches, calls and
returns, service-response retirement, and cancellation.  The normal full
controller suite remains the behavioral closure.
