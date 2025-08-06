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
};

fn lispvalue_print(writer: anytype, v: LispValue) !void {
    switch (v) {
        .num => |num| {
            try writer.print("{d}\n", .{ num });
        }
    }
}

fn eval_op(x: LispValue, op: u8, y: LispValue) !LispValue {
    return switch (op) {
        '+' => LispValue{ .num = x.num + y.num },
        '-' => LispValue{ .num = x.num - y.num },
        '*' => LispValue{ .num = x.num * y.num },
        '/' => {
            if (y.num == 0) {
                return error.DivZero;
            }
            return LispValue{ .num = @divTrunc(x.num, y.num) };
        },
        else => error.BadOperation,
    };
}

fn eval(t: *mpc.mpc_ast_t) !LispValue {
    if (c.strstr(t.tag, "number") != 0) {
        const v = try std.fmt.parseInt(i64, std.mem.span(t.contents), 10);
        return LispValue{ .num = v };
    }

    const op = t.children[1].*.contents;

    var x = try eval(t.children[2]);

    var i: u64 = 3;

    while (c.strstr(t.children[i].*.tag, "expr") != 0) {
        x = try eval_op(x, op[0], try eval(t.children[i]));
        i += 1;
    }

    return x;
}

pub fn main() !void {
    const number = mpc.mpc_new("number");
    const operator = mpc.mpc_new("operator");
    const expr = mpc.mpc_new("expr");
    const zlisp = mpc.mpc_new("zlisp");

    _ = mpc.mpca_lang(mpc.MPCA_LANG_DEFAULT,
        \\  number   : /-?[0-9]+/ ;
        \\  operator : '+' | '-' | '*' | '/' ;
        \\  expr     : <number> | '(' <operator> <expr>+ ')' ;
        \\  zlisp    : /^/ <operator> <expr>+ /$/ ;
    , number, operator, expr, zlisp);
    defer mpc.mpc_cleanup(4, number, operator, expr, zlisp);

    const stdout = std.io.getStdOut().writer();

    try stdout.print("Zlisp Version 0.0.3\n", .{});
    try stdout.print("Press Ctrl+C to Exit\n", .{});

    while (true) {
        const raw_input = c.readline("zlisp> ");
        defer std.c.free(raw_input);

        if (raw_input) |input| {
            _ = c.add_history(input);

            var r: mpc.mpc_result_t = undefined;

            if (mpc.mpc_parse("<stdin>", input, zlisp, &r) != 0) {
                const ast: *mpc.mpc_ast_t = @alignCast(@ptrCast(r.output));
                defer mpc.mpc_ast_delete(ast);

                if (eval(ast)) |result| {
                    try lispvalue_print(stdout, result);
                } else |err| switch (err) {
                    error.DivZero => try stdout.print("Error: Division by zero!\n", .{}),
                    error.InvalidCharacter,
                        error.Overflow => try stdout.print("Error: Invalid number!\n", .{}),
                    error.BadOperation => try stdout.print("Error: Invalid operator!\n", .{}),
                    else => |other_err| return other_err
                }


            } else {
                const err: *mpc.mpc_err_t = @alignCast(@ptrCast(r.@"error"));
                defer mpc.mpc_err_delete(err);

                mpc.mpc_err_print(err);
            }
        }
    }
}

// test "+ 1 2" {
//
// }
