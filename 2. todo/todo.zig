const std = @import("std");
const generalHeapAlloc = @import("alloc.zig").generalHeapAlloc;

const utils = @import("utils.zig");
const parseCommand = utils.parseCommand;
const clearConsole = utils.clearConsole;
const trimEnd = utils.trimEnd;
const escapeStr = utils.escapeStr;
const awaitInput = utils.awaitInput;

// keep IO under consts because would need to convert out of pointer anyways, not much typing saved
const consts = @import("consts.zig");
const FileStructure = consts.FileStructure;
const savedData = &consts.savedData;
const Config = @import("config.zig");

var searchTrie: @import("trie.zig").TrieClass = undefined;
var trieInitialised = false;
const initTrie = @import("trie.zig").init;

const readSaved = @import("storage.zig").readSaved;
const writeSaved = @import("storage.zig").writeSaved;


pub fn main() !void {
	consts.init();
	searchTrie = initTrie(generalHeapAlloc);

	// cant be moved up or else therell be a random segfault
	clearConsole();
	try readSaved();

	while (true) {
		try parseInput(awaitInput());
	}
}


fn sortAssitPointer(_: void, A: *FileStructure, B: *FileStructure) bool {
	return A.priority > B.priority;
}

fn parseInput(str: []u8) !void {
	clearConsole();

	sw: switch (parseCommand(str)) {

	.add => {
		const appendingData = try savedData.allocator.create(FileStructure);

		std.debug.print("Input the title", .{});
		// needs escaping because of json format saving
		// if implemented non json format then no need to escape
		const title = escapeStr(awaitInput());
		appendingData.title = try savedData.allocator.dupe(u8, title);

		while (true) {
			std.debug.print("Input the priority level", .{});
			const priority = awaitInput();

			// could be done simpler
			const convertedInt = std.fmt.parseInt(u8, priority, 10) catch {
				std.debug.print("Input is not a number or is too big!\n", .{});
				continue;
			};

			// u8 is copied
			appendingData.priority = convertedInt;
			break;
		}

		std.debug.print("Input notes", .{});
		const notes = awaitInput();
		appendingData.notes = try savedData.allocator.dupe(u8, notes);

		try savedData.put(appendingData.title, appendingData);
		try searchTrie.add(appendingData);
	},


	.delete, .remove => {
		var title: []const u8 = undefined;
		
		// delete and remove are the same len, so if command only has that then ask for name
		// otherwise assume name passed as arg
		if (str.len <= 6) {
			std.debug.print("Input title", .{});
			title = awaitInput();
		}
		else {
			title = str[7..str.len];
		}

		const val = savedData.get(title) orelse {
			std.debug.print("No todo with the name {s} exists", .{title});
			return;
		};
		// already checked if exists before
		// must remove BEFORE destryoing title
		_ = savedData.remove(title);
		// title is val.title so it is destroyed when val.title is
		savedData.allocator.free(val.title);
		savedData.allocator.free(val.notes);
		savedData.allocator.destroy(val);

		std.debug.print("Removed {s} from the todo",.{title});
	},


	.list => {
		var iter = savedData.valueIterator();
		var order = try std.ArrayList(*FileStructure).initCapacity(generalHeapAlloc, iter.len);
		defer order.deinit(generalHeapAlloc);

		while (iter.next()) |item| {
			try order.append(generalHeapAlloc, item.*);
		}

		std.mem.sort(*FileStructure,order.items,{}, sortAssitPointer);

		for (order.items) |item| {
			std.debug.print("{d}  {s}\n{s}\n\n", .{item.priority, item.title, item.notes});
		}
	},


	// simplify and clean up later
	.config => {
		std.debug.print("Choose a config to change:", .{});
		inline for (Config.configHumanReadable.nameArr, @typeInfo(Config.Config).@"struct".field_names, 0..,) |display_name, field_name, index| {
			std.debug.print("\n{d}: {s}: {any}", .{index, display_name, @field(Config.config, field_name)});
		}

		const input = awaitInput();
		if (
			input.len > 2 or
			input[0] < '0' or
			input[0] > '9' or
			(input.len == 2 and (input[1] < '0' or input[1] > '9'))
		) {
			clearConsole();
			std.debug.print("Invalid input!", .{});
			break :sw;
		}

		const num = if (input.len == 1) input[0] - '0' else (input[0] - '0') * 10 + (input[1] - '0');
		if (num >= Config.configHumanReadable.nameArr.len) {
			std.debug.print("Number is too large", .{});
			break :sw;
		}


		clearConsole();
		std.debug.print("Modifying: {s}\n", .{Config.configHumanReadable.nameArr[num]});
		for (Config.configHumanReadable.valueArr[num], 0..) |nameItem, index| {
			std.debug.print("\n{d}: {s}", .{index, nameItem});
		}


		const input2 = awaitInput();
		if (
			input2.len > 2 or
			input2[0] < '0' or
			input2[0] > '9' or
			(input2.len == 2 and (input2[1] < '0' or input2[1] > '9'))
		) {
			clearConsole();
			std.debug.print("Invalid input!", .{});
			break :sw;
		}

		const num2 = if (input2.len == 1) input2[0] - '0' else (input2[0] - '0') * 10 + (input2[1] - '0');
		if (num2 >= Config.configHumanReadable.valueArr[num].len) {
			std.debug.print("Number is too large", .{});
			break :sw;
		}

		Config.mutateFieldFromIndex(num, num2);
		// improve message
		std.debug.print("Assigned {s}", .{Config.configHumanReadable.valueArr[num][num2]});
	},


	.search => {
		if (!trieInitialised) {
			var iter = savedData.valueIterator();
			while (iter.next()) |item| {
				try searchTrie.add(item.*);
			}
			trieInitialised = true;
		}

		std.debug.print("Enter title to search for", .{});
		const searchItem = awaitInput();

		var tempAlloc = std.heap.ArenaAllocator.init(generalHeapAlloc);
		defer tempAlloc.deinit();
		const searchAlloc = tempAlloc.allocator();

		const searchResult = searchTrie.search(searchItem, searchAlloc) catch |err| {
			std.debug.print("Unable to search through trie\n {}", .{err});
			break :sw;
		};

		if (searchResult == null) {
			std.debug.print("No matching items", .{});
			break :sw;
		}

		std.mem.sort(*FileStructure,searchResult.?.items,{}, sortAssitPointer);

		for (searchResult.?.items) |item| {
			std.debug.print("\n{d}  {s}\n{s}\n\n", .{item.priority, item.title, item.notes});
		}
	},


	.help => {
		const info = @typeInfo(consts.Commands).@"enum";
		inline for (info.field_names, info.field_values) |name, value| {
			const convertedValue: consts.Commands = @fromBackingInt(value);
			std.debug.print("{s}: {s}\n", .{name, convertedValue.describe()});
		}
	},

	.exit, .cls => {
		clearConsole();
		std.process.exit(0);
	},

	.save => {
		if (str.len <= 4) {
			writeSaved(null);
			return;
		}

		// 4 chars for save and 1 for space
		var arg = str[5..];
		for (arg, 0..) |char, x| {
			arg[x] = std.ascii.toLower(char);
		}

		std.debug.print("arg, '{s}'", .{arg});

		// binary length is 6 lens
		if (arg.len <= 6 and std.mem.startsWith(u8, arg, "bin")) {
			writeSaved(.BINARY);
		}
		else if (std.mem.eql(u8, arg, "json")) {
			writeSaved(.JSON);
		}
	},

	// switch will return Commands.invalid for a invalid command, so i dont have to make a union so its less verbose
	.invalid => std.debug.print("Invalid input", .{}),

	}
}