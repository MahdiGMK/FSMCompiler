const std = @import("std");
const clap = @import("clap");
const debug = std.debug;
const io = std.io;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-i, --input <str>              Source file
        \\-o, --output <str>           Output file
        \\-h, --help         Display this help and exit.
        \\
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = arena.allocator(),
    }) catch |err| {
        // Report useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    const source_filename: []const u8 = (res.args.input) orelse return error.NoInputFile;

    const output_filename = (res.args.output) orelse val: {
        const addr = try arena.allocator().alloc(u8, source_filename.len + 2);
        @memcpy(addr[0..source_filename.len], source_filename);
        addr[addr.len - 2] = '.';
        addr[addr.len - 1] = 'c';
        break :val addr;
    };
    debug.print("{s}", .{output_filename});
    const source = std.fs.cwd().readFileAlloc(arena.allocator(), source_filename, std.math.maxInt(usize)) catch |e| {
        debug.print("unable to read source code \"{s}\"\n", .{source_filename});
        return e;
    };
    var root_node = parse(source, arena.allocator()) catch |e| {
        debug.print("syntax error\n", .{});
        return e;
    };
    const output_file = try std.fs.cwd().createFile(output_filename, std.fs.File.CreateFlags{});
    root_node.matchTransitions() catch |e| {
        debug.print("semantic error\n", .{});
        return e;
    };
    // root_node.print(0);
    try root_node.compile(output_file.writer(), arena.allocator());
}

const ASTNodeId = usize;
const ASTTransition = struct { event: []const u8, next_state: []const u8, next_state_id: ASTNodeId };
const ASTNode = struct {
    var cntr: ASTNodeId = 0;
    id: ASTNodeId,
    name: []const u8,
    children: std.ArrayList(ASTNode),
    transitions: std.ArrayList(ASTTransition),
    const Self = @This();
    fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        Self.cntr += 1;
        return Self{ .id = Self.cntr, .name = name, .children = std.ArrayList(ASTNode).init(allocator), .transitions = std.ArrayList(ASTTransition).init(allocator) };
    }
    fn fixind(indlvl: u8) void {
        for (0..indlvl) |_| {
            debug.print("    ", .{});
        }
    }
    fn print(self: *const Self, indlvl: u8) void {
        fixind(indlvl);
        debug.print("{s}({d})  {c}\n", .{ self.name, self.id, '{' });
        for (self.transitions.items) |tran| {
            fixind(indlvl + 1);
            debug.print("{s} -> {s}({})\n", .{ tran.event, tran.next_state, tran.next_state_id });
        }
        debug.print("\n", .{});
        for (self.children.items) |chld| {
            chld.print(indlvl + 1);
        }
        fixind(indlvl);
        debug.print("{c}\n", .{'}'});
    }

    fn matchTransitions(self: *Self) !void {
        for (self.transitions.items) |*trans| {
            if (trans.next_state_id > 0) break;
            trans.next_state_id = val: {
                for (self.children.items) |chld| {
                    if (std.mem.eql(u8, chld.name, trans.next_state[1..])) {
                        break :val chld.id;
                    }
                }
                return error.Invalid;
            };
        }
        for (self.children.items) |*child| {
            for (child.transitions.items) |*trans| {
                trans.next_state_id = val: {
                    for (if (trans.next_state[0] == '.')
                        child.children.items
                    else
                        self.children.items) |chld|
                    {
                        if (std.mem.eql(u8, chld.name, trans.next_state[@intFromBool(trans.next_state[0] == '.')..])) {
                            break :val chld.id;
                        }
                    }
                    return error.Invalid;
                };
            }
            try child.matchTransitions();
        }
    }

    fn compile(self: *const Self, writer: anytype, allocator: std.mem.Allocator) !void {
        _ = try writer.write(
            \\#include<string.h>
            \\int main() {
            \\    unsigned long state = 1;
            \\    char evt[256] = "_";
            \\    while(1) {
            \\    unsigned long nstate = state;
            \\        switch(state) {
            \\
        );
        var sname_prefix = std.ArrayList(u8).init(allocator);
        var par_transitions = std.ArrayList(ASTTransition).init(allocator);
        try self.compile_states(writer, &sname_prefix, &par_transitions);
        _ = try writer.write(
            \\        }
            \\        state = nstate;
            \\    }
            \\}
            \\
        );
    }
    fn compile_states(self: *const Self, writer: anytype, sname_prefix: *std.ArrayList(u8), par_transitions: *std.ArrayList(ASTTransition)) !void {
        _ = try std.fmt.format(writer,
            \\            case {}: {c}
            \\                {s}{s}_reaction();
            \\
        , .{ self.id, '{', sname_prefix.items, self.name });
        // write transitions

        for (par_transitions.items) |trans| {
            _ = try std.fmt.format(writer,
                \\                if(strcmp(evt, "{s}") == 0) nstate = {};
                \\
            , .{ trans.event, trans.next_state_id });
        }
        var added_transitions: usize = 0;
        for (self.transitions.items) |trans| {
            if (!std.mem.eql(u8, trans.event, "_")) {
                _ = try std.fmt.format(writer,
                    \\                if(strcmp(evt, "{s}") == 0) nstate = {};
                    \\
                , .{ trans.event, trans.next_state_id });
                try par_transitions.append(trans);
                added_transitions += 1;
            } else {
                _ = try std.fmt.format(writer,
                    \\                nstate = {};
                    \\
                , .{trans.next_state_id});
            }
        }
        _ = try writer.write(
            \\            } break;
            \\
        );
        try sname_prefix.appendSlice(self.name);
        try sname_prefix.appendSlice("__");
        for (self.children.items) |child| {
            try child.compile_states(writer, sname_prefix, par_transitions);
        }
        par_transitions.items.len -= added_transitions;
        sname_prefix.items.len -= self.name.len + 2;
    }
};

