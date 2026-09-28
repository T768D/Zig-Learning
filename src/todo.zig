const std = @import("std");


// add, remove, list, complete
// Store todos in memory first, then save them to a file.

const FileStructure = struct {
	title: []const u8,
	priority: u16,
	notes: []const u8
};


const Commands = enum {
	help,
	add,
	delete
};
const CommandDescription: struct {
	help: []const u8,
	add: []const u8,
	delete: []const u8
} = .{
	.help = "",
	.add = "",
	.delete = ""
};
comptime {
    for (@typeInfo(Commands).@"enum".fields) |field| {
        if (!@hasField(@TypeOf(CommandDescription), field.name))
            @compileError("Missing description for command: " ++ field.name);
    }
}

var arena: std.heap.ArenaAllocator = undefined;
// hashmap because we need to access title when user enteres add/remove
var savedData: std.StringHashMap(FileStructure) = undefined;

var ioType: std.Io.Threaded = undefined;
var IO: std.Io = undefined;


pub fn main() !void {
	arena = .init(std.heap.page_allocator);
    savedData = .init(arena.allocator());
    ioType = .init_single_threaded;
    IO = ioType.io();
	
	defer ioType.deinit();

	// cant be moved up or else therell be a random segfault
	clearConsole();
	try readSaved();

	while (true) {
		const input = awaitInput();
		try parseInput(input);
	}
}


fn trimEnd(str: []const u8) []const u8 {
	if (str.len == 0)
		return str;

	var strLen = str.len - 1;
	while (str[strLen] == ' ') {
		strLen -= 1;
	}

	return str[0..strLen];
}

fn clearConsole() void {
	// "\x1b[2J" clears the screen and "\x1b[H" moves the cursor to the top-left
	std.Io.File.stdout().writeStreamingAll(IO, "\x1b[2J\x1b[H") catch {};
}


fn awaitInput() []const u8 {

	std.debug.print("\n>",.{});
	const stdin = std.Io.File.stdin();
	var inputBuffer: [2048]u8 = undefined;
	var reader = stdin.readerStreaming(IO, &inputBuffer);

	// this waits until \n is streamed into the buffer then executes, is blocking
	const input = reader.interface.takeDelimiterExclusive('\n') catch |err| {
		std.debug.print("Error when reading input buffer, {}", .{err});
		return "";
	};

	return trimEnd(input);
}

// need the 1st var to be void because compiler doesnt like it
fn sortAssit(_: void, A: FileStructure, B: FileStructure) bool {
	return A.priority > B.priority;
}


fn parseInput(str: []const u8) !void {
	if (std.mem.eql(u8, str, "add")) {
		var appendingData: FileStructure = .{
			.title = "",
			.priority = 0,
			.notes = ""
		};

		std.debug.print("Input the title", .{});
		const title = awaitInput();
		appendingData.title = title;

		// potential memory leak here, when is buffer deallocated? how long does it live for?
		while (true) {
			std.debug.print("Input the priority level", .{});
			const priority = awaitInput();

			const convertedInt = std.fmt.parseInt(u8, priority, 10) catch {
				std.debug.print("Input is not a number or is too big!\n", .{});
				continue;
			};

			appendingData.priority = convertedInt;
			appendingData.title = title;
			break;
		}

		std.debug.print("Input notes", .{});
		const input = awaitInput();
		appendingData.notes = input;

		try savedData.put(appendingData.title, appendingData);
	}

	else if (std.mem.startsWith(u8,str, "delete")) {
		const title = str[7..str.len];
		if (savedData.remove(title)) {
			std.debug.print("Removed {s} from the todo",.{title});
		}
		else {
			std.debug.print("No todo with the name {s} exists", .{title});
		}
	}

	else if (std.mem.eql(u8, str, "list")) {
		var iter = savedData.valueIterator();
		var order = try std.ArrayList(FileStructure).initCapacity(std.heap.smp_allocator, iter.len);

		while (iter.next()) |item| {
			try order.append(std.heap.smp_allocator, item.*);
		}

		std.mem.sort(FileStructure,order.items,{}, sortAssit);
	
		for (order.items) |item| {
			std.debug.print("\n{d} {s}\n{s}\n\n", .{item.priority, item.title, item.notes});
		}
	}

	else if (std.mem.eql(u8, str, "help")) {
		// std.meta.fields is comptime, therefore loop needs inlining
		// std.meta.fields takes a comptime object and makes its data accessible
		inline for (std.meta.fields(@TypeOf(CommandDescription))) |cmd| {
			std.debug.print("{s}\n", .{cmd.name});
		}
	}

	else if (std.mem.eql(u8, str, "cls") or std.mem.eql(u8, str, "exit")) {
		clearConsole();
		std.process.exit(0);
	}

	else {
		clearConsole();
		std.debug.print("Invalid input", .{});
	}
}


fn readSaved() !void {

	const cwd = std.Io.Dir.cwd();
	// need the try to catch the error propogated from cwd.createFile in this catch block
	const file = cwd.openFile(IO, "config.json", .{}) catch |err| switch (err) {
		std.Io.File.OpenError.FileNotFound => try cwd.createFile(IO, "config.json", .{}),
		else =>	return err
	};

	var reader = file.reader(IO, &.{});
	const fileContents = reader.interface.allocRemaining(
		std.heap.smp_allocator,
		.unlimited,
	) catch |err| {
		std.debug.print("Failed to read config file: {}", .{err});
		std.process.exit(1);
	};
	defer std.heap.smp_allocator.free(fileContents);

	// std.debug.print("File Contents: \n{s}\n\n", .{fileContents});

	const json = std.json.parseFromSlice([]FileStructure, std.heap.smp_allocator, fileContents, .{}) catch |err| {
		std.debug.print("Unable to parse json, defaulting to empty data. {}", .{err});
		// initialised as a slice, need to give the actaul value
		return;
	};
	defer json.deinit();

	for (json.value) |block| {
		try savedData.put(block.title, block);
	}
}


fn writeSaved() void {
	const cwd = std.Io.Dir.cwd();

	const file = cwd.openFile(IO, "config.json", .{}) catch |err| switch (err) {
		std.Io.File.OpenError.FileNotFound => try cwd.createFile(IO, "config.json", .{}),
		else => return err
	};

	var writer = file.writer(IO, &.{});
	writer.interface.writeAll() catch |err| {
		std.debug.print("Failed to write to config file: {}", .{err});
		std.process.exit(1);
	};
}