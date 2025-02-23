const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.vsr);

// vsr.zig is the root of a zig package, reexport all public APIs.
//
// Note that we don't promise any stability of these interfaces yet.
pub const constants = @import("constants.zig");
pub const io = @import("io.zig");
pub const message_bus = @import("message_bus.zig");
pub const message_pool = @import("message_pool.zig");
pub const state_machine = @import("state_machine.zig");
pub const storage = @import("storage.zig");
pub const tigerbeetle = @import("tigerbeetle.zig");
pub const time = @import("time.zig");
pub const tracer = @import("tracer.zig");
pub const stdx = @import("stdx.zig");
pub const flags = @import("flags.zig");
pub const superblock = @import("vsr/superblock.zig");
pub const aof = @import("aof.zig");
pub const lsm = .{
    .tree = @import("lsm/tree.zig"),
    .groove = @import("lsm/groove.zig"),
    .forest = @import("lsm/forest.zig"),
};
pub const testing = .{
    .cluster = @import("testing/cluster.zig"),
};

pub const ReplicaType = @import("vsr/replica.zig").ReplicaType;
pub const ReplicaEvent = @import("vsr/replica.zig").ReplicaEvent;
pub const format = @import("vsr/replica_format.zig").format;
pub const Status = @import("vsr/replica.zig").Status;
pub const SyncStage = @import("vsr/sync.zig").Stage;
pub const SyncTarget = @import("vsr/sync.zig").Target;
pub const SyncTargetCandidate = @import("vsr/sync.zig").TargetCandidate;
pub const SyncTargetQuorum = @import("vsr/sync.zig").TargetQuorum;
pub const SyncTrailer = @import("vsr/sync.zig").Trailer;
pub const Client = @import("vsr/client.zig").Client;
pub const ClockType = @import("vsr/clock.zig").ClockType;
pub const GridType = @import("vsr/grid.zig").GridType;
pub const JournalType = @import("vsr/journal.zig").JournalType;
pub const ClientRepliesType = @import("vsr/client_replies.zig").ClientRepliesType;
pub const SlotRange = @import("vsr/journal.zig").SlotRange;
pub const SuperBlockType = superblock.SuperBlockType;
pub const SuperBlockTrailer = superblock.Trailer;
pub const VSRState = superblock.SuperBlockHeader.VSRState;
pub const checksum = @import("vsr/checksum.zig").checksum;

/// The version of our Viewstamped Replication protocol in use, including customizations.
/// For backwards compatibility through breaking changes (e.g. upgrading checksums/ciphers).
pub const Version: u8 = 0;

pub const ProcessType = enum { replica, client };

pub const Zone = enum {
    superblock,
    wal_headers,
    wal_prepares,
    client_replies,
    grid,

    const size_superblock = superblock.superblock_zone_size;
    const size_wal_headers = constants.journal_size_headers;
    const size_wal_prepares = constants.journal_size_prepares;
    const size_client_replies = constants.client_replies_size;

    comptime {
        for (.{
            size_superblock,
            size_wal_headers,
            size_wal_prepares,
            size_client_replies,
        }) |zone_size| {
            assert(zone_size % constants.sector_size == 0);
        }
    }

    pub fn offset(zone: Zone, offset_logical: u64) u64 {
        if (zone.size()) |zone_size| {
            assert(offset_logical < zone_size);
        }

        return zone.start() + offset_logical;
    }

    pub fn start(zone: Zone) u64 {
        comptime var start_offset = 0;
        inline for (comptime std.enums.values(Zone)) |z| {
            if (z == zone) return start_offset;
            start_offset += comptime size(z) orelse 0;
        }
        unreachable;
    }

    pub fn size(zone: Zone) ?u64 {
        return switch (zone) {
            .superblock => size_superblock,
            .wal_headers => size_wal_headers,
            .wal_prepares => size_wal_prepares,
            .client_replies => size_client_replies,
            .grid => null,
        };
    }
};

/// Viewstamped Replication protocol commands:
pub const Command = enum(u8) {
    reserved = 0,

    ping = 1,
    pong = 2,

    ping_client = 3,
    pong_client = 4,

    request = 5,
    prepare = 6,
    prepare_ok = 7,
    reply = 8,
    commit = 9,

    start_view_change = 10,
    do_view_change = 11,
    start_view = 12,

    request_start_view = 13,
    request_headers = 14,
    request_prepare = 15,
    request_reply = 16,
    headers = 17,

    eviction = 18,

    request_blocks = 19,
    block = 20,

    request_sync_manifest = 21,
    request_sync_free_set = 22,
    request_sync_client_sessions = 23,

    sync_manifest = 24,
    sync_free_set = 25,
    sync_client_sessions = 26,

    comptime {
        for (std.enums.values(Command), 0..) |result, index| {
            assert(@intFromEnum(result) == index);
        }
    }
};

/// This type exists to avoid making the Header type dependant on the state
/// machine used, which would cause awkward circular type dependencies.
pub const Operation = enum(u8) {
    /// Operations reserved by VR protocol (for all state machines):
    /// The value 0 is reserved to prevent a spurious zero from being interpreted as an operation.
    reserved = 0,
    /// The value 1 is reserved to initialize the cluster.
    root = 1,
    /// The value 2 is reserved to register a client session with the cluster.
    register = 2,
    /// The value 3 is reserved for reconfiguration request.
    reconfigure = 3,

    /// Operations <vsr_operations_reserved are reserved for the control plane.
    /// Operations ≥vsr_operations_reserved are available for the state machine.
    _,

    pub fn from(comptime StateMachine: type, op: StateMachine.Operation) Operation {
        check_state_machine_operations(StateMachine);
        return @as(Operation, @enumFromInt(@intFromEnum(op)));
    }

    pub fn cast(self: Operation, comptime StateMachine: type) StateMachine.Operation {
        check_state_machine_operations(StateMachine);
        assert(self.valid(StateMachine));
        assert(!self.vsr_reserved());
        return @as(StateMachine.Operation, @enumFromInt(@intFromEnum(self)));
    }

    pub fn valid(self: Operation, comptime StateMachine: type) bool {
        check_state_machine_operations(StateMachine);

        inline for (.{ Operation, StateMachine.Operation }) |Enum| {
            const ops = comptime std.enums.values(Enum);
            inline for (ops) |op| {
                if (@intFromEnum(self) == @intFromEnum(op)) {
                    return true;
                }
            }
        }

        return false;
    }

    pub fn vsr_reserved(self: Operation) bool {
        return @intFromEnum(self) < constants.vsr_operations_reserved;
    }

    pub fn tag_name(self: Operation, comptime StateMachine: type) []const u8 {
        assert(self.valid(StateMachine));
        inline for (.{ Operation, StateMachine.Operation }) |Enum| {
            inline for (@typeInfo(Enum).Enum.fields) |field| {
                const op = @field(Enum, field.name);
                if (@intFromEnum(self) == @intFromEnum(op)) {
                    return field.name;
                }
            }
        }
        unreachable;
    }

    fn check_state_machine_operations(comptime StateMachine: type) void {
        comptime {
            assert(@typeInfo(StateMachine.Operation).Enum.is_exhaustive);
            assert(@typeInfo(StateMachine.Operation).Enum.tag_type ==
                @typeInfo(Operation).Enum.tag_type);
            for (@typeInfo(StateMachine.Operation).Enum.fields) |field| {
                const op = @field(StateMachine.Operation, field.name);
                if (@intFromEnum(op) < constants.vsr_operations_reserved) {
                    @compileError("StateMachine.Operation is reserved");
                }
            }
        }
    }
};