fn parse(code: []const u8, arena: std.mem.Allocator) (error{Invalid} || std.mem.Allocator.Error)!ASTNode {
    var root_node = ASTNode.init(arena, "root");
    var node_stack = std.ArrayList(*ASTNode).init(arena);
    try node_stack.append(&root_node);
    var ind: usize = 0;
    while (ind < code.len) : (ind += 1) {
        if (std.ascii.isWhitespace(code[ind])) continue;
        if (code[ind] == '.') {
            // .state_name {
            ind += 1;
            var last = ind;
            while (last < code.len) : (last += 1) {
                if (std.ascii.isWhitespace(code[last]) or code[last] == '{') break;
            }
            const sname = code[ind..last];
            ind = last;
            while (ind < code.len) : (ind += 1) {
                if (std.ascii.isWhitespace(code[ind])) continue;
                if (code[ind] == '{') break;
                return error.Invalid;
            }
            const par = node_stack.getLast();
            try par.children.append(ASTNode.init(arena, sname));
            try node_stack.append(&par.children.items[par.children.items.len - 1]);
            continue;
        }
        if (code[ind] == '}') {
            // }
            _ = node_stack.pop();
            if (node_stack.items.len == 0) return error.Invalid;
            continue;
        }
        // event_name => state_name;
        var last = ind;
        while (last < code.len) : (last += 1) {
            if (std.ascii.isWhitespace(code[last])) break;
        }
        const ename = code[ind..last];
        ind = last;
        while (ind < code.len) : (ind += 1) {
            if (!std.ascii.isWhitespace(code[ind])) break;
        }
        if (code[ind] != '=' or code[ind + 1] != '>') return error.Invalid;
        ind += 2;
        while (ind < code.len) : (ind += 1) {
            if (!std.ascii.isWhitespace(code[ind])) break;
        }
        last = ind;
        while (last < code.len) : (last += 1) {
            if (std.ascii.isWhitespace(code[last]) or code[last] == ';') break;
        }
        const sname = code[ind..last];
        ind = last;
        while (ind < code.len) : (ind += 1) {
            if (std.ascii.isWhitespace(code[ind])) continue;
            if (code[ind] == ';') break;
            return error.Invalid;
        }
        try node_stack.getLast().transitions.append(ASTTransition{ .event = ename, .next_state = sname, .next_state_id = 0 });
    }
    if (node_stack.items.len != 1) return error.Invalid;
    return root_node;
}
