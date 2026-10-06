-- Core/Codec: the plain writer and reader, base64url, Adler-32, DEFLATE and
-- the shared-string form around them. The comms frame on top of the same writer
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
        local n, len = w:Mark()
        w:Bytes("nope"):U(300)
        eq(w:Len(), 8, "len")
        w:Restore(n, len)
        eq(w:Len(), 1, "len after restore")
        w:U(1)
        eq(w:Finish(), "\9\1", "written after restore")
    end)

    test("restores nested marks, inner then outer", function()
        local w = Codec.Writer():U(1)
        local n1, l1 = w:Mark()
        w:U(2)
        local n2, l2 = w:Mark()
        w:Bytes("abc")
        w:Restore(n2, l2)
        eq(w:Finish(), "\1\2", "inner")
        w:U(3)
        w:Restore(n1, l1)
        eq(w:Len(), 1, "outer len")
        eq(w:U(4):Finish(), "\1\4", "outer")
    end)

    test("refuses a restore with no mark", function()
        local w = Codec.Writer():U(1)
        errors(function() w:Restore() end, "nothing")
        errors(function() w:Restore(1) end, "half a mark")
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

    test("agrees with the slow way at every length around a step and a chunk", function()
        local bytes, x = {}, 7
        for i = 1, 8300 do
            x = (x * 1103515245 + 12345) % 2147483648
            bytes[i] = string.char(x % 256)
        end
        local s = table.concat(bytes)
        for _, n in ipairs({ 1, 15, 16, 17, 31, 32, 33, 4095, 4096, 4097, 4111, 4112, 4113, 8192, 8300 }) do
            local a, b = 1, 0
            for i = 1, n do
                a = (a + s:byte(i)) % 65521
                b = (b + a) % 65521
            end
            eq(Codec.Adler32(s:sub(1, n)), b * 65536 + a, n .. " bytes")
        end
    end)
end)

--------------------------------------------------------------------------------

