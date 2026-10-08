const std = @import("std");
const FileStructure = @import("consts.zig").FileStructure;

const Node = struct {
	val: ?*FileStructure,
	next: ?std.AutoHashMap(u8, *Node),
};

pub const TrieClass = struct {
	rootNode: Node,
	allocator: std.mem.Allocator,
	
	pub fn addItem(self: *@This(), item: *FileStructure) !void {
		// dont want to make entire class mutable
		var lastNode = &self.rootNode;

		for (item.title) |char| {
			if (lastNode.next == null) {
				lastNode.next = self.initHashmap();
			}

			var hashmap: *std.AutoHashMap(u8, *Node) = &(lastNode.next orelse @panic("lastnode.next should be defined"));
			if (hashmap.get(char)) |nextNode| {
                lastNode = nextNode;
                continue;
            }

			const nextNode = try self.allocator.create(Node);
			nextNode.* = .{
				.next = self.initHashmap(),
				.val = null
			};
			// no need to alloc to heap, hashmap copies the value
			try hashmap.put(char, nextNode);
			lastNode = nextNode;
		}

		lastNode.val = item;
	}

	// pub fn delete(self: *@This(), item: *FileStructure) bool {
	// }

	fn iterate(self: *@This(), str: []const u8) ?*const Node {
		var lastNode = &self.rootNode;

		for (str) |char| {
			lastNode = lastNode.next.?.get(char) orelse return null;
		}

		return lastNode;
	}

	// resultAlloc should be a arena allocator to deinit the slices in the array easily
	pub fn search(self: *@This(), str: []const u8, resultAlloc: std.mem.Allocator) !?std.ArrayList(*FileStructure) {
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
				try stack.append(searchAlloc, block.*);
			}
		}
		
		return results;
	}

	fn initHashmap(self: *@This()) std.AutoHashMap(u8, *Node) {
		return std.AutoHashMap(u8, *Node).init(self.allocator);
	}

	// pub fn deinit() void {
		// self.allocTemp.deinit();
	// }
};


// alloc cant be arena, individual nodes may need to be cleared, but also needs to be able to clear all at once
pub fn init(alloc: std.mem.Allocator) TrieClass {
    return .{
        .allocator = alloc,
        .rootNode = .{
			.next = std.AutoHashMap(u8, *Node).init(alloc),
			.val = null
		},
    };
}