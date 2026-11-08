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


const Config = struct {
    savedDataType: savedDataEnum,
	backupBeforeSave: backupBeforeSaveEnum,
	deleteBackupIfNoErr: bool,
};

pub var config: Config = .{
    .savedDataType = .BINARY,
	.backupBeforeSave = .OFF,
	.deleteBackupIfNoErr = true
};


// generate names for each config
// for each config enum generate the names of them and store in arr where index is the name
// display array and let user choose index, assinging it to struct

// return type is 2 arrays linked by index, one is name, another is options
// enums here are assumed to have their order the same as their value
// needs less nesting!
// add convert to title case
inline fn getReadable() struct {
	nameArr: []const []const u8,
	valueArr: []const []const []const u8,
} {
	const info = @typeInfo(Config).@"struct";
	const arrayLen = info.field_names.len;
	comptime var nameArr: [arrayLen][]const u8 = undefined;
	comptime var valueArr: [arrayLen][]const []const u8 = undefined;

	inline for (info.field_names, info.field_types, 0..) |nameName, nameType, nameIndex| {
		nameArr[nameIndex] = nameName;

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