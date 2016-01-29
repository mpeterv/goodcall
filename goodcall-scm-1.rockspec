package = "goodcall"
version = "scm-1"
source = {
   url = "git://github.com/mpeterv/goodcall"
}
description = {
   summary = "Error catching and rethrowing utilities for Lua",
   detailed = [[
goodcall is a small library that provides some tools for catching and
rethrowing Lua errors. It supports yielding from protected functions even on
Lua 5.1. The main functions are `goodcall.try_except_else_finally`,
simulating Python's try statement, and `goodcall.rethrow` for rethrowing
errors without losing original stack tracebacks.
]],
   homepage = "https://github.com/mpeterv/goodcall",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1, < 5.4"
}
build = {
   type = "builtin",
   modules = {
      goodcall = "goodcall.lua"
   }
}
