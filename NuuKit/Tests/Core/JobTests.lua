-- Core/Job.lua: work spread over frames. The client's clock and timer are
-- stood in for here: the clock moves only when a test says so, and the timer
-- keeps what it is given until the test runs it.
local Kit = _G.LoadKit().Kit
local W = dofile("Tests/Support/CommsWorld.lua")
local suite, test, ok, eq, before, after = W.suite, W.test, W.ok, W.eq, W.before, W.after

local Job = Kit.Job

local now, queued = 0, {}
local saved = {}
local function install()
    saved.debugprofilestop, saved.C_Timer = _G.debugprofilestop, _G.C_Timer
    now, queued = 0, {}
    _G.debugprofilestop = function() return now end
    _G.C_Timer = { After = function(_, fn) queued[#queued + 1] = fn end }
end
local function remove()
    _G.debugprofilestop, _G.C_Timer = saved.debugprofilestop, saved.C_Timer
end
-- Runs the next frame's slice.
local function frame()
    local fn = table.remove(queued, 1)
    if fn then fn() end
    return fn ~= nil
end

--------------------------------------------------------------------------------

suite("Jobs outside the client", function()
    test("run to their end inside Start, and Pause does nothing", function()
        local got
        local job = Job.Start(function()
            for _ = 1, 10 do Job.Pause() end
            return "done", 2
        end, function(okRun, a, b) got = { okRun, a, b } end)
        eq(got[1], true, "ok")
        eq(got[2], "done", "first result")
        eq(got[3], 2, "second result")
        ok(job:Finished(), "finished")
        Job.Pause()
    end)
end)

suite("Jobs in the client", function()
    before(install)
    after(remove)

    test("hand the rest to the next frame once the slice is used", function()
        local steps, got = 0, nil
        Job.Start(function()
            for _ = 1, 10 do
                steps = steps + 1
                now = now + 1
                Job.Pause()
            end
            return steps
        end, function(okRun, n) got = { okRun, n } end)
        eq(steps, Job.SLICE_MS, "the first slice runs inside Start, for its time")
        eq(got, nil, "not done yet")
        ok(frame(), "the next frame is asked for")
        eq(steps, 2 * Job.SLICE_MS, "the next slice")
        while frame() do end
        eq(got[1], true, "done")
        eq(got[2], 10, "with its result")
    end)

    test("finish inside Start when the work is short", function()
        local got
        Job.Start(function() Job.Pause(); return 1 end, function(okRun, n) got = n end)
        eq(got, 1, "done before Start returns")
        eq(#queued, 0, "no frame asked for")
    end)

    test("hand an error to done, with the stack", function()
        local got
        Job.Start(function()
            now = now + 10
            Job.Pause()
            error("broken")
        end, function(okRun, message) got = { okRun, message } end)
        while frame() do end
        eq(got[1], false, "not ok")
        ok(tostring(got[2]):find("broken", 1, true) and tostring(got[2]):find("traceback", 1, true),
            "the message and its stack: " .. tostring(got[2]))
    end)

    test("raise an error when nothing takes it", function()
        Job.Start(function()
            now = now + 10
            Job.Pause()
            error("nobody listens")
        end)
        local raised, message = pcall(frame)
        ok(not raised and tostring(message):find("nobody listens", 1, true), "raised: " .. tostring(message))
    end)

    test("stop when cancelled, without calling done", function()
        local steps, called = 0, false
        local job = Job.Start(function()
            while true do
                steps = steps + 1
                now = now + 10
                Job.Pause()
            end
        end, function() called = true end)
        job:Cancel()
        while frame() do end
        eq(steps, 1, "no slice after Cancel")
        eq(called, false, "done not called")
    end)

    test("stop at the next Pause when the work cancels itself", function()
        local steps, called, job = 0, false, nil
        job = Job.Start(function()
            for _ = 1, 100 do
                steps = steps + 1
                if steps == 1 then now = now + 10 end
                if steps == 2 then job:Cancel() end
                Job.Pause()
            end
        end, function() called = true end)
        while frame() do end
        eq(steps, 2, "nothing past the Pause after Cancel")
        eq(called, false, "done not called")
    end)

    test("stop when the work cancels itself and returns without pausing", function()
        local called, job = false, nil
        job = Job.Start(function()
            now = now + 10
            Job.Pause()
            job:Cancel()
            return "late"
        end, function() called = true end)
        while frame() do end
        eq(called, false, "done not called")
        eq(job:Finished(), false, "not finished: it was cancelled")
    end)

    test("swallow an error the work raises after cancelling itself", function()
        local job
        job = Job.Start(function()
            now = now + 10
            Job.Pause()
            job:Cancel()
            error("after cancel")
        end)
        ok(pcall(function() while frame() do end end), "nothing raised")
    end)

    test("take a Cancel after the end, or twice, as nothing", function()
        local got
        local job = Job.Start(function() return 1 end, function(_, n) got = n end)
        job:Cancel()
        job:Cancel()
        eq(got, 1, "done was called before")
        ok(job:Finished(), "and it stays finished")
        local other = Job.Start(function()
            now = now + 10
            Job.Pause()
        end)
        other:Cancel()
        other:Cancel()
        while frame() do end
        eq(other:Finished(), false, "a twice-cancelled job never finishes")
    end)

    test("run a job started inside a job on slices of its own", function()
        local inner, outer
        Job.Start(function()
            Job.Start(function()
                for _ = 1, 5 do
                    now = now + 10
                    Job.Pause()
                end
                return "inner"
            end, function(_, v) inner = v end)
            for _ = 1, 5 do
                now = now + 10
                Job.Pause()
            end
            return "outer"
        end, function(_, v) outer = v end)
        while frame() do end
        eq(inner, "inner", "the inner job finishes")
        eq(outer, "outer", "and the outer one")
    end)

    test("let Pause be in a coroutine of the caller's own", function()
        now = 1000
        local co = coroutine.create(function()
            now = now + 10
            Job.Pause()
            return "through"
        end)
        local okRun, v = coroutine.resume(co)
        eq(okRun and v, "through", "Pause did not yield a coroutine that is not a job")
    end)

    test("carry on after the work yields by itself", function()
        local got
        Job.Start(function()
            local a = 1
            coroutine.yield()
            return a + 1
        end, function(_, v) got = v end)
        eq(got, nil, "waiting for the next frame")
        while frame() do end
        eq(got, 2, "then done")
    end)

    test("give the same base64 and Adler-32 over frames as at once, around every pause", function()
        local bytes, x = {}, 3
        for i = 1, 3 * 4095 + 7 do
            x = (x * 1103515245 + 12345) % 2147483648
            bytes[i] = string.char(x % 256)
        end
        local all = table.concat(bytes)
        _G.debugprofilestop = function() now = now + 1; return now end
        for _, n in ipairs({ 4094, 4095, 4096, 8190, 8191, 3 * 4095 + 7 }) do
            local s = all:sub(1, n)
            local text, back, sum
            Job.Start(function()
                local t = Kit.Codec.ToBase64(s)
                return t, Kit.Codec.FromBase64(t), Kit.Codec.Adler32(s)
            end, function(_, a, b, c) text, back, sum = a, b, c end)
            while frame() do end
            eq(text, Kit.Codec.ToBase64(s), n .. " bytes: base64")
            eq(back, s, n .. " bytes: back")
            eq(sum, Kit.Codec.Adler32(s), n .. " bytes: Adler-32")
        end
    end)

    test("compress a shared string over several frames, to the same text", function()
        local parts = {}
        for i = 1, 3000 do parts[i] = ("step %d: kill %d boars at %d, %d. "):format(i, i % 7, i % 97, i % 89) end
        local body = table.concat(parts)
        local direct = Kit.Codec.ToText(1, body)
        -- Every look at the clock moves it a millisecond.
        _G.debugprofilestop = function() now = now + 1; return now end
        local text
        Job.Start(function()
            return Kit.Codec.ToText(1, body)
        end, function(okRun, result) text = result end)
        local frames = 1
        while frame() do frames = frames + 1 end
        eq(text, direct, "the same text as at once")
        ok(frames > 10, "over " .. frames .. " frames")
        local back
        Job.Start(function() return Kit.Codec.FromText(text) end, function(okRun, schema, result) back = result end)
        while frame() do end
        eq(back, body, "and read back in a job")
    end)
end)

print("NuuKit job tests passed (" .. W.count .. " tests)")
return true
