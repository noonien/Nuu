-- Core/Codec: the plain writer and reader, base64url, Adler-32 and the
-- shared-string form around them. The comms frame on top of the same writer
-- and reader is Tests/Core/Comms/FrameTests.lua's.
local Kit = _G.LoadKit().Kit
local W = dofile("Tests/Support/CommsWorld.lua")
local suite, test, ok, eq, errors = W.suite, W.test, W.ok, W.eq, W.errors

local Codec = Kit.Codec

local function hex(s)
    return (s:gsub(".", function(c) return ("%02X "):format(c:byte()) end):gsub(" $", ""))
end

--------------------------------------------------------------------------------

suite("The writer", function()
    test("writes plain bytes, with no version, COBS or cap", function()
        eq(Codec.Writer():U(0):Finish(), "\0", "U(0) is one zero byte")
        eq(hex(Codec.Writer():U(300):Finish()), "AC 02", "U(300)")
        eq(hex(Codec.Writer():I(-1):I(1):Finish()), "01 02", "zigzag")
        eq(Codec.Writer():Bytes("a\0b"):Finish(), "\3a\0b", "bytes keep their NUL")
        eq(Codec.Writer():Finish(), "", "nothing written is the empty string")
        local long = string.rep("x", 1000)
        eq(Codec.Writer():Bytes(long):Finish(), "\232\7" .. long, "a long string")
    end)

    test("takes every whole number a Lua number holds exactly", function()
        local big = 9007199254740992
        local r = Codec.Reader(Codec.Writer():U(big):U(1790640000):I(-4503599627370496):I(4503599627370496):Finish())
        eq(r:U(), big, "U(2^53)")
        eq(r:U(), 1790640000, "a timestamp")
        eq(r:I(), -4503599627370496, "I(-2^52)")
        eq(r:I(), 4503599627370496, "I(2^52)")
        eq(r:Ok(), true, "ok")
        errors(function() Codec.Writer():U(big + 2) end, "U above 2^53")
        errors(function() Codec.Writer():U(-1) end, "U below 0")
        errors(function() Codec.Writer():I(4503599627370498) end, "I above 2^52")
    end)

    test("narrows to the limits it is given", function()
        local limits = { groups = 4, umax = 268435455, imin = -134217728, imax = 134217727 }
        errors(function() Codec.Writer(limits):U(268435456) end, "U above four groups")
        eq(Codec.Reader(Codec.Writer():U(268435456):Finish(), limits):U(), 0, "a reader with the limits refuses it")
    end)

    test("counts and restores", function()
        local w = Codec.Writer():U(9)
        local mark = w:Mark()
        w:Bytes("nope"):U(300)
        eq(w:Len(), 8, "len")
        w:Restore(mark)
        eq(w:Len(), 1, "len after restore")
        w:U(1)
        eq(w:Finish(), "\9\1", "written after restore")
    end)
end)

--------------------------------------------------------------------------------

suite("The reader", function()
    test("reads every field the writer writes", function()
        local w = Codec.Writer():U(5):I(-300):True():False():Bytes("hi")
        w:U8(255):I8(-1):U16(513):I16(-2):U32(4294967295):I32(-5):U64(9007199254740992):I64(-9007199254740992)
        local r = Codec.Reader(w:Finish())
        eq(r:U(), 5, "U")
        eq(r:I(), -300, "I")
        eq(r:Bool(), true, "true")
        eq(r:Bool(), false, "false")
        eq(r:Bytes(), "hi", "bytes")
        eq(r:U8(), 255, "u8")
        eq(r:I8(), -1, "i8")
        eq(r:U16(), 513, "u16")
        eq(r:I16(), -2, "i16")
        eq(r:U32(), 4294967295, "u32")
        eq(r:I32(), -5, "i32")
        eq(r:U64(), 9007199254740992, "u64")
        eq(r:I64(), -9007199254740992, "i64")
        eq(r:Ok(), true, "ok")
        eq(r:More(), false, "consumed")
    end)

    test("reads as zero and not ok past the end, and stays not ok", function()
        local r = Codec.Reader("\5")
        eq(r:U(), 5, "the one field")
        eq(r:Bytes(), "", "a string past the end")
        eq(r:Ok(), false, "not ok")
        eq(r:U(), 0, "later reads are 0")
        eq(Codec.Reader("\3ab"):Bytes(), "", "a string longer than what is left")
    end)

    test("refuses an overlong varint and one with too many groups", function()
        local r = Codec.Reader("\128\0")
        eq(r:U(), 0, "overlong zero")
        eq(r:Ok(), false, "overlong is not ok")
        r = Codec.Reader(string.rep("\255", 8) .. "\1")
        eq(r:U(), 0, "nine groups")
        eq(r:Ok(), false, "nine groups is not ok")
    end)

    test("says what is left, takes the rest, and can be failed", function()
        local r = Codec.Reader("\1abc")
        eq(r:U(), 1, "first")
        eq(r:Left(), 3, "three bytes left")
        eq(r:Rest(), "abc", "the rest")
        eq(r:More(), false, "nothing more")
        r:Fail()
        eq(r:Ok(), false, "failed")
        eq(r:Left(), 0, "a failed reader has nothing left")
    end)
end)

--------------------------------------------------------------------------------

