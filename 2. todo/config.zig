const generalHeapAlloc = @import("alloc.zig").generalHeapAlloc;
const std = @import("std");


pub const savedDataEnum = enum {
	JSON,
	BINARY
};

const backupBeforeSaveEnum = enum {
	OFF,
	JSON,
	BINARY,
	ALL
};

pub const Config = struct {
    savedDataType: savedDataEnum,
	backupBeforeSave: backupBeforeSaveEnum,
	deleteBackupIfNoErr: bool,
	printExitMsg: bool,
	printTitleMsg: bool
};

pub var config: Config = .{
    .savedDataType = .BINARY,
	.backupBeforeSave = .OFF,
	.deleteBackupIfNoErr = true,
	.printExitMsg = true,
	.printTitleMsg = true,
};

pub fn mutateFieldFromIndex(index: usize, value: usize) void {
    switch (index) {
        0 => config.savedDataType = @fromBackingInt(@intCast(value)),
        1 => config.backupBeforeSave = @fromBackingInt(@intCast(value)),
        2 => config.deleteBackupIfNoErr = (value == 0), // true comes first
		3 => config.printExitMsg = (value == 0),
		4 => config.printTitleMsg = (value == 0),
        else => @panic("Invalid struct index"),
    }
}


// needs less nesting!
// add convert to title case

// Compile time function that gets the names and names of the values of the configs and returns them
// Array index correlates names and values
// a hashmap is probably a better choice but comptime sounds interesting
inline fn getReadable() struct {
	nameArr: []const []const u8,
	valueArr: []const []const []const u8,
} {
	const info = @typeInfo(Config).@"struct";
	const arrayLen = info.field_names.len;
	comptime var nameArr: [arrayLen][]const u8 = undefined;
	comptime var valueArr: [arrayLen][]const []const u8 = undefined;

	inline for (info.field_names, info.field_types, 0..) |nameName, nameType, nameIndex| {
		nameArr[nameIndex] = comptime makeTitleCase(nameName);

		switch (@typeInfo(nameType)) {
			
			.@"enum" => |enumInfo| {
				const enumLen = enumInfo.field_names.len;
				comptime var currentEnumArr: [enumLen][]const u8 = undefined;

				inline for (enumInfo.field_names, enumInfo.field_values, 0..) |enumName, enumValue, enumIndex| {
					currentEnumArr[enumIndex] = enumName;
					if (enumValue != enumIndex) {
						@compileError("The index of a enum item is not equal to the value of the enum item!");
					}
				}

				const nonComptimeEnumArr = currentEnumArr;
				valueArr[nameIndex] = &nonComptimeEnumArr;
			},

			.@"bool" => {
				valueArr[nameIndex] = &[_][]const u8{"True", "False"};
			},

			else => unreachable
		}
	}

	const nonComptimeNameArr = nameArr;
	const nonComptimeValueArr = valueArr;

	return .{
		.nameArr = &nonComptimeNameArr,
		.valueArr = &nonComptimeValueArr,
	};
}

pub const configHumanReadable = getReadable();


pub inline fn makeTitleCase(comptime str: []const u8) []const u8 {
	comptime var count = str.len;

	for (str) |char| {
		if (char > 'A' and char < 'Z') {
			count += 1;
		}
	}

	if (count == 0) {
		return str;
	}

	comptime var buf: [count]u8 = undefined;
	comptime var x = 0;
	for (str) |char| {
		if (char > 'A' and char < 'Z') {
			buf[x] = ' ';
			x += 1;
		}
		buf[x] = char;
		x += 1;
	}

	buf[0] = comptime std.ascii.toUpper(buf[0]);
	const nonComptimeStr = buf;
	return nonComptimeStr[0..];
}