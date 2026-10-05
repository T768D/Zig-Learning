const std = @import("std");

const utils = @import("utils.zig");
const clearConsole = utils.clearConsole;
const trimEnd = utils.trimEnd;

const consts = @import("consts.zig");
const reader = &consts.reader.interface;
const FileStructure = consts.FileStructure;
const CommandDescription = consts.CommandDescription;
const savedData = &consts.savedData;


pub fn main() !void {
	consts.init();

	// cant be moved up or else therell be a random segfault
	clearConsole();
	try readSaved();

	while (true) {
		const input = awaitInput();
		try parseInput(input);
	}
}


fn awaitInput() []const u8 {

	std.debug.print("\n>",.{});

	// this waits until \n is streamed into the buffer then executes, is blocking
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


fn parseInput(str: []const u8) !void {
	clearConsole();

	if (std.mem.eql(u8, str, @tagName(consts.Commands.add))) {
		var appendingData: FileStructure = .{
			.title = "",
			.priority = 0,
			.notes = ""
		};

		std.debug.print("Input the title", .{});
		const title = awaitInput();
		appendingData.title = title;

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

		appendingData.title = try savedData.*.allocator.dupe(u8, appendingData.title);
		appendingData.notes = try savedData.*.allocator.dupe(u8, appendingData.notes);
		try savedData.*.put(appendingData.title, appendingData);
	}

	else if (std.mem.startsWith(u8,str, @tagName(consts.Commands.delete))) {
		var title: []const u8 = undefined;

		if (str.len <= 6) {
			std.debug.print("Input title", .{});
			title = awaitInput();
		}
		else {
			title = str[7..str.len];
		}

		if (savedData.*.remove(title)) {
			std.debug.print("Removed {s} from the todo",.{title});
		}
		else {
			std.debug.print("No todo with the name {s} exists", .{title});
		}
	}

	else if (std.mem.eql(u8, str, @tagName(consts.Commands.list))) {
		var iter = savedData.*.valueIterator();
		var order = try std.ArrayList(FileStructure).initCapacity(std.heap.smp_allocator, iter.len);
		defer order.deinit(std.heap.smp_allocator);

		while (iter.next()) |item| {
			try order.append(std.heap.smp_allocator, item.*);
		}

		std.mem.sort(FileStructure,order.items,{}, sortAssit);
	
		for (order.items) |item| {
			std.debug.print("\n{d} {s}\n{s}\n\n", .{item.priority, item.title, item.notes});
		}
	}

	else if (std.mem.eql(u8, str, @tagName(consts.Commands.help))) {
		// std.meta.fields is comptime, therefore loop needs inlining
		// std.meta.fields takes a comptime object and makes its data accessible
		inline for (std.meta.fields(@TypeOf(CommandDescription))) |cmd| {
			std.debug.print("{s}\n", .{cmd.name});
		}
	}

	else if (std.mem.eql(u8, str, "cls") or std.mem.eql(u8, str, "exit")) {
		std.process.exit(0);
	}

	else if (std.mem.eql(u8, str, "save")) {
		writeSaved();
	}

	else {
		std.debug.print("Invalid input", .{});
	}
}


fn readSaved() !void {

	const cwd = std.Io.Dir.cwd();
	// need the try to catch the error propogated from cwd.createFile in this catch block
	const file = cwd.openFile(consts.IO, "config.json", .{ .mode = .read_write }) 
		catch |err| switch (err) {
			std.Io.File.OpenError.FileNotFound => createConfigFile(cwd),
			else =>	return err
		};

	var fileReader = file.reader(consts.IO, &.{});
	const fileContents = fileReader.interface.allocRemaining(
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

	// *block makes the capture block mutable
	for (json.value) |*block| {
		std.debug.print("{s} {s}", .{block.title, block.notes});

		block.title = try savedData.*.allocator.dupe(u8, block.title);
		block.notes = try savedData.*.allocator.dupe(u8, block.notes);
		try savedData.*.put(block.title, block.*);
	}
}


fn writeSaved() void {
	const cwd = std.Io.Dir.cwd();

	const file = cwd.openFile(consts.IO, "config.json", .{ .mode = .write_only})
		catch |err| switch (err) {
			std.Io.File.OpenError.FileNotFound => createConfigFile(cwd),
			else => {
				std.debug.print("Unable to access file \n\n{}", .{err});
				return;
			}
		};

	var writer = file.writer(consts.IO, &.{});
	var iter = savedData.*.valueIterator();

	writer.interface.writeByte('[') catch |err| {
		std.debug.print("Failed to write initialiser to config file: {}", .{err});
		return;
	};

	var isFirst = true;
	while (iter.next()) |block| {

		const formatted = std.fmt.allocPrint(
			std.heap.smp_allocator,
			// needs {{ otherwise zig will think its format string
			"{s}\n{{\n    \"title\": \"{s}\",\n    \"priority\": {d},\n    \"notes\": \"{s}\"\n}}\n",
			.{ if (isFirst) "" else ",", block.title, block.priority, block.notes },
		) catch |err| {
			std.debug.print("Failed to format json string\n {}", .{err});
			return;
		};
		defer std.heap.smp_allocator.free(formatted);

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
	return cwd.createFile(consts.IO, "config.json", .{}) catch |err| {
		std.debug.print("Unable to create config file in cwd, {}", .{err});
		std.process.exit(1); // lazy fix
	};
}