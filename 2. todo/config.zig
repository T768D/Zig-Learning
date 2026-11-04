pub const savedDataEnum = enum {
	JSON,
	BINARY
};

const Config = struct {
    savedDataType: savedDataEnum,
};

pub var config: Config = .{
    .savedDataType = .BINARY,
};