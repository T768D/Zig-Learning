pub const savedDataEnum = enum {
	JSON,
	BINARY
};


pub var config: struct {
	savedDataType: savedDataEnum
} = .{
	.savedDataType = savedDataEnum.JSON
};