const std = @import("std");
const generalHeapAlloc = @import("alloc.zig").generalHeapAlloc;

const utils = @import("utils.zig");
const parseCommand = utils.parseCommand;
const clearConsole = utils.clearConsole;
const trimEnd = utils.trimEnd;
const escapeStr = utils.escapeStr;

// keep IO under consts because would need to convert out of pointer anyways, not much typing saved
const consts = @import("consts.zig");
const FileStructure = consts.FileStructure;
const reader = &consts.reader.interface;
const savedData = &consts.savedData;

var searchTrie: @import("trie.zig").TrieClass = undefined;
var trieInitialised = false;
const initTrie = @import("trie.zig").init;


pub fn main() !void {
	consts.init();
	searchTrie = initTrie(generalHeapAlloc);

	// cant be moved up or else therell be a random segfault
	clearConsole();
	try readSaved();

	while (true) {
		try parseInput(awaitInput());
	}
}


fn awaitInput() []const u8 {

	std.debug.print("\n>",.{});

	// is blocking: waits until \n is entered into the buffer then executes
	const input = reader.takeDelimiterExclusive('\n') catch |err| {
		std.debug.print("Error when reading input buffer, {}", .{err});
		return "";
	};

	// must toss the current input otherwise itll stay on the current \n in awaitInput
	// and cause it to advance without user input
	reader.toss(1);

	return trimEnd(input);
}


// need the 1st var to be void because compiler doesnt like it
fn sortAssit(_: void, A: FileStructure, B: FileStructure) bool {
	return A.priority > B.priority;
}
fn sortAssitPointer(_: void, A: *FileStructure, B: *FileStructure) bool {
	return A.priority > B.priority;
}


fn parseInput(str: []const u8) !void {
	clearConsole();

	sw: switch (parseCommand(str)) {

	.add => {
		const appendingData = try savedData.allocator.create(FileStructure);

		std.debug.print("Input the title", .{});
		// needs escaping because of json format saving
		// if implemented non json format then no need to escape
		const title = escapeStr(@constCast(awaitInput()));
		appendingData.title = try savedData.allocator.dupe(u8, title);

		while (true) {
			std.debug.print("Input the priority level", .{});
			const priority = awaitInput();

			const convertedInt = std.fmt.parseInt(u8, priority, 10) catch {
				std.debug.print("Input is not a number or is too big!\n", .{});
				continue;
			};

			// u8 is copied
			appendingData.priority = convertedInt;
			break;
		}

		std.debug.print("Input notes", .{});
		const notes = awaitInput();
		appendingData.notes = try savedData.allocator.dupe(u8, notes);

		try savedData.put(appendingData.title, appendingData);
		try searchTrie.add(appendingData);
	},

	.delete, .remove => {
		var title: []const u8 = undefined;

		if (str.len <= 6) {
			std.debug.print("Input title", .{});
			title = awaitInput();
		}
		else {
			title = str[7..str.len];
		}

		const val = savedData.get(title) orelse {
			std.debug.print("No todo with the name {s} exists", .{title});
			return;
		};
		// already checked if exists before
		// must remove BEFORE destryoing title
		_ = savedData.remove(title);
		// title is val.title so it is destroyed when val.title is
		savedData.allocator.free(val.title);
		savedData.allocator.free(val.notes);
		savedData.allocator.destroy(val);

		std.debug.print("Removed {s} from the todo",.{title});
	},

	.list => {
		var iter = savedData.valueIterator();
		var order = try std.ArrayList(*FileStructure).initCapacity(generalHeapAlloc, iter.len);
		defer order.deinit(generalHeapAlloc);

		while (iter.next()) |item| {
			try order.append(generalHeapAlloc, item.*);
		}

		std.mem.sort(*FileStructure,order.items,{}, sortAssitPointer);
	
		for (order.items) |item| {
			std.debug.print("\n{d}  {s}\n{s}\n\n", .{item.priority, item.title, item.notes});
		}
	},

	.search => {
		if (!trieInitialised) {
			var iter = savedData.valueIterator();
			while (iter.next()) |item| {
				try searchTrie.add(item.*);
			}
			trieInitialised = true;
		}

		std.debug.print("Enter title to search for", .{});
		const searchItem = awaitInput();

		var tempAlloc = std.heap.ArenaAllocator.init(generalHeapAlloc);
		defer tempAlloc.deinit();
		const searchAlloc = tempAlloc.allocator();

		const searchResult = searchTrie.search(searchItem, searchAlloc) catch |err| {
			std.debug.print("Unable to search through trie\n {}", .{err});
			break :sw;
		};

		if (searchResult == null) {
			std.debug.print("No matching items", .{});
			break :sw;
		}

		std.mem.sort(*FileStructure,searchResult.?.items,{}, sortAssitPointer);
	
		for (searchResult.?.items) |item| {
			std.debug.print("\n{d}  {s}\n{s}\n\n", .{item.priority, item.title, item.notes});
		}
	},

	.help => {
		// std.meta.fields is comptime, therefore loop needs inlining
		// std.meta.fields takes a comptime object and makes its data accessible
		inline for (std.meta.fields(consts.Commands)) |cmd| {
			std.debug.print("{s}: {s}\n", .{cmd.name, @field(consts.Commands, cmd.name).describe()});
		}
	},

	.exit, .cls => {
		clearConsole();
		std.process.exit(0);
	},

	.save => writeSaved(),
	// switch will return Commands.invalid for a invalid command, so i dont have to make a union so its less verbose
	.invalid => std.debug.print("Invalid input", .{}),

	}
}


