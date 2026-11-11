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
	delete, remove,
	list,
	search,
	config,
	save,
	load,
	cls, exit,
	invalid,

	pub fn describe(self: @This()) []const u8 {
		return switch (self)  {
			.help => "Lists all the commands and what they do",
			.add => "Adds a item to the todo list",
			.delete, .remove => "Deletes a item from the todo list. This command can accept the item name as a param",
			.list => "Lists all the items in the todo list",
			.search => "Searches the todo list based on user input",
			.config => "Modifies the settings for this program",
			.save => "Saves the todo list",
			.load => "Reloads the todo list and discards current data",
			.cls, .exit => "Exits the program",
			// adding a return union was too verbose
			.invalid => "A invalid command, here for technical reasons"
		};
	}
};



// hashmap because we need to access title when user enteres add/remove
pub var currentData: std.StringHashMap(*FileStructure) = undefined;
pub var currentDataArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

var ioType: std.Io.Threaded = undefined;
pub var IO: std.Io = undefined;
pub var reader: std.Io.File.Reader = undefined;
// inputBuffer is implicitly sent to awaitInput and parseInput via reader
var inputBuffer: [2048]u8 = undefined;


pub fn init() void {
    currentData = .init(currentDataArena.allocator());

    ioType = .init_single_threaded;
    IO = ioType.io();
	// defer ioType.deinit();

	const stdin = std.Io.File.stdin();
	reader = stdin.readerStreaming(IO, &inputBuffer);
}