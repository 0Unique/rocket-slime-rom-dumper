const std = @import("std");

// rocket slime uses 8-bit and 16-bit LZ77 compression
// these implementations roughly match how the game implements it

const CompressionHeader = packed struct {
    reserved: u4,
    format: enum(u4) {
        LZ77 = 1,
        huffman = 2,
        runlength_or_diff = 3,
        _,
    },
    dest_size: u24,
};

// TODO: 8-bit decompression

// TODO: test to confirm that decompression is accurate
pub fn decompress16(src: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const header: *align(1) const CompressionHeader = @ptrCast(&src[0]);
    if (header.format != .LZ77) {
        // pretty sure rocket slime only uses LZ77 compression
        return error.InvalidFormat;
    }
    if (header.dest_size == 0) return error.InvalidSize;

    var in = src[4..];
    const out = try allocator.alloc(u8, header.dest_size);
    errdefer allocator.free(out);

    var out_pos: usize = 0;

    while (out_pos < header.dest_size) {
        var flags: u8 = in[0];
        in = in[1..];

        var bit: u4 = 0;
        while (bit < 8) : (bit += 1) {
            if (out_pos >= header.dest_size) break;

            if ((flags & 0x80) == 0) {
                // literal
                out[out_pos] = in[0];
                in = in[1..];
                out_pos += 1;
            } else {
                // sequence
                const b0 = in[0];
                const b1 = in[1];
                in = in[2..];

                const length: usize = @as(usize, b0 >> 4) + 3;
                const raw_offset: u16 = (@as(u16, b0 & 0x0F) << 8) | b1;
                const byte_offset: usize = @as(usize, raw_offset + 1);

                var j: usize = 0;
                while (j < length) : (j += 1) {
                    out[out_pos] = out[out_pos - byte_offset];
                    out_pos += 1;
                }
            }

            flags <<= 1;
        }
    }

    return out;
}
