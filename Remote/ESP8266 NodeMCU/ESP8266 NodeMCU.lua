
--**************************************************************************$
--* Copyright (C) 2013-2018 Ing. Buero Riesberg - All Rights Reserved
--* Unauthorized copy, print, modify or use of this file, via any medium is
--* strictly prohibited. Proprietary and confidential.
--* Written by Andre Riesberg <andre@riesberg-net.de>
--***************************************************************************/

target = {
  name = 'ESP8266 NodeMCU',

  parameter = {
    com = 4,
    baud = 115200,
    powerupStart = false,
  },

  init = function(self)
  end,

  open = function(self)
    gui.add('HTMLInfo', 'Info', self.name, [[
<b>NodeMCU with ESP8266 running eLua</b><br><br>
Use then <a href="https://nodemcu-build.com/">https://nodemcu-build.com/</a> to build a P+ compatible firmware.<br>
Setup minimum the modules: file, GPIO, net, node timer, UART and WiFi.<br><br>
You can also use the <i>modemcu-master-7-modules-2018-03-06-06-04-14-float.bin</i> from the <i>\Resorces\Remote\ESP8266 NodeMCU</i><br>
folder inside the P+ folder. There are also links to Firmware Flash Tool.<br><br>
Note: Some other firmware builds use different baudrates!<br>
]], {Height = 180})
    gui.add('Edit', 'EditCOM', 'COM port number', {IntegerMode = true})
    gui.add('Edit', 'EditBaud', 'Baud rate', {IntegerMode = true})
    gui.add('CheckBox', 'CheckBoxPowerupStart', 'Start model on power up', {Width = 200})
    gui.set('EditCOM', 'Integer', self.parameter.com)
    gui.set('EditBaud', 'Integer', self.parameter.baud)
    gui.set('CheckBoxPowerupStart', 'Checked', self.parameter.powerupStart)
    gui.add('HTMLLabel', 'HTMLLabel1', [[
<b>Note:</b><br>Don't set this option during development!<br>
If this option is set you have only a timeslot of <b>5</b> seconds after<br>
manual reset too upload a new applicatin.
    ]], {Left = 150, Width = 400, Height = 80})
  end,

  apply = function(self)
    self.parameter.com = gui.get('EditCOM', 'Integer')
    self.parameter.baud = gui.get('EditBaud', 'Integer')
    self.parameter.powerupStart = gui.get('CheckBoxPowerupStart', 'Checked')
  end,

  close = function(self)
  end,

  generate = function(self, what)
--    if what == 'GENERATOR_REQUIRE' then
--      return [[
--token = {set = function() end, get = function() end}
--      ]]
--    end
    if what == 'GENERATOR_MAIN' then
      return [[
do
  tmr.create():alarm(
    sim.stepRateS * 1000,
    tmr.ALARM_AUTO,
    function()
      block.step()
      collectgarbage()
      sim.step = sim.step + 1
      sim.stepT0 = sim.stepT0 + 1
      sim.timeS = sim.timeS + sim.stepRateS
    end
  )
end
      ]]
    end
  end,

  inject = function(self, files)
    local sys = require 'sys'
    local token = require 'token'
    local serial = require 'serial'

    sys.debug('Injector start')

    local esp = serial.new(self.parameter.com)
    esp:open(self.parameter.baud, 8, 'N', 1)

    local function s(s)
      --print(s)
      esp:send(s .. '\n')
      esp:recv()
      --sys.debug(esp:recv())
    end

    s("node.restart()")
    sys.sleep(0.5)
    print(esp:recv())
    
    for i = 1, #files do
      local f = io.open(files[i].host, 'rb')
      injector.assert(f:read(1) ~= 27, 'Injector don\'t support precompiled files') 
    end

    -- Count the total number of lines
    local lineCountTotal = 0
    local fileSizes = {}
    for i = 1, #files do
      local fileSize = 0
      s("f = file.open('" .. files[i].remote .. "','w+')")
      for line in io.lines(files[i].host) do
        if line:len() > 0 and line:sub(1, 2) ~= '--' then
          lineCountTotal = lineCountTotal + 1
          fileSize = fileSize + line:len() + 1
        end
      end
      fileSizes[files[i].remote] = fileSize
    end

    local pb = injector.addProgressBar('Waiting', lineCountTotal, false)
    local fl = injector.addFileList('Uploading')

    local lineCount = 0
    for i = 1, #files do
      injector.addFile(fl, files[i].remote)
      s("file.remove('" .. files[i].remote .. "')")
      sys.sleep(0.1)
      if false then --bin
        s("f = file.open('" .. files[i].remote .. "','wb+')")
        local f = io.open(files[i].host, 'rb')
        local b = f:read('*all')
        f:close()
        while b:len() > 0 do
          local n = math.min(b:len(), 16)
          local line = ''
          for i = 1, n do
            line = line .. '\\x' .. string.format('%02X', b:byte(i))
          end
          b = b:sub(17)
          print(line)
          s("f:write('" .. line .. "')")
          lineCount = lineCount + 1
          sys.sleep(0.1)
        end
        injector.setProgressBar(pb, lineCount)
      else
        s("f = file.open('" .. files[i].remote .. "','w+')")
        for line in io.lines(files[i].host) do
          if line:len() > 0 and line:sub(1, 2) ~= '--' then
            s("f:writeline([[" .. line .. "]])")
            lineCount = lineCount + 1
            injector.setProgressBar(pb, lineCount)
            --local t = 10.0 / self.parameter.baud * line:len()
            sys.sleep(0.1)
          end
        end
      end
      s("f:close()")
    end

    local lineGetter = coroutine.create(
      function ()
        do
          local s = ''
          while true do
            s = s .. esp:recv()
            local p = s:find('\n')
            while p do
              coroutine.yield(s:sub(1, p - 1))
              s = s:sub(p + 1)
              p = s:find('\n')
            end
            sys.sleep(0.01)
          end
        end
      end
    )

    --for k, v in pairs(fileSizes) do
    --  print('->', k, v)
    --end

    sys.sleep(0.2)
    esp:recv()
    s("do local l = file.list() for k,v in pairs(l) do print(k..':'..v) end print('#') end")
    local errorCount = 0
    while true do
      local _, line = coroutine.resume(lineGetter)
      if line:byte() == 35 then
        break
      end
      local name, size = line:match('^(.*):(%d+)')
      if fileSizes[name] then
        if fileSizes[name] ~= tonumber(size) then
          errorCount = errorCount + 1
        end
      end
    end
    if errorCount > 0 then
      injector.addLabel('<FONT size="10"><FONT color="#FF0000"><b>File size wrong on ' .. errorCount .. ' uploaded files!</b></FONT></FONT>')
    else
      injector.addLabel('<FONT size="10"><FONT color="#008000"><b>Success</b></FONT></FONT>')
    end

    if self.parameter.powerupStart then
      s("f = file.open('init.lua','w+')")
      s("f:writeline([[print('Start in 5 seconds...']]")
      s("f:writeline([[tmr.alarm(0, 5000, 0, function() dofile('startup.lua') end]]")
      s("f:close")
    else
      s("file.remove('ini.lua')")
    end

    injector.addLabel('Start <i>startup.lua</i>')
    s("dofile('startup.lua')")

    injector.addLabel('<FONT size="10"><FONT color="#000080"><b>Redirect boards output (COM' .. self.parameter.com .. ') to console.</b></FONT></FONT>')

    while true do
      print(coroutine.resume(lineGetter))
    end


    do
      local s = ''
      while true do
        s = s .. esp:recv()
        local p = s:find('\n')
        if p then
          print(s:sub(1, p - 1))
          s = s:sub(p + 1)
        else
          sys.sleep(0.01)
        end
      end
    end

    esp:close()
    injector.close()
  end,
}





