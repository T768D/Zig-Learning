const std = @import("std");
const generalHeapAlloc = @import("alloc.zig").generalHeapAlloc;

const consts = @import("consts.zig");
const FileStructure = consts.FileStructure;
const savedData = &consts.savedData;

const config = &@import("config.zig").config;


fn createConfigFile(cwd: std.Io.Dir) std.Io.File {
	return cwd.createFile(consts.IO, if (config.savedDataType == .JSON) "config.json" else "config.bin", .{ .lock = .exclusive }) catch |err| {
		std.debug.print("Unable to create config file in cwd, {}", .{err});
		std.process.exit(1);
	};
}


fn parseJSON(alloc: std.mem.Allocator, fileContents: []const u8) !std.json.Parsed([]FileStructure) {
	return try std.json.parseFromSlice([]FileStructure, alloc, fileContents, .{});
}

pub fn readSaved() !void {
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

	// todo
	const parsed = (if (config.savedDataType == .JSON) parseJSON(generalHeapAlloc, fileContents) else parseJSON(generalHeapAlloc, fileContents)) catch |err| {
		std.debug.print("Unable to parse json, defaulting to empty data. {}", .{err});
		// initialised as a slice, need to give the actaul value
		return;
	};
	defer parsed.deinit();

	// *block makes the capture block mutable
	for (parsed.value) |block| {
		// deep clone everything to be owned by savedData
		const newBlock = try savedData.allocator.create(FileStructure);
		newBlock.notes = try savedData.allocator.dupe(u8, block.notes);
		newBlock.title = try savedData.allocator.dupe(u8, block.title);
		newBlock.priority = block.priority;

		try savedData.put(newBlock.title, newBlock);
	}
}


fn formatJSON(writer: *std.Io.Writer) void {
	var iter = savedData.valueIterator();
	var isFirst = true;

	writer.writeByte('[') catch |err| {
		std.debug.print("Failed to write initialiser to config file: {}\n", .{err});
		return;
	};

	while (iter.next()) |block| {
		const formatted = std.fmt.allocPrint(
			generalHeapAlloc,
			// needs {{ otherwise zig will think its format string
			"{s}{{\n    \"title\": \"{s}\",\n    \"priority\": {d},\n    \"notes\": \"{s}\"\n}}",
			.{ if (isFirst) "" else ",\n", block.*.title, block.*.priority, block.*.notes },
		) catch |err| {
			std.debug.print("Failed to format block\n {}\n", .{err});
			return;
		};
		// could the allocation slot be reused? check .len of the 2 slices, and add the u16
		defer generalHeapAlloc.free(formatted);

		writer.writeAll(formatted) catch |err| {
			std.debug.print("Failed to write block to config file: {}\n", .{err});
			return;
		};

		isFirst = false;
	}

	writer.writeByte(']') catch |err| {
		std.debug.print("Failed to write initialiser to config file: {}\n", .{err});
		return;
	};

	std.debug.print("Written to config file", .{});
}


/// Structure:
/// version: u8
/// [priority:u16, notesOffset: u16, notes: []const u8, titleOffset: u16, title: []const u8] repeated
const storageVersion: u8 = 1;
fn formatBinary(writer: *std.Io.Writer) void {
	var iter = savedData.valueIterator();
	// this stores how many u8s are from the last offset
	// u16 max is 65,535 so its plenty
	// only title and notes have a offset, priority is always u16 in size

	// Sends bytes to the logical sink. A write will only be sent here if it
    // could not fit into `buffer`, or during a `flush` operation.
	// from zig docs
	// so calling multiple write requests wont do anything

	writer.writeByte(storageVersion) catch |err| {
		std.debug.print("Failed to write number of offsets to end of file:\n{}", .{err});
		return;
	};

	while (iter.next()) |block| {
		writer.writeInt(u16, block.*.priority, .big) catch |err| {
			std.debug.print("Failed to write priority to config file:\n{}", .{err});
			return;
		};

		writer.writeInt(u16, @intCast(block.*.title.len), .big) catch |err| {
			std.debug.print("Failed to write offset for title: '{s}' to file:\n{}", .{block.*.title, err});
			return;
		};
		writer.writeAll(block.*.title) catch |err| {
			std.debug.print("Failed to write title: '{s}' to file:\n{}", .{block.*.title, err});
			return;
		};

		writer.writeInt(u16, @intCast(block.*.notes.len), .big) catch |err| {
			std.debug.print("Failed to write offset for note: '{s}' to file:\n{}", .{block.*.notes, err});
			return;
		};
		writer.writeAll(block.*.notes) catch |err| {
			std.debug.print("Failed to write notes: '{s}' to file:\n{}", .{block.*.notes, err});
			return;
		};
	}

	std.debug.print("Written to config file", .{});
}

pub fn writeSaved() void {
	const cwd = std.Io.Dir.cwd();
	const file = cwd.openFile(
		consts.IO,
		if (config.savedDataType == .JSON) "config.json" else "config",
		.{ .mode = .write_only, .lock = .exclusive }
	)
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
		std.debug.print("Unable to set file length to 0:\n{}", .{err});
	};

	var writer = file.writer(consts.IO, &.{});
	if (config.savedDataType == .JSON) {
		formatJSON(&writer.interface);
	}
	else {
		formatBinary(&writer.interface);
	}

	// writer.flush just calls to writer.interface.flush so same thing
	writer.interface.flush() catch |err| {
		std.debug.print("Unable to flush reamining information in write buffer:\n{}", .{err});
	};
}