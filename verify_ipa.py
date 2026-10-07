#!/usr/bin/env python3
"""Verify the produced Erosion IPA is a real, self-installable iOS app bundle.

Checks:
  - zip integrity + Payload/Erosion.app present
  - Mach-O header (magic / cputype / cpusubtype) of the main executable
  - Info.plist: bundle id, min OS, platform, device family
  - the bad_query symbols (from bad_query.c) actually got linked in
  - SwiftUI / embedded frameworks presence
  - rough size sanity (should be multiple MB, not a 1.8 KB shell)
"""
import io
import os
import struct
import sys
import zipfile

IPA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dist", "Erosion.ipa")


def macho_info(data):
    """Return (magic, cputype, cpusubtype) for a Mach-O blob, or None."""
    if len(data) < 8:
        return None
    magic = struct.unpack("<I", data[:4])[0]
    known = {
        0xFEEDFACF: ("MH_MAGIC_64", "<"),      # 64-bit, little endian
        0xFEEDFACE: ("MH_MAGIC", "<"),         # 32-bit, little endian
        0xCFFAEDFE: ("MH_CIGAM_64", ">"),      # 64-bit, big endian (byteswapped view)
        0xCEFAEDFE: ("MH_CIGAM", ">"),         # 32-bit
    }
    if magic not in known:
        return None
    name, _ = known[magic]
    if name.endswith("64"):
        cputype, cpusubtype = struct.unpack("<ii", data[4:12])
        return (name, cputype, cpusubtype)
    cputype, cpusubtype = struct.unpack("<ii", data[4:12])
    return (name, cputype, cpusubtype)


def main():
    if not os.path.exists(IPA):
        print(f"FAIL: {IPA} does not exist")
        return 1
    size = os.path.getsize(IPA)
    print(f"IPA: {IPA}")
    print(f"size: {size} bytes ({size/1048576:.2f} MB)")
    ok = True

    if size < 1_000_000:
        print("FAIL: suspiciously small (empty-shell symptom)")
        ok = False

    with zipfile.ZipFile(IPA) as z:
        names = z.namelist()
        print(f"entries: {len(names)}")

        app = "Payload/Erosion.app/"
        if not any(n.startswith(app) for n in names):
            print(f"FAIL: no {app} in archive")
            return 1

        exe = app + "Erosion"
        if exe not in names:
            print(f"FAIL: no {exe} (main executable) in archive")
            return 1

        data = z.read(exe)
        print(f"executable size: {len(data)} bytes")
        info = macho_info(data[:32])
        if not info:
            print("FAIL: main executable is not a Mach-O")
            return 1
        name, cputype, cpusubtype = info
        print(f"mach-o: {name} cputype=0x{cputype & 0xFFFFFFFF:08x} cpusubtype=0x{cpusubtype & 0xFFFFFFFF:08x}")
        if cputype == 0x0100000C:
            print("  -> ARM64 (good for sideloading)")
        elif cputype == 0x0100000C | 0x02000000:
            print("  -> ARM64e (pointer-auth; harder to sideload, but works on TrollStore)")
        if cpusubtype & 0x00000002:
            print("  note: arm64e ABI flag set (PURE/ABI)")

        # bad_query symbols (from bad_query.c) should be linked in
        blob = data
        for sym in (b"bad_query", b"sandbox_extension_consume", b"container_query"):
            hit = sym in blob
            print(f"symbol {sym.decode():32s}: {'present' if hit else 'MISSING'}")
            if sym == b"bad_query" and not hit:
                ok = False

        # Info.plist
        plist_path = app + "Info.plist"
        if plist_path in names:
            raw = z.read(plist_path)
            txt = raw.decode("utf-8", "replace")
            for key in ("CFBundleIdentifier", "MinimumOSVersion", "DTPlatformName",
                        "CFBundleExecutable", "CFBundleShortVersionString"):
                if key in txt:
                    idx = txt.find(key)
                    frag = txt[idx:idx + 160]
                    v = frag.split("<string>", 1)
                    val = v[1].split("</string>", 1)[0] if len(v) > 1 else "?"
                    print(f"{key}: {val}")
                else:
                    print(f"{key}: (absent)")
                    if key in ("CFBundleIdentifier", "MinimumOSVersion"):
                        ok = False
        else:
            print("FAIL: no Info.plist in app bundle")
            ok = False

        # embedded frameworks + signature structure
        fw = [n for n in names if n.startswith(app + "Frameworks/") and n.endswith(".framework/")]
        print(f"embedded frameworks: {len(fw)}")
        for f in sorted(fw)[:10]:
            print("   -", f.rstrip("/"))
        if z.NameToInfo.get(app + "_CodeSignature/CodeResources"):
            print("_CodeSignature/CodeResources: present (re-signable)")
        else:
            print("_CodeSignature/CodeResources: ABSENT")

        # asset catalog
        if app + "Assets.car" in names:
            print("Assets.car: present")
        else:
            print("Assets.car: absent")

    print()
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