suite("Base64url", function()
    -- RFC 4648 section 10, with the padding taken off.
    local vectors = { { "", "" }, { "f", "Zg" }, { "fo", "Zm8" }, { "foo", "Zm9v" }, { "foob", "Zm9vYg" },
        { "fooba", "Zm9vYmE" }, { "foobar", "Zm9vYmFy" } }

    test("encodes the RFC 4648 vectors, unpadded", function()
        for _, v in ipairs(vectors) do eq(Codec.ToBase64(v[1]), v[2], ("%q"):format(v[1])) end
    end)

    test("decodes them back", function()
        for _, v in ipairs(vectors) do eq(Codec.FromBase64(v[2]), v[1], v[2]) end
    end)

    test("uses - and _ where base64 has + and /", function()
        eq(Codec.ToBase64("\251\255"), "-_8", "fb ff")
        eq(Codec.FromBase64("-_8"), "\251\255", "and back")
    end)

    test("round trips every byte value and every length", function()
        local all = {}
        for i = 0, 255 do all[#all + 1] = string.char(i) end
        all = table.concat(all)
        for n = 0, 70 do
            local s = all:sub(1, n)
            eq(Codec.FromBase64(Codec.ToBase64(s)), s, "length " .. n)
        end
        eq(Codec.FromBase64(Codec.ToBase64(all .. all)), all .. all, "512 bytes")
    end)

    test("ignores whitespace", function()
        eq(Codec.FromBase64(" Zm9v\nYmFy\r\n "), "foobar", "wrapped text")
    end)

    test("refuses what is not canonical base64url", function()
        eq(Codec.FromBase64("Zm9v+"), nil, "a + is base64, not base64url")
        eq(Codec.FromBase64("Zg=="), nil, "padding")
        eq(Codec.FromBase64("Z"), nil, "one character left over")
        eq(Codec.FromBase64("Zh"), nil, "stray bits in the last character")
        eq(Codec.FromBase64("Zm9"), nil, "stray bits in the last of three")
        eq(Codec.FromBase64(nil), nil, "not a string")
    end)
end)

--------------------------------------------------------------------------------

suite("Adler-32", function()
    test("matches known checksums", function()
        eq(Codec.Adler32(""), 1, "empty")
        eq(Codec.Adler32("a"), 0x00620062, "a")
        eq(Codec.Adler32("abc"), 0x024D0127, "abc")
        eq(Codec.Adler32("Wikipedia"), 0x11E60398, "Wikipedia")
    end)

    test("stays exact over long input", function()
        -- 100000 bytes of 0xFF, worked out the slow way.
        local a, b = 1, 0
        for _ = 1, 100000 do
            a = (a + 255) % 65521
            b = (b + a) % 65521
        end
        eq(Codec.Adler32(string.rep("\255", 100000)), b * 65536 + a, "100000 x FF")
    end)
end)

--------------------------------------------------------------------------------

suite("Shared strings", function()
    test("are nuu: and base64url of version, schema, body and checksum", function()
        local text = Codec.ToText(1, "body")
        ok(text:sub(1, 4) == "nuu:", "prefix")
        local bytes = Codec.FromBase64(text:sub(5))
        eq(bytes:sub(1, 6), "\1\1body", "version, schema, body")
        eq(Codec.Reader(bytes:sub(7)):U32(), Codec.Adler32("\1\1body"), "the checksum covers the rest")
    end)

    test("read back to their schema and body", function()
        local schema, body = Codec.FromText(Codec.ToText(300, "a\0b"))
        eq(schema, 300, "schema")
        eq(body, "a\0b", "body")
        schema, body = Codec.FromText(Codec.ToText(2, ""))
        eq(schema, 2, "empty body: schema")
        eq(body, "", "empty body")
    end)

    test("are recognised with whitespace around and inside", function()
        local text = Codec.ToText(1, string.rep("guide ", 20))
        local wrapped = "  " .. text:sub(1, 30) .. "\n" .. text:sub(31) .. "\n"
        ok(Codec.IsText(wrapped), "IsText")
        eq(select(2, Codec.FromText(wrapped)), string.rep("guide ", 20), "wrapped text reads")
    end)

    test("refuse text that is not one, or was damaged", function()
        local text = Codec.ToText(1, "body")
        eq(Codec.IsText("{ kind = \"guide\" }"), false, "Lua text is not a shared string")
        local value, problem = Codec.FromText("hello")
        ok(value == nil and problem:find("not a shared string", 1, true), "not one: " .. tostring(problem))
        value, problem = Codec.FromText(text:sub(1, -3))
        ok(value == nil and problem:find("damaged", 1, true), "cut short: " .. tostring(problem))
        local changed = text:sub(1, 8) .. (text:sub(9, 9) == "A" and "B" or "A") .. text:sub(10)
        value, problem = Codec.FromText(changed)
        ok(value == nil and problem:find("damaged", 1, true), "one character changed: " .. tostring(problem))
        value, problem = Codec.FromText("nuu:!!")
        ok(value == nil and problem:find("damaged", 1, true), "not base64: " .. tostring(problem))
    end)

    test("refuse a container version this kit does not know", function()
        local head = "\2\1body"
        local text = "nuu:" .. Codec.ToBase64(head .. Codec.Writer():U32(Codec.Adler32(head)):Finish())
        local value, problem = Codec.FromText(text)
        ok(value == nil and problem:find("newer version", 1, true), "version 2: " .. tostring(problem))
    end)
end)

print("NuuKit codec tests passed (" .. W.count .. " tests)")
return true
