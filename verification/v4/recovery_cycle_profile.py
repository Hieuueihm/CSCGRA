"""Summarize testbench job-clock events without introducing RTL counters."""
def cycle_profile(text, job=1):
    pending = {}
    services = []
    instructions = []
    previous_retire = 0
    frames = 0
    program_done = None
    job_done = None
    for line in text.splitlines():
        fields = line.split()
        if not fields or len(fields) < 2 or int(fields[1]) != job:
            continue
        if fields[0] == 'D':
            job_done = int(fields[-1])
        if fields[0] != 'P':
            continue
        tick, event, value = int(fields[2]), fields[3], int(fields[4])
        if event == 'RETIRE':
            instructions.append(dict(pc=value, clocks=tick-previous_retire))
            previous_retire = tick
        elif event.endswith('_BEGIN'):
            pending[event[:-6]] = (tick, value, frames)
        elif event.endswith('_END'):
            kind = event[:-4]
            start, operation, before_frames = pending.pop(kind)
            accepted_frames = value-before_frames if kind == 'KERNEL' else 0
            services.append(dict(kind=kind, operation=operation, clocks=tick-start,
                                 accepted_frames=accepted_frames))
            if kind == 'KERNEL':
                frames = value
        elif event == 'PROGRAM_DONE':
            program_done = tick
    totals = {}
    for service in services:
        key = f"{service['kind']}:{service['operation']}"
        group = totals.setdefault(key, dict(calls=0, clocks=0, min_clocks=None,
                                            max_clocks=0, accepted_frames=0))
        clocks = service['clocks']
        group['calls'] += 1
        group['clocks'] += clocks
        group['min_clocks'] = clocks if group['min_clocks'] is None else min(group['min_clocks'], clocks)
        group['max_clocks'] = max(group['max_clocks'], clocks)
        group['accepted_frames'] += service['accepted_frames']
    return dict(service_totals=totals, services=services, instruction_clocks=instructions,
                program_done_clock=program_done, job_done_clock=job_done,
                result_drain_clocks=None if program_done is None or job_done is None else job_done-program_done,
                accepted_frames=frames, incomplete_services=sorted(pending),
                clock_scope='Accepted START through DONE; retirement deltas include controller overhead')
