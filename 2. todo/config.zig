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