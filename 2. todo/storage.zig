const std = @import("std");
const generalHeapAlloc = @import("alloc.zig").generalHeapAlloc;
const config = &@import("config.zig").config;
const savedDataEnum = @import("config.zig").savedDataEnum;

const consts = @import("consts.zig");
const FileStructure = consts.FileStructure;
const currentData = &consts.currentData;
const currentDataArena = &consts.currentDataArena;
const consoleReader = &consts.reader.interface;

const awaitInput = @import("utils.zig").awaitInput;
const clearConsole = @import("utils.zig").clearConsole;


fn createStorageFile(cwd: std.Io.Dir) std.Io.File {
	return cwd.createFile(consts.IO, if (config.savedDataType == .JSON) "storage.json" else "storage.bin", .{ .lock = .exclusive }) catch |err| {
		std.debug.print("Unable to create storage file in cwd, {}", .{err});
		std.process.exit(1);
	};
}


/// Structure:
/// version: u8
/// [priority:u16, notesOffset: u16, notes: []const u8, titleOffset: u16, title: []const u8] repeated
fn parseBinary(reader: *std.Io.Reader) !void {
	// instead of reading from buffer already in memory read streaming from file
	const version = reader.takeByte() catch |err| {
		std.debug.print("Unable to peek the first byte of the binary storage file. Is the file empty? Version:\n{}",. {err});
		return;
	};

	if (version != storageVersion) {
		while (true) {
			clearConsole();
			std.debug.print("Storage version does not match the current program version, you can attempt to parse it but it may not work. Proceed? (Y/N)\n>", .{});
			const input = try consoleReader.takeDelimiter('\n') orelse continue;

			if (input[0] == 'y' or input[0] == 'Y') {
				break;
			}
			else if (input[0] == 'n' or input[0] == 'N') {
				std.debug.print("Saving aborted!\n", .{});
				return;
			}
		}
	}

	while (reader.seek < reader.end) {
		const block = try currentData.allocator.create(FileStructure);

		const priorityBytes = try reader.takeArray(2);
		block.priority = (@as(u16, priorityBytes[0]) << 8) | priorityBytes[1];

		const titleBytes = try reader.takeArray(2);
		const titleOffset = (@as(u16, titleBytes[0]) << 8) | titleBytes[1];
		block.title = try currentData.allocator.dupe(u8, try reader.take(titleOffset));

		const noteBytes = try reader.takeArray(2);
		const noteOffset = (@as(u16, noteBytes[0]) << 8) | noteBytes[1];
		block.notes = try currentData.allocator.dupe(u8, try reader.take(noteOffset));

		try currentData.put(block.title, block);
	}
}

fn parseJSON(fileReader: *std.Io.Reader) !void {
	const fileContents = fileReader.allocRemaining(generalHeapAlloc,.unlimited) catch |err| {
		std.debug.print("Failed to read from json storage file: {}", .{err});
		return;
	};
	defer generalHeapAlloc.free(fileContents);

	if (fileContents.len == 0) {
		std.debug.print("JSON storage file is empty!", .{});
		return;
	}

	const parsed = try std.json.parseFromSlice([]FileStructure, generalHeapAlloc, fileContents, .{});
	defer parsed.deinit();

	// *block makes the capture block mutable
	for (parsed.value) |block| {
		// deep clone everything to be owned by savedData
		const newBlock = try currentData.allocator.create(FileStructure);
		newBlock.title = try currentData.allocator.dupe(u8, block.title);
		newBlock.notes = try currentData.allocator.dupe(u8, block.notes);
		newBlock.priority = block.priority;

		try currentData.put(newBlock.title, newBlock);
	}
}

