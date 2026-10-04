# eBPF probes for KeePassIOS core code

iOS has no eBPF, but the core packages in `Packages/KeePassCore` also build on Linux. There, every `Trace.span` calls two exported marker functions, `kp_probe_begin(span, id, argument)` and `kp_probe_end(...)`, and these bpftrace scripts attach uprobes to them. The same span names show up in Instruments on Apple platforms through `OSSignposter`.

| Script | Shows |
|---|---|
| `spans.bt` | Latency histogram and count per span |
| `offcpu.bt` | Time each span spends blocked (I/O, locks, sleeps) |
| `io.bt` | Syscall latency per span and syscall number (74 is `fsync`, 82 `rename` on x86_64) |
| `alloc.bt` | `malloc` calls and bytes per span |

Nested spans are handled: time inside an inner span is charged to it, and the outer span picks up again when it ends.

## Running

Needs Linux, root (or `CAP_BPF` + `CAP_PERFMON`) and bpftrace 0.20 or newer.

```sh
cd Packages/KeePassCore
swift build -c release
../../Tools/bpf/run.sh spans.bt .build/release/kpbench probe-check --iterations 30
```

`run.sh` runs the binary under bpftrace and replaces numeric span IDs with names using `kpbench spans`. `kpbench probe-check` emits a known pattern of nested spans (2 ms inside `kdf.argon2`, 1 ms inside `kdbx.decrypt`) to check the pipeline end to end.

Example output:

```text
@span_us[unlock.total]:
[2K, 4K)              28 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[4K, 8K)               2 |@@@                                                 |

@span_us[kdf.argon2]:
[2K, 4K)              29 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[4K, 8K)               1 |@                                                   |

@span_us[kdbx.decrypt]:
[1K, 2K)              30 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
```

## How the markers survive optimization

The markers are declared with `@_silgen_name`, so Swift calls them by their plain symbol names (a `@_cdecl` thunk would be bypassed by Swift callers). Each one stores a value computed from all three arguments into its own atomic. Without that side effect the optimizer deleted the calls, dropped the unused arguments and merged the two markers into one symbol. See `Sources/KPObservability/ProbeBackend.swift`.
