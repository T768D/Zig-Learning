const std = @import("std");
const IO = &@import("consts.zig").IO;


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