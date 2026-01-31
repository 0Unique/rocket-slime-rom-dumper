pub fn address(addr: comptime_int) comptime_int {
    if (addr > 0x02000000) return addr - 0x1FFC000; // adjusting for address ghidra/other decompilers will have
    return addr;
}
