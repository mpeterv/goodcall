local goodcall = require "goodcall"

local pack = table.pack or function(...)
   return {n = select("#", ...), ...}
end

describe("pcoxpcall", function()
   it("calls a function", function()
      local called = false
      goodcall.pcoxpcall(function() called = true end)
      assert.is_true(called)
   end)

   it("calls a callable", function()
      local called = false
      local function func() called = true end
      goodcall.pcoxpcall(setmetatable({}, {__call = func}))
      assert.is_true(called)
   end)

   it("passes extra arguments", function()
      local args
      goodcall.pcoxpcall(
         function(...) args = pack(...) end,
         function() end,
         "foo",
         "bar",
         nil,
         nil,
         "baz",
         nil
      )
      assert.same({"foo", "bar", [5] = "baz", n = 6}, args)
   end)

   it("supports yielding from within the function", function()
      local co = coroutine.create(function()
         return goodcall.pcoxpcall(coroutine.yield, function() end, 42)
      end)

      local ok, ret = coroutine.resume(co)
      assert.is_true(ok)
      assert.equal(42, ret)
      local ok2, ret2, ret3 = coroutine.resume(co, 43)
      assert.is_true(ok2)
      assert.is_true(ret2)
      assert.equal(43, ret3)
   end)

   context("on success", function()
      it("returns true", function()
         local ok = goodcall.pcoxpcall(function() end)
         assert.is_true(ok)
      end)

      it("passes back returns of the function", function()
         local rets = pack(goodcall.pcoxpcall(
            function() return 1, nil, 2, nil end)
         )
         assert.same({true, 1, [4] = 2, n = 5}, rets)
      end)

      it("does not call error handler", function()
         local called = false
         goodcall.pcoxpcall(
            function() end,
            function() called = true end
         )
         assert.is_false(called)
      end)
   end)

   context("on error", function()
      it("returns false", function()
         local ok = goodcall.pcoxpcall(error, function() end)
         assert.is_false(ok)
      end)

      it("calls error handling function", function()
         local called = false
         goodcall.pcoxpcall(error, function() called = true end)
         assert.is_true(called)
      end)

      it("calls error handling callable", function()
         local called = false
         local function func() called = true end
         goodcall.pcoxpcall(error, setmetatable({}, {__call = func}))
         assert.is_true(called)
      end)

      it("passes error as the first argument to error handler", function()
         local first_arg
         goodcall.pcoxpcall(error,
            function(err) first_arg = err end, "err!", 0)
         assert.equal("err!", first_arg)
      end)

      it("passes thread and level to error handler for debugging", function()
         local function func2()
            local var = 12345 -- luacheck: no unused
            return var.field
         end

         local function func1()
            local var = 54321 -- luacheck: no unused
            func2()
         end

         local var_value

         local function handler(_, thread, level)
            local index = 1

            while true do
               local name, value

               if thread then
                  name, value = debug.getlocal(thread, level, index)
               else
                  name, value = debug.getlocal(level, index)
               end

               if not name or name == "var" then
                  var_value = value
                  break
               else
                  index = index + 1
               end
            end
         end

         goodcall.pcoxpcall(function()
            func1()
         end, handler)

         assert.equal(12345, var_value)
      end)

      it("passes back returns of the handler", function()
         local rets = pack(goodcall.pcoxpcall(error, function()
            return 1, nil, 2, nil
         end))
         assert.same({false, 1, [4] = 2, n = 5}, rets)
      end)
   end)
end)