fn readSaved() !void {

	const cwd = std.Io.Dir.cwd();
	// need the try to catch the error propogated from cwd.createFile in this catch block
	// reading doesnt need locks
	const file = cwd.openFile(consts.IO, "config.json", .{ .mode = .read_only }) 
		catch |err| switch (err) {
			std.Io.File.OpenError.FileNotFound => createConfigFile(cwd),
			else =>	return err
		};

	var fileReader = file.reader(consts.IO, &.{});
	const fileContents = fileReader.interface.allocRemaining(
		generalHeapAlloc,
		.unlimited,
	) catch |err| {
		std.debug.print("Failed to read config file: {}", .{err});
		std.process.exit(1);
	};
	defer generalHeapAlloc.free(fileContents);

	// std.debug.print("File Contents: \n{s}\n\n", .{fileContents});

	const json = std.json.parseFromSlice([]FileStructure, generalHeapAlloc, fileContents, .{}) catch |err| {
		std.debug.print("Unable to parse json, defaulting to empty data. {}", .{err});
		// initialised as a slice, need to give the actaul value
		return;
	};
	defer json.deinit();

	// *block makes the capture block mutable
	for (json.value) |block| {
		// deep clone everything to be owned by savedData
		const newBlock = try savedData.allocator.create(FileStructure);
		newBlock.notes = try savedData.allocator.dupe(u8, block.notes);
		newBlock.title = try savedData.allocator.dupe(u8, block.title);
		newBlock.priority = block.priority;

		try savedData.put(newBlock.title, newBlock);
	}
}


fn writeSaved() void {
	const cwd = std.Io.Dir.cwd();

	const file = cwd.openFile(consts.IO, "config.json", .{ .mode = .write_only, .lock = .exclusive })
		catch |err| switch (err) {
			std.Io.File.OpenError.FileNotFound => createConfigFile(cwd),
			else => {
				std.debug.print("Unable to access file \n\n{}", .{err});
				return;
			}
		};
	// already locked when using openFile
	defer file.unlock(consts.IO);

	file.setLength(consts.IO, 0) catch |err| {
		std.debug.print("Unable to set file length to 0, {}", .{err});
	};

	var writer = file.writer(consts.IO, &.{});
	var iter = savedData.valueIterator();

	writer.interface.writeByte('[') catch |err| {
		std.debug.print("Failed to write initialiser to config file: {}", .{err});
		return;
	};

	var isFirst = true;
	while (iter.next()) |block| {

		const formatted = std.fmt.allocPrint(
			generalHeapAlloc,
			// needs {{ otherwise zig will think its format string
			"{s}{{\n    \"title\": \"{s}\",\n    \"priority\": {d},\n    \"notes\": \"{s}\"\n}}",
			.{ if (isFirst) "" else ",\n", block.*.title, block.*.priority, block.*.notes },
		) catch |err| {
			std.debug.print("Failed to format json string\n {}", .{err});
			return;
		};
		defer generalHeapAlloc.free(formatted);

		writer.interface.writeAll(formatted) catch |err| {
			std.debug.print("Failed to write block to config file: {}", .{err});
			return;
		};

		isFirst = false;
	}

	writer.interface.writeByte(']') catch |err| {
		std.debug.print("Failed to write initialiser to config file: {}", .{err});
		return;
	};


	std.debug.print("Written to config file", .{});
}


fn createConfigFile(cwd: std.Io.Dir) std.Io.File {
	return cwd.createFile(consts.IO, "config.json", .{ .lock = .exclusive }) catch |err| {
		std.debug.print("Unable to create config file in cwd, {}", .{err});
		std.process.exit(1); // lazy fix
	};
}