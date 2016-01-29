local goodcall = {_VERSION = "0.0.1"}

local xpcall = xpcall
local running = coroutine.running
local unpack = table.unpack or unpack -- luacheck: read globals unpack
local pack = table.pack or function(...)
   return {n = select("#", ...), ...}
end
local function noop() end

-- At the lowest level there is goodcall.pcoxpcall
-- (meaning portable coroutine-safe extended protected call, obviously),
-- which calls a function or callable object in protected mode,
-- passing provided arguments.
-- If no error occurs, returns true plus values returned by the function.
-- If it throws an error, calls error handler with three arguments:
-- the error plus thread (optional) and level that can be passed
-- to debug.* functions, such as debug.traceback, to get more context.
-- The protected function may be wrapped in a coroutine, in which case
-- debugging can't get information on functions lower in the stack.
-- pcoxpcall then returns false plus values returned by the handler.
-- On Lua 5.1 pcoxpcall has to use coroutine magic a-la coxpcall, and
-- goodcall.coroutine_magic is true. goodcall.running returns true parent
-- coroutine for its argument or current coroutine.

-- Implementation of pcoxpcall used when xpcall is already coroutine-safe.

local xpcall_supports_extra_args = xpcall(assert, noop, true)

local function handle_xpcall_returns(ok, ...)
   if ok then
      return true, ...
   else
      local handler_returns = ... -- TODO: handle error in error handling.
      return false, unpack(handler_returns, 1, handler_returns.n)
   end
end

local function native_pcoxpcall(callable, handler, ...)
   if not xpcall_supports_extra_args then
      local nargs = select("#", ...)

      if nargs > 0 then
         local original_callable = callable
         local args = {...}
         function callable()
            return original_callable(unpack(args, 1, nargs))
         end
      end
   end

   -- xpcall only returns the first return value of the error handler,
   -- pack them.
   local function wrapped_handler(err)
      return pack(handler(err, nil, 3))
   end

   return handle_xpcall_returns(xpcall(callable, wrapped_handler, ...))
end

-- pcoxpcall using a coroutine wrapper and coroutine.resume.

local parents = setmetatable({}, {__mode = "k"})

local function co_running(co)
   if co == nil then
      co = running()
   end

   while parents[co] do
      co = parents[co]
   end

   return co
end

local function handle_resume_returns(co, handler, ok, ...)
   if ok then
      if coroutine.status(co) == "suspended" then
         -- The coroutine yielded; act as a proxy between it
         -- and parent coroutine.
         -- TODO: see if additional handling is needed when
         -- there is no parent.
         return handle_resume_returns(co, handler,
            coroutine.resume(co, coroutine.yield(...)))
      else
         -- The coroutine returned.
         return true, ...
      end
   else
      -- TODO: call handler in protected mode?
      return false, handler(..., co, 0)
   end
end

local function co_pcoxpcall(callable, handler, ...)
   -- coroutine.create may expect a Lua function, rejecting
   -- callable objects and C functions.
   -- TODO: ensure that callable is actually callable,
   -- same for native version.
   local ok, co = pcall(coroutine.create, callable)

   if not ok then
      co = coroutine.create(function(...) return callable(...) end)
   end

   parents[co] = coroutine.running()
   return handle_resume_returns(co, handler, coroutine.resume(co, ...))
end

-- Select which version to use.

local xpcall_is_coroutine_safe
local test_coroutine = coroutine.create(function()
   return xpcall(coroutine.yield, noop)
end)

coroutine.resume(test_coroutine)
-- If xpcall is not coroutine friendly, it immediately returns
-- and the coroutine is dead.
xpcall_is_coroutine_safe = coroutine.resume(test_coroutine)

if xpcall_is_coroutine_safe then
   goodcall.pcoxpcall = native_pcoxpcall
   goodcall.coroutine_magic = false
   goodcall.running = running
else
   goodcall.pcoxpcall = co_pcoxpcall
   goodcall.coroutine_magic = true
   goodcall.running = co_running
end

-- This section implements catching and rethrowing mechanisms:
-- goodcall.try, goodcall.rethrow and goodcall.rethrow_string.
-- goodcall.try is a version of pcall that additionally returns stack
-- traceback on error. It also unwraps errors thrown with goodcall.rethrow.
-- goodcall.rethrow takes an error and a traceback and throws a wrapper
-- object. It turns into concatenation of them when tostring is applied,
-- and has same effect as original error when caught by goodcall.try.
-- There are also some lower-level functions for dealing with wrapped errors:
-- goodcall.is_wrapped, goodcall.wrap, goodcall.unwrap, goodcall.to_string.

