"""The client's DB2 tables (WDC3 to WDC5), read row by row.

Columns come from the community WoWDBDefs definitions (a .dbd per table,
matched by the table's layout hash), cached in .cache/dbd/. Handled: tables
with fixed-size records, and variable-size records with an offset map (such as
ItemSparse, whose strings are inline); plain, bitpacked, common-data and pallet
columns; the id list, copy table and relationship data. Encrypted sections the
client has no key for are skipped, including ones the file leaves out entirely.
Written after the layout wow.export's WDCReader reads.
"""

import os
import re
import struct
import urllib.request

from casc import CACHE

DBD_URL = "https://raw.githubusercontent.com/wowdev/WoWDBDefs/master/definitions/%s.dbd"
NONE, BITPACKED, COMMON, PALLET, PALLET_ARRAY, BITPACKED_SIGNED = range(6)


def definition(table):
    """The table's .dbd text, downloaded once."""
    folder = os.path.join(CACHE, "dbd")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, table + ".dbd")
    if not os.path.exists(path):
        with urllib.request.urlopen(DBD_URL % table) as response, open(path, "wb") as out:
            out.write(response.read())
    return open(path, encoding="utf-8").read()


def layout(table, layout_hash):
    """[(name, type, array length, noninline id, relation)] for a layout.

    The COLUMNS block gives each column's type (int, float, string,
    locstring); a LAYOUT block lists the columns in record order."""
    text = definition(table)
    types = {}
    columns, _, rest = text.partition("\n\n")
    for line in columns.splitlines()[1:]:
        match = re.match(r"(\w+)(?:<[^>]*>)?\s+(\w+)", line.strip())
        if match:
            types[match.group(2).rstrip("?")] = match.group(1)
    for block in text.split("\n\n"):
        lines = [line.strip() for line in block.strip().splitlines()]
        heads = [line for line in lines if line.startswith("LAYOUT")]
        if not any(layout_hash.upper() in head.upper() for head in heads):
            continue
        fields = []
        for line in lines:
            if line.startswith(("LAYOUT", "BUILD", "COMMENT")) or not line:
                continue
            line = line.split("//")[0].strip()
            match = re.match(r"(\$[^$]*\$)?(\w+)(?:<(u?)(\d+)>)?(?:\[(\d+)\])?", line)
            if not match:
                continue
            flags, name = match.group(1) or "", match.group(2)
            fields.append({"name": name, "type": types.get(name, "int"),
                           "unsigned": match.group(3) == "u", "bits": int(match.group(4) or 32),
                           "count": int(match.group(5) or 1),
                           "noninline": "noninline" in flags, "relation": "relation" in flags,
                           "id": "id" in flags.replace("noninline", "")})
        return fields
    raise ValueError("%s: no layout %s in its definition" % (table, layout_hash))


