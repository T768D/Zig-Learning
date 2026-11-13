const std = @import("std");
const FileStructure = @import("consts.zig").FileStructure;
const generalHeapAlloc = @import("alloc.zig").generalHeapAlloc;

const Node = struct {
	val: ?*FileStructure,
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

	// does not remove pointer from Node.next, you need to do it before this
	fn freeNodeIfExist(self: *@This(), fileStructure: ?*FileStructure) !void {
		if (fileStructure == null) {
			return;
		}
		self.allocator.free(fileStructure.title);
		self.allocator.free(fileStructure.notes);
		self.allocator.free(fileStructure);
	}

	fn initHashmap(self: *@This()) std.AutoHashMap(u8, *Node) {
		return std.AutoHashMap(u8, *Node).init(self.allocator);
	}


	pub fn add(self: *@This(), item: *FileStructure) !void {
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

	pub fn delete(self: *@This(), item: *FileStructure) !bool {
		var stack = try std.ArrayList(*const Node).initCapacity(generalHeapAlloc, 10);
		defer stack.deinit(generalHeapAlloc);

		var lastNode = &self.rootNode;

		for (item.title) |char| {
			lastNode = lastNode.next.?.get(char) orelse return false;
			try stack.append(generalHeapAlloc, lastNode);
		}

		// if search str is 0 or tree depth is 0, then stack will have len 0, and cause panic when popping stack (i think)
		if (lastNode.val == null or stack.items.len == 0)  {
			return false;
		}

		self.freeNodeIfExist(lastNode.val);
		lastNode.val = null;

		if (lastNode.next == null) {
			return true;
		}

		var depth = stack.items.len - 1;
		while (stack.pop()) |stackItem| {
			// stops removing the leafs if it contains another child node, or it is a ending node
			if (stackItem.val != null or stackItem.next.?.count() >= 2) {
				return true;
			}

			const existed = stackItem.next.?.remove(item.title[depth]);
			if (!existed) {
				std.debug.print("Trie hashmap does not have char {c} for some reason", .{item.title[depth]});
			}
			depth -= 1;
		}

		return true;
	}


	/// Iterates to the end of the string provided and returns the node
	fn iterateTo(self: *@This(), str: []const u8) ?*const Node {
		var lastNode = &self.rootNode;

		for (str) |char| {
			lastNode = lastNode.next.?.get(char) orelse return null;
		}

		return lastNode;
	}

	/// resultAlloc should be a arena allocator to deinit the slices in the array easily
	pub fn search(self: *@This(), str: []const u8, resultAlloc: std.mem.Allocator) !?std.ArrayList(*FileStructure) {
		const lastNode = self.iterateTo(str) orelse return null;

		var stack = try std.ArrayList(*const Node).initCapacity(generalHeapAlloc, 15);
		defer stack.deinit(generalHeapAlloc);
		stack.appendAssumeCapacity(lastNode);

		// initialised with resultAlloc beacuse lives after func ends
		var results = try std.ArrayList(*FileStructure).initCapacity(resultAlloc, 5);

		// do depth first because shifting arr by 1 is o(n) each time
		while (stack.pop()) |last| {
			if (last.val) |val| {
				try results.append(resultAlloc, val);
			}

			var iter = last.next.?.valueIterator();
			while (iter.next()) |block| {
				// block might be stack memory, need to copy to resultAlloc?
				try stack.append(generalHeapAlloc, block.*);
			}
		}
		
		return results;
	}


	/// Returns pointers to all the items in the trie
	/// Do not assume that all pointers to the items will be valid forever
	/// Allocator param is only used for the returned arraylist
	pub fn getAllItems(self: *@This(), alloc: std.mem.Allocator) !std.ArrayList(*const FileStructure) {
		var output = try std.ArrayList(*const FileStructure).initCapacity(alloc, 100);

		var stack = try std.ArrayList(*const Node).initCapacity(generalHeapAlloc, 15);
		defer stack.deinit(generalHeapAlloc);
		stack.appendAssumeCapacity(&self.rootNode);

		// do depth first because shifting arr by 1 is o(n) each time
		while (stack.pop()) |last| {
			if (last.val) |val| {
				try output.append(alloc, val);
			}

			var iter = last.next.?.valueIterator();
			while (iter.next()) |block| {
				// block might be stack memory, need to copy to resultAlloc?
				try stack.append(generalHeapAlloc, block.*);
			}
		}

		return output;
	}

	// pub fn deinit() void {
		// self.allocTemp.deinit();
	// }
};