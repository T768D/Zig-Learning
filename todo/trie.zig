const std = @import("std");
const FileStructure = @import("consts.zig").FileStructure;

const Node = struct {
	val: ?*FileStructure,
	next: ?std.AutoHashMap(u8, Node),
};

pub const TrieClass = struct {
	rootNode: std.AutoHashMap(u8, Node),
	allocator: std.mem.Allocator,

	fn rootNodePacked(self: @This()) Node {
		return .{
			.next = self.rootNode,
			.val = null
		};
	}
	
	pub fn addItem(self: @This(), item: *FileStructure) !void {
		var lastNode = @constCast(&self.rootNodePacked());

		for (item.title) |char| {
			if (lastNode.next == null) {
				lastNode.next = initHashmap();
			}

			var hashmap = lastNode.next orelse @panic("lastnode.next should be defined");
			lastNode = hashmap.getPtr(char) orelse b: {
				const nextNode: Node = .{
					.next = initHashmap(),
					.val = null
				};
				// no need to alloc to heap, hashmap copies the value
				try hashmap.put(char, nextNode);
				break :b hashmap.getPtr(char) orelse @panic("added node to hashmap but unable to get same node");
			};
		}

		lastNode.val = item;
	}

	// pub fn delete(self: @This(), item: *FileStructure) bool {
	// }

	fn iterate(self: @This(), str: []const u8) ?*const Node {
		// idk if this is the best way but whatever
		var lastNode = &self.rootNodePacked();

		for (str) |char| {
			std.debug.print("{s} {c}", .{str, char});
			lastNode = lastNode.next.?.getPtr(char) orelse return null;
		}

		return lastNode;
	}

	// resultAlloc should be a arena allocator to deinit the slices in the array easily
	pub fn search(self: @This(), str: []const u8, resultAlloc: std.mem.Allocator) !?std.ArrayList(*FileStructure) {
		const lastNode = self.iterate(str) orelse return null;

		var allocTemp = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
		defer allocTemp.deinit();
		const searchAlloc = allocTemp.allocator();

		var stack = try std.ArrayList(*const Node).initCapacity(searchAlloc, 60);
		stack.appendAssumeCapacity(lastNode);

		// initialised with resultAlloc beacuse lives after func ends
		var results = try std.ArrayList(*FileStructure).initCapacity(resultAlloc, 20);

		// do depth first because shifting arr by 1 is o(n) each time
		while (stack.pop()) |last| {
			if (last.val) |val| {
				try results.append(resultAlloc, val);
			}

			var iter = last.next.?.valueIterator();
			while (iter.next()) |block| {
				// block might be stack memory, need to copy to resultAlloc?
				try stack.append(searchAlloc, block);
			}
		}
		
		return results;
	}

	// pub fn deinit() void {
		// self.allocTemp.deinit();
	// }
};


// alloc cant be arena, individual nodes may need to be cleared, but also needs to be able to clear all at once
pub fn init(alloc: std.mem.Allocator) TrieClass {
    return .{
        .allocator = alloc,
        .rootNode = initHashmap(),
    };
}

fn initHashmap() std.AutoHashMap(u8, Node) {
	return std.AutoHashMap(u8, Node).init(std.heap.smp_allocator);
}