pub fn readSaved(override: ?savedDataEnum) !void {
	const savedDataType = override orelse config.savedDataType;

	const cwd = std.Io.Dir.cwd();
	// need the try to catch the error propogated from cwd.createFile in this catch block
	// reading doesnt need locks
	const file = cwd.openFile(
		consts.IO, 
		if (savedDataType == .JSON) "storage.json" else "storage.bin", 
		.{ .mode = .read_only, .lock = .exclusive }
	)
		catch |err| switch (err) {
			std.Io.File.OpenError.FileNotFound => createStorageFile(cwd),
			else =>	return err
		};
	defer file.unlock(consts.IO);
	defer file.close(consts.IO);

	var buffer: [4096]u8 = undefined;
	var fileReader = file.reader(consts.IO, &buffer);

	currentData.deinit();
	currentDataArena.deinit();
	currentDataArena.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    currentData.* = .init(currentDataArena.allocator());

	if (savedDataType == .JSON) {
		try parseJSON(&fileReader.interface);
	}
	else {
		try parseBinary(&fileReader.interface);
	}
}


fn formatJSON(writer: *std.Io.Writer) void {
	var iter = currentData.valueIterator();
	var isFirst = true;

	writer.writeByte('[') catch |err| {
		std.debug.print("Failed to write initialiser to storage file: {}\n", .{err});
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
			std.debug.print("Failed to write block to storage file: {}\n", .{err});
			return;
		};

		isFirst = false;
	}

	writer.writeByte(']') catch |err| {
		std.debug.print("Failed to write initialiser to storage file: {}\n", .{err});
		return;
	};

	std.debug.print("Written to JSON storage file", .{});
}


/// Structure:
/// version: u8
/// [priority:u16, notesOffset: u16, notes: []const u8, titleOffset: u16, title: []const u8] repeated
const storageVersion: u8 = 1;
fn formatBinary(writer: *std.Io.Writer) void {
	var iter = currentData.valueIterator();
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
			std.debug.print("Failed to write priority to storage file:\n{}", .{err});
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

	std.debug.print("Written to binary storage file", .{});
}

pub fn writeSaved(override: ?savedDataEnum) void {
	const savedDataType = override orelse config.savedDataType;

	const storagePath = if (savedDataType == .JSON) "storage.json" else "storage.bin";
	const backupPath = if (savedDataType == .JSON) "storage_backup.json" else "storage_backup.bin";

	const cwd = std.Io.Dir.cwd();
	const file = cwd.openFile(
		consts.IO,
		storagePath,
		.{ .mode = .write_only, .lock = .exclusive }
	)
		catch |err| switch (err) {
			std.Io.File.OpenError.FileNotFound => 
				// cwd.createFile is sent to file varaible if no errors
				cwd.createFile(consts.IO, storagePath, .{ .lock = .exclusive }) catch |err2| {
					std.debug.print("Unable to create storage file in cwd:\n{}\n", .{err2});
					return;
				}
			,
			else => {
				std.debug.print("Unable to access file:\n{}\n", .{err});
				return;
			}
		};
	// already locked when using openFile
	defer file.unlock(consts.IO);
	defer file.close(consts.IO);

	// file already created if not exists
	if (
		config.backupBeforeSave == .ALL or
		(config.backupBeforeSave == .JSON and savedDataType == .JSON) or
		(config.backupBeforeSave == .BINARY and savedDataType == .BINARY)
	) {
		cwd.copyFile(storagePath, cwd, backupPath, consts.IO, .{}) catch |err| {
			std.debug.print("Unable to create a backup of the config file:\n{}", .{err});
			return;
		};
	}

	file.setLength(consts.IO, 0) catch |err| {
		std.debug.print("Unable to set file length to 0:\n{}", .{err});
	};

	var buffer: [1024]u8 = undefined;
	var writer = file.writer(consts.IO, &buffer);
	if (savedDataType == .JSON) {
		formatJSON(&writer.interface);
	}
	else {
		formatBinary(&writer.interface);
	}

	// writer.flush just calls to writer.interface.flush so same thing
	writer.interface.flush() catch |err| {
		std.debug.print("Unable to flush reamining information in write buffer:\n{}", .{err});
		return;
	};

	if (config.deleteBackupIfNoErr) {
		cwd.deleteFile(consts.IO, backupPath) catch |err| {
			if (err != std.Io.File.OpenError.FileNotFound) {
				std.debug.print("Unable to delete backup file:\n{}", .{err});
				return;
			}
		};
	}
}