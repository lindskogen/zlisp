const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("readline/readline.h");
    @cInclude("readline/history.h");
    @cInclude("string.h");
});

const mpc = @cImport({
    @cInclude("mpc.h");
});

const LispValue = union(enum) {
    num: i64,
    sym: []u8,
    cell: std.ArrayList(LispValue),

    fn deinit(self: LispValue) void {
        switch (self) {
            .cell => |slice| {
                for (slice.items) |item| {
                    std.debug.print("remove: ", .{});
                    // lispvalue_debug(item);
                    std.debug.print("\n", .{});
                    item.deinit();
                }
                slice.deinit();
            },
            else => {},
        }
    }
};

const EvalError = error{ SexpressionNoStartWithSymbol, BuiltinCannotOperateOnNonNumber, BadOperation, DivZero };

fn eval_lispvalue(v: *LispValue) !LispValue {
    return switch (v.*) {
        .cell => eval_sexpr(v),
        else => v.*,
    };
}

fn eval_sexpr(v: *LispValue) EvalError!LispValue {
    switch (v.*) {
        .cell => |*cells| {
            for (0..cells.items.len) |i| {
                v.cell.items[i] = try eval_lispvalue(&v.cell.items[i]);
            }

            if (cells.items.len == 0) {
                return v.*;
            }

            if (cells.items.len == 1) {
                const item = cells.pop() orelse unreachable;
                v.deinit();
                return item;
            }

            const f = cells.orderedRemove(0);
            defer f.deinit();


            switch (f) {
                .sym => |sym| {
                    return builtin_op(v, sym[0]);
                },
                else => {
                    v.deinit();
                    return EvalError.SexpressionNoStartWithSymbol;
                },
            }
        },
        else => unreachable,
    }
}

fn lispvalue_debug(v: LispValue) void {
    switch (v) {
        .num => |num| {
            std.debug.print("{d}", .{num});
        },
        .sym => |sym| {
            std.debug.print("{s}", .{sym});
        },
        .cell => |cells| {
            std.debug.print("(", .{});
            for (cells.items, 0..) |cell, i| {
                lispvalue_debug(cell);
                if (i < cells.items.len - 1) {
                    std.debug.print(" ", .{});
                }
            }
            std.debug.print(")", .{});
        },
    }
}

fn lispvalue_print(writer: anytype, v: LispValue) !void {
    switch (v) {
        .num => |num| {
            try writer.print("{d}", .{num});
        },
        .sym => |sym| {
            try writer.print("{s}", .{sym});
        },
        .cell => |cells| {
            try writer.print("(", .{});
            for (cells.items, 0..) |cell, i| {
                try lispvalue_print(writer, cell);
                if (i < cells.items.len - 1) {
                    try writer.print(" ", .{});
                }
            }
            try writer.print(")", .{});
        },
    }
}

fn builtin_op(a: *LispValue, op: u8) !LispValue {
    defer a.deinit();

    for (a.cell.items) |cell| {
        switch (cell) {
            .num => {},
            else => {
                std.debug.print("error! ", .{});
                lispvalue_debug(a.*);
                return EvalError.BuiltinCannotOperateOnNonNumber;
            },
        }
    }

    var x = a.cell.orderedRemove(0);

    if (op == '-' and a.cell.items.len == 0) {
        x.num = -x.num;
    }

    for (a.cell.items) |y| {
        switch (op) {
            '+' => x.num += y.num,
            '-' => x.num -= y.num,
            '*' => x.num *= y.num,
            '/' => {
                if (y.num == 0) {
                    x.deinit();
                    y.deinit();
                    return EvalError.DivZero;
                }
                x.num = @divTrunc(x.num, y.num);
            },
            else => return EvalError.BadOperation,
        }
    }

    return x;
}

fn lispvalue_read(t: *mpc.mpc_ast_t, alloc: std.mem.Allocator) !LispValue {
    const tag = std.mem.span(t.tag);
    if (std.mem.indexOf(u8, tag, "number")) |_| {
        const v = try std.fmt.parseInt(i64, std.mem.span(t.contents), 10);
        return LispValue{ .num = v };
    }
    if (std.mem.indexOf(u8, tag, "symbol")) |_| {
        return LispValue{ .sym = std.mem.span(t.contents) };
    }
    var list = std.ArrayList(LispValue).init(alloc);
    errdefer list.deinit();

    // sexpr?

    for (0..@intCast(t.children_num)) |i| {
        if (t.children[i].*.contents[0] == '(') {
            continue;
        }
        if (t.children[i].*.contents[0] == ')') {
            continue;
        }
        if (c.strcmp(t.children[i].*.tag, "regex") == 0) {
            continue;
        }
        const v = try lispvalue_read(t.children[i], alloc);
        std.debug.print("append: ", .{});
        lispvalue_debug(v);
        std.debug.print("\n", .{});
        try list.append(v);
    }

    return LispValue{ .cell = list };
}

