const std = @import("std");
const FileStructure = @import("consts.zig").FileStructure;
const generalHeapAlloc = @import("alloc.zig").generalHeapAlloc;

const Node = struct {
	val: ?*const FileStructure,
	next: ?std.AutoHashMap(u8, *Node),
};

pub const TrieClass = struct {
	rootNode: Node,
	allocator: std.mem.Allocator,

	// alloc cant be arena, individual nodes may need to be cleared, but also needs to be able to clear all at once
	pub inline fn init(alloc: std.mem.Allocator) TrieClass {
		return .{
			.allocator = alloc,
			.rootNode = .{
				.next = std.AutoHashMap(u8, *Node).init(alloc),
				.val = null
			},
		};
	}

	fn initHashmap(self: *@This()) std.AutoHashMap(u8, *Node) {
		return std.AutoHashMap(u8, *Node).init(self.allocator);
	}


	pub fn add(self: *@This(), item: *const FileStructure) !void {
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

	/// Returns true if item was deleted, false if item did not exist
	/// currentData's allocator owns the structs, the only thing we own here is the hashmap and node
	pub fn delete(self: *@This(), item: *const FileStructure) !bool {

		var path = (try self.iterateToRetainStack(item.title, generalHeapAlloc)) orelse return false;
		defer path.deinit(generalHeapAlloc);

		// index 0 is root node, do not iterate over it
		var index = path.items.len - 1;
		while (index >= 1) {
			const node = path.items[index];
			// iterates upwards so if parentNodeNext is removed, itll be covered next iter
			if (node.next == null and node.val == null) {
				self.allocator.destroy(node);
			}

			const parentNode = path.items[index - 1];
			// this has to have existed otherwise self.iterateToRetainStack cant reach this
			var parentNodeNext = parentNode.next orelse unreachable;
			// assumes that the title and stack have the same char at same index
			std.debug.assert(parentNodeNext.remove(item.title[index - 1]));
			
			if (parentNodeNext.count() == 0) {
				parentNodeNext.deinit();
				parentNode.next = null;
			}

			index -= 1;
		}
		
		return true;
	}


	/// Iterates to the end of the string provided, and returns a stack of the nodes visited, allocated with alloc param
	fn iterateToRetainStack(self: *@This(), str: []const u8, alloc: std.mem.Allocator) !?std.ArrayList(*Node) {
		var lastNode = &self.rootNode;
		var stack = try std.ArrayList(*Node).initCapacity(alloc, 15);
		errdefer stack.deinit(alloc);
		stack.appendAssumeCapacity(lastNode);

		for (str) |char| {
			lastNode = lastNode.next.?.get(char) orelse return null;
			try stack.append(alloc, lastNode);
		}

		return stack;
	}


	/// Iterates to the end of the string provided and returns the node
	fn iterateTo(self: *@This(), str: []const u8) ?*const Node {
		var lastNode = &self.rootNode;

		for (str) |char| {
			lastNode = lastNode.next.?.get(char) orelse return null;
		}

		return lastNode;
	}

	/// Iterates over all subnodes of the given node and returns a arraylist with pointers to the values of each node
	fn iterate(self: *@This(), startNode: *const Node, resultAlloc: std.mem.Allocator) !std.ArrayList(*const FileStructure) {
		// self isint used but i still want this to be a class method
		_ = self;

		var output = try std.ArrayList(*const FileStructure).initCapacity(resultAlloc, 15);

		var stack = try std.ArrayList(*const Node).initCapacity(generalHeapAlloc, 15);
		defer stack.deinit(generalHeapAlloc);
		stack.appendAssumeCapacity(startNode);

		// do depth first because shifting arr by 1 is o(n) each time
		while (stack.pop()) |last| {
			if (last.val) |val| {
				try output.append(resultAlloc, val);
			}

			var iter = last.next.?.valueIterator();
			while (iter.next()) |block| {
				// block might be stack memory, need to copy to resultAlloc?
				try stack.append(generalHeapAlloc, block.*);
			}
		}

		return output;
	}


	pub fn search(self: *@This(), str: []const u8, resultAlloc: std.mem.Allocator) !?std.ArrayList(*const FileStructure) {
		const endOfExactMatch = self.iterateTo(str) orelse return null;

		// initialised with resultAlloc beacuse lives after func ends
		return try self.iterate(endOfExactMatch, resultAlloc);
	}

	/// Returns pointers to all the items in the trie
	/// Do not assume that all pointers to the items will be valid forever
	/// Allocator param is only used for the returned arraylist
	pub fn getAllItems(self: *@This(), resultAlloc: std.mem.Allocator) !std.ArrayList(*const FileStructure) {
		return try self.iterate(&self.rootNode, resultAlloc);
	}

	// pub fn deinit() void {
		// self.allocTemp.deinit();
	// }
};