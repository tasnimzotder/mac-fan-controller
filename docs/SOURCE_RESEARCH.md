# Existing implementations reviewed

Read on 2026-10-04 before completing the first implementation. These repositories were cloned outside this checkout for study; no dependency or executable from them is bundled.

| Project / revision | Source reviewed | Findings used |
| --- | --- | --- |
| [Stats](https://github.com/exelban/stats/tree/3220916207c08bfabb752b1afb088d61b4accd75) | `SMC/smc.swift`, `SMC/Helper/main.swift`, `Modules/Sensors/values.swift` | Firmware result must be checked separately from IOKit status. Probe the fan-mode key's case. Attempt direct mode writes before the Apple Silicon diagnostic unlock. Model generations use different CPU/GPU sensor keys. |
| [MacFanControl](https://github.com/raminsharifi/MacFanControl/tree/94e6d52e0e5b3e321bbabe1fff8b1264f9dcfea8) | `src/smc.rs`, `src/control.rs`, `src/fan.rs`, `src/temps.rs` | The C AppleSMC packet is 80 bytes with natural alignment. Float and fixed-point RPM encodings differ. Manual mode, target clearing, and the unlock flag are separate restoration steps. Control runs on a worker with exit recovery. |

Our controller adds a helper-owned eight-second heartbeat lease, a durable root-owned override marker, retryable restoration, kernel-enforced exact-peer code-signing requirements, per-fan cooling hold, RPM slew limits, and a thermal-pressure override. No thermal service is killed, suspended, or disabled. Quiet mode never stops a fan in manual mode.

These sources establish implementation patterns, not verification of this app's behavior on M2 Pro/M3 Pro or macOS 26/27. The upstream sources themselves have different support and testing scopes. We need our own hardware evidence before advertising fan-write compatibility.
