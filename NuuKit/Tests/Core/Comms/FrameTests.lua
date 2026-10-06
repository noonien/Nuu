-- The comms wire format, from both ends: a Writer frame that a Reader takes
-- apart, and the edges around it. Signed integers, NUL placement in Bytes,
-- COBS runs that fill or overflow a block, frames larger than one addon
-- message, and everything a malformed frame can be. From Sonar's
-- tests/test_codec.lua. The fields themselves are Core/Codec's
-- (Tests/Core/Codec/CodecTests.lua); these are about the frame around them.
local Kit = _G.LoadKit().Kit
local W = dofile("Tests/Support/CommsWorld.lua")
local suite, test, ok, eq, errors = W.suite, W.test, W.ok, W.eq, W.errors

local Codec = Kit.Comms
local V = Codec.VERSION

--------------------------------------------------------------------------------
-- Frame builders, for the frames a Writer refuses to make
--------------------------------------------------------------------------------

local function varint(n)
    local out = {}
    repeat
        local byte = n % 128
        n = math.floor(n / 128)
        if n > 0 then byte = byte + 128 end
        out[#out + 1] = string.char(byte)
    until n == 0
    return table.concat(out)
end

-- Little-endian two's complement field bytes, the same width the writer emits.
local function le(n, k)
    local out = {}
    for i = 1, k do
        out[i] = string.char(n % 256)
        n = math.floor(n / 256)
    end
    return table.concat(out)
end

-- A wire frame built from the logical field bytes, the way Writer would if the
-- 255-byte cap did not apply. Runs of 254 use the full-block code and imply no
-- NUL; every other block implies one unless it ends the frame.
local function frame(fields)
    local out, i = { string.char(V) }, 1
    while true do
        local zero = fields:find("\0", i, true)
        local run = zero and fields:sub(i, zero - 1) or fields:sub(i)
        while #run >= 254 do
            out[#out + 1] = string.char(255) .. run:sub(1, 254)
            run = run:sub(255)
        end
        out[#out + 1] = string.char(#run + 1) .. run
        if not zero then break end
        i = zero + 1
    end
    return table.concat(out)
end

-- Writer -> Finish -> Reader, with the frame checked on the way through.
local function pipeline(build, read, name)
    local writer = Codec.Writer()
    build(writer)
    local packet = writer:Finish()
    ok(packet ~= nil, name .. ": finish")
    if not packet then return end
    ok(not packet:find("\0", 1, true), name .. ": no NUL")
    ok(#packet <= Codec.MAX_PAYLOAD, name .. ": fits")
    eq(packet:byte(1), V, name .. ": version prefix")
    eq(Codec.Accept(packet), true, name .. ": accept")
    local reader = Codec.Reader(packet)
    read(reader, name)
    eq(reader:Ok(), true, name .. ": ok")
    eq(reader:More(), false, name .. ": consumed")
end

--------------------------------------------------------------------------------

suite("The frame header", function()
    test("names the encoding and the size the client allows", function()
        eq(Codec.VERSION, 1, "VERSION")
        eq(Codec.MIN_PAYLOAD, 3, "MIN_PAYLOAD")
        eq(Codec.MAX_PAYLOAD, 255, "MAX_PAYLOAD")
    end)

    test("leads every frame", function()
        local packet = Codec.Writer():U(1):Finish()
        eq(packet:byte(1), V, "U(1) version is first wire byte")
        eq(Codec.Reader(packet):U(), 1, "U(1) reader skips version")
    end)

    test("refuses a frame with no field in it", function()
        errors(function() Codec.Writer():Finish() end, "empty Finish asserts")
        local writer = Codec.Writer()
        eq(writer:Len(), 2, "len empty is version + pending COBS code")
    end)
end)

--------------------------------------------------------------------------------

suite("Accept", function()
    test("takes a well formed frame", function()
        eq(Codec.Accept(Codec.Writer():U(1):Finish()), true, "accept writer frame")
        eq(Codec.Accept("\1\2a"), true, "well formed frame accepted")
    end)

    test("passes over a frame of another encoding", function()
        eq(Codec.Accept(string.char(2, 2, 1)), nil, "accept unknown version")
        eq(Codec.Accept("\2\2a"), nil, "other version rejected")
        eq(Codec.Accept(""), nil, "empty string has no version")
        eq(Codec.Accept(string.char(0)), nil, "accept NUL")
    end)

    test("calls a frame of our own encoding with no body a violation", function()
        eq(Codec.Accept(string.char(V)), Codec.VIOLATION, "accept version only")
        eq(Codec.Accept(string.char(V, 1)), Codec.VIOLATION, "accept empty COBS")
        eq(Codec.Accept("\1"), Codec.VIOLATION, "frame below the minimum is a violation")
    end)
end)

--------------------------------------------------------------------------------

suite("Unsigned integers", function()
    test("round trip through a frame", function()
        pipeline(function(w)
            w:U(0):U(1):U(127):U(128):U(300):U(268435455)
        end, function(r, name)
            eq(r:U(), 0, name .. " u0")
            eq(r:U(), 1, name .. " u1")
            eq(r:U(), 127, name .. " u127")
            eq(r:U(), 128, name .. " u128")
            eq(r:U(), 300, name .. " u300")
            eq(r:U(), 268435455, name .. " uMax")
        end, "u")
    end)

    test("encode zero as one byte", function()
        eq(Codec.Writer():U(0):Finish(), string.char(V, 1, 1), "U(0) is version + COBS of a zero byte")
        eq(Codec.Reader(Codec.Writer():U(0):U(127):U(128):Finish()):U(), 0, "read U(0) then more")
    end)

    test("refuse a value outside the range", function()
        errors(function() Codec.Writer():U(-1) end, "unsigned below range rejected")
        errors(function() Codec.Writer():U(268435456) end, "unsigned above range rejected")
    end)

    test("floor a value that is not whole", function()
        eq(Codec.Reader(Codec.Writer():U(7.9):Finish()):U(), 7, "unsigned value floors")
    end)
end)

--------------------------------------------------------------------------------

suite("Signed integers", function()
    local signed = { 0, 1, -1, 63, -63, 64, -64, 127, -128, 300, -300,
        16383, -16384, 2097151, -2097152, 134217727, -134217728 }

    test("round trip through a frame", function()
        pipeline(function(w)
            w:I(0):I(-1):I(1):I(-2):I(64):I(-64):I(-134217728):I(134217727)
        end, function(r, name)
            eq(r:I(), 0, name .. " 0")
            eq(r:I(), -1, name .. " -1")
            eq(r:I(), 1, name .. " 1")
            eq(r:I(), -2, name .. " -2")
            eq(r:I(), 64, name .. " 64")
            eq(r:I(), -64, name .. " -64")
            eq(r:I(), -134217728, name .. " iMin")
            eq(r:I(), 134217727, name .. " iMax")
        end, "i")
    end)

    test("round trip one at a time across the whole range", function()
        for _, n in ipairs(signed) do
            local packet = Codec.Writer():I(n):Finish()
            ok(packet ~= nil, ("signed %d: finish"):format(n))
            eq(Codec.Reader(packet):I(), n, ("signed %d round trip"):format(n))
        end
    end)

    test("read the same packed together, where a read starts mid-run", function()
        local writer = Codec.Writer()
        for _, n in ipairs(signed) do writer:I(n) end
        local reader = Codec.Reader(writer:Finish())
        for _, n in ipairs(signed) do
            eq(reader:I(), n, ("packed signed %d"):format(n))
        end
        eq(reader:Ok(), true, "signed packed: ok")
        eq(reader:More(), false, "signed packed: consumed")
        eq(reader:I(), 0, "signed read past the end is 0")
        eq(reader:Ok(), false, "signed read past the end is not ok")
    end)

    test("read across a block that a NUL broke", function()
        local reader = Codec.Reader(Codec.Writer():I(-300):False():I(300):Finish())
        eq(reader:I(), -300, "signed before the block break")
        eq(reader:Bool(), false, "false reads as false")
        eq(reader:I(), 300, "signed after the block break")
    end)

    test("encode zero as one byte", function()
        eq(Codec.Writer():I(0):Finish(), string.char(V, 1, 1), "I(0) is version + COBS of a zero byte")
    end)

    test("refuse a value outside the range", function()
        errors(function() Codec.Writer():I(134217728) end, "signed above range rejected")
        errors(function() Codec.Writer():I(-134217729) end, "signed below range rejected")
    end)

    test("read a wire value at the edge of the range", function()
        eq(Codec.Reader(frame(string.char(0xFE, 0xFF, 0xFF, 0x7F))):I(), 134217727,
            "zigzag of iMax reads back")
        eq(Codec.Reader(frame(string.char(0xFF, 0xFF, 0xFF, 0x7F))):I(), -134217728,
            "zigzag of iMin reads back")
    end)

    test("refuse a wire value past the edge of the range", function()
        -- Five LEB groups is above VARINT_GROUPS.
        local over = Codec.Reader(frame(string.char(0x80, 0x80, 0x80, 0x80, 0x01)))
        eq(over:I(), 0, "signed value with too many groups")
        eq(over:Ok(), false, "too many groups is not ok")
    end)

    test("floor a value that is not whole", function()
        eq(Codec.Reader(Codec.Writer():I(7.9):Finish()):I(), 7, "signed value floors")
    end)
end)

--------------------------------------------------------------------------------

suite("True and False", function()
    test("read back as true and false", function()
        local reader = Codec.Reader(Codec.Writer():True():False():True():Finish())
        eq(reader:Bool(), true, "true reads as true")
        eq(reader:Bool(), false, "false reads as false")
        eq(reader:Bool(), true, "true after false")
        eq(reader:Ok(), true, "flags: ok")
        eq(reader:More(), false, "flags: consumed")
        eq(reader:Bool(), false, "bool past the end is false")
        eq(reader:Ok(), false, "bool past the end is not ok")
    end)

    test("are the only two bytes that read as a flag", function()
        local reader = Codec.Reader(Codec.Writer():U(2):Finish())
        eq(reader:Bool(), false, "byte other than 0 or 1 is not a flag")
        eq(reader:Ok(), false, "a bad flag is not ok")
    end)

    test("head an optional field and an array", function()
        pipeline(function(w)
            w:False()
            w:True():U(0)
            w:True():U(2):U(9):U(8)
            w:Bytes("")
            w:Bytes("ab\0c")
        end, function(r, name)
            eq(r:Bool(), false, name .. " false")
            eq(r:Bool(), true, name .. " true empty")
            eq(r:U(), 0, name .. " array 0")
            eq(r:Bool(), true, name .. " true items")
            eq(r:U(), 2, name .. " array 2")
            eq(r:U(), 9, name .. " item1")
            eq(r:U(), 8, name .. " item2")
            eq(r:Bytes(), "", name .. " empty string")
            eq(r:Bytes(), "ab\0c", name .. " string with NUL")
        end, "opt/array/string")
    end)
end)

--------------------------------------------------------------------------------

suite("Fixed-width integers", function()
    test("round trip every width through a frame", function()
        pipeline(function(w)
            w:U8(0):U8(255):I8(-128):I8(127):I8(-1)
            w:U16(0):U16(256):U16(65535):I16(-32768):I16(32767):I16(-1)
            w:U32(0):U32(4294967295):I32(-2147483648):I32(2147483647):I32(-1)
            w:U64(0):U64(9007199254740992):I64(-9007199254740992):I64(9007199254740992):I64(-1)
        end, function(r, name)
            eq(r:U8(), 0, name .. " u8 0")
            eq(r:U8(), 255, name .. " u8 max")
            eq(r:I8(), -128, name .. " i8 min")
            eq(r:I8(), 127, name .. " i8 max")
            eq(r:I8(), -1, name .. " i8 -1")
            eq(r:U16(), 0, name .. " u16 0")
            eq(r:U16(), 256, name .. " u16 256")
            eq(r:U16(), 65535, name .. " u16 max")
            eq(r:I16(), -32768, name .. " i16 min")
            eq(r:I16(), 32767, name .. " i16 max")
            eq(r:I16(), -1, name .. " i16 -1")
            eq(r:U32(), 0, name .. " u32 0")
            eq(r:U32(), 4294967295, name .. " u32 max")
            eq(r:I32(), -2147483648, name .. " i32 min")
            eq(r:I32(), 2147483647, name .. " i32 max")
            eq(r:I32(), -1, name .. " i32 -1")
            eq(r:U64(), 0, name .. " u64 0")
            eq(r:U64(), 9007199254740992, name .. " u64 2^53")
            eq(r:I64(), -9007199254740992, name .. " i64 -2^53")
            eq(r:I64(), 9007199254740992, name .. " i64 2^53")
            eq(r:I64(), -1, name .. " i64 -1")
        end, "fixed")
    end)

    test("write little-endian bytes, including a zero that breaks the run", function()
        eq(Codec.Writer():U16(0x0201):Finish(), string.char(V, 3, 0x01, 0x02),
            "U16(0x0201) is 01 02")
        eq(Codec.Writer():U16(256):Finish(), string.char(V, 1, 2, 1),
            "U16(256) is 00 01, so COBS splits on the zero")
        eq(Codec.Reader(Codec.Writer():U16(256):U8(9):Finish()):U16(), 256, "u16 with a zero byte")
        eq(Codec.Reader(Codec.Writer():I32(-1):Finish()):I32(), -1, "i32 -1 is four 0xFF bytes")
    end)

    test("refuse a value outside the range", function()
        errors(function() Codec.Writer():U8(-1) end, "u8 below range")
        errors(function() Codec.Writer():U8(256) end, "u8 above range")
        errors(function() Codec.Writer():I8(-129) end, "i8 below range")
        errors(function() Codec.Writer():I8(128) end, "i8 above range")
        errors(function() Codec.Writer():U16(65536) end, "u16 above range")
        errors(function() Codec.Writer():I16(-32769) end, "i16 below range")
        errors(function() Codec.Writer():U32(-1) end, "u32 below range")
        errors(function() Codec.Writer():I32(2147483648) end, "i32 above range")
        errors(function() Codec.Writer():I32(-2147483649) end, "i32 below range")
        errors(function() Codec.Writer():U64(-1) end, "u64 below range")
        errors(function() Codec.Writer():U64(18014398509481984) end, "u64 above 2^53")
        errors(function() Codec.Writer():I64(18014398509481984) end, "i64 above 2^53")
        errors(function() Codec.Writer():I64(-18014398509481984) end, "i64 below -2^53")
    end)

    test("floor a value that is not whole", function()
        eq(Codec.Reader(Codec.Writer():U8(7.9):Finish()):U8(), 7, "u8 floors")
        eq(Codec.Reader(Codec.Writer():I16(-3.2):Finish()):I16(), -4, "i16 floors toward -inf")
        eq(Codec.Reader(Codec.Writer():U32(1.1):Finish()):U32(), 1, "u32 floors")
    end)

    test("read a truncated field as zero and not ok", function()
        local u16 = Codec.Reader(string.char(V, 2, 1))
        eq(u16:U16(), 0, "truncated u16")
        eq(u16:Ok(), false, "truncated u16 is not ok")
        local i32 = Codec.Reader(string.char(V, 2, 1))
        eq(i32:I32(), 0, "truncated i32")
        eq(i32:Ok(), false, "truncated i32 is not ok")
        local u64 = Codec.Reader(string.char(V, 2, 1))
        eq(u64:U64(), 0, "truncated u64")
        eq(u64:Ok(), false, "truncated u64 is not ok")
        local empty = Codec.Reader("")
        eq(empty:U8(), 0, "empty frame u8")
        eq(empty:Ok(), false, "empty frame is not ok")
    end)

    test("read a 64-bit pattern past 2^53 as zero and not ok", function()
        local u64 = Codec.Reader(frame(le(1, 4) .. le(2097152, 4)))
        eq(u64:U64(), 0, "u64 2^53+1 is not an exact Lua integer")
        eq(u64:Ok(), false, "u64 past 2^53 is not ok")
        local i64 = Codec.Reader(frame(le(0xFFFFFFFF, 4) .. le(0xFFDFFFFF, 4)))
        eq(i64:I64(), 0, "i64 below -2^53")
        eq(i64:Ok(), false, "i64 below -2^53 is not ok")
    end)
end)

--------------------------------------------------------------------------------

suite("Bytes", function()
    test("carry a NUL wherever it falls, and leave none on the wire", function()
        local strings = {
            "", "a", "\0", "\0a", "a\0", "a\0b", "\0\0", "\0\0\0", "ab\0\0cd",
            "\0abc\0", string.rep("\0", 8), "abc", "\128\254a\0\255",
        }
        for _, text in ipairs(strings) do
            local packet = Codec.Writer():Bytes(text):Finish()
            ok(packet ~= nil, ("bytes %q: finish"):format(text))
            ok(not packet:find("\0", 1, true), ("bytes %q: frame has no NUL"):format(text))
            eq(Codec.Reader(packet):Bytes(), text, ("bytes %q round trip"):format(text))
        end
    end)

    test("leave the fields behind them readable", function()
        local reader = Codec.Reader(Codec.Writer():Bytes("a\0b"):Bytes("c"):U(9):Finish())
        eq(reader:Bytes(), "a\0b", "first string with an inner NUL")
        eq(reader:Bytes(), "c", "string after a NUL-bearing string")
        eq(reader:U(), 9, "integer after a NUL-bearing string")
    end)

    test("hold a long payload whole", function()
        local text = "ab\0c" .. string.rep("z", 200)
        eq(Codec.Reader(Codec.Writer():Bytes(text):Finish()):Bytes(), text, "bytes: payload intact")
    end)

    test("take a string and nothing else", function()
        errors(function() Codec.Writer():Bytes(false) end, "non-string throws")
    end)
end)

--------------------------------------------------------------------------------

suite("Mark and restore", function()
    test("put the writer back where the mark was taken", function()
        local writer = Codec.Writer()
        writer:U(9)
        local mark = writer:Mark()
        writer:Bytes("nope"):U(300)
        ok(writer:Len() > mark.len, "grew after mark")
        writer:Restore(mark)
        eq(writer:Len(), 3, "restore len")
        eq(writer:Finish(), string.char(V, 2, 9), "restore body")
    end)

    test("can put it back to empty, where there is nothing to finish", function()
        local writer = Codec.Writer()
        local mark = writer:Mark()
        writer:U(1)
        writer:Restore(mark)
        eq(writer:Len(), 2, "restore to empty len")
        errors(function() writer:Finish() end, "restore to empty Finish asserts")
    end)

    test("keep the run state of an open block", function()
        local writer = Codec.Writer()
        for _ = 1, 252 do writer:U(1) end
        local mark = writer:Mark()
        writer:U(1):U(2)
        writer:Restore(mark)
        eq(writer:Len(), 254, "restore open run len")
        eq(#writer:Finish(), 254, "restore open run body")

        writer:U(1)
        mark = writer:Mark()
        writer:U(2)
        writer:Restore(mark)
        eq(writer:Len(), 255, "restore full cap len")
        eq(#writer:Finish(), 255, "restore full cap body")
        eq(writer:Finish():byte(1), V, "full cap keeps version")
    end)

    test("take a mark and nothing else", function()
        errors(function() Codec.Writer():U(1):Restore(nil) end, "bad mark throws")
    end)
end)

--------------------------------------------------------------------------------

suite("The payload cap", function()
    test("lets a caller cram records in until the next one would not fit", function()
        local writer = Codec.Writer()
        local records = 0
        while true do
            local mark = writer:Mark()
            writer:Bytes("x")
            if writer:Len() > Codec.MAX_PAYLOAD then
                writer:Restore(mark)
                break
            end
            records = records + 1
        end
        ok(records >= 1, "cram: at least one record")
        ok(writer:Len() <= Codec.MAX_PAYLOAD, "cram: within MAX_PAYLOAD")
        local packet = writer:Finish()
        ok(packet, "cram: finish")
        ok(#packet <= Codec.MAX_PAYLOAD, "cram: packet <= 255")
        eq(packet:byte(1), V, "cram: version prefix")
    end)

    test("allows a frame that fills it exactly", function()
        local writer = Codec.Writer()
        while writer:Len() < Codec.MAX_PAYLOAD do writer:U(1) end
        eq(writer:Len(), Codec.MAX_PAYLOAD, "fill: exact MAX_PAYLOAD")
        local packet = writer:Finish()
        ok(packet, "fill: finish")
        eq(#packet, Codec.MAX_PAYLOAD, "fill: uses 255")
        ok(Codec.Writer():U(1):Finish() and true, "small still works after fill")
    end)

    test("counts the length of a mixed frame the way Finish does", function()
        local writer = Codec.Writer()
        writer:U(1):U(128):Bytes("ab")
        eq(writer:Len(), 8, "len mixed")
        eq(#writer:Finish(), 8, "len matches finish")
        eq(writer:Finish():byte(1), V, "mixed version prefix")
    end)

    test("holds 253 single bytes and no more", function()
        local writer = Codec.Writer()
        for _ = 1, 253 do writer:U(1) end
        local packet = writer:Finish()
        ok(packet, "253 ones: finish")
        eq(#packet, 255, "253 ones: version + code + 253 data")
        eq(packet:byte(1), V, "253 ones: version")
        eq(packet:byte(2), 254, "253 ones: COBS code 254")
        local reader = Codec.Reader(packet)
        for i = 1, 253 do eq(reader:U(), 1, "253 ones: byte " .. i) end
        eq(reader:Ok(), true, "253 ones: ok")
        eq(reader:More(), false, "253 ones: consumed")
        eq(reader:U(), 0, "253 ones: extra read is 0")
        eq(reader:Ok(), false, "253 ones: extra read is not ok")
        writer:U(1)
        ok(writer:Len() > 255, "254th one overflows the cap")
        eq(writer:Finish(), nil, "254th one: finish is nil")
    end)
end)

--------------------------------------------------------------------------------

suite("Runs that fill or overflow a block", function()
    test("close the run at the full-block code and go on writing", function()
        local writer = Codec.Writer()
        for _ = 1, 253 do writer:U(1) end
        eq(writer:Len(), 255, "253 nonzero bytes fill the frame")
        writer:U(1)
        eq(writer:Len(), 256, "the 254th byte closes the run at the full-block code")
        eq(writer:Finish(), nil, "a closed full run does not fit an addon message")
        writer:U(1)
        ok(writer:Len() > 256, "writing continues in a fresh run")
    end)

    test("take the slow varint path where the open run is nearly full", function()
        local writer = Codec.Writer()
        for _ = 1, 251 do writer:U(1) end
        eq(writer:Len(), 253, "251 bytes written")
        writer:U(300)
        eq(writer:Len(), 255, "a multi-byte varint past the packing limit still writes")
        local packet = writer:Finish()
        ok(packet ~= nil, "the frame still fits an addon message")
        local reader = Codec.Reader(packet)
        for i = 1, 251 do eq(reader:U(), 1, "slow varint path: byte " .. i) end
        eq(reader:U(), 300, "value written through the slow varint path")
    end)

    test("refuse to finish a string longer than one block", function()
        local writer = Codec.Writer()
        writer:Bytes(string.rep("x", 300))
        ok(writer:Len() > Codec.MAX_PAYLOAD, "a 300-byte string overflows one block")
        eq(writer:Finish(), nil, "the overflowing string does not fit")
    end)

    test("refuse to finish a string longer than the room left", function()
        local writer = Codec.Writer()
        writer:Bytes(string.rep("y", 200))
        writer:Bytes(string.rep("z", 200))
        ok(writer:Len() > Codec.MAX_PAYLOAD, "two partial strings overflow one block")
        eq(writer:Finish(), nil, "the overflowing pair does not fit")
    end)

    test("land a four-group varint on the full-block code", function()
        local writer = Codec.Writer()
        for _ = 1, 250 do writer:U(1) end
        writer:U(268435455)
        eq(writer:Len(), 256, "a four-group varint ends the run on the full-block code")
        eq(writer:Finish(), nil, "the filled run does not fit an addon message")
    end)

    test("land a string on the full-block code", function()
        local writer = Codec.Writer()
        writer:Bytes(string.rep("x", 252))
        eq(writer:Len(), 256, "a string ending the run lands on the full-block code")
        eq(writer:Finish(), nil, "the filled string run does not fit")
    end)

    test("spill a string into the next run", function()
        local writer = Codec.Writer()
        for _ = 1, 252 do writer:U(1) end
        writer:Bytes("ab")
        ok(writer:Len() > Codec.MAX_PAYLOAD, "a string with one byte of room spills to the next run")
        eq(writer:Finish(), nil, "the spilled string does not fit")
    end)
end)

--------------------------------------------------------------------------------

suite("Reading a frame larger than one add-on message", function()
    test("reads a string that spans several full blocks", function()
        local long = string.rep("q", 600)
        eq(Codec.Reader(frame(varint(#long) .. long)):Bytes(), long,
            "string spanning several full blocks")
    end)

    test("reads a string that an inner NUL broke across blocks", function()
        local body = string.rep("m", 300) .. "\0" .. string.rep("n", 300)
        eq(Codec.Reader(frame(varint(#body) .. body)):Bytes(), body,
            "string with an inner NUL across blocks")
    end)

    test("reads a varint that continues past a full block", function()
        local prefix = string.rep("p", 253)
        local reader = Codec.Reader(frame(varint(#prefix) .. prefix .. string.char(0xAC, 0x02)))
        eq(reader:Bytes(), prefix, "prefix string before the boundary")
        eq(reader:U(), 300, "varint continuing past a full block")
    end)

    test("reads a varint split across the block break", function()
        local prefix = string.rep("p", 254)
        local reader = Codec.Reader(frame(varint(#prefix) .. prefix .. string.char(0xAC, 0x02)))
        eq(reader:Bytes(), prefix, "prefix string filling the block")
        eq(reader:U(), 300, "varint split across the block break")
    end)

    test("stays inside a full block, which implies no NUL", function()
        local fields = varint(5) .. "abcde" .. varint(599) .. string.rep("z", 300)
        local reader = Codec.Reader(frame(fields))
        eq(reader:Bytes(), "abcde", "string read from inside a full block")
        eq(reader:I(), -300, "signed value read from inside a full block")
    end)

    test("reads a length whose bytes live in the next block", function()
        local reader = Codec.Reader(frame(string.rep("\1", 253) .. varint(3) .. "abc"))
        for i = 1, 253 do eq(reader:U(), 1, "full block filler " .. i) end
        eq(reader:Bytes(), "abc", "string whose bytes start in the next block")
    end)
end)

--------------------------------------------------------------------------------

suite("Malformed frames", function()
    test("read as zero and not ok where the frame runs out", function()
        local bytes = Codec.Reader("\1\2a")
        eq(bytes:Bytes(), "", "length past the end of the frame")
        eq(bytes:Ok(), false, "length past the end is not ok")
        local short = Codec.Reader("\1")
        eq(short:U(), 0, "short frame reads 0")
        eq(short:Ok(), false, "short frame is not ok")
        local past = Codec.Reader("\1\255ab")
        eq(past:U(), 0, "block code past the end of the frame")
        eq(past:Ok(), false, "truncated block is not ok")
        local empty = Codec.Reader("")
        eq(empty:U(), 0, "truncated U")
        eq(empty:Ok(), false, "empty is not ok")
        local cont = Codec.Reader(string.char(V, 2, 0x80))
        eq(cont:U(), 0, "truncated continuation")
        eq(cont:Ok(), false, "truncated continuation is not ok")
        local nul = Codec.Reader(string.char(0, 1))
        eq(nul:U(), 0, "NUL packet")
        eq(nul:Ok(), false, "NUL packet is not ok")
    end)

    test("read as zero and not ok where the varint grammar is broken", function()
        local function bad(fields, name)
            local reader = Codec.Reader(frame(fields))
            eq(reader:U(), 0, name)
            eq(reader:Ok(), false, name .. ": not ok")
        end
        bad(string.rep(string.char(0x80), 4), "unterminated varint")
        bad(string.rep(string.char(0x80), 4) .. "\1", "varint longer than four groups")
        bad(string.char(0x80, 0x00), "overlong two-byte varint")
        local overlong = Codec.Reader(string.char(V, 2, 0x80, 1))
        eq(overlong:U(), 0, "overlong U(0)")
        eq(overlong:Ok(), false, "overlong U(0) is not ok")
        bad(string.char(0xFF, 0xFF, 0xFF, 0xFF, 0x0F), "unsigned five-group value")
    end)

    test("stop after a rejected field instead of reading the next one", function()
        -- A rejected but complete overflowing varint sticks err, so later
        -- reads return 0 and do not throw.
        local reader = Codec.Reader(string.char(V, 8, 1, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F, 2, 1))
        eq(reader:U(), 1, "overflow: prefix")
        eq(reader:Ok(), true, "overflow: prefix ok")
        eq(reader:U(), 0, "overflow: rejected")
        eq(reader:Ok(), false, "overflow: not ok")
        eq(reader:U(), 0, "overflow: later reads stay 0")
        eq(reader:More(), false, "overflow: more is false once not ok")
    end)

    test("refuse a frame whose COBS is cut short, from its first field", function()
        -- The last code (0x80) promises 127 bytes the frame does not hold.
        local reader = Codec.Reader(string.char(V, 8, 1, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F, 0x80, 0x80))
        eq(reader:Ok(), false, "cut COBS: not ok before any read")
        local returned, value = pcall(reader.U, reader)
        ok(returned, "cut COBS: does not throw")
        eq(value, 0, "cut COBS: reads are 0")
        eq(reader:More(), false, "cut COBS: nothing to read")
    end)
end)

--------------------------------------------------------------------------------

suite("A reader that stops early or runs short", function()
    test("may leave the tail of a frame unread", function()
        local reader = Codec.Reader(Codec.Writer():U(5):U(6):Finish())
        eq(reader:U(), 5, "trailing: first")
        eq(reader:Ok(), true, "trailing: still ok")
        eq(reader:More(), true, "trailing: unread field remains")
        -- The second field is unread on purpose, the way an older reader
        -- would leave it.
    end)

    test("sees leftover across a COBS block boundary", function()
        local reader = Codec.Reader(Codec.Writer():U(0):U(1):Finish())
        eq(reader:U(), 0, "boundary: first")
        eq(reader:Ok(), true, "boundary: still ok")
        eq(reader:More(), true, "boundary: next run remains")
        eq(reader:U(), 1, "boundary: second")
        eq(reader:More(), false, "boundary: consumed")
        local zero = Codec.Reader(Codec.Writer():U(0):Finish())
        eq(zero:U(), 0, "empty tail: the zero")
        eq(zero:More(), false, "empty tail: trailing EOF code is not leftover")
        -- A block whose data would run past EOF makes the whole frame bad.
        local cut = Codec.Reader(string.char(V, 1, 10, 1))
        eq(cut:U(), 0, "cut: nothing is read")
        eq(cut:Ok(), false, "cut: a truncated block is not ok")
    end)

    test("reads the fields it knows and stops", function()
        local packet = Codec.Writer():U(1):U(2):Bytes("ab\0c"):U(3):False():True():U(300):Finish()
        local reader = Codec.Reader(packet)
        eq(reader:U(), 1, "partial fields: first")
        eq(reader:U(), 2, "partial fields: second")
        eq(reader:Bytes(), "ab\0c", "partial fields: string with NUL")
    end)

    test("reads a field the frame does not carry as not ok", function()
        local reader = Codec.Reader(Codec.Writer():U(3):Finish())
        eq(reader:U(), 3, "short: known")
        eq(reader:Ok(), true, "short: known is ok")
        eq(reader:More(), false, "short: nothing left")
        eq(reader:Bool(), false, "short: missing bool is false")
        eq(reader:Ok(), false, "short: missing bool is not ok")
    end)

    test("reads a short frame of two fields", function()
        local packet = Codec.Writer():U(42):Bytes("hi"):Finish()
        ok(packet and #packet <= Codec.MAX_PAYLOAD, "close: one packet")
        local reader = Codec.Reader(packet)
        eq(reader:U(), 42, "close: postedAt")
        eq(reader:Bytes(), "hi", "close: extra")
    end)
end)


print("NuuKit comms frame tests passed (" .. W.count .. " tests)")
return true