/// Network message and journal entry header:
/// We reuse the same header for both so that prepare messages from the primary can simply be
/// journalled as is by the backups without requiring any further modification.
pub const Header = extern struct {
    /// Aegis128 (used by checksum) uses hardware accelerated AES via inline asm which isn't
    /// available at comptime. Use a hard-coded value instead and verify via a test.
    const checksum_body_empty: u128 = 0x49F174618255402DE6E7E3C40D60CC83;
    test "empty checksum" {
        assert(checksum_body_empty == checksum(&.{}));
    }

    /// A checksum covering only the remainder of this header.
    /// This allows the header to be trusted without having to recv() or read() the associated body.
    /// This checksum is enough to uniquely identify a network message or journal entry.
    checksum: u128 = 0,

    /// A checksum covering only the associated body after this header.
    checksum_body: u128 = 0,

    /// A backpointer to the previous request or prepare checksum for hash chain verification.
    /// This provides a cryptographic guarantee for linearizability:
    /// 1. across our distributed log of prepares, and
    /// 2. across a client's requests and our replies.
    /// This may also be used as the initialization vector for AEAD encryption at rest, provided
    /// that the primary ratchets the encryption key every view change to ensure that prepares
    /// reordered through a view change never repeat the same IV for the same encryption key.
    ///
    /// * A `prepare_ok` sets this to the checkpoint id. (TODO(Big headers): Use a separate field.)
    /// * A `commit` sets this to the checkpoint id. (Possibly uncanonical.)
    /// * A `ping` sets this to the checkpoint id. (Possibly uncanonical.)
    /// * A `request_sync_manifest` sets this to the requested checkpoint id.
    /// * A `request_sync_free_set` sets this to the requested checkpoint id.
    /// * A `request_sync_client_sessions` sets this to the requested checkpoint id.
    /// * A `sync_manifest` sets this to the checkpoint id.
    /// * A `sync_free_set` sets this to the checkpoint id.
    /// * A `sync_client_sessions` sets this to the checkpoint id.
    parent: u128 = 0,

    /// Each client process generates a unique, random and ephemeral client ID at initialization.
    /// The client ID identifies connections made by the client to the cluster for the sake of
    /// routing messages back to the client.
    ///
    /// With the client ID in hand, the client then registers a monotonically increasing session
    /// number (committed through the cluster) to allow the client's session to be evicted safely
    /// from the client table if too many concurrent clients cause the client table to overflow.
    /// The monotonically increasing session number prevents duplicate client requests from being
    /// replayed.
    ///
    /// The problem of routing is therefore solved by the 128-bit client ID, and the problem of
    /// detecting whether a session has been evicted is solved by the session number.
    ///
    /// * A `request_reply` sets this to the client of the reply being requested.
    /// * A `do_view_change` sets this to a bitset of "present" prepares. If a bit is set, then
    ///   the corresponding header is not "blank", the replica has the prepare, and the prepare
    ///   is not known to be faulty.
    /// * A `sync_free_set` sets this to the vsr_state.previous_checkpoint_id.
    /// * A `sync_client_sessions` sets this to the vsr_state.commit_min_checksum.
    client: u128 = 0,

    /// The checksum of the message to which this message refers.
    ///
    /// We use this cryptographic context in various ways, for example:
    ///
    /// * A `request` sets this to the client's session number.
    /// * A `reply` sets this to a "stable" checksum.
    ///   Replies for a specific op may have different views (and checksums),
    ///   but are guaranteed to have the same context.
    /// * A `prepare` sets this to the checksum of the client's request.
    /// * A `prepare_ok` sets this to the checksum of the prepare being acked.
    /// * A `commit` sets this to the checksum of the latest committed prepare.
    /// * A `do_view_change` sets this to a bitset, with set bits indicating headers
    ///   in the message body which it has definitely not prepared (i.e. "nack").
    ///   The corresponding header may be an actual prepare header, or it may be a "blank" header.
    /// * A `request_start_view` sets this to a unique nonce, to detect outdated SVs.
    /// * A `start_view` sets this to zero for a new view, and to a nonce from an RSV when
    ///   responding to the RSV.
    /// * A `request_prepare` sets this to the checksum of the prepare being requested.
    /// * A `request_reply` sets this to the checksum of the reply being requested.
    /// * A `sync_manifest` sets this to the complete Manifest's checksum.
    /// * A `sync_free_set` sets this to the complete FreeSet's checksum.
    /// * A `sync_manifest` sets this to the complete ClientSessions's checksum.
    ///
    /// This allows for cryptographic guarantees beyond request, op, and commit numbers, which have
    /// low entropy and may otherwise collide in the event of any correctness bugs.
    context: u128 = 0,

    /// Each request is given a number by the client and later requests must have larger numbers
    /// than earlier ones. The request number is used by the replicas to avoid running requests more
    /// than once; it is also used by the client to discard duplicate responses to its requests.
    /// A client is allowed to have at most one request inflight at a time.
    ///
    /// * A `do_view_change` sets this to its latest log_view number.
    /// * A `request_sync_manifest` sets this to the requested offset within the encoded Manifest.
    /// * A `request_sync_free_set` sets this to the requested offset within the encoded FreeSet.
    /// * A `request_sync_client_sessions` sets this to the requested offset within the encoded ClientSessions.
    /// * A `sync_manifest` sets this to the offset within the encoded Manifest.
    /// * A `sync_free_set` sets this to the offset within the encoded FreeSet.
    /// * A `sync_client_sessions` sets this to the offset within the encoded ClientSessions.
    request: u32 = 0,

    /// The cluster number binds intention into the header, so that a client or replica can indicate
    /// the cluster it believes it is speaking to, instead of accidentally talking to the wrong
    /// cluster (for example, staging vs production).
    cluster: u32,

    /// The cluster reconfiguration epoch number (for future use).
    epoch: u32 = 0,

    /// Every message sent from one replica to another contains the sending replica's current view.
    /// A `u32` allows for a minimum lifetime of 136 years at a rate of one view change per second.
    view: u32 = 0,

    /// The op number of the latest prepare that may or may not yet be committed. Uncommitted ops
    /// may be replaced by different ops if they do not survive through a view change.
    ///
    /// * A `commit` sets this to its checkpoint op.
    /// * A `ping` sets this to its checkpoint op.
    /// * A `request_headers` sets this to the maximum op requested (inclusive).
    /// * A `request_prepare` sets this to the requested op.
    /// * A `request_reply` sets this to the requested op.
    /// * A `request_sync_manifest` sets this to the requested checkpoint op.
    /// * A `request_sync_free_set` sets this to the requested checkpoint op.
    /// * A `request_sync_client_sessions` sets this to the requested checkpoint op.
    /// * A `sync_manifest` sets this to the checkpoint op.
    /// * A `sync_free_set` sets this to the checkpoint op.
    /// * A `sync_client_sessions` sets this to the checkpoint op.
    op: u64 = 0,

    /// The commit number of the latest committed prepare. Committed ops are immutable.
    ///
    /// * A `do_view_change` sets this to `commit_min`, to indicate the sending replica's progress.
    ///   The sending replica may continue to commit after sending the DVC.
    /// * A `start_view` sets this to `commit_min`/`commit_max` (they are the same).
    /// * A `request_headers` sets this to the minimum op requested (inclusive).
    /// * A `sync_manifest` sets this to the complete Manifest's size.
    /// * A `sync_free_set` sets this to the complete FreeSet's size.
    /// * A `sync_client_sessions` sets this to the complete ClientSessions's size.
    /// * A `ping` sets this to its monotonic timestamp.
    /// * A `pong` echoes the ping's monotonic timestamp.
    commit: u64 = 0,

    /// This field is used in various ways:
    ///
    /// * A `prepare` sets this to the primary's state machine `prepare_timestamp`.
    ///   For `create_accounts` and `create_transfers` this is the batch's highest timestamp.
    /// * A `reply` sets this to the corresponding `prepare`'s timestamp.
    ///   This allows the test workload to verify transfer timeouts.
    /// * A `pong` sets this to the sender's wall clock value.
    /// * A `commit` message sets this to the replica's monotonic timestamp.
    /// * A `do_view_change` and `start_view` set this to the replica's `op_checkpoint`.
    timestamp: u64 = 0,

    /// The size of the Header structure (always), plus any associated body.
    size: u32 = @sizeOf(Header),

    /// The index of the replica in the cluster configuration array that authored this message.
    /// This identifies only the ultimate author because messages may be forwarded amongst replicas.
    replica: u8 = 0,

    /// The Viewstamped Replication protocol command for this message.
    command: Command,

    /// The state machine operation to apply.
    operation: Operation = .reserved,

    /// The version of the protocol implementation that originated this message.
    version: u8 = Version,

    comptime {
        assert(@sizeOf(Header) == 128);
        assert(stdx.no_padding(Header));
    }

    pub fn calculate_checksum(self: *const Header) u128 {
        const checksum_size = @sizeOf(@TypeOf(self.checksum));
        assert(checksum_size == 16);
        const checksum_value = checksum(std.mem.asBytes(self)[checksum_size..]);
        assert(@TypeOf(checksum_value) == @TypeOf(self.checksum));
        return checksum_value;
    }

    pub fn calculate_checksum_body(self: *const Header, body: []const u8) u128 {
        assert(self.size == @sizeOf(Header) + body.len);
        const checksum_size = @sizeOf(@TypeOf(self.checksum_body));
        assert(checksum_size == 16);
        const checksum_value = checksum(body);
        assert(@TypeOf(checksum_value) == @TypeOf(self.checksum_body));
        return checksum_value;
    }

    /// This must be called only after set_checksum_body() so that checksum_body is also covered:
    pub fn set_checksum(self: *Header) void {
        self.checksum = self.calculate_checksum();
    }

    pub fn set_checksum_body(self: *Header, body: []const u8) void {
        self.checksum_body = self.calculate_checksum_body(body);
    }

    pub fn valid_checksum(self: *const Header) bool {
        return self.checksum == self.calculate_checksum();
    }

    pub fn valid_checksum_body(self: *const Header, body: []const u8) bool {
        return self.checksum_body == self.calculate_checksum_body(body);
    }

    /// Returns null if all fields are set correctly according to the command, or else a warning.
    /// This does not verify that checksum is valid, and expects that this has already been done.
    pub fn invalid(self: *const Header) ?[]const u8 {
        if (self.version != Version) return "version != Version";
        if (self.size < @sizeOf(Header)) return "size < @sizeOf(Header)";
        if (self.epoch != 0) return "epoch != 0";
        return switch (self.command) {
            .reserved => self.invalid_reserved(),
            .ping => self.invalid_ping(),
            .pong => self.invalid_pong(),
            .ping_client => self.invalid_ping_client(),
            .pong_client => self.invalid_pong_client(),
            .request => self.invalid_request(),
            .prepare => self.invalid_prepare(),
            .prepare_ok => self.invalid_prepare_ok(),
            .reply => self.invalid_reply(),
            .commit => self.invalid_commit(),
            .start_view_change => self.invalid_start_view_change(),
            .do_view_change => self.invalid_do_view_change(),
            .start_view => self.invalid_start_view(),
            .request_start_view => self.invalid_request_start_view(),
            .request_headers => self.invalid_request_headers(),
            .request_prepare => self.invalid_request_prepare(),
            .request_reply => self.invalid_request_reply(),
            .request_blocks => self.invalid_request_blocks(),
            .headers => self.invalid_headers(),
            .eviction => self.invalid_eviction(),
            .block => self.invalid_block(),
            .request_sync_manifest => self.invalid_request_sync_manifest(),
            .request_sync_free_set => self.invalid_request_sync_free_set(),
            .request_sync_client_sessions => self.invalid_request_sync_client_sessions(),
            .sync_manifest => self.invalid_sync_manifest(),
            .sync_free_set => self.invalid_sync_free_set(),
            .sync_client_sessions => self.invalid_sync_client_sessions(),
            // The `Command` enum is exhaustive, so we can't write an "else" branch here. An unknown
            // command is a possibility, but that means that someone has send us a message with
            // matching cluster, matching version, correct checksum, and a command we don't know
            // about. Ignoring unknown commands might be unsafe, so the replica intentionally
            // crashes here, which is guaranteed by Zig's ReleaseSafe semantics.
            //
            // _ => unreachable
        };
    }

    fn invalid_reserved(self: *const Header) ?[]const u8 {
        assert(self.command == .reserved);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.request != 0) return "request != 0";
        if (self.view != 0) return "view != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.replica != 0) return "replica != 0";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_ping(self: *const Header) ?[]const u8 {
        assert(self.command == .ping);
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.request != 0) return "request != 0";
        if (self.view != 0) return "view != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_pong(self: *const Header) ?[]const u8 {
        assert(self.command == .pong);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.request != 0) return "request != 0";
        if (self.view != 0) return "view != 0";
        if (self.op != 0) return "op != 0";
        if (self.timestamp == 0) return "timestamp == 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_ping_client(self: *const Header) ?[]const u8 {
        assert(self.command == .ping_client);
        if (self.parent != 0) return "parent != 0";
        if (self.client == 0) return "client == 0";
        if (self.context != 0) return "context != 0";
        if (self.request != 0) return "request != 0";
        if (self.view != 0) return "view != 0";
        if (self.op != 0) return "op != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.replica != 0) return "replica != 0";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_pong_client(self: *const Header) ?[]const u8 {
        assert(self.command == .pong_client);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.request != 0) return "request != 0";
        if (self.op != 0) return "op != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_request(self: *const Header) ?[]const u8 {
        assert(self.command == .request);
        if (self.client == 0) return "client == 0";
        if (self.op != 0) return "op != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0 and !constants.aof_recovery) return "timestamp != 0";
        if (self.replica != 0) return "replica != 0";
        switch (self.operation) {
            .reserved => return "operation == .reserved",
            .root => return "operation == .root",
            .register => {
                // The first request a client makes must be to register with the cluster:
                if (self.parent != 0) return "register: parent != 0";
                if (self.context != 0) return "register: context != 0";
                if (self.request != 0) return "register: request != 0";
                // The .register operation carries no payload:
                if (self.checksum_body != checksum_body_empty) return "register: checksum_body != expected";
                if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
            },
            else => {
                if (self.operation == .reconfigure) {
                    if (self.size != @sizeOf(Header) + @sizeOf(ReconfigurationRequest)) {
                        return "size != @sizeOf(Header) + @sizeOf(ReconfigurationRequest)";
                    }
                } else if (@intFromEnum(self.operation) < constants.vsr_operations_reserved) {
                    return "operation is reserved";
                }
                // Thereafter, the client must provide the session number in the context:
                // These requests should set `parent` to the `checksum` of the previous reply.
                if (self.context == 0) return "context == 0";
                if (self.request == 0) return "request == 0";
            },
        }
        return null;
    }

    fn invalid_prepare(self: *const Header) ?[]const u8 {
        assert(self.command == .prepare);
        switch (self.operation) {
            .reserved => return "operation == .reserved",
            .root => {
                if (self.parent != 0) return "root: parent != 0";
                if (self.client != 0) return "root: client != 0";
                if (self.context != 0) return "root: context != 0";
                if (self.request != 0) return "root: request != 0";
                if (self.view != 0) return "root: view != 0";
                if (self.op != 0) return "root: op != 0";
                if (self.commit != 0) return "root: commit != 0";
                if (self.timestamp != 0) return "root: timestamp != 0";
                if (self.checksum_body != checksum_body_empty) return "root: checksum_body != expected";
                if (self.size != @sizeOf(Header)) return "root: size != @sizeOf(Header)";
                if (self.replica != 0) return "root: replica != 0";
            },
            else => {
                if (self.client == 0) return "client == 0";
                if (self.op == 0) return "op == 0";
                if (self.op <= self.commit) return "op <= commit";
                if (self.timestamp == 0) return "timestamp == 0";
                if (self.operation == .register) {
                    // Client session numbers are replaced by the reference to the previous prepare.
                    if (self.request != 0) return "request != 0";
                } else {
                    // Client session numbers are replaced by the reference to the previous prepare.
                    if (self.request == 0) return "request == 0";
                }
            },
        }
        return null;
    }

    fn invalid_prepare_ok(self: *const Header) ?[]const u8 {
        assert(self.command == .prepare_ok);
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        switch (self.operation) {
            .reserved => return "operation == .reserved",
            .root => {
                const root_checksum = Header.root_prepare(self.cluster).checksum;
                if (self.client != 0) return "root: client != 0";
                if (self.context != root_checksum) return "root: context != expected";
                if (self.request != 0) return "root: request != 0";
                if (self.op != 0) return "root: op != 0";
                if (self.commit != 0) return "root: commit != 0";
                if (self.timestamp != 0) return "root: timestamp != 0";
            },
            else => {
                if (self.client == 0) return "client == 0";
                if (self.op == 0) return "op == 0";
                if (self.op <= self.commit) return "op <= commit";
                if (self.timestamp == 0) return "timestamp == 0";
                if (self.operation == .register) {
                    if (self.request != 0) return "request != 0";
                } else {
                    if (self.request == 0) return "request == 0";
                }
            },
        }
        return null;
    }

    fn invalid_reply(self: *const Header) ?[]const u8 {
        assert(self.command == .reply);
        // Initialization within `client.zig` asserts that client `id` is greater than zero:
        if (self.client == 0) return "client == 0";
        if (self.op != self.commit) return "op != commit";
        if (self.timestamp == 0) return "timestamp == 0";
        if (self.operation == .register) {
            // In this context, the commit number is the newly registered session number.
            // The `0` commit number is reserved for cluster initialization.
            if (self.commit == 0) return "commit == 0";
            if (self.request != 0) return "request != 0";
        } else {
            if (self.commit == 0) return "commit == 0";
            if (self.request == 0) return "request == 0";
        }
        return null;
    }

    fn invalid_commit(self: *const Header) ?[]const u8 {
        assert(self.command == .commit);
        if (self.client != 0) return "client != 0";
        if (self.request != 0) return "request != 0";
        if (self.timestamp == 0) return "timestamp == 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_start_view_change(self: *const Header) ?[]const u8 {
        assert(self.command == .start_view_change);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.request != 0) return "request != 0";
        if (self.op != 0) return "op != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_do_view_change(self: *const Header) ?[]const u8 {
        assert(self.command == .do_view_change);
        if (self.parent != 0) return "parent != 0";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_start_view(self: *const Header) ?[]const u8 {
        assert(self.command == .start_view);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.request != 0) return "request != 0";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_request_start_view(self: *const Header) ?[]const u8 {
        assert(self.command == .request_start_view);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.request != 0) return "request != 0";
        if (self.op != 0) return "op != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_request_headers(self: *const Header) ?[]const u8 {
        assert(self.command == .request_headers);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.request != 0) return "request != 0";
        if (self.commit > self.op) return "op_min > op_max";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_request_prepare(self: *const Header) ?[]const u8 {
        assert(self.command == .request_prepare);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.request != 0) return "request != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_request_reply(self: *const Header) ?[]const u8 {
        assert(self.command == .request_reply);
        if (self.parent != 0) return "parent != 0";
        if (self.client == 0) return "client == 0";
        if (self.request != 0) return "request != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_request_blocks(self: *const Header) ?[]const u8 {
        assert(self.command == .request_blocks);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.request != 0) return "request != 0";
        if (self.view != 0) return "view != 0";
        if (self.op != 0) return "op != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.size == @sizeOf(Header)) return "size == @sizeOf(Header)";
        if ((self.size - @sizeOf(Header)) % @sizeOf(BlockRequest) != 0) {
            return "size multiple invalid";
        }
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_headers(self: *const Header) ?[]const u8 {
        assert(self.command == .headers);
        if (self.parent != 0) return "parent != 0";
        if (self.client != 0) return "client != 0";
        if (self.request != 0) return "request != 0";
        if (self.op != 0) return "op != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_eviction(self: *const Header) ?[]const u8 {
        assert(self.command == .eviction);
        if (self.parent != 0) return "parent != 0";
        if (self.context != 0) return "context != 0";
        if (self.request != 0) return "request != 0";
        if (self.op != 0) return "op != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_block(self: *const Header) ?[]const u8 {
        assert(self.command == .block);
        if (self.client != 0) return "client != 0";
        if (self.view != 0) return "view != 0";
        if (self.op == 0) return "op == 0"; // address ≠ 0
        if (self.commit != 0) return "commit != 0";
        if (self.replica != 0) return "replica != 0";
        if (self.operation == .reserved) return "operation == .reserved";
        return null;
    }

    fn invalid_request_sync_manifest(self: *const Header) ?[]const u8 {
        assert(self.command == .request_sync_manifest);
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.view != 0) return "view != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_request_sync_free_set(self: *const Header) ?[]const u8 {
        assert(self.command == .request_sync_free_set);
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.view != 0) return "view != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_request_sync_client_sessions(self: *const Header) ?[]const u8 {
        assert(self.command == .request_sync_client_sessions);
        if (self.client != 0) return "client != 0";
        if (self.context != 0) return "context != 0";
        if (self.view != 0) return "view != 0";
        if (self.commit != 0) return "commit != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_sync_manifest(self: *const Header) ?[]const u8 {
        assert(self.command == .sync_manifest);
        if (self.size - @sizeOf(Header) > constants.sync_trailer_message_body_size_max) return "size > max";
        if (self.client != 0) return "client != 0";
        if (self.view != 0) return "view != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_sync_free_set(self: *const Header) ?[]const u8 {
        assert(self.command == .sync_free_set);
        if (self.size - @sizeOf(Header) > constants.sync_trailer_message_body_size_max) return "size > max";
        if (self.view != 0) return "view != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    fn invalid_sync_client_sessions(self: *const Header) ?[]const u8 {
        assert(self.command == .sync_client_sessions);
        if (self.size - @sizeOf(Header) > constants.sync_trailer_message_body_size_max) return "size > max";
        if (self.view != 0) return "view != 0";
        if (self.timestamp != 0) return "timestamp != 0";
        if (self.operation != .reserved) return "operation != .reserved";
        return null;
    }

    /// Returns whether the immediate sender is a replica or client (if this can be determined).
    /// Some commands such as .request or .prepare may be forwarded on to other replicas so that
    /// Header.replica or Header.client only identifies the ultimate origin, not the latest peer.
    pub fn peer_type(self: *const Header) enum { unknown, replica, client } {
        switch (self.command) {
            .reserved => unreachable,
            // These messages cannot always identify the peer as they may be forwarded:
            .request => switch (self.operation) {
                // However, we do not forward the first .register request sent by a client:
                .register => return .client,
                else => return .unknown,
            },
            .prepare => return .unknown,
            // These messages identify the peer as either a replica or a client:
            .ping_client => return .client,
            // All other messages identify the peer as a replica:
            else => return .replica,
        }
    }

    pub fn reserved(cluster: u32, slot: u64) Header {
        assert(slot < constants.journal_slot_count);

        var header = Header{
            .command = .reserved,
            .cluster = cluster,
            .op = slot,
        };
        header.set_checksum_body(&[0]u8{});
        header.set_checksum();
        assert(header.invalid() == null);
        return header;
    }

    pub fn root_prepare(cluster: u32) Header {
        var header = Header{
            .cluster = cluster,
            .size = @sizeOf(Header),
            .command = .prepare,
            .operation = .root,
        };
        header.set_checksum_body(&[0]u8{});
        header.set_checksum();
        assert(header.invalid() == null);
        return header;
    }
};

