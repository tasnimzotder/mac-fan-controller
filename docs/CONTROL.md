# Fan control

Apple automatic is the startup default. Selecting a preset or manual mode explicitly acquires control. Control mode is never restored from SQLite. Launch at login, if enabled, therefore starts monitoring rather than silently forcing fans.

## Performance algorithm

1. Read the hottest known CPU/GPU temperature every second in the helper. Known CPU/GPU keys for M1–M5 generations are probed without a fan-control model allowlist. Sensor keys remain generation-specific because their meanings can differ. Every sensor discovered initially must continue returning a plausible reading; missing/invalid readings release control. Models without readable CPU/GPU keys remain monitoring-only; unrelated battery/board temperatures are never used as a fallback.
2. Filter temperature using a two-second rising and ten-second falling time constant. Use the greater of raw and filtered temperature, so rising temperature is never hidden by smoothing.
3. Evaluate the preset curve at the greater of raw and filtered temperature. This is feedforward cooling, normalized to each fan's hardware range.
4. Add cooling-action PID feedback: `e = filteredTemperature - setpoint`, `P = Kp*e`, `I += Ki*(e + previousError)*dt/2`, and `D = Kd*filteredTemperatureRate`. Derivative is on measurement with a three-second exponential low-pass filter; rising temperature increases cooling. Integrate using actual elapsed sample time. Clamp correction to 0–35% of fan range, integral to 0–20%, and combined demand to 100%. Negative error unwinds the integral; feedback never lowers the curve's cooling floor. Pause positive integration at output saturation or when the previous demand exceeds the ramp-limited target by more than four percentage points. Emergency cooling clears the integral. Preset changes reset all feedback state.
5. Apply a 150 RPM deadband. Increase at up to 1,200 RPM/second. Hold reductions for 15 continuous seconds, then decrease by at most 100 RPM/second. Each fan has its own cooling-hold state.
6. At a raw temperature of 95°C or serious/critical macOS thermal pressure, request each fan's full hardware range immediately, including manual mode. Fresh sensors are checked again after a potentially slow unlock handshake.

| Preset | Temperature to fan-range fraction |
| --- | --- |
| Performance | 40°C:15%, 50°C:30%, 60°C:55%, 70°C:80%, 80°C:100% |
| Balanced | 40°C:5%, 50°C:10%, 60°C:25%, 70°C:50%, 80°C:75%, 90°C:100% |
| Quiet | 50°C:0%, 65°C:15%, 75°C:35%, 85°C:70%, 92°C:100% |

Turbo requests every fan's hardware maximum immediately. Selecting another preset applies its lower target immediately; temperature-driven reductions within a preset keep the cooling hold and gradual ramp-down.

These are initial engineering parameters, not calibrated hardware limits or an Apple recommendation. Performance mode intentionally makes more noise and spends more fan power. PID gains are conservative starting values, not calibrated thermal models. Workload and acoustic tuning is still required on each hardware family. PID tuning (output units are fractions of fan range):

| Preset | Setpoint °C | Kp /°C | Ki /(°C·s) | Kd s/°C |
| --- | --- | --- | --- | --- |
| Performance | 65 | 0.012 | 0.0008 | 0.025 |
| Balanced | 75 | 0.010 | 0.0006 | 0.020 |
| Quiet | 82 | 0.008 | 0.0004 | 0.015 |

Setpoints are feedback references, not guaranteed temperatures or Apple limits. Turbo and manual bypass PID; sensor validation and emergency protection remain active.

Manual targets remain between hardware minimum and maximum; a zero fraction means minimum RPM, not a stopped fan. Apple automatic may stop fans at idle.

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


## Live PID readings

The helper returns an optional PID snapshot with each control/status reply. It captures the actual filtered/raw temperature, setpoint, elapsed interval, gains, error, filtered temperature rate, P/I/D contributions, curve fraction, clamped correction, pre-ramp demand, post-ramp targets, and limiting/emergency state from the same control iteration. The UI refreshes with the normal two-second heartbeat, hides readings older than six seconds or from another mode, and clears them after control errors/restoration. Automatic, Turbo, and manual modes report PID inactive; demo mode does not pretend to have live helper readings. Values are current diagnostics, not additional persisted history.