fn read_and_print(writer: anytype, ast: *mpc.mpc_ast_t, allocator: std.mem.Allocator) !void {
    var result = try lispvalue_read(ast, allocator);
    try lispvalue_print(writer, try eval_lispvalue(&result));
    try writer.print("\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const number = mpc.mpc_new("number");
    const symbol = mpc.mpc_new("symbol");
    const sexpr = mpc.mpc_new("sexpr");
    const expr = mpc.mpc_new("expr");
    const zlisp = mpc.mpc_new("zlisp");

    _ = mpc.mpca_lang(mpc.MPCA_LANG_DEFAULT,
        \\  number   : /-?[0-9]+/ ;
        \\  symbol : '+' | '-' | '*' | '/' ;
        \\  sexpr  : '(' <expr>* ')' ;
        \\  expr     : <number> | <symbol> | <sexpr> ;
        \\  zlisp    : /^/ <expr>+ /$/ ;
    , number, symbol, sexpr, expr, zlisp);
    defer mpc.mpc_cleanup(5, number, symbol, sexpr, expr, zlisp);

    const stdout = std.io.getStdOut().writer();

    try stdout.print("Zlisp Version 0.0.3\n", .{});
    try stdout.print("Press Ctrl+C to Exit\n", .{});

    if (true) {
        const raw_input = c.readline("zlisp> ");
        defer std.c.free(raw_input);

        if (raw_input) |input| {
            _ = c.add_history(input);

            var r: mpc.mpc_result_t = undefined;

            if (mpc.mpc_parse("<stdin>", input, zlisp, &r) != 0) {
                const ast: *mpc.mpc_ast_t = @alignCast(@ptrCast(r.output));
                defer mpc.mpc_ast_delete(ast);

                read_and_print(stdout, ast, allocator) catch |err| switch (err) {
                    EvalError.SexpressionNoStartWithSymbol => try stdout.print("Error: S-Expression Must start with a Symbol!\n", .{}),
                    EvalError.BuiltinCannotOperateOnNonNumber => try stdout.print("Error: Cannot operate on non-number!\n", .{}),
                    EvalError.DivZero => try stdout.print("Error: Division by zero!\n", .{}),
                    // error.InvalidCharacter,
                    //     error.Overflow => try stdout.print("Error: Invalid number!\n", .{}),
                    // error.BadOperation => try stdout.print("Error: Invalid operator!\n", .{}),
                    else => |other_err| return other_err,
                };
            } else {
                const err: *mpc.mpc_err_t = @alignCast(@ptrCast(r.@"error"));
                defer mpc.mpc_err_delete(err);

                mpc.mpc_err_print(err);
            }
        }
    }
}

fn run_test(input: anytype, writer: anytype, allocator: std.mem.Allocator) !void {
    const number = mpc.mpc_new("number");
    const symbol = mpc.mpc_new("symbol");
    const sexpr = mpc.mpc_new("sexpr");
    const expr = mpc.mpc_new("expr");
    const zlisp = mpc.mpc_new("zlisp");

    _ = mpc.mpca_lang(mpc.MPCA_LANG_DEFAULT,
        \\  number   : /-?[0-9]+/ ;
        \\  symbol : '+' | '-' | '*' | '/' ;
        \\  sexpr  : '(' <expr>* ')' ;
        \\  expr     : <number> | <symbol> | <sexpr> ;
        \\  zlisp    : /^/ <expr>+ /$/ ;
    , number, symbol, sexpr, expr, zlisp);
    defer mpc.mpc_cleanup(5, number, symbol, sexpr, expr, zlisp);

    var r: mpc.mpc_result_t = undefined;

    if (mpc.mpc_parse("<stdin>", input, zlisp, &r) != 0) {
        const ast: *mpc.mpc_ast_t = @alignCast(@ptrCast(r.output));
        defer mpc.mpc_ast_delete(ast);

        try read_and_print(writer, ast, allocator);
    } else {
        const err: *mpc.mpc_err_t = @alignCast(@ptrCast(r.@"error"));
        defer mpc.mpc_err_delete(err);

        mpc.mpc_err_print(err);
    }
}

test "+ 1 (* 7 5) 3" {

    const input = "+ 1 (* 7 5) 3";
    var output = std.mem.zeroes([1024]u8);
    var stream = std.io.fixedBufferStream(&output);
    const writer = stream.writer();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    try run_test(input, writer, allocator);


    try std.testing.expectEqualStrings("39\n", stream.getWritten());
}


test "- 100" {

    const input = "- 100";
    var output = std.mem.zeroes([1024]u8);
    var stream = std.io.fixedBufferStream(&output);
    const writer = stream.writer();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    try run_test(input, writer, allocator);


    try std.testing.expectEqualStrings("-100\n", stream.getWritten());
}



test "/" {

    const input = "/";
    var output = std.mem.zeroes([1024]u8);
    var stream = std.io.fixedBufferStream(&output);
    const writer = stream.writer();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    try run_test(input, writer, allocator);


    try std.testing.expectEqualStrings("/\n", stream.getWritten());
}


test "(/ ())" {
    std.debug.print("--- START ---", .{});
    const input = "(/ ())";
    var output = std.mem.zeroes([1024]u8);
    var stream = std.io.fixedBufferStream(&output);
    const writer = stream.writer();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const res = run_test(input, writer, allocator);

    try std.testing.expectEqual(EvalError.BuiltinCannotOperateOnNonNumber, res);
}
