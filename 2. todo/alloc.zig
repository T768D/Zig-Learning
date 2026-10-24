const std = @import("std");

// var debugAlloc: std.heap.DebugAllocator(.{}) = .init;
// pub const mainHeapAlloc = debugAlloc.allocator();

pub const generalHeapAlloc = std.heap.smp_allocator;