# goodcall

[![Build Status](https://travis-ci.org/mpeterv/goodcall.svg?branch=master)](https://travis-ci.org/mpeterv/goodcall)

```bash
$ cat test.lua
```

```lua
local goodcall = require "goodcall"

local function read_file(name)
   local file
   return goodcall.try_finally(function()
      file = assert(io.open(name))
      return assert(file:read("*a"))
   end, function()
      print("Finally block is executed even when an error happens.")
      if file then file:close() end
   end)
end

local function main()
   print(read_file("non-existent-file.lua"))
end

goodcall.try_except(main, function(err, trace)
   io.stderr:write("Error: ", err, "\n")
   io.stderr:write(trace, "\n")
end)
```

```bash
$ lua test.lua
```

```
Finally block is executed even when an error happens.
Error: test.lua:6: non-existent-file.lua: No such file or directory
stack traceback:
   [C]: in function 'assert'
   test.lua:6: in function <test.lua:5>
   [C]: in function 'xpcall'
   ./goodcall.lua:58: in function 'goodcall.pcoxpcall'
   (...tail calls...)
   ./goodcall.lua:261: in function 'goodcall.try_except_else_finally'
   (...tail calls...)
   test.lua:15: in function <test.lua:14>
   [C]: in function 'xpcall'
   ./goodcall.lua:58: in function 'goodcall.pcoxpcall'
   (...tail calls...)
   ./goodcall.lua:261: in function 'goodcall.try_except_else_finally'
   (...tail calls...)
   test.lua:18: in main chunk
   [C]: in ?
```
