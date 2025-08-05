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


fn eval_op(x: i64, op: u8, y: i64) i64 {
    return switch (op) {
        '+' => x + y,
        '-' => x - y,
        '*' => x * y,
        '/' => @divTrunc(x, y),
        else => 0,
    };
}

fn eval(t: *mpc.mpc_ast_t) i64 {
    if (c.strstr(t.tag, "number") != 0) {
        return c.atoi(t.contents);
    }

    const op = t.children[1].*.contents;

    var x = eval(t.children[2]);

    var i: u64 = 3;

    while (c.strstr(t.children[i].*.tag, "expr") != 0) {
        x = eval_op(x, op[0], eval(t.children[i]));
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

                const result = eval(ast);
                
                try stdout.print("{d}\n", .{ result });
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
