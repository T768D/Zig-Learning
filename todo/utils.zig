const std = @import("std");
const IO = &@import("consts.zig").IO;
const Commands = @import("consts.zig").Commands;


pub fn clearConsole() void {
	// "\x1b[2J" clears the screen and "\x1b[H" moves the cursor to the top-left
	std.Io.File.stdout().writeStreamingAll(IO.*, "\x1b[2J\x1b[H") catch {};
}

pub fn trimEnd(str: []const u8) []const u8 {
	if (str.len == 0)
		return str;

	var strLen = str.len - 1;
	while (str[strLen] == ' ') {
		strLen -= 1;
	}

	return str[0..strLen];
}

pub fn parseCommand(str: []const u8) Commands {
	inline for (std.meta.fields(Commands)) |cmd| {
        if (std.mem.startsWith(u8, str, cmd.name)) {
            return @field(Commands, cmd.name);
        }
	}

	return Commands.invalid;
}

// []const u8 takes in both []const u8 and []u8
pub fn removeNewLines(str: []const u8) []const u8 {
	const mutstr = @constCast(str);

	for (mutstr, 0..) |char, index| {
		if (char == '\n') {
			mutstr[index] = ' ';
		}
	}

	return mutstr;
}