pub const BlockRequest = extern struct {
    block_checksum: u128,
    block_address: u64,
    reserved: [8]u8 = [_]u8{0} ** 8,

    comptime {
        assert(@sizeOf(BlockRequest) == 32);
        assert(stdx.no_padding(BlockRequest));
    }
};

/// Body of the builtin operation=.reconfigure request.
pub const ReconfigurationRequest = extern struct {
    /// The new list of members.
    ///
    /// Request is rejected if it is not a permutation of an existing list of members.
    /// This is done to separate different failure modes of physically adding a new machine to the
    /// cluster as opposed to logically changing the set of machines participating in quorums.
    members: Members,
    /// The new epoch.
    ///
    /// Request is rejected if it isn't exactly current epoch + 1, to protect from operator errors.
    /// Although there's already an `epoch` field in vsr.Header, we don't want to rely on that for
    /// reconfiguration itself, as it is updated automatically by the clients, and here we need
    /// a manual confirmation from the operator.
    epoch: u32,
    /// The new replica count.
    ///
    /// At the moment, we require this to be equal to the old count.
    replica_count: u8,
    /// The new standby count.
    ///
    /// At the moment, we require this to be equal to the old count.
    standby_count: u8,
    reserved: [54]u8 = [_]u8{0} ** 54,
    /// The result of this request. Set to zero by the client and filled-in by the primary when it
    /// accepts a reconfiguration request.
    result: ReconfigurationResult,

    comptime {
        assert(@sizeOf(ReconfigurationRequest) == 256);
        assert(stdx.no_padding(ReconfigurationRequest));
    }

    pub fn validate(
        request: *const ReconfigurationRequest,
        current: struct {
            members: *const Members,
            epoch: u32,
            replica_count: u8,
            standby_count: u8,
        },
    ) ReconfigurationResult {
        assert(member_count(current.members) == current.replica_count + current.standby_count);

        if (request.replica_count == 0) return .replica_count_zero;
        if (request.replica_count > constants.replicas_max) return .replica_count_max_exceeded;
        if (request.standby_count > constants.standbys_max) return .standby_count_max_exceeded;

        if (!valid_members(&request.members)) return .members_invalid;
        if (member_count(&request.members) != request.replica_count + request.standby_count) {
            return .members_count_invalid;
        }

        if (!std.mem.allEqual(u8, &request.reserved, 0)) return .reserved_field;
        if (request.result != .reserved) return .result_must_be_reserved;

        if (request.replica_count != current.replica_count) return .different_replica_count;
        if (request.standby_count != current.standby_count) return .different_standby_count;

        if (request.epoch < current.epoch) return .epoch_in_the_past;
        if (request.epoch == current.epoch) {
            return if (std.meta.eql(request.members, current.members.*))
                .configuration_applied
            else
                .configuration_conflict;
        }
        if (request.epoch - current.epoch > 1) return .epoch_in_the_future;

        assert(request.epoch == current.epoch + 1);

        assert(valid_members(current.members));
        assert(valid_members(&request.members));
        assert(member_count(current.members) == member_count(&request.members));
        // We have just asserted that the sets have no duplicates and have equal lengths,
        // so it's enough to check that current.members ⊂ request.members.
        for (current.members) |member_current| {
            if (member_current == 0) break;
            for (request.members) |member| {
                if (member == member_current) break;
            } else return .different_member_set;
        }

        if (std.meta.eql(request.members, current.members.*)) {
            return .configuration_is_no_op;
        }

        return .ok;
    }
};

