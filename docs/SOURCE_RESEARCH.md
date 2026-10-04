# Existing implementations reviewed

Read on 2026-10-04 before completing the first implementation. These repositories were cloned outside this checkout for study; no dependency or executable from them is bundled.

| Project / revision | Source reviewed | Findings used |
| --- | --- | --- |
| [Stats](https://github.com/exelban/stats/tree/3220916207c08bfabb752b1afb088d61b4accd75) | `SMC/smc.swift`, `SMC/Helper/main.swift`, `Modules/Sensors/values.swift` | Firmware result must be checked separately from IOKit status. Probe the fan-mode key's case. Attempt direct mode writes before the Apple Silicon diagnostic unlock. Model generations use different CPU/GPU sensor keys; the M1–M5 key identifiers inform runtime probing. |
| [MacFanControl](https://github.com/raminsharifi/MacFanControl/tree/94e6d52e0e5b3e321bbabe1fff8b1264f9dcfea8) | `src/smc.rs`, `src/control.rs`, `src/fan.rs`, `src/temps.rs` | The C AppleSMC packet is 80 bytes with natural alignment. Float and fixed-point RPM encodings differ. Manual mode, target clearing, and the unlock flag are separate restoration steps. Control runs on a worker with exit recovery. |

Our controller adds a helper-owned eight-second heartbeat lease, a durable root-owned override marker, retryable restoration, kernel-enforced exact-peer code-signing requirements, per-fan cooling hold, RPM slew limits, and a thermal-pressure override. No thermal service is killed, suspended, or disabled. Quiet mode never stops a fan in manual mode.

These sources establish implementation patterns, not verification of this app's behavior on every fan-equipped Apple Silicon model or macOS version. The upstream sources themselves have different support and testing scopes. We need our own hardware evidence before advertising fan-write compatibility.

## Helper approval and dynamic control research

Reviewed live on 2026-10-04:

- [Apple SMAppService registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register()): launch daemons require administrator approval in System Settings. Registration is distinct from successful XPC communication. Inspect `requiresApproval` even when registration throws, and expose the approval path.
- [Apple unregistration](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister()): stops the service. Await it before replacing an installed app. Quit the GUI and restore automatic mode first. `--prepare-update` verifies automatic hardware state and unregisters without re-registering; `--repair-helper` refreshes registration from the installed app. Run as the logged-in user, not through sudo. Do not reset shared BTM data as routine repair.
- [Apple code signing TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html): stable designated requirements matter across versions. Ad hoc builds change code identity on rebuild. Set `MFC_SIGN_IDENTITY` to a consistent Developer ID for distribution. A build-number change does not stabilize signing identity.
- [Crystalidea FAQ](https://crystalidea.com/macs-fan-control/faq): administrator authorization initially and after updates. Its public repository is an issue tracker/translations/release archive, not implementation source.
- [Stats SMC implementation](https://github.com/exelban/stats/blob/a0d3ea560f13008e485008147a95a3374f09e356/SMC/smc.swift): direct manual-mode attempt, Ftst fallback, and three-second fresh-unlock settling interval. An undocumented implementation reference, not an Apple guarantee.
- [Control Guru: derivative on measurement](https://controlguru.com/pid-control-and-derivative-on-measurement/): avoid derivative kick from setpoint changes. Our cooling-action sign is positive for rising measurement; derivative is low-pass filtered.
- [Control Guru: integral windup](https://controlguru.com/integral-reset-windup-jacketing-logic-and-the-velocity-pi-form/): prevent accumulation while actuator output is constrained. We condition integration on saturation/ramp limits and allow unwinding.

MathWorks returned HTTP 403 and was not used as evidence. Apple forum responses were not readable; forum claims were not treated as verified guidance. CONTROL.md gains are engineering starting values, not values established by these sources.
