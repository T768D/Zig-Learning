const std = @import("std");


// add, remove, list, complete
// Store todos in memory first, then save them to a file.
pub const FileStructure = struct {
	title: []const u8,
	priority: u16,
	notes: []const u8
};

pub const Commands = enum {
	help,
	add,
	delete,
	list,
	save,
	cls,
	exit,
	invalid,

	pub fn describe(self: @This()) []const u8 {
		return switch (self)  {
			.help => "Lists all the commands and what they do",
			.add => "Adds a item to the todo list",
			.delete => "Deletes a item from the todo list. This command can accept the item name as a param",
			.list => "Lists all the items in the todo list",
			.save => "Saves the todo list",
			.cls => "Exits the program",
			.exit => "Exits the program",
			// adding a return union was too verbose
			.invalid => "A invalid command, here for technical reasons"
		};
	}
};


var arena: std.heap.ArenaAllocator = undefined;
// hashmap because we need to access title when user enteres add/remove
pub var savedData: std.StringHashMap(FileStructure) = undefined;

var ioType: std.Io.Threaded = undefined;
pub var IO: std.Io = undefined;
pub var reader: std.Io.File.Reader = undefined;
// inputBuffer is implicitly sent to awaitInput and parseInput via reader
var inputBuffer: [2048]u8 = undefined;


pub fn init() void {
	arena = .init(std.heap.page_allocator);
	// defer arena.deinit();

    savedData = .init(arena.allocator());
    ioType = .init_single_threaded;
    IO = ioType.io();
	// defer ioType.deinit();

	const stdin = std.Io.File.stdin();
	reader = stdin.readerStreaming(IO, &inputBuffer);
}