pub const ReconfigurationResult = enum(u32) {
    reserved = 0,
    /// Reconfiguration request is valid.
    /// The cluster is guaranteed to transition to the new epoch with the specified configuration.
    ok = 1,

    /// replica_count must be at least 1.
    replica_count_zero = 2,
    replica_count_max_exceeded = 3,
    standby_count_max_exceeded = 4,

    /// The Members array is syntactically invalid --- duplicate entries or internal zero entries.
    members_invalid = 5,
    /// The number of non-zero entries in Members array does not match the sum of replica_count
    /// and standby_count.
    members_count_invalid = 6,

    /// A reserved field is non-zero.
    reserved_field = 7,
    /// result must be set to zero (.reserved).
    result_must_be_reserved = 8,

    /// epoch is in the past (smaller than the current epoch).
    epoch_in_the_past = 9,
    /// epoch is too far in the future (larger than current epoch + 1).
    epoch_in_the_future = 10,

    /// Reconfiguration changes the number of replicas, that is not currently supported.
    different_replica_count = 11,
    /// Reconfiguration changes the number of standbys, that is not currently supported.
    different_standby_count = 12,
    /// members must be a permutation of the current set of cluster members.
    different_member_set = 13,

    /// epoch is equal to the current epoch and configuration is the same.
    /// This is a duplicate request.
    configuration_applied = 14,
    /// epoch is equal to the current epoch but configuration is different.
    /// A conflicting reconfiguration request was accepted.
    configuration_conflict = 15,
    /// The request is valid, but there's no need to advance the epoch, because / configuration
    /// exactly matches the current one.
    configuration_is_no_op = 16,

    comptime {
        for (std.enums.values(ReconfigurationResult), 0..) |result, index| {
            assert(@intFromEnum(result) == index);
        }
    }
};

