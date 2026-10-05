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
	cls,
	exit
};
pub const CommandDescription: struct {
	help: []const u8,
	add: []const u8,
	delete: []const u8,
	list: []const u8,
	cls: []const u8,
	exit: []const u8
} = .{
	.help = "",
	.add = "",
	.delete = "",
	.list = "",
	.cls = "",
	.exit = "",
};
comptime {
    for (@typeInfo(Commands).@"enum".fields) |field| {
        if (!@hasField(@TypeOf(CommandDescription), field.name))
            @compileError("Missing description for command: " ++ field.name);
    }
}


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