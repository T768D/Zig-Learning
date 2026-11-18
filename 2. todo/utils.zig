const std = @import("std");

const Commands = @import("consts.zig").Commands;
const IO = &@import("consts.zig").IO;
const reader = &@import("consts.zig").reader.interface;

const saveDataEnum = @import("config.zig").savedDataEnum; 


pub fn clearConsole() void {
	// \x1b[2J clears visible screen 
	// \x1b[3J clears scrollback history
	// \x1b[H moves cursor to top left
	std.Io.File.stdout().writeStreamingAll(IO.*, "\x1b[3J\x1b[2J\x1b[H") catch {};
	std.debug.print("Zigdo CLI\n\n", .{});
}

pub fn trimEnd(str: []u8) []u8 {
	if (str.len == 0)
		return str;

	var strLen = str.len - 1;
	while (str[strLen] == ' ') {
		strLen -= 1;
	}

	return str[0..strLen];
}

pub fn parseCommand(str: []const u8) Commands {
	const info = @typeInfo(Commands).@"enum";
	inline for (info.field_names, info.field_values) |name, value| {
        if (std.mem.startsWith(u8, str, name)) {
            return @fromBackingInt(value);
        }
	}

	return Commands.invalid;
}

// returns const so any mutation must be explicitly const casted
pub fn removeNewLines(str: []u8) []const u8 {
	for (str, 0..) |char, index| {
		if (char == '\n') {
			str[index] = ' ';
		}
	}

	return str;
}

/// Returning null means no changes were made
/// Escapes things that may cause issues in json storage format
pub fn escapeStr(str: []const u8, alloc: std.mem.Allocator) !?std.ArrayList(u8) {
	var increaseCount: usize = 0;

	for (str) |char| {
		if (char == '"' or char == '\'' or char == '\\' or char == '\n') {
			increaseCount += 1;
		}
	}

	if (increaseCount == 0) {
		return null;
	}

	var arr = try std.ArrayList(u8).initCapacity(alloc, str.len + increaseCount);
	errdefer arr.deinit();

	for (str) |char| {
		// no escaping ' as json saves using "
		if (char == '"' or char == '\\' or char == '\n') {
			arr.appendAssumeCapacity('\\');
		}
		arr.appendAssumeCapacity(char);
	}

	return arr;
}

// slice returned is one directly to reader buffer, clone if it needs long life
pub fn awaitInput() []u8 {
	std.debug.print("\n>",.{});

	// is blocking: waits until \n is entered into the buffer then executes
	// takeDelimterExclusive does not advance current item pointer
	const input = reader.takeDelimiter('\n') catch |err| {
		std.debug.print("Error when reading input buffer, {}", .{err});
		return "";
	} orelse return "";

	return trimEnd(input);
}

pub fn parseFormat(arg: []u8) ?saveDataEnum {
    for (arg) |*char| {
        char.* = std.ascii.toLower(char.*);
    }

    if (arg.len <= 6 and std.mem.startsWith(u8, arg, "bin")) {
        return .BINARY;
    }

    if (std.mem.eql(u8, arg, "json")) {
        return .JSON;
    }

    return null;
}