function goodcall.to_string(err, traceback)
   err = tostring(err)

   if err:sub(-1) == "\n" then
      return err .. traceback
   else
      return err .. "\n" .. traceback
   end
end

local wrapper_mt = {}

function wrapper_mt:__tostring()
   return goodcall.to_string(self[1], self[2])
end

function wrapper_mt:__concat(other)
   return tostring(self) .. tostring(other)
end

function goodcall.is_wrapped(err)
   return rawequal(debug.getmetatable(err), wrapper_mt)
end

function goodcall.wrap(err, traceback)
   return setmetatable({err, traceback}, wrapper_mt)
end

function goodcall.unwrap(wrapper)
   return wrapper[1], wrapper[2]
end

local function error_handler(err, co, level)
   local traceback

   if goodcall.is_wrapped(err) then
      err, traceback = goodcall.unwrap(err)
   else
      if co then
         traceback = debug.traceback(co, "", level)
      else
         traceback = debug.traceback("", level)
      end

      traceback = traceback:sub(2)
   end

   if co then
      local lower_traceback = debug.traceback("", 3)
      traceback = traceback .. lower_traceback:gsub("\n.-\n", "\n", 1)
   end

   return err, traceback
end

function goodcall.try(callable, ...)
   return goodcall.pcoxpcall(callable, error_handler, ...)
end

function goodcall.rethrow(err, traceback)
   return error(goodcall.wrap(err, traceback))
end

-- This section implements Lua equivalent of Python's try statement.
-- The main function is goodcall.try_except_else_finally, which takes
-- four callables - try block, except block, else block, and finally block,
-- plus extra arguments passed to try and finally blocks. All blocks except
-- the first one are optional and can be replaced with nil.
-- goodcall.try_except_else_finally runs as follows: first, try block is
-- executed. If there is an error, except block is called with error +
-- traceback; otherwise, else block is called with return values from
-- try block. Finally block is always executed last.
-- try_except_else_finally returns whatever the last executed block returned,
-- excluding finally block.
-- There are also several shortcuts useful when some blocks are missing:
-- goodcall.try_except, goodcall.try_else_finally, and so on.

local function handle_try_returns_with_finally(args, finally, ok, ...)
    -- TODO: what to do if both handler and finally blocks error?
   if finally ~= nil then
      finally(unpack(args))
   end

   if ok then
      return ...
   else
      goodcall.rethrow(...)
   end
end

local function handle_main_try_returns(args, except, else_, finally, ok, ...)
   -- Select handler block to be executed based on success flag of try block.
   local handler

   if ok then
      handler = else_
   else
      handler = except
   end

   if handler ~= nil then
      if finally ~= nil then
         -- Need to run handler block in protected mode so that
         -- potential error can be rethrown after finally block is executed.
         return handle_try_returns_with_finally(args, finally,
            goodcall.try(handler, ...))
      else
         -- No finally block, just call the handler.
         return handler(...)
      end
   else
      return handle_try_returns_with_finally(args, finally, ok, ...)
   end
end

function goodcall.try_except_else_finally(try, except, else_, finally, ...)
   local args = pack(...)
   return handle_main_try_returns(args, except, else_, finally,
      goodcall.try(try, ...))
end

function goodcall.try_except(try, except, ...)
   return goodcall.try_except_else_finally(try, except, nil, nil, ...)
end

function goodcall.try_else(try, else_, ...)
   return goodcall.try_except_else_finally(try, nil, else_, nil, ...)
end

function goodcall.try_finally(try, finally, ...)
   return goodcall.try_except_else_finally(try, nil, nil, finally, ...)
end

function goodcall.try_except_else(try, except, else_, ...)
   return goodcall.try_except_else_finally(try, except, else_, nil, ...)
end

function goodcall.try_except_finally(try, except, finally, ...)
   return goodcall.try_except_else_finally(try, except, nil, finally, ...)
end

function goodcall.try_else_finally(try, else_, finally, ...)
   return goodcall.try_except_else_finally(try, nil, else_, finally, ...)
end

return goodcall
