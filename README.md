# zLisp

A naive lisp implementation in zig. Following along https://www.buildyourownlisp.com/


## How to compile

As of writing this README, current version of Zig is 0.14.1.

This project currently depends on readline, so you'll probably need to get that installed by using homebrew (or other package manager of your choice).

You should be good to go, just run the project with `zig build run`.


## Goals

- Learn about interfacing between Zig <-> C.
- Learn about parser combinators.
- Rewrite dependencies with Zig in the future?
