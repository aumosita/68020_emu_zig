const std = @import("std");

/// NCR 5380 SCSI Controller
/// Implements SCSI bus phase state machine for Macintosh LC.
///
/// Register Map (active low accent omitted for clarity):
///   0: Current SCSI Data (R) / Output Data (W)
///   1: Initiator Command (R/W)
///   2: Mode (R/W)
///   3: Target Command (R/W)
///   4: Current Bus Status (R) / Select Enable (W)
///   5: Bus and Status (R) / Start DMA Send (W)
///   6: Input Data (R) / Start DMA Target Receive (W)
///   7: Reset Parity/Interrupt (R) / Start DMA Initiator Receive (W)
pub const Scsi5380 = struct {
    // ── SCSI Bus Phase ──
    pub const Phase = enum(u3) {
        DataOut = 0,
        DataIn = 1,
        Command = 2,
        Status = 3,
        // 4,5 reserved
        MessageOut = 6,
        MessageIn = 7,
    };

    pub const BusState = enum {
        BusFree,
        Arbitration,
        Selection,
        Reselection,
        InformationTransfer,
    };

    // ── ICR Bits (Reg 1) ──
    pub const ICR_RST: u8 = 0x80;
    pub const ICR_AIP: u8 = 0x40; // Arbitration In Progress (read-only)
    pub const ICR_LA: u8 = 0x20; // Lost Arbitration (read-only)
    pub const ICR_ACK: u8 = 0x10;
    pub const ICR_BSY: u8 = 0x08;
    pub const ICR_SEL: u8 = 0x04;
    pub const ICR_ATN: u8 = 0x02;
    pub const ICR_DATA_BUS: u8 = 0x01; // Assert Data Bus

    // ── Mode Register Bits (Reg 2) ──
    pub const MODE_BLOCK_DMA: u8 = 0x80;
    pub const MODE_TARGET: u8 = 0x40;
    pub const MODE_PARITY_CHK: u8 = 0x20;
    pub const MODE_PARITY_INT: u8 = 0x10;
    pub const MODE_EOP_INT: u8 = 0x08;
    pub const MODE_MONITOR_BSY: u8 = 0x04;
    pub const MODE_DMA: u8 = 0x02;
    pub const MODE_ARBITRATE: u8 = 0x01;

    // ── Current Bus Status Bits (Reg 4, Read) ──
    pub const STAT_RST: u8 = 0x80;
    pub const STAT_BSY: u8 = 0x40;
    pub const STAT_REQ: u8 = 0x20;
    pub const STAT_MSG: u8 = 0x10;
    pub const STAT_CD: u8 = 0x08;
    pub const STAT_IO: u8 = 0x04;
    pub const STAT_SEL: u8 = 0x02;
    pub const STAT_DBP: u8 = 0x01; // Data Bus Parity

    // ── Bus and Status Bits (Reg 5, Read) ──
    pub const BAS_END_DMA: u8 = 0x80;
    pub const BAS_DRQ: u8 = 0x40;
    pub const BAS_PARITY_ERR: u8 = 0x20;
    pub const BAS_IRQ: u8 = 0x10;
    pub const BAS_PHASE_MATCH: u8 = 0x08;
    pub const BAS_BSY_ERR: u8 = 0x04;
    pub const BAS_ATN: u8 = 0x02;
    pub const BAS_ACK: u8 = 0x01;

    // ── Registers ──
    out_data: u8 = 0, // Reg 0 Write: Output Data Register
    icr: u8 = 0, // Reg 1: Initiator Command Register
    mode: u8 = 0, // Reg 2: Mode Register
    tcr: u8 = 0, // Reg 3: Target Command Register
    sel_enable: u8 = 0, // Reg 4 Write: Select Enable Register

    // ── Internal Bus State ──
    bus_state: BusState = .BusFree,
    bus_data: u8 = 0, // Current data on the SCSI bus
    bus_signals: u8 = 0, // BSY, SEL, REQ, ACK, MSG, C/D, I/O, RST

    // ── Arbitration ──
    initiator_id: u3 = 7, // Mac is always SCSI ID 7
    arb_in_progress: bool = false,
    lost_arb: bool = false,

    // ── Interrupt / DRQ State ──
    irq_active: bool = false,
    drq_active: bool = false,

    // ── Connected Target (null = no device responds) ──
    target_id: ?u3 = null,
    selection_timeout_counter: u16 = 0,

    const SELECTION_TIMEOUT: u16 = 250; // cycles approx

    pub fn init() Scsi5380 {
        return .{};
    }

    pub fn reset(self: *Scsi5380) void {
        self.out_data = 0;
        self.icr = 0;
        self.mode = 0;
        self.tcr = 0;
        self.sel_enable = 0;
        self.bus_state = .BusFree;
        self.bus_data = 0;
        self.bus_signals = 0;
        self.arb_in_progress = false;
        self.lost_arb = false;
        self.irq_active = false;
        self.drq_active = false;
        self.target_id = null;
        self.selection_timeout_counter = 0;
    }

    // ────────────────────────────────────────────
    //  Register Read
    // ────────────────────────────────────────────

    pub fn read(self: *Scsi5380, addr: u3) u8 {
        return switch (addr) {
            // Reg 0: Current SCSI Data
            0 => self.bus_data,

            // Reg 1: Initiator Command Register
            1 => blk: {
                var val = self.icr & 0x1F; // Lower 5 bits are R/W
                if (self.arb_in_progress) val |= ICR_AIP;
                if (self.lost_arb) val |= ICR_LA;
                break :blk val;
            },

            // Reg 2: Mode Register
            2 => self.mode,

            // Reg 3: Target Command Register
            3 => self.tcr,

            // Reg 4: Current Bus Status
            4 => self.getCurrentBusStatus(),

            // Reg 5: Bus and Status
            5 => self.getBusAndStatus(),

            // Reg 6: Input Data (latched)
            6 => self.bus_data,

            // Reg 7: Reset Parity/Interrupt
            7 => blk: {
                self.irq_active = false;
                break :blk 0;
            },
        };
    }

    // ────────────────────────────────────────────
    //  Register Write
    // ────────────────────────────────────────────

    pub fn write(self: *Scsi5380, addr: u3, value: u8) void {
        switch (addr) {
            // Reg 0: Output Data Register
            0 => {
                self.out_data = value;
                if ((self.icr & ICR_DATA_BUS) != 0) {
                    self.bus_data = value;
                }
            },

            // Reg 1: Initiator Command Register
            1 => {
                const old_icr = self.icr;
                self.icr = value & 0x9F; // bits 5,6 are read-only

                // RST asserted → bus reset
                if ((value & ICR_RST) != 0 and (old_icr & ICR_RST) == 0) {
                    self.busReset();
                    return;
                }

                // Update bus signals from ICR
                self.updateBusSignalsFromIcr();

                // Check for arbitration start
                if ((self.mode & MODE_ARBITRATE) != 0 and
                    (value & ICR_DATA_BUS) != 0 and
                    self.bus_state == .BusFree)
                {
                    self.startArbitration();
                }
            },

            // Reg 2: Mode Register
            2 => {
                self.mode = value;

                // Arbitration mode bit cleared → end arbitration
                if ((value & MODE_ARBITRATE) == 0) {
                    self.arb_in_progress = false;
                }
            },

            // Reg 3: Target Command Register
            3 => {
                self.tcr = value & 0x0F;
            },

            // Reg 4 Write: Select Enable Register
            4 => {
                self.sel_enable = value;
            },

            // Reg 5 Write: Start DMA Send
            5 => {
                if ((self.mode & MODE_DMA) != 0) {
                    self.drq_active = true;
                }
            },

            // Reg 6 Write: Start DMA Target Receive
            6 => {
                if ((self.mode & MODE_DMA) != 0) {
                    self.drq_active = true;
                }
            },

            // Reg 7 Write: Start DMA Initiator Receive
            7 => {
                if ((self.mode & MODE_DMA) != 0) {
                    self.drq_active = true;
                }
            },
        }
    }

    // ────────────────────────────────────────────
    //  Bus Operations
    // ────────────────────────────────────────────

    fn busReset(self: *Scsi5380) void {
        self.bus_state = .BusFree;
        self.bus_signals = 0;
        self.bus_data = 0;
        self.arb_in_progress = false;
        self.lost_arb = false;
        self.target_id = null;
        self.drq_active = false;
        self.irq_active = true; // RST causes interrupt
    }

    fn startArbitration(self: *Scsi5380) void {
        self.bus_state = .Arbitration;
        self.arb_in_progress = true;
        self.lost_arb = false;

        // In emulation, the Mac (ID 7) always wins arbitration
        // since there are no other initiators.
        self.bus_data = @as(u8, 1) << self.initiator_id;
        self.bus_signals |= STAT_BSY;
    }

    /// Called when the initiator asserts SEL after winning arbitration.
    /// Returns true if a target responded.
    fn attemptSelection(self: *Scsi5380) bool {
        // In a real system, the initiator puts its ID + target ID on the bus.
        // We check if any virtual device responds.

        // Parse target ID from bus data (excluding initiator bit)
        const initiator_bit = @as(u8, 1) << self.initiator_id;
        const target_bits = self.bus_data & ~initiator_bit;

        if (target_bits == 0) {
            // No target specified
            return false;
        }

        // Find the target ID
        var tid: u3 = 0;
        while (tid < 7) : (tid += 1) {
            if ((target_bits & (@as(u8, 1) << tid)) != 0) {
                break;
            }
        }

        // Currently no virtual SCSI devices are connected.
        // Selection always times out (no device responds).
        // In the future, a disk image or CD-ROM emulation
        // would register here and respond with BSY.
        self.target_id = null;
        return false;
    }

    fn updateBusSignalsFromIcr(self: *Scsi5380) void {
        // Map ICR control bits to bus signals
        var signals: u8 = 0;
        if ((self.icr & ICR_BSY) != 0) signals |= STAT_BSY;
        if ((self.icr & ICR_SEL) != 0) signals |= STAT_SEL;

        // Check if SEL was just asserted (transition to Selection)
        if ((self.icr & ICR_SEL) != 0 and self.bus_state == .Arbitration) {
            self.arb_in_progress = false;
            self.bus_state = .Selection;
            self.selection_timeout_counter = 0;

            // Attempt selection
            if (self.attemptSelection()) {
                // Target responded (future: enter InformationTransfer)
                self.bus_state = .InformationTransfer;
                signals |= STAT_BSY; // Target asserts BSY
            }
            // If no target responds, selection will timeout on subsequent reads
        }

        // BSY deasserted → back to BusFree
        if ((self.icr & ICR_BSY) == 0 and (self.icr & ICR_SEL) == 0) {
            if (self.bus_state != .BusFree and self.bus_state != .InformationTransfer) {
                self.bus_state = .BusFree;
                signals = 0;
            }
        }

        self.bus_signals = signals;
    }

    // ────────────────────────────────────────────
    //  Status Register Helpers
    // ────────────────────────────────────────────

    fn getCurrentBusStatus(self: *Scsi5380) u8 {
        var status: u8 = 0;

        // Reflect bus signals
        if ((self.bus_signals & STAT_BSY) != 0) status |= STAT_BSY;
        if ((self.bus_signals & STAT_SEL) != 0) status |= STAT_SEL;

        // In Selection state with no target, we do NOT set BSY
        // (target hasn't responded), which causes the OS to detect timeout.
        if (self.bus_state == .Selection) {
            self.selection_timeout_counter +|= 1;
            // After timeout, clear SEL to indicate failure
            if (self.selection_timeout_counter >= SELECTION_TIMEOUT) {
                status &= ~STAT_BSY;
            }
        }

        return status;
    }

    fn getBusAndStatus(self: *Scsi5380) u8 {
        var status: u8 = 0;

        // Phase Match: compare TCR phase bits with actual bus phase (MSG, C/D, I/O)
        const tcr_phase = self.tcr & 0x07;
        const bus_phase = (self.bus_signals >> 2) & 0x07; // Extract I/O, C/D, MSG
        if (tcr_phase == bus_phase) status |= BAS_PHASE_MATCH;

        // DRQ
        if (self.drq_active) status |= BAS_DRQ;

        // IRQ
        if (self.irq_active) status |= BAS_IRQ;

        // BSY error (lost the bus unexpectedly)
        if ((self.mode & MODE_MONITOR_BSY) != 0 and
            self.bus_state == .InformationTransfer and
            (self.bus_signals & STAT_BSY) == 0)
        {
            status |= BAS_BSY_ERR;
        }

        return status;
    }

    // ────────────────────────────────────────────
    //  Public API for future device attachment
    // ────────────────────────────────────────────

    /// Check if the SCSI controller has a pending interrupt.
    pub fn getInterruptOutput(self: *const Scsi5380) bool {
        return self.irq_active;
    }
};
