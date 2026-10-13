const std = @import("std");

pub fn main() !void {

	std.debug.print("Enter args\n", .{});
	var ioType = std.Io.Threaded.init_single_threaded;
	defer ioType.deinit();

	const IO = ioType.io();
	const standardInput = std.Io.File.stdin();

	var inputBuffer: [2048]u8 = undefined;
	var reader = standardInput.readerStreaming(IO, &inputBuffer);

	// this waits until \n is streamed into the buffer then executes, is blocking
	const input = try reader.interface.takeDelimiterExclusive('\n');
	var inputEnd: usize = input.len - 1;

	// why is there no reverse iteration??
	while (input[inputEnd] == ' ') {
		inputEnd -= 1;
	}

	const parsingState = enum {
		initial,
		none,
		param,
		// uncertain if next is val or param, check for -
		uncertain,
		value
	};

	var arrayAllocObj = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	defer arrayAllocObj.deinit();

	// allocator for anything that needs to be stored as the parsed output
	// the variables argValue and argParam first own the strings 
	// hashmap is then passed slices
	// both hashmap and arraylists are cleared at the same time when arena allocator is freed
	const outputAlloc = arrayAllocObj.allocator();
	var argsMap = std.StringHashMap([]const u8).init(outputAlloc);
	defer argsMap.deinit();

	var argValue = try std.ArrayList(u8).initCapacity(outputAlloc, 1);
	var argParam = try std.ArrayList(u8).initCapacity(outputAlloc, 1);
    var parseState = parsingState.initial;

    for (0..inputEnd) |x| {
		const char = input[x];

		if (parseState == parsingState.initial and char == '-') {
			parseState = parsingState.param;	
		}

		else if (parseState == parsingState.none) {
			// if parsing state is none and char is not - it just skips checking the rest
			if (char == '-') {
				parseState = parsingState.param;
				try argsMap.put(argParam.items, argValue.items);
				argParam = try std.ArrayList(u8).initCapacity(outputAlloc, 1);
				argValue = try std.ArrayList(u8).initCapacity(outputAlloc, 1);
			}
		}

		else if (parseState == parsingState.param) {
			if (char == ' ') {
				parseState = parsingState.uncertain;
				continue;
			}

			try argParam.append(outputAlloc, char);
		}

		else if (parseState == parsingState.uncertain) {
			if (char == '-') {
				parseState = parsingState.param;
				try argsMap.put(argParam.items, "");
				argParam = try std.ArrayList(u8).initCapacity(outputAlloc, 1);
				argValue = try std.ArrayList(u8).initCapacity(outputAlloc, 1);
			}
			else {
				parseState = parsingState.value;
				try argValue.append(outputAlloc, char);
			}
		}

		else if (parseState == parsingState.value) {
			if (char == ' ') {
				parseState = parsingState.none;
				continue;
			}

			try argValue.append(outputAlloc, char);
		}

    }

	try argsMap.put(argParam.items, argValue.items);

	std.debug.print("---- Hashmap printing ----\n\n", .{});
	var iter = argsMap.iterator();
	while (iter.next()) |item| {
		std.debug.print("{s} : {s}\n", .{item.key_ptr.*, item.value_ptr.*});
	}
}