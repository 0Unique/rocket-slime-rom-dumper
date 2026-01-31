const std = @import("std");

// rocket slime uses 8-bit and 16-bit LZ77 compression
// these implementations roughly match how the game implements it

pub fn decompress8(srch: []const u8, allocator: *std.mem.Allocator) []u8 {
    if (srch.len == 0) return &[0]u8{};

    // Read header and initialize
    const header = std.mem.readInt(u32, srch[0..4], .little);
    var src = srch[4..];

    var dest_count = header >> 8;
    var dest: []u8 = allocator.alloc(u8, dest_count) catch {
        @panic("memory error");
    };
    const destp = dest;
    const is_ex_format = (header & 0x0F) != 0;

    while (dest_count > 0) {
        var flags = src[0];
        src = src[1..];

        var i: u32 = 8;
        while (i > 0) {
            i -= 1;

            if (flags & 0x80 == 0) {
                // Direct byte copy
                dest[0] = src[0];
                src = src[1..];
                dest = dest[1..];
                dest_count -= 1;
            } else {
                // Back reference compression
                const byte1 = src[0];
                var length: u32 = undefined;
                var offset: u16 = undefined;

                if (!is_ex_format) {
                    // Standard format
                    length = (byte1 >> 4) + 3;
                    offset = (@as(u16, byte1 & 0x0F) << 8) | src[1];
                    src = src[2..];
                    offset += 1;
                } else {
                    // Extended format
                    const high_nibble = byte1 >> 4;

                    if (high_nibble > 1) {
                        length = high_nibble + 1;
                        offset = (@as(u16, byte1 & 0x0F) << 8) | src[1];
                        src = src[2..];
                        offset += 1;
                    } else {
                        // Extended length encoding
                        src = src[1..];
                        var extended_length = @as(u32, byte1 & 0x0F) << 4;

                        if (high_nibble == 1) {
                            // Wide extended format
                            extended_length <<= 8;
                            extended_length |= @as(u32, src[0]) << 4;
                            src = src[1..];
                            extended_length += 0x100;
                        }

                        extended_length += 0x11;
                        const byte3 = src[0];
                        length = extended_length + (byte3 >> 4);
                        src = src[1..];

                        offset = (@as(u16, byte3 & 0x0F) << 8) | src[0];
                        src = src[1..];
                        offset += 1;
                    }
                }

                // Copy back reference
                dest_count -= length;
                var j: u32 = 0;
                while (j < length) : (j += 1) {
                    dest[j] = dest[j - offset];
                }
                dest = dest[length..];
            }

            // Check if we've decompressed everything
            if (dest_count <= 0) {
                break;
            }

            // Shift flags for next iteration
            flags <<= 1;
        }
    }
    return destp;
}

pub fn decompress16(srcp: []const u8, allocator: *std.mem.Allocator) void {
    var src = srcp;

    // Read header and initialize variables
    const header = std.mem.readIntLittle(u32, src[0..4]);
    src += 4;

    var dest_count: u32 = header >> 8;
    var dest: []u8 = allocator.alloc(u8, dest_count);

    var dest_tmp: u16 = 0;
    var shift: u32 = 0;
    const is_ex_format: bool = (header & 0x0F) != 0;

    while (dest_count > 0) {
        var flags: u8 = src[0];
        src += 1;

        var i: u32 = 0;
        while (i < 8) : (i += 1) {
            if (dest_count <= 0) break;

            if (flags & 0x80 == 0) {
                // Uncompressed byte
                const byte = src[0];
                src += 1;

                dest_tmp |= @as(u16, byte) << @intCast(shift);
                dest_count -= 1;

                shift ^= 8;
                if (shift == 0) {
                    std.mem.writeIntLittle(u16, dest[0..2], dest_tmp);
                    dest += 2;
                    dest_tmp = 0;
                }
            } else {
                // Compressed data
                var byte1 = src[0];
                var length: u32 = undefined;

                if (!is_ex_format) {
                    length = (byte1 >> 4) + 3;
                } else {
                    if (byte1 & 0xE0 != 0) {
                        length = (byte1 >> 4) + 1;
                    } else {
                        src += 1;
                        var extended_length: u32 = (byte1 & 0x0F) << 4;

                        if (byte1 & 0x10 != 0) {
                            extended_length = (extended_length << 8) | (@as(u32, src[0]) << 4);
                            src += 1;
                            extended_length += 0x100;
                        }

                        extended_length += 0x11;
                        byte1 = src[0];
                        length = extended_length + (byte1 >> 4);
                    }
                }

                // Read offset
                const byte2 = src[0];
                src += 1;
                const byte3 = src[0];
                src += 1;

                var offset: u16 = (@as(u16, byte2 & 0x0F) << 8) | byte3;
                offset += 1;

                // Copy compressed data
                dest_count -= length;

                var copy_length = length;
                var offset0_8: u32 = (8 - shift) ^ ((offset & 1) << 3);

                while (copy_length > 0) : (copy_length -= 1) {
                    offset0_8 ^= 8;

                    // Calculate source position for copying
                    const byte_offset = (offset + ((8 - shift) >> 3)) >> 1;
                    const src_pos = dest - byte_offset * 2;

                    // Read 16-bit value from history
                    const history_val = std.mem.readIntLittle(u16, src_pos[0..2]);

                    // Extract appropriate byte based on shift and offset
                    const mask: u16 = 0xFF << @intCast(offset0_8);
                    const byte_val: u8 = @intCast((history_val & mask) >> @intCast(offset0_8));

                    dest_tmp |= @as(u16, byte_val) << @intCast(shift);

                    shift ^= 8;
                    if (shift == 0) {
                        std.mem.writeIntLittle(u16, dest[0..2], dest_tmp);
                        dest += 2;
                        dest_tmp = 0;
                    }
                }
            }

            flags <<= 1;
            if (dest_count <= 0) break;
        }
    }

    // Write any remaining partial word
    if (shift != 0) {
        std.mem.writeIntLittle(u16, dest[0..2], dest_tmp);
    }
}
