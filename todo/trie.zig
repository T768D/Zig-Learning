const std = @import("std");
const FileStructure = @import("consts.zig").FileStructure;

const Node = struct {
	val: ?*FileStructure,
	next: ?std.AutoHashMap(u8, Node),
};

pub const TrieClass = struct {
	rootNode: std.AutoHashMap(u8, Node),
	allocTemp: std.heap.ArenaAllocator,
	alloc: std.mem.Allocator,
	
	pub fn addItem(self: @This(), item: *FileStructure) !void {
		var lastNode: Node = .{
			.next = self.rootNode,
			.val = undefined
		};

		for (item.title) |char| {
			if (lastNode.next != null) {
				lastNode.next = initHashmap();
			}

			var hashmap = lastNode.next.?;
			lastNode = hashmap.get(char) orelse b: {
				const nextNode: Node = .{
					.next = initHashmap(),
					.val = undefined
				};
				// dupe to outlive stack
				try hashmap.put(char, self.alloc.dupe(Node, nextNode));
				break :b nextNode;
			};
		}

		lastNode.val = item;
	}

	fn iterate(self: @This(), str: []const u8) ?Node {
		var lastNode: Node = self.rootNode;

		for (str) |char| {
			lastNode = lastNode.next.?.get(char) orelse return;
		}

		return lastNode;
	}

	// resultAlloc should be a arena allocator to deinit the slices in the array easily
	pub fn search(self: @This(), str: []const u8, resultAlloc: std.mem.Allocator) !?std.ArrayList(*FileStructure) {
		const lastNode = self.iterate(str) orelse return; //empty slice

		const allocTemp = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
		defer allocTemp.deinit();
		const searchAlloc = allocTemp.allocator();

		const stack = try std.ArrayList(Node).initCapacity(searchAlloc, 60);
		stack.appendAssumeCapacity(lastNode);

		// initialised with resultAlloc beacuse lives after func ends
		const results = try std.ArrayList(*FileStructure).initCapacity(resultAlloc, 20);

		// do depth first because shifting arr by 1 is o(n) each time
		while (stack.pop()) |last| {

			if (last.val.?) {
				results.append(last.val.?);
			}

			var iter = last.next.?.valueIterator();
			while (iter.next()) |block| {
				// block might be stack memory, need to copy to resultAlloc?
				stack.append(searchAlloc, block);
			}
		}
		
		return results;
	}

	pub fn deinit(self: @This()) void {
		self.allocTemp;
	}
};


pub fn init() TrieClass {
    var alloc = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    return .{
        .allocTemp = alloc,
        .alloc = alloc.allocator(),
        .rootNode = initHashmap(),
    };
}

fn initHashmap() std.AutoHashMap(u8, Node) {
	return std.AutoHashMap(u8, Node).init(std.heap.smp_allocator);
}