test "ReconfigurationRequest" {
    const ResultSet = std.EnumSet(ReconfigurationResult);

    const Test = struct {
        members: Members = to_members(.{ 1, 2, 3, 4 }),
        epoch: u32 = 1,
        replica_count: u8 = 3,
        standby_count: u8 = 1,

        tested: ResultSet = ResultSet{},

        fn check(t: *@This(), request: ReconfigurationRequest, expected: ReconfigurationResult) !void {
            const actual = request.validate(.{
                .members = &t.members,
                .epoch = t.epoch,
                .replica_count = t.replica_count,
                .standby_count = t.standby_count,
            });

            try std.testing.expectEqual(expected, actual);
            t.tested.insert(expected);
        }

        fn to_members(m: anytype) Members {
            var result = [_]u128{0} ** constants.members_max;
            inline for (m, 0..) |member, index| result[index] = member;
            return result;
        }
    };

    var t: Test = .{};

    const r: ReconfigurationRequest = .{
        .members = Test.to_members(.{ 4, 1, 2, 3 }),
        .epoch = 2,
        .replica_count = 3,
        .standby_count = 1,
        .result = .reserved,
    };

    try t.check(r, .ok);
    try t.check(stdx.update(r, .{ .replica_count = 0 }), .replica_count_zero);
    try t.check(stdx.update(r, .{ .replica_count = 255 }), .replica_count_max_exceeded);
    try t.check(
        stdx.update(r, .{ .standby_count = constants.standbys_max + 1 }),
        .standby_count_max_exceeded,
    );
    try t.check(
        stdx.update(r, .{ .members = Test.to_members(.{ 4, 1, 4, 3 }) }),
        .members_invalid,
    );
    try t.check(
        stdx.update(r, .{ .members = Test.to_members(.{ 4, 1, 0, 2, 3 }) }),
        .members_invalid,
    );
    try t.check(
        stdx.update(r, .{ .epoch = 0, .members = Test.to_members(.{ 4, 1, 0, 2, 3 }) }),
        .members_invalid,
    );
    try t.check(
        stdx.update(r, .{ .epoch = 1, .members = Test.to_members(.{ 4, 1, 0, 2, 3 }) }),
        .members_invalid,
    );
    try t.check(stdx.update(r, .{ .replica_count = 4 }), .members_count_invalid);
    try t.check(stdx.update(r, .{ .reserved = [_]u8{1} ** 54 }), .reserved_field);
    try t.check(stdx.update(r, .{ .result = .ok }), .result_must_be_reserved);
    try t.check(stdx.update(r, .{ .epoch = 0 }), .epoch_in_the_past);
    try t.check(stdx.update(r, .{ .epoch = 3 }), .epoch_in_the_future);
    try t.check(
        stdx.update(r, .{ .members = Test.to_members(.{ 1, 2, 3 }), .replica_count = 2 }),
        .different_replica_count,
    );
    try t.check(
        stdx.update(r, .{ .members = Test.to_members(.{ 1, 2, 3, 4, 5 }), .standby_count = 2 }),
        .different_standby_count,
    );
    try t.check(
        stdx.update(r, .{ .members = Test.to_members(.{ 8, 1, 2, 3 }) }),
        .different_member_set,
    );
    try t.check(
        stdx.update(r, .{ .epoch = 1, .members = Test.to_members(.{ 1, 2, 3, 4 }) }),
        .configuration_applied,
    );
    try t.check(stdx.update(r, .{ .epoch = 1 }), .configuration_conflict);
    try t.check(
        stdx.update(r, .{ .members = Test.to_members(.{ 1, 2, 3, 4 }) }),
        .configuration_is_no_op,
    );

    assert(t.tested.count() < ResultSet.initFull().count());
    t.tested.insert(.reserved);
    assert(t.tested.count() == ResultSet.initFull().count());

    t.epoch = std.math.maxInt(u32);
    try t.check(r, .epoch_in_the_past);
    try t.check(stdx.update(r, .{ .epoch = std.math.maxInt(u32) }), .configuration_conflict);
    try t.check(
        stdx.update(r, .{
            .epoch = std.math.maxInt(u32),
            .members = Test.to_members(.{ 1, 2, 3, 4 }),
        }),
        .configuration_applied,
    );
}

pub const Timeout = struct {
    name: []const u8,
    id: u128,
    after: u64,
    attempts: u8 = 0,
    rtt: u64 = constants.rtt_ticks,
    rtt_multiple: u8 = constants.rtt_multiple,
    ticks: u64 = 0,
    ticking: bool = false,

    /// Increments the attempts counter and resets the timeout with exponential backoff and jitter.
    /// Allows the attempts counter to wrap from time to time.
    /// The overflow period is kept short to surface any related bugs sooner rather than later.
    /// We do not saturate the counter as this would cause round-robin retries to get stuck.
    pub fn backoff(self: *Timeout, random: std.rand.Random) void {
        assert(self.ticking);

        self.ticks = 0;
        self.attempts +%= 1;

        log.debug("{}: {s} backing off", .{ self.id, self.name });
        self.set_after_for_rtt_and_attempts(random);
    }

    /// It's important to check that when fired() is acted on that the timeout is stopped/started,
    /// otherwise further ticks around the event loop may trigger a thundering herd of messages.
    pub fn fired(self: *const Timeout) bool {
        if (self.ticking and self.ticks >= self.after) {
            log.debug("{}: {s} fired", .{ self.id, self.name });
            if (self.ticks > self.after) {
                log.err("{}: {s} is firing every tick", .{ self.id, self.name });
                @panic("timeout was not reset correctly");
            }
            return true;
        } else {
            return false;
        }
    }

    pub fn reset(self: *Timeout) void {
        self.attempts = 0;
        self.ticks = 0;
        assert(self.ticking);
        // TODO Use self.prng to adjust for rtt and attempts.
        log.debug("{}: {s} reset", .{ self.id, self.name });
    }

    /// Sets the value of `after` as a function of `rtt` and `attempts`.
    /// Adds exponential backoff and jitter.
    /// May be called only after a timeout has been stopped or reset, to prevent backward jumps.
    pub fn set_after_for_rtt_and_attempts(self: *Timeout, random: std.rand.Random) void {
        // If `after` is reduced by this function to less than `ticks`, then `fired()` will panic:
        assert(self.ticks == 0);
        assert(self.rtt > 0);

        const after = (self.rtt * self.rtt_multiple) + exponential_backoff_with_jitter(
            random,
            constants.backoff_min_ticks,
            constants.backoff_max_ticks,
            self.attempts,
        );

        // TODO Clamp `after` to min/max tick bounds for timeout.

        log.debug("{}: {s} after={}..{} (rtt={} min={} max={} attempts={})", .{
            self.id,
            self.name,
            self.after,
            after,
            self.rtt,
            constants.backoff_min_ticks,
            constants.backoff_max_ticks,
            self.attempts,
        });

        self.after = after;
        assert(self.after > 0);
    }

    pub fn set_rtt(self: *Timeout, rtt_ticks: u64) void {
        assert(self.rtt > 0);
        assert(rtt_ticks > 0);

        log.debug("{}: {s} rtt={}..{}", .{
            self.id,
            self.name,
            self.rtt,
            rtt_ticks,
        });

        self.rtt = rtt_ticks;
    }

    pub fn start(self: *Timeout) void {
        self.attempts = 0;
        self.ticks = 0;
        self.ticking = true;
        // TODO Use self.prng to adjust for rtt and attempts.
        log.debug("{}: {s} started", .{ self.id, self.name });
    }

    pub fn stop(self: *Timeout) void {
        self.attempts = 0;
        self.ticks = 0;
        self.ticking = false;
        log.debug("{}: {s} stopped", .{ self.id, self.name });
    }

    pub fn tick(self: *Timeout) void {
        if (self.ticking) self.ticks += 1;
    }
};

/// Calculates exponential backoff with jitter to prevent cascading failure due to thundering herds.
pub fn exponential_backoff_with_jitter(
    random: std.rand.Random,
    min: u64,
    max: u64,
    attempt: u64,
) u64 {
    const range = max - min;
    assert(range > 0);

    // Do not use `@truncate(u6, attempt)` since that only discards the high bits:
    // We want a saturating exponent here instead.
    const exponent = @as(u6, @intCast(@min(std.math.maxInt(u6), attempt)));

    // A "1" shifted left gives any power of two:
    // 1<<0 = 1, 1<<1 = 2, 1<<2 = 4, 1<<3 = 8
    const power = std.math.shlExact(u128, 1, exponent) catch unreachable; // Do not truncate.

    // Ensure that `backoff` is calculated correctly when min is 0, taking `@max(1, min)`.
    // Otherwise, the final result will always be 0. This was an actual bug we encountered.
    const min_non_zero = @max(1, min);
    assert(min_non_zero > 0);
    assert(power > 0);

    // Calculate the capped exponential backoff component, `min(range, min * 2 ^ attempt)`:
    const backoff = @min(range, min_non_zero * power);
    const jitter = random.uintAtMostBiased(u64, backoff);

    const result = @as(u64, @intCast(min + jitter));
    assert(result >= min);
    assert(result <= max);

    return result;
}

test "exponential_backoff_with_jitter" {
    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    const attempts = 1000;
    const max: u64 = std.math.maxInt(u64);
    const min = max - attempts;

    var attempt = max - attempts;
    while (attempt < max) : (attempt += 1) {
        const ebwj = exponential_backoff_with_jitter(random, min, max, attempt);
        try std.testing.expect(ebwj >= min);
        try std.testing.expect(ebwj <= max);
    }
}

/// Returns An array containing the remote or local addresses of each of the 2f + 1 replicas:
/// Unlike the VRR paper, we do not sort the array but leave the order explicitly to the user.
/// There are several advantages to this:
/// * The operator may deploy a cluster with proximity in mind since replication follows order.
/// * A replica's IP address may be changed without reconfiguration.
/// This does require that the user specify the same order to all replicas.
/// The caller owns the memory of the returned slice of addresses.
pub fn parse_addresses(allocator: std.mem.Allocator, raw: []const u8, address_limit: usize) ![]std.net.Address {
    const address_count = std.mem.count(u8, raw, ",") + 1;
    if (address_count > address_limit) return error.AddressLimitExceeded;

    const addresses = try allocator.alloc(std.net.Address, address_count);
    errdefer allocator.free(addresses);

    var index: usize = 0;
    var comma_iterator = std.mem.split(u8, raw, ",");
    while (comma_iterator.next()) |raw_address| : (index += 1) {
        assert(index < address_limit);
        if (raw_address.len == 0) return error.AddressHasTrailingComma;
        addresses[index] = try parse_address(raw_address);
    }
    assert(index == address_count);

    return addresses;
}

pub fn parse_address(raw: []const u8) !std.net.Address {
    var colon_iterator = std.mem.split(u8, raw, ":");
    // The split iterator will always return non-null once, even if the delimiter is not found:
    const raw_ipv4 = colon_iterator.next().?;

    if (colon_iterator.next()) |raw_port| {
        if (colon_iterator.next() != null) return error.AddressHasMoreThanOneColon;

        const port = std.fmt.parseUnsigned(u16, raw_port, 10) catch |err| switch (err) {
            error.Overflow => return error.PortOverflow,
            error.InvalidCharacter => return error.PortInvalid,
        };
        return std.net.Address.parseIp4(raw_ipv4, port) catch {
            return error.AddressInvalid;
        };
    } else {
        // There was no colon in the address so there are now two cases:
        // 1. an IPv4 address with the default port, or
        // 2. a port with the default IPv4 address.

        // Let's try parsing as a port first:
        if (std.fmt.parseUnsigned(u16, raw, 10)) |port| {
            return std.net.Address.parseIp4(constants.address, port) catch unreachable;
        } else |err| switch (err) {
            error.Overflow => return error.PortOverflow,
            error.InvalidCharacter => {
                // Something was not a digit, let's try parsing as an IPv4 instead:
                return std.net.Address.parseIp4(raw, constants.port) catch {
                    return error.AddressInvalid;
                };
            },
        }
    }
}

test "parse_addresses" {
    const vectors_positive = &[_]struct {
        raw: []const u8,
        addresses: []const std.net.Address,
    }{
        .{
            // Test the minimum/maximum address/port.
            .raw = "1.2.3.4:567,0.0.0.0:0,255.255.255.255:65535",
            .addresses = &[3]std.net.Address{
                std.net.Address.initIp4([_]u8{ 1, 2, 3, 4 }, 567),
                std.net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 0),
                std.net.Address.initIp4([_]u8{ 255, 255, 255, 255 }, 65535),
            },
        },
        .{
            // Addresses are not reordered.
            .raw = "3.4.5.6:7777,200.3.4.5:6666,1.2.3.4:5555",
            .addresses = &[3]std.net.Address{
                std.net.Address.initIp4([_]u8{ 3, 4, 5, 6 }, 7777),
                std.net.Address.initIp4([_]u8{ 200, 3, 4, 5 }, 6666),
                std.net.Address.initIp4([_]u8{ 1, 2, 3, 4 }, 5555),
            },
        },
        .{
            // Test default address and port.
            .raw = "1.2.3.4:5,4321,2.3.4.5",
            .addresses = &[3]std.net.Address{
                std.net.Address.initIp4([_]u8{ 1, 2, 3, 4 }, 5),
                try std.net.Address.parseIp4(constants.address, 4321),
                std.net.Address.initIp4([_]u8{ 2, 3, 4, 5 }, constants.port),
            },
        },
        .{
            // Test addresses less than address_limit.
            .raw = "1.2.3.4:5,4321",
            .addresses = &[2]std.net.Address{
                std.net.Address.initIp4([_]u8{ 1, 2, 3, 4 }, 5),
                try std.net.Address.parseIp4(constants.address, 4321),
            },
        },
    };

    const vectors_negative = &[_]struct {
        raw: []const u8,
        err: anyerror![]std.net.Address,
    }{
        .{ .raw = "", .err = error.AddressHasTrailingComma },
        .{ .raw = "1.2.3.4:5,2.3.4.5:6,4.5.6.7:8", .err = error.AddressLimitExceeded },
        .{ .raw = "1.2.3.4:7777,", .err = error.AddressHasTrailingComma },
        .{ .raw = "1.2.3.4:7777,2.3.4.5::8888", .err = error.AddressHasMoreThanOneColon },
        .{ .raw = "1.2.3.4:5,A", .err = error.AddressInvalid }, // default port
        .{ .raw = "1.2.3.4:5,2.a.4.5", .err = error.AddressInvalid }, // default port
        .{ .raw = "1.2.3.4:5,2.a.4.5:6", .err = error.AddressInvalid }, // specified port
        .{ .raw = "1.2.3.4:5,2.3.4.5:", .err = error.PortInvalid },
        .{ .raw = "1.2.3.4:5,2.3.4.5:A", .err = error.PortInvalid },
        .{ .raw = "1.2.3.4:5,65536", .err = error.PortOverflow }, // default address
        .{ .raw = "1.2.3.4:5,2.3.4.5:65536", .err = error.PortOverflow },
    };

    for (vectors_positive) |vector| {
        const addresses_actual = try parse_addresses(std.testing.allocator, vector.raw, 3);
        defer std.testing.allocator.free(addresses_actual);

        try std.testing.expectEqual(addresses_actual.len, vector.addresses.len);
        for (vector.addresses, 0..) |address_expect, i| {
            const address_actual = addresses_actual[i];
            try std.testing.expectEqual(address_expect.in.sa.family, address_actual.in.sa.family);
            try std.testing.expectEqual(address_expect.in.sa.port, address_actual.in.sa.port);
            try std.testing.expectEqual(address_expect.in.sa.addr, address_actual.in.sa.addr);
            try std.testing.expectEqual(address_expect.in.sa.zero, address_actual.in.sa.zero);
        }
    }

    for (vectors_negative) |vector| {
        try std.testing.expectEqual(vector.err, parse_addresses(std.testing.allocator, vector.raw, 2));
    }
}

pub fn sector_floor(offset: u64) u64 {
    const sectors = math.divFloor(u64, offset, constants.sector_size) catch unreachable;
    return sectors * constants.sector_size;
}

pub fn sector_ceil(offset: u64) u64 {
    const sectors = math.divCeil(u64, offset, constants.sector_size) catch unreachable;
    return sectors * constants.sector_size;
}

