local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Core/Job.lua: long work spread over frames, so the game never stalls.
--
--     local job = Kit.Job.Start(function()
--         return Kit.Codec.ToText(GuideCodec.SCHEMA, bytes)
--     end, function(ok, text) ... end)
--     job:Cancel()
--
-- The work runs in a coroutine. Kit.Job.Pause(), called often from inside it
-- (the codec calls it every few hundred bytes), hands the rest to the next
-- frame once this frame's slice (Job.SLICE_MS, timed with debugprofilestop)
-- is used. Outside a job Pause does nothing, so the same work called directly
-- runs to its end at once. The first slice runs inside Start: a small job is
-- finished, and done called, before Start returns.
--
-- done(true, ...) gets what the work returned; done(false, message) its error,
-- with the coroutine's stack. Without done, an error is raised from the frame
-- it happened in. Cancel stops the work before its next slice (or, called
-- from the work itself, at its next Pause), and done is not called. Without debugprofilestop or C_Timer.After (outside the client)
-- the work runs to its end inside Start.
local Job = Kit.Job or {}
Kit.Job = Job

Job.SLICE_MS = 4

local create, resume, yield, status, running = coroutine.create, coroutine.resume, coroutine.yield,
    coroutine.status, coroutine.running

-- The jobs whose work is running, by coroutine; CANCELLED for one cancelled
-- while it runs, so its next Pause stops it. The value never refers to its
-- key: Lua 5.1 would keep both.
local jobs = setmetatable({}, { __mode = "k" })
local CANCELLED = {}

local function clock()
    return debugprofilestop()
end

local function sliced()
    return type(debugprofilestop) == "function" and type(C_Timer) == "table" and type(C_Timer.After) == "function"
end

function Job.Pause()
    local co = running()
    local job = co and jobs[co]
    if job == CANCELLED or (job and job.sliced and clock() - job.started >= Job.SLICE_MS) then yield() end
end

local function settle(job, ok, ...)
    if job.cancelled then return end
    if status(job.co) ~= "dead" then
        C_Timer.After(0, job.step)
        return
    end
    jobs[job.co] = nil
    job.finished = true
    if not ok then
        local message = ...
        if type(debug) == "table" and type(debug.traceback) == "function" then
            message = debug.traceback(job.co, tostring(message))
        end
        if not job.onDone then error(message, 0) end
        job.onDone(false, message)
    elseif job.onDone then
        job.onDone(true, ...)
    end
end

local Handle = {}
Handle.__index = Handle

function Handle:Cancel()
    if self.finished then return end
    self.cancelled = true
    jobs[self.co] = CANCELLED
end

-- Whether the work has returned or failed.
function Handle:Finished()
    return self.finished == true
end

function Job.Start(work, onDone)
    local job = setmetatable({ co = create(work), onDone = onDone, sliced = sliced(), started = 0 }, Handle)
    jobs[job.co] = job
    job.step = function()
        if job.cancelled then return end
        if job.sliced then job.started = clock() end
        settle(job, resume(job.co))
    end
    job.step()
    return job
end
