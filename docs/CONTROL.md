# Fan control

Apple automatic is the startup default. Selecting a preset or manual mode explicitly acquires control. Control mode is never restored from SQLite. Launch at login, if enabled, therefore starts monitoring rather than silently forcing fans.

## Performance algorithm

1. Read the hottest known CPU/GPU temperature every second in the helper. Known CPU/GPU keys for M1–M5 generations are probed without a fan-control model allowlist. Sensor keys remain generation-specific because their meanings can differ. Every sensor discovered initially must continue returning a plausible reading; missing/invalid readings release control. Models without readable CPU/GPU keys remain monitoring-only; unrelated battery/board temperatures are never used as a fallback.
2. Filter temperature using a two-second rising and ten-second falling time constant. Use the greater of raw and filtered temperature, so rising temperature is never hidden by smoothing.
3. Add a bounded trend lookahead: `min(5°C, max(0, temperature slope) × 2 seconds)`. Interpolate the selected curve.
4. Map the fraction to each fan's own firmware minimum/maximum. Synchronized manual mode means equal fractions, allowing different absolute RPM for different fans.
5. Apply a 150 RPM deadband. Increase at up to 1,200 RPM/second. Hold reductions for 15 continuous seconds, then decrease by at most 100 RPM/second. Each fan has its own cooling-hold state.
6. At a raw temperature of 95°C or serious/critical macOS thermal pressure, request each fan's full hardware range immediately, including manual mode. Fresh sensors are checked again after a potentially slow unlock handshake.

| Preset | Temperature to fan-range fraction |
| --- | --- |
| Performance | 40°C:0%, 50°C:20%, 60°C:45%, 70°C:70%, 80°C:100% |
| Balanced | 45°C:0%, 60°C:20%, 70°C:45%, 80°C:75%, 90°C:100% |
| Quiet | 50°C:0%, 65°C:15%, 75°C:35%, 85°C:70%, 92°C:100% |

These are initial engineering parameters, not calibrated hardware limits or an Apple recommendation. Performance mode intentionally makes more noise and spends more fan power. A closed-loop PID without identified thermal dynamics would add tuning uncertainty; a bounded curve is easier to validate for this first version. Manual targets remain between hardware minimum and maximum; a zero fraction means minimum RPM, not a stopped fan. Apple automatic may stop fans at idle.

## Ownership and recovery

The UI sends a heartbeat about every two seconds. The helper runs its own one-second loop. XPC messages are restricted by the kernel to the exact bundled peer's code-directory hash in both directions. A single connection holds the controller lease. No arbitrary SMC key, command execution, filesystem path, or privileged SQLite operation is exposed over XPC.

Fan-mode acquisition has a ten-second monotonic deadline shared across all fans. It tries direct mode writes, then uses the firmware unlock key when available and retries at 100 ms intervals, checking mode readback. XPC disconnection or sleep cancels acquisition between operations. The UI allows twenty seconds for a response, including recovery. The normal eight-second heartbeat lease starts after acquisition completes. An individual blocking IOKit call cannot be interrupted by this software deadline.

The UI marks recovery as unconfirmed after a timeout/disconnection; it does not claim Apple control until a successful helper response. Helper logs record request mode, elapsed time, and returned errors for diagnosis.

Before the first write, the helper syncs a marker inside a root-owned, mode-0700 recovery directory. It removes that marker only after restoration succeeds. On restart, a retained marker starts recovery; without it, an idle helper does not reset another app's fans. Initial temperature validation and journal errors prevent fan writes.

Stale readings, sampling gaps, invalid limits, write/readback errors, connection invalidation, or an eight-second heartbeat expiry stop requests and attempt restoration. Failed restoration remains visible and is retried once per second. Sleep selects Apple automatic; wake remains automatic. SIGTERM/SIGINT attempt cleanup. A launchd KeepAlive job restarts a crashed helper so the marker can be recovered.

Restoration releases each manual fan mode, clears forced targets, and releases `Ftst`; readback failures remain errors. This is recovery machinery, not a promise that firmware or a failed daemon can always be controlled. A crash of both processes, failed launchd restart, power loss, or SMC refusal cannot be made into a software guarantee. Avoid running another fan-control app concurrently.

## Hardware verification required

For each fan-equipped Apple Silicon model and macOS version:

- Capture read-only probe output and confirm CPU/GPU sensor selection and each fan's range.
- Install in `/Applications`, enable the helper, approve the service, and confirm authenticated XPC connectivity.
- Exercise each preset and independent/synchronized manual targets; compare target readback and actual RPM during ramp-up and settling.
- Run a bounded sustained workload, then stop it. Observe temperature, ramp-up, cooling hold, ramp-down, and thermal-pressure response.
- Test return to Apple, normal quit, UI crash, helper crash/restart, heartbeat suspension, sleep/wake, and removal. Verify both mode keys, targets, and unlock release, not just the UI label.
- Repeat after OS upgrades. Do not infer one machine's success from another's results.

A fanless M2 MacBook Air on macOS 27 was available during development. It verifies monitoring and native UI behavior; it does not establish fan-write support.
