const std = @import("std");
const generalHeapAlloc = @import("alloc.zig").generalHeapAlloc;

const consts = @import("consts.zig");
const FileStructure = consts.FileStructure;
const savedData = &consts.savedData;

const config = &@import("config.zig").config;


fn createConfigFile(cwd: std.Io.Dir) std.Io.File {
	return cwd.createFile(consts.IO, if (config.savedDataType == .JSON) "config.json" else "config.bin", .{ .lock = .exclusive }) catch |err| {
		std.debug.print("Unable to create config file in cwd, {}", .{err});
		std.process.exit(1); // 
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
}


// Structure:
// data: [priority:u16, notes: []const u8, title: []const u8] repeated
// offsets: [notesoffset: u16, titleoffset: u16] repeated
// version: u16
const storageVersion = 1;
fn formatBinary(writer: *std.Io.Writer) void {
	var iter = savedData.valueIterator();
	// this stores how many u8s are from the last offset
	// u16 max is 65,535 so its plenty
	// only title and notes have a offset, priority is always u16 in size
	var offsets = std.ArrayList(u16).initCapacity(generalHeapAlloc, 10) catch |err| {
		std.debug.print("Unable to create arraylist due to memory issues outside this programs control.\n{}", .{err});
		return;
	};

	while (iter.next()) |block| {
		var buffer = generalHeapAlloc.alloc(u8, block.*.title.len + block.*.notes.len + 2) catch |err| {
			std.debug.print("Unable to create arraylist due to memory issues outside this programs control.\n{}", .{err});
			return;
		};
		defer generalHeapAlloc.free(buffer);

		// cant i just write individually instead of assigning to buffer
		const lowerPart: u8 = @truncate(block.*.priority);
		const upperPart: u8 = @truncate(block.*.priority >> 8);
		buffer[0] = lowerPart;
		buffer[1] = upperPart;

		const titleEnd = block.*.title.len + 2;
		@memcpy(buffer[2..titleEnd], block.*.*.title);
		@memcpy(buffer[titleEnd..], block.*.*.notes);

		offsets.append(generalHeapAlloc, @intCast(block.*.notes.len)) catch |err| {
			std.debug.print("Unable to append to arraylist due to memory issues outside this programs control.\n{}", .{err});
			return;
		};
		offsets.append(generalHeapAlloc, @intCast(block.*.title.len)) catch |err| {
			std.debug.print("Unable to append to arraylist due to memory issues outside this programs control.\n{}", .{err});
			return;
		};

		writer.writeAll(buffer) catch |err| {
			std.debug.print("Failed to write block to config file:\n{}", .{err});
			return;
		};
	}

	writer.writeSliceEndian(u16, offsets.items, .big) catch |err| {
		std.debug.print("Failed to write offsets to end of file:\n{}", .{err});
		return;
	};

	writer.writeInt(u16, @intCast(offsets.items.len), .big) catch |err| {
		std.debug.print("Failed to write number of offsets to end of file:\n{}", .{err});
		return;
	};

	writer.writeInt(u16, @intCast(storageVersion), .big) catch |err| {
		std.debug.print("Failed to write number of offsets to end of file:\n{}", .{err});
		return;
	};
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


	std.debug.print("Written to config file", .{});
}