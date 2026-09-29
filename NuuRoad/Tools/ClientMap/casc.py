"""The client's CASC data store, read through CascLib, file by file ID.

The Forever beta shares one store with every other installed WoW product
(`World of Warcraft/Data`), so the product name picks the build. Paths come
from the community listfile; the store itself only knows file IDs.
"""

import ctypes as C
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")
# The addon lives in <root>/_classic_beta_/Interface/Nuu/NuuRoad.
WOW_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "..", ".."))
PRODUCT = "wow_classic_beta"

CASC_OPEN_BY_FILEID = 3
ERROR_HANDLE_EOF = 1005  # CascLib's "read to the end", not a failure


def _lib():
    path = os.path.join(CACHE, "libcasc.so")
    if not os.path.exists(path):
        raise SystemExit("CascLib is not built: run Tools/ClientMap/setup.sh (see Tools/ClientMap/README.md)")
    lib = C.CDLL(path)
    lib.CascOpenStorage.argtypes = [C.c_char_p, C.c_uint32, C.POINTER(C.c_void_p)]
    lib.CascOpenFile.argtypes = [C.c_void_p, C.c_void_p, C.c_uint32, C.c_uint32, C.POINTER(C.c_void_p)]
    lib.CascReadFile.argtypes = [C.c_void_p, C.c_void_p, C.c_uint32, C.POINTER(C.c_uint32)]
    lib.CascCloseFile.argtypes = [C.c_void_p]
    lib.GetCascError.restype = C.c_uint32
    return lib


class Storage:
    def __init__(self, product=PRODUCT, root=WOW_ROOT):
        self.lib = _lib()
        self.handle = C.c_void_p()
        if not self.lib.CascOpenStorage((root + "*" + product).encode(), 0, C.byref(self.handle)):
            raise OSError("cannot open the CASC store %s*%s (error %d)" % (root, product, self.lib.GetCascError()))
        self._names = None
        self._ids = None

    def read(self, file_id):
        """The file's bytes, or None when the store does not have it."""
        lib = self.lib
        handle = C.c_void_p()
        if not lib.CascOpenFile(self.handle, C.c_void_p(file_id), 0, CASC_OPEN_BY_FILEID, C.byref(handle)):
            return None
        out = bytearray()
        buf = C.create_string_buffer(1 << 20)
        got = C.c_uint32()
        try:
            while True:
                if not lib.CascReadFile(handle, buf, len(buf), C.byref(got)):
                    if lib.GetCascError() != ERROR_HANDLE_EOF:
                        return None
                    out += buf.raw[:got.value]
                    break
                if got.value == 0:
                    break
                out += buf.raw[:got.value]
        finally:
            lib.CascCloseFile(handle)
        return bytes(out)

    def _listfile(self):
        if self._names is None:
            path = os.path.join(CACHE, "listfile.csv")
            names, ids = {}, {}
            with open(path, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    number, _, name = line.rstrip("\n").partition(";")
                    if number.isdigit():
                        names[int(number)] = name
                        ids[name.lower()] = int(number)
            self._names, self._ids = names, ids
        return self._names, self._ids

    def name(self, file_id):
        return self._listfile()[0].get(file_id)

    def file_id(self, path):
        return self._listfile()[1].get(path.lower().replace("\\", "/"))

    def read_picture(self, file_id):
        """A texture's bytes. The Forever beta does not keep every texture on
        disk (it fetches some when first drawn), so a texture it lacks is
        taken from the other products in the same store (Classic Era,
        Anniversary, retail), where the same file ID is the same picture.
        Only for pictures: models can differ between builds."""
        data = self.read(file_id)
        if data is not None:
            return data
        if not hasattr(self, "_others"):
            self._others = []
            for product in ("wow_classic_era", "wow_anniversary", "wow"):
                try:
                    self._others.append(Storage(product))
                except OSError:
                    pass
        for other in self._others:
            data = other.read(file_id)
            if data is not None:
                return data
        return None

    def read_path(self, path):
        file_id = self.file_id(path)
        return None if file_id is None else self.read(file_id)