pub fn quorums(replica_count: u8) struct {
    replication: u8,
    view_change: u8,
    nack_prepare: u8,
    majority: u8,
} {
    assert(replica_count > 0);

    assert(constants.quorum_replication_max >= 2);
    // For replica_count=2, set quorum_replication=2 even though =1 would intersect.
    // This improves durability of small clusters.
    const quorum_replication = if (replica_count == 2) 2 else @min(
        constants.quorum_replication_max,
        stdx.div_ceil(replica_count, 2),
    );
    assert(quorum_replication <= replica_count);
    assert(quorum_replication >= 2 or quorum_replication == replica_count);

    // For replica_count=2, set quorum_view_change=2 even though =1 would intersect.
    // This avoids special cases for a single-replica view-change in Replica.
    const quorum_view_change =
        if (replica_count == 2) 2 else replica_count - quorum_replication + 1;
    // The view change quorum may be more expensive to make the replication quorum cheaper.
    // The insight is that the replication phase is by far more common than the view change.
    // This trade-off allows us to optimize for the common case.
    // See the comments in `constants.zig` for further explanation.
    assert(quorum_view_change <= replica_count);
    assert(quorum_view_change >= 2 or quorum_view_change == replica_count);
    assert(quorum_view_change >= @divFloor(replica_count, 2) + 1);
    assert(quorum_view_change + quorum_replication > replica_count);

    // We need to have enough nacks to guarantee that `quorum_replication` was not reached,
    // because if the replication quorum was reached, then it may have been committed.
    const quorum_nack_prepare = replica_count - quorum_replication + 1;
    assert(quorum_nack_prepare + quorum_replication > replica_count);

    const quorum_majority =
        stdx.div_ceil(replica_count, 2) + @intFromBool(@mod(replica_count, 2) == 0);
    assert(quorum_majority > @divFloor(replica_count, 2));

    return .{
        .replication = quorum_replication,
        .view_change = quorum_view_change,
        .nack_prepare = quorum_nack_prepare,
        .majority = quorum_majority,
    };
}

test "quorums" {
    if (constants.quorum_replication_max != 3) return error.SkipZigTest;

    const expect_replication = [_]u8{ 1, 2, 2, 2, 3, 3, 3, 3 };
    const expect_view_change = [_]u8{ 1, 2, 2, 3, 3, 4, 5, 6 };
    const expect_nack_prepare = [_]u8{ 1, 1, 2, 3, 3, 4, 5, 6 };
    const expect_majority = [_]u8{ 1, 2, 2, 3, 3, 4, 4, 5 };

    for (expect_replication[0..], 0..) |_, i| {
        const replicas = @as(u8, @intCast(i)) + 1;
        const actual = quorums(replicas);
        try std.testing.expectEqual(actual.replication, expect_replication[i]);
        try std.testing.expectEqual(actual.view_change, expect_view_change[i]);
        try std.testing.expectEqual(actual.nack_prepare, expect_nack_prepare[i]);
        try std.testing.expectEqual(actual.majority, expect_majority[i]);

        // The nack quorum only differs from the view-change quorum when R=2.
        if (replicas == 2) {
            try std.testing.expectEqual(actual.nack_prepare, 1);
        } else {
            try std.testing.expectEqual(actual.nack_prepare, actual.view_change);
        }
    }
}

/// Set of replica_ids of cluster members, where order of ids determines replica indexes.
///
/// First replica_count elements are active replicas,
/// then standby_count standbys, the rest are zeros.
/// Order determines ring topology for replication.
pub const Members = [constants.members_max]u128;

/// Deterministically assigns replica_ids for the initial configuration.
///
/// Eventually, we want to identify replicas using random u128 ids to prevent operator errors.
/// However, that requires unergonomic two-step process for spinning a new cluster up.  To avoid
/// needlessly compromising the experience until reconfiguration is fully implemented, derive
/// replica ids for the initial cluster deterministically.
pub fn root_members(cluster: u32) Members {
    const IdSeed = extern struct {
        cluster_config_checksum: u128 align(1),
        cluster: u32 align(1),
        replica: u8 align(1),
    };
    comptime assert(@sizeOf(IdSeed) == 21);

    var result = [_]u128{0} ** constants.members_max;
    var replica: u8 = 0;
    while (replica < constants.members_max) : (replica += 1) {
        const seed = IdSeed{
            .cluster_config_checksum = constants.config.cluster.checksum(),
            .cluster = cluster,
            .replica = replica,
        };
        result[replica] = checksum(std.mem.asBytes(&seed));
    }

    assert(valid_members(&result));
    return result;
}

/// Check that:
///  - all non-zero elements are different
///  - all zero elements are trailing
pub fn valid_members(members: *const Members) bool {
    for (members, 0..) |replica_i, i| {
        for (members[0..i]) |replica_j| {
            if (replica_j == 0 and replica_i != 0) return false;
            if (replica_j != 0 and replica_j == replica_i) return false;
        }
    }
    return true;
}

fn member_count(members: *const Members) u8 {
    for (members, 0..) |member, index| {
        if (member == 0) return @as(u8, @intCast(index));
    }
    return constants.members_max;
}

pub fn member_index(members: *const Members, replica_id: u128) ?u8 {
    assert(replica_id != 0);
    assert(valid_members(members));
    for (members, 0..) |member, replica_index| {
        if (member == replica_id) return @intCast(replica_index);
    } else return null;
}

pub const Headers = struct {
    pub const Array = stdx.BoundedArray(Header, constants.view_change_headers_max);
    /// The SuperBlock's persisted VSR headers.
    /// One of the following:
    ///
    /// - SV headers (consecutive chain)
    /// - DVC headers (disjoint chain)
    pub const ViewChangeSlice = ViewChangeHeadersSlice;
    pub const ViewChangeArray = ViewChangeHeadersArray;

    fn dvc_blank(op: u64) Header {
        return std.mem.zeroInit(Header, .{
            .command = .reserved,
            .op = op,
            .checksum = 0,
        });
    }

    pub fn dvc_header_type(header: *const Header) enum { blank, valid } {
        if (std.meta.eql(header.*, Headers.dvc_blank(header.op))) return .blank;

        if (constants.verify) assert(header.valid_checksum());
        assert(header.command == .prepare);
        assert(header.invalid() == null);
        return .valid;
    }
};

pub const ViewChangeCommand = enum { do_view_change, start_view };

const ViewChangeHeadersSlice = struct {
    command: ViewChangeCommand,
    /// Headers are ordered from high-to-low op.
    slice: []const Header,

    pub fn init(command: ViewChangeCommand, slice: []const Header) ViewChangeHeadersSlice {
        const headers = ViewChangeHeadersSlice{
            .command = command,
            .slice = slice,
        };
        headers.verify();
        return headers;
    }

    pub fn verify(headers: ViewChangeHeadersSlice) void {
        assert(headers.slice.len > 0);
        assert(headers.slice.len <= constants.view_change_headers_max);

        const head = &headers.slice[0];
        // A DVC's head op is never a gap or faulty.
        // A SV never includes gaps or faulty headers.
        assert(Headers.dvc_header_type(head) == .valid);

        if (headers.command == .start_view) {
            assert(headers.slice.len >= @min(
                constants.view_change_headers_suffix_max,
                head.op + 1, // +1 to include the head itself.
            ));
        }

        var child = head;
        for (headers.slice[1..], 0..) |*header, i| {
            const index = i + 1;
            assert(header.command == .prepare or header.command == .reserved);
            assert(header.op < child.op);

            // DVC: Ops are consecutive (with explicit blank headers).
            // SV: The first "pipeline + 1" ops of the SV are consecutive.
            if (headers.command == .do_view_change or
                (headers.command == .start_view and
                index < constants.pipeline_prepare_queue_max + 1))
            {
                assert(header.op == head.op - index);
            }

            switch (Headers.dvc_header_type(header)) {
                .blank => {
                    assert(headers.command == .do_view_change);
                    continue; // Don't update "child".
                },
                .valid => {
                    assert(header.view <= child.view);
                    assert(header.timestamp < child.timestamp);
                    if (header.op + 1 == child.op) {
                        assert(header.checksum == child.parent);
                    }
                },
            }
            child = header;
        }
    }

    const ViewRange = struct {
        min: u32, // inclusive
        max: u32, // inclusive

        pub fn contains(range: ViewRange, view: u32) bool {
            return range.min <= view and view <= range.max;
        }
    };

    /// Returns the range of possible views (of prepare, not commit) for a message that is part of
    /// the same log_view as these headers.
    ///
    /// - When these are DVC headers for a log_view=V, we must be in view_change status working to
    ///   transition to a view beyond V. So we will never prepare anything else as part of view V.
    /// - When these are SV headers for a log_view=V, we can continue to add to them (by preparing
    ///   more ops), but those ops will laways be part of the log_view. If they were prepared during
    ///   a view prior to the log_view, they would already be part of the headers.
    pub fn view_for_op(headers: ViewChangeHeadersSlice, op: u64, log_view: u32) ViewRange {
        const header_newest = &headers.slice[0];
        const header_oldest = blk: {
            var oldest: ?usize = null;
            for (headers.slice, 0..) |*header, i| {
                switch (Headers.dvc_header_type(header)) {
                    .blank => assert(i > 0),
                    .valid => oldest = i,
                }
            }
            break :blk &headers.slice[oldest.?];
        };
        assert(header_newest.view <= log_view);
        assert(header_newest.view >= header_oldest.view);
        assert(header_newest.op >= header_oldest.op);

        if (op < header_oldest.op) return .{ .min = 0, .max = header_oldest.view };
        if (op > header_newest.op) return .{ .min = log_view, .max = log_view };

        for (headers.slice) |*header| {
            if (Headers.dvc_header_type(header) == .valid and header.op == op) {
                return .{ .min = header.view, .max = header.view };
            }
        }

        var header_next = &headers.slice[0];
        assert(Headers.dvc_header_type(header_next) == .valid);

        for (headers.slice[1..]) |*header_prev| {
            if (Headers.dvc_header_type(header_prev) == .valid) {
                if (header_prev.op < op and op < header_next.op) {
                    return .{ .min = header_prev.view, .max = header_next.view };
                }
                header_next = header_prev;
            }
        }
        unreachable;
    }
};