suite("DEFLATE", function()
    -- Bytes that do not repeat: a linear congruential generator.
    local function noise(n, seed)
        local out, x = {}, seed
        for i = 1, n do
            x = (x * 1103515245 + 12345) % 2147483648
            out[i] = string.char(math.floor(x / 65536) % 256)
        end
        return table.concat(out)
    end

    test("round trips empty, short, repeating, random and long input", function()
        local all = {}
        for i = 0, 255 do all[#all + 1] = string.char(i) end
        local cases = {
            "", "a", "ab", "abc", table.concat(all), string.rep("a", 1000), string.rep("abc", 5000),
            noise(5000, 7), noise(70000, 3) .. string.rep("guide ", 20000),
        }
        for i, input in ipairs(cases) do
            local packed = Codec.Deflate(input)
            local back, problem = Codec.Inflate(packed)
            ok(back == input, ("case %d (%d bytes) comes back: %s"):format(i, #input, tostring(problem)))
        end
    end)

    test("stores what does not compress, at a few bytes' cost", function()
        local input = noise(4000, 11)
        local packed = Codec.Deflate(input)
        ok(#packed <= #input + 10, "random bytes: " .. #packed .. " for " .. #input)
    end)

    test("inflates what zlib wrote, compressed and stored", function()
        local zlib = "\243\206\204\201\81\176\80\240\206\79\202\207\73\81\8\75\45\202\205\204\211\83\240"
            .. "\30\21\29\228\162\33\165\69\121\10\153\121\10\137\37\10\174\137\233\137\121\10\1\169\57"
            .. "\37\197\217\153\121\121\169\69\122\0"
        eq(Codec.Inflate(zlib), string.rep("Kill 8 Kobold Vermin. ", 20) .. "Turn in at Eagan Peltskinner.", "level 9")
        eq(Codec.Inflate("\1\12\0\243\255stored bytes"), "stored bytes", "a stored block")
    end)

    test("refuses a stream that is damaged, cut short, too long or too big", function()
        local packed = Codec.Deflate(string.rep("Turn in at Eagan Peltskinner. ", 30))
        local value, problem = Codec.Inflate(packed:sub(1, -3))
        ok(value == nil and problem == "damaged", "cut short: " .. tostring(problem))
        value, problem = Codec.Inflate(packed .. "x")
        ok(value == nil and problem == "bytes after the end", "a byte after: " .. tostring(problem))
        value, problem = Codec.Inflate("\7")
        ok(value == nil and problem == "damaged", "block type 3: " .. tostring(problem))
        value, problem = Codec.Inflate("")
        ok(value == nil and problem == "damaged", "nothing: " .. tostring(problem))
        value, problem = Codec.Inflate(packed, 100)
        ok(value == nil and problem == "too big", "past maxSize: " .. tostring(problem))
        value, problem = Codec.Inflate("\1\12\0\243\255stored bytes", 5)
        ok(value == nil and problem == "too big", "a stored block past maxSize: " .. tostring(problem))
    end)

    test("never raises on damaged input", function()
        local packed = Codec.Deflate(noise(300, 5) .. string.rep("Kobold ", 200))
        for i = 1, #packed do
            local damaged = packed:sub(1, i - 1) .. string.char((packed:byte(i) + 37) % 256) .. packed:sub(i + 1)
            local okCall = pcall(Codec.Inflate, damaged)
            ok(okCall, "byte " .. i .. " changed")
        end
    end)
end)

--------------------------------------------------------------------------------

suite("Shared strings", function()
    test("are nuu: and base64url of version, schema, deflated body and checksum", function()
        local text = Codec.ToText(1, "body")
        ok(text:sub(1, 4) == "nuu:", "prefix")
        local bytes = Codec.FromBase64(text:sub(5))
        local head = "\1\1" .. Codec.Deflate("body")
        eq(bytes:sub(1, -5), head, "version, schema, deflated body")
        eq(Codec.Reader(bytes:sub(-4)):U32(), Codec.Adler32(head), "the checksum covers the rest")
    end)

    test("are shorter than their body when it repeats", function()
        local body = string.rep("Kill 8 Kobold Vermin. ", 40)
        local text = Codec.ToText(1, body)
        ok(#text < #body / 4, "compressed: " .. #text .. " characters for " .. #body .. " bytes")
        eq(select(2, Codec.FromText(text)), body, "and read back")
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

    test("refuse a body that inflates past the limit", function()
        local head = "\1\1" .. Codec.Deflate(string.rep("x", Codec.TEXT_MAX_BODY + 1))
        local text = "nuu:" .. Codec.ToBase64(head .. Codec.Writer():U32(Codec.Adler32(head)):Finish())
        local value, problem = Codec.FromText(text)
        ok(value == nil and problem:find("more than this version reads", 1, true), "too big: " .. tostring(problem))
    end)

    test("refuse a body that is not DEFLATE, though its checksum holds", function()
        local head = "\1\1\255\255\255"
        local text = "nuu:" .. Codec.ToBase64(head .. Codec.Writer():U32(Codec.Adler32(head)):Finish())
        local value, problem = Codec.FromText(text)
        ok(value == nil and problem:find("damaged", 1, true), "not deflate: " .. tostring(problem))
    end)

    test("refuse a container version this kit does not know", function()
        local head = "\2\1body"
        local text = "nuu:" .. Codec.ToBase64(head .. Codec.Writer():U32(Codec.Adler32(head)):Finish())
        local value, problem = Codec.FromText(text)
        ok(value == nil and problem:find("newer version", 1, true), "version 2: " .. tostring(problem))
    end)

    test("never raise on a string cut short or changed anywhere", function()
        local body = string.rep("kill ten boars, then return. ", 20)
        local text = Codec.ToText(3, body)
        local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        for cut = 0, #text - 1 do
            local good, value, problem = pcall(Codec.FromText, text:sub(1, cut))
            ok(good, "cut at " .. cut .. " raised: " .. tostring(value))
            ok(value == nil and type(problem) == "string", "cut at " .. cut .. " is refused")
        end
        for at = 5, #text do
            local c = text:sub(at, at)
            local i = alphabet:find(c, 1, true)
            local other = alphabet:sub(i % 64 + 1, i % 64 + 1)
            local changed = text:sub(1, at - 1) .. other .. text:sub(at + 1)
            local good, value, problem = pcall(Codec.FromText, changed)
            ok(good, "change at " .. at .. " raised: " .. tostring(value))
            ok(value == nil and type(problem) == "string", "change at " .. at .. " is refused")
        end
    end)

    test("read the largest schema number and an empty body", function()
        local text = Codec.ToText(268435455, "")
        local schema, body = Codec.FromText(text)
        eq(schema, 268435455, "schema")
        eq(body, "", "body")
    end)

    test("refuse what is not text at all", function()
        for _, value in ipairs({ 1, true, {}, "", "nuu", "nuu:", " nuu: ", "NUU:abc" }) do
            local good, schema, problem = pcall(Codec.FromText, value)
            ok(good and schema == nil and type(problem) == "string", "refused: " .. tostring(value))
        end
        eq(Codec.IsText(nil), false, "nil is not text")
    end)

    test("call an older container version damaged, not newer", function()
        local head = "\0\1body"
        local text = "nuu:" .. Codec.ToBase64(head .. Codec.Writer():U32(Codec.Adler32(head)):Finish())
        local value, problem = Codec.FromText(text)
        ok(value == nil and problem:find("damaged", 1, true), "version 0: " .. tostring(problem))
    end)
end)

print("NuuKit codec tests passed (" .. W.count .. " tests)")
return true