def read(storage, table):
    """Every row of dbfilesclient/<table>.db2 as a dict by column name."""
    data = storage.read_path("dbfilesclient/%s.db2" % table.lower())
    if data is None:
        raise OSError("%s.db2 is not in the store" % table)
    magic = data[:4]
    if magic not in (b"WDC3", b"WDC4", b"WDC5"):
        raise ValueError("%s: %r is not a table format this reads" % (table, magic))
    version = int(magic[3:4])
    offset = 4 + (132 if version == 5 else 0)
    (record_count, field_count, record_size, string_size, table_hash, layout_hash, min_id, max_id, locale,
     flags, id_index, total_fields, bitpacked_offset, lookup_columns, storage_size, common_size, pallet_size,
     section_count) = struct.unpack_from("<9I2H7I", data, offset)
    sparse = bool(flags & 1)
    offset += 68
    sections = []
    for _ in range(section_count):
        (tact, file_offset, count, strings, records_end, id_list, relations, offset_map, copies) = \
            struct.unpack_from("<Q8I", data, offset)
        sections.append({"tact": tact, "at": file_offset, "records": count, "strings": strings,
                         "records_end": records_end, "ids": id_list, "relations": relations,
                         "offset_map": offset_map, "copies": copies})
        offset += 40
    offset += 4 * total_fields  # field_structure: size and position, also in the storage info
    info = []
    for _ in range(storage_size // 24):
        bit_offset, bit_size, extra, compression, a, b, c = struct.unpack_from("<2H5I", data, offset)
        info.append({"offset": bit_offset, "size": bit_size, "extra": extra, "compression": compression,
                     "packing": (a, b, c)})
        offset += 24
    pallets = []
    for field in info:
        if field["compression"] in (PALLET, PALLET_ARRAY):
            pallets.append(struct.unpack_from("<%dI" % (field["extra"] // 4), data, offset))
            offset += field["extra"]
        else:
            pallets.append(None)
    commons = []
    for field in info:
        if field["compression"] == COMMON:
            pairs = struct.unpack_from("<%dI" % (field["extra"] // 4), data, offset)
            commons.append(dict(zip(pairs[0::2], pairs[1::2])))
            offset += field["extra"]
        else:
            commons.append(None)
    if version > 3:
        # Encrypted-record id lists, one per encrypted section.
        for _ in range(sum(1 for section in sections if section["tact"])):
            n = struct.unpack_from("<I", data, offset)[0]
            offset += 4 + 4 * n
    fields = layout(table, "%08X" % layout_hash)
    # A relation column is sometimes stored in the record as well as in the
    # relationship data: then it has storage info like any other column.
    inline_relation = len(info) == sum(1 for f in fields if not f["noninline"])
    # (A $noninline,relation$ column is only ever in the relationship data.)
    stored = [f for f in fields
              if not f["noninline"] and not (f["relation"] and not inline_relation)]
    rows = []
    string_base = 0
    prev_records = 0
    for section in sections:
        # A string column holds the distance from itself to its string, as if
        # every section's records came first and every string block after
        # them: `shift` takes that back to this section's own layout.
        shift = (record_count - prev_records - section["records"]) * record_size + string_base
        prev_records += section["records"]
        if section["at"] >= len(data):
            # An encrypted section the file leaves out altogether.
            string_base += section["strings"]
            continue
        records_at = offset
        if sparse:
            strings_at = section["records_end"]
            offset = strings_at
        else:
            strings_at = records_at + record_size * section["records"]
            offset = strings_at + section["strings"]
        ids = struct.unpack_from("<%dI" % (section["ids"] // 4), data, offset)
        offset += section["ids"]
        copies = [struct.unpack_from("<2i", data, offset + 8 * i) for i in range(section["copies"])]
        offset += 8 * section["copies"]
        spans = [struct.unpack_from("<IH", data, offset + 6 * i) for i in range(section["offset_map"])]
        offset += 6 * section["offset_map"]
        relations = {}
        if section["relations"]:
            n = struct.unpack_from("<I", data, offset)[0]
            for i in range(n):
                foreign, index = struct.unpack_from("<2I", data, offset + 12 + 8 * i)
                relations[index] = foreign
            offset += section["relations"]
        offset += 4 * section["offset_map"]
        if section["tact"] and not any(data[records_at:strings_at]):
            string_base += section["strings"]
            continue  # an encrypted section this client has no key for
        by_id = {}
        if sparse:
            for r, (at, size) in enumerate(spans):
                if not size:
                    continue
                row = read_sparse(data, at, fields, relations, r, inline_relation)
                row["ID"] = ids[r] if ids else row.get("ID")
                rows.append(row)
                by_id[row["ID"]] = row
            for dest, source in copies:
                if source in by_id:
                    rows.append(dict(by_id[source], ID=dest))
            continue
        for r in range(section["records"]):
            base = records_at + r * record_size
            # Common-data columns are looked up by record ID, so a table with
            # the ID in the record (no id list) needs that column first.
            if ids:
                record_id = ids[r]
            else:
                record_id = decode(data, base, info[id_index], stored[id_index], pallets[id_index],
                                   commons[id_index], None, shift)
            row, column = {}, 0
            for field in fields:
                if field["relation"] and (field["noninline"] or not inline_relation):
                    row[field["name"]] = relations.get(r, 0)
                    continue
                if field["noninline"]:
                    row[field["name"]] = ids[r] if ids else None
                    continue
                spec = info[column]
                values = decode(data, base, spec, field, pallets[column], commons[column], record_id, shift)
                row[field["name"]] = values
                if not ids and column == id_index:
                    row.setdefault("ID", values)
                column += 1
            if ids:
                row.setdefault("ID", ids[r])
            rows.append(row)
            by_id[row.get("ID")] = row
        for dest, source in copies:
            if source in by_id:
                rows.append(dict(by_id[source], ID=dest))
        string_base += section["strings"]
    return rows


def read_sparse(data, at, fields, relations, index, inline_relation):
    """One variable-size record: its columns one after another at their
    full width, strings inline and zero-terminated, nothing packed."""
    row = {}
    for field in fields:
        if field["relation"] and (field["noninline"] or not inline_relation):
            row[field["name"]] = relations.get(index, 0)
            continue
        if field["noninline"]:
            continue
        out = []
        for _ in range(field["count"]):
            if field["type"] in ("string", "locstring"):
                end = data.index(b"\0", at)
                out.append(data[at:end].decode("utf-8", "replace"))
                at = end + 1
                continue
            if field["type"] == "float":
                fmt = "f"
            else:
                fmt = {8: "b", 16: "h", 32: "i", 64: "q"}[field["bits"]]
                if field["unsigned"]:
                    fmt = fmt.upper()
            out.append(struct.unpack_from("<" + fmt, data, at)[0])
            at += struct.calcsize(fmt)
        row[field["name"]] = out if field["count"] > 1 else out[0]
    return row


def decode(data, base, spec, field, pallet, common, record_id, shift):
    """One column of one record."""
    count, kind = field["count"], field["type"]
    compression = spec["compression"]
    if compression == NONE:
        at = base + spec["offset"] // 8
        if kind in ("string", "locstring"):
            out = []
            for i in range(count):
                pos = at + 4 * i
                ref = struct.unpack_from("<I", data, pos)[0]
                out.append(read_string(data, pos + ref - shift) if ref else "")
            return out if count > 1 else out[0]
        if kind == "float":
            fmt = "f"
        else:
            fmt = {8: "b", 16: "h", 32: "i", 64: "q"}[field["bits"]]
            if field["unsigned"]:
                fmt = fmt.upper()
        size = struct.calcsize(fmt)
        out = list(struct.unpack_from("<%d%s" % (count, fmt), data, at))
        return out if count > 1 else out[0]
    if compression == COMMON:
        raw = common.get(record_id, spec["packing"][0])
        return cast(raw, field)
    at = base + spec["offset"] // 8
    chunk = data[at:at + 8].ljust(8, b"\0")
    raw = (struct.unpack("<Q", chunk)[0] >> (spec["offset"] & 7)) & ((1 << spec["size"]) - 1)
    if compression == PALLET_ARRAY:
        n = spec["packing"][2]
        return [cast(pallet[raw * n + i], field) for i in range(n)]
    if compression == PALLET:
        return cast(pallet[raw], field)
    if compression == BITPACKED_SIGNED and raw >> (spec["size"] - 1):
        raw -= 1 << spec["size"]
    return cast(raw, field)


def cast(raw, field):
    """A 32-bit pattern read as the column's type."""
    if field["type"] == "float":
        return struct.unpack("<f", struct.pack("<I", raw & 0xFFFFFFFF))[0]
    if not field["unsigned"] and field["bits"] == 32 and raw >= 1 << 31:
        return raw - (1 << 32)
    return raw


def read_string(data, at):
    end = data.index(b"\0", at)
    return data[at:end].decode("utf-8", "replace")