test "Headers.ViewChangeSlice.view_for_op" {
    var headers_array = [_]Header{
        std.mem.zeroInit(Header, .{
            .checksum = undefined,
            .client = 6,
            .request = 7,
            .command = .prepare,
            .operation = @as(Operation, @enumFromInt(constants.vsr_operations_reserved + 8)),
            .op = 9,
            .view = 10,
            .timestamp = 11,
        }),
        Headers.dvc_blank(8),
        Headers.dvc_blank(7),
        std.mem.zeroInit(Header, .{
            .checksum = undefined,
            .client = 3,
            .request = 4,
            .command = .prepare,
            .operation = @as(Operation, @enumFromInt(constants.vsr_operations_reserved + 5)),
            .op = 6,
            .view = 7,
            .timestamp = 8,
        }),
        Headers.dvc_blank(5),
    };

    headers_array[0].set_checksum();
    headers_array[3].set_checksum();

    const headers = Headers.ViewChangeSlice.init(.do_view_change, &headers_array);
    try std.testing.expect(std.meta.eql(headers.view_for_op(11, 12), .{ .min = 12, .max = 12 }));
    try std.testing.expect(std.meta.eql(headers.view_for_op(10, 12), .{ .min = 12, .max = 12 }));
    try std.testing.expect(std.meta.eql(headers.view_for_op(9, 12), .{ .min = 10, .max = 10 }));
    try std.testing.expect(std.meta.eql(headers.view_for_op(8, 12), .{ .min = 7, .max = 10 }));
    try std.testing.expect(std.meta.eql(headers.view_for_op(7, 12), .{ .min = 7, .max = 10 }));
    try std.testing.expect(std.meta.eql(headers.view_for_op(6, 12), .{ .min = 7, .max = 7 }));
    try std.testing.expect(std.meta.eql(headers.view_for_op(5, 12), .{ .min = 0, .max = 7 }));
    try std.testing.expect(std.meta.eql(headers.view_for_op(0, 12), .{ .min = 0, .max = 7 }));
}

/// The headers of a SV or DVC message.
const ViewChangeHeadersArray = struct {
    command: ViewChangeCommand,
    array: Headers.Array,

    pub fn root(cluster: u32) ViewChangeHeadersArray {
        return ViewChangeHeadersArray.init_from_slice(.start_view, &.{
            Header.root_prepare(cluster),
        });
    }

    pub fn init_from_slice(
        command: ViewChangeCommand,
        slice: []const Header,
    ) ViewChangeHeadersArray {
        const headers = ViewChangeHeadersArray{
            .command = command,
            .array = Headers.Array.from_slice(slice) catch unreachable,
        };
        headers.verify();
        return headers;
    }

    fn init_from_array(command: ViewChangeCommand, array: Headers.Array) ViewChangeHeadersArray {
        const headers = ViewChangeHeadersArray{
            .command = command,
            .array = array,
        };
        headers.verify();
        return headers;
    }

    pub fn verify(headers: *const ViewChangeHeadersArray) void {
        (ViewChangeHeadersSlice{
            .command = headers.command,
            .slice = headers.array.const_slice(),
        }).verify();
    }

    pub fn start_view_into_do_view_change(headers: *ViewChangeHeadersArray) void {
        assert(headers.command == .start_view);
        // This function is only called by a replica that is lagging behind the primary's
        // checkpoint, so the start_view has a full suffix of headers.
        assert(headers.array.get(0).op >= constants.journal_slot_count);
        assert(headers.array.count() >= constants.view_change_headers_suffix_max);
        assert(headers.array.count() >= constants.pipeline_prepare_queue_max + 1);

        const commit_max = @max(
            headers.array.get(0).op -| constants.pipeline_prepare_queue_max,
            headers.array.get(0).commit,
        );
        const commit_max_header = headers.array.get(headers.array.get(0).op - commit_max);
        assert(commit_max_header.command == .prepare);
        assert(commit_max_header.op == commit_max);

        // SVs may include more headers than DVC:
        // - Remove the SV "hook" checkpoint trigger(s), since they would create gaps in the ops.
        // - Remove any SV headers that don't fit in the DVC's body.
        //   (SV headers are determined by view_change_headers_suffix_max,
        //   but DVC headers must stop at commit_max.)
        headers.command = .do_view_change;
        headers.array.truncate(constants.pipeline_prepare_queue_max + 1);

        headers.verify();
    }

    pub fn replace(
        headers: *ViewChangeHeadersArray,
        command: ViewChangeCommand,
        slice: []const Header,
    ) void {
        headers.command = command;
        headers.array.clear();
        for (slice) |*header| headers.array.append_assume_capacity(header.*);
        headers.verify();
    }

    pub fn append(headers: *ViewChangeHeadersArray, header: *const Header) void {
        // We don't do comprehensive validation here — assume that verify() will be called
        // after any series of appends.
        headers.array.append_assume_capacity(header.*);
    }

    pub fn append_blank(headers: *ViewChangeHeadersArray, op: u64) void {
        assert(headers.command == .do_view_change);
        assert(headers.array.count() > 0);
        headers.array.append_assume_capacity(Headers.dvc_blank(op));
    }
};

/// For a replica with journal_slot_count=8 and lsm_batch_multiple=2:
///
///   checkpoint() call           0   1   2   3
///   op_checkpoint               0   5  11  17
///   op_checkpoint_next          5  11  17  23
///   op_checkpoint_next_trigger  7  13  19  25
///
///     commit log (ops)           │ write-ahead log (slots)
///     0   4   8   2   6   0   4  │ 0---4---
///   0 ─────✓·%                   │ 01234✓6%   initial log fill
///   1 ───────────✓·%             │ 890✓2%45   first wrap of log
///   2 ─────────────────✓·%       │ 6✓8%0123   second wrap of log
///   3 ───────────────────────✓·% │ 4%67890✓   third wrap of log
///
/// Legend:
///
///   ─/✓  op on disk at checkpoint
///   ·/%  op in memory at checkpoint
///     ✓  op_checkpoint
///     %  op_checkpoint's trigger
///
pub const Checkpoint = struct {
    comptime {
        assert(constants.journal_slot_count > constants.lsm_batch_multiple);
        assert(constants.journal_slot_count % constants.lsm_batch_multiple == 0);
    }

    pub fn checkpoint_after(checkpoint: u64) u64 {
        assert(valid(checkpoint));

        const result = op: {
            if (checkpoint == 0) {
                // First wrap: op_checkpoint_next = 8-2-1 = 5
                break :op constants.journal_slot_count - constants.lsm_batch_multiple - 1;
            } else {
                // Second wrap: op_checkpoint_next = 5+8-2 = 11
                // Third wrap: op_checkpoint_next = 11+8-2 = 17
                break :op checkpoint + constants.journal_slot_count - constants.lsm_batch_multiple;
            }
        };

        assert((result + 1) % constants.lsm_batch_multiple == 0);
        assert(valid(result));

        return result;
    }

    pub fn trigger_for_checkpoint(checkpoint: u64) ?u64 {
        assert(valid(checkpoint));

        if (checkpoint == 0) {
            return null;
        } else {
            return checkpoint + constants.lsm_batch_multiple;
        }
    }

    pub fn valid(op: u64) bool {
        return op == 0 or (op + 1) % constants.lsm_batch_multiple == 0;
    }
};
