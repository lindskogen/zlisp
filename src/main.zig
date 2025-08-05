const std = @import("std");
const c = @cImport({
    @cInclude("readline/readline.h");
    @cInclude("readline/history.h");
    @cInclude("string.h");
});

const mpc = @cImport({
    @cInclude("mpc.h");
});


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

    try stdout.print("Zlisp Version 0.0.1\n", .{});
    try stdout.print("Press Ctrl+C to Exit\n", .{});


    while (true) {
        const raw_input = c.readline("zlisp> ");
        defer std.c.free(raw_input);

        if (raw_input) |input| {
            _ = c.add_history(input);

            var r: mpc.mpc_result_t = undefined;

            if (mpc.mpc_parse("<stdin>", input, zlisp, &r) != 0) {
                defer mpc.mpc_ast_delete(@alignCast(@ptrCast(r.output)));

                mpc.mpc_ast_print(@alignCast(@ptrCast(r.output)));
            } else {
                defer mpc.mpc_err_delete(@alignCast(@ptrCast(r.@"error")));

                mpc.mpc_err_print(@alignCast(@ptrCast(r.@"error")));
            }

        }
    }


}

