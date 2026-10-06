import Synchronization

/// Calls the exported `kp_probe_begin` and `kp_probe_end` marker functions
/// so bpftrace can attach uprobes to them on Linux (see `Tools/bpf`).
///
/// The markers do nothing themselves; a uprobe reads their arguments
/// (span ID number, per-span ID, argument) from registers when it fires.
/// Without an attached probe the cost is one empty function call.
public struct ProbeBackend: TraceBackend {
    public init() {}

    public func begin(_ span: SpanName, id: UInt64, argument: UInt64) {
        kpProbeBegin(span.rawValue, id, argument)
    }

    public func end(_ span: SpanName, id: UInt64, argument: UInt64) {
        kpProbeEnd(span.rawValue, id, argument)
    }
}

// `@_silgen_name` gives each marker an unmangled symbol that Swift code
// calls directly, so a uprobe on `kp_probe_begin` fires on every span.
// (`@_cdecl` would only add a C thunk that Swift callers bypass.) The
// arguments are plain integers, so they arrive in the first three argument
// registers, where bpftrace reads them as arg0, arg1 and arg2.
//
// The optimizer deletes calls to functions without side effects, drops
// arguments a function doesn't read, and merges functions with identical
// bodies. Each marker therefore stores a value computed from all three
// arguments into its own atomic: that keeps every call, keeps the
// arguments in their registers, and keeps the two markers distinct.

let lastProbeBegin = Atomic<UInt64>(0)
let lastProbeEnd = Atomic<UInt64>(0)

@_silgen_name("kp_probe_begin")
@inline(never)
public func kpProbeBegin(_ span: UInt32, _ id: UInt64, _ argument: UInt64) {
    lastProbeBegin.store(probeFingerprint(span, id, argument), ordering: .relaxed)
}

@_silgen_name("kp_probe_end")
@inline(never)
public func kpProbeEnd(_ span: UInt32, _ id: UInt64, _ argument: UInt64) {
    lastProbeEnd.store(probeFingerprint(span, id, argument), ordering: .relaxed)
}

@inline(__always)
private func probeFingerprint(_ span: UInt32, _ id: UInt64, _ argument: UInt64) -> UInt64 {
    (UInt64(span) << 48) ^ id ^ argument
}
