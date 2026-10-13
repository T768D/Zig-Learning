const std = @import("std");

var debugAlloc: std.heap.DebugAllocator(.{}) = .init;
pub const mainHeapAlloc = debugAlloc.allocator();

// pub const mainHeapAlloc = std.heap.smp_allocator;