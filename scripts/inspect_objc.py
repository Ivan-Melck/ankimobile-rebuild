#!/usr/bin/env python3
"""Supplemental byte inspection for this arm64 Mach-O (not canonical REA evidence).
Reads DYLD_CHAINED_PTR_64_OFFSET rebases and Objective-C relative method lists.
Does not execute or modify the binary. Output stays in ignored local evidence.
"""
import argparse, json, pathlib, struct
parser = argparse.ArgumentParser()
parser.add_argument('binary', type=pathlib.Path)
args = parser.parse_args()
data = args.binary.read_bytes()
u32 = lambda o: struct.unpack_from('<I', data, o)[0]
u64 = lambda o: struct.unpack_from('<Q', data, o)[0]
s32 = lambda o: struct.unpack_from('<i', data, o)[0]
assert u32(0) == 0xfeedfacf and u32(4) == 0x100000c, "Expected a 64-bit arm64 Mach-O"
segments, sections = [], []
o = 32
for _ in range(u32(16)):
    cmd, size = struct.unpack_from('<II', data, o)
    if cmd == 0x19:
        name = data[o+8:o+24].rstrip(b'\0').decode()
        vm, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', data, o+24)
        segments.append((name, vm, vmsize, fileoff, filesize))
        for i in range(u32(o+64)):
            p = o+72+i*80
            name = data[p:p+16].rstrip(b'\0').decode()
            address, length = struct.unpack_from('<QQ', data, p+32)
            sections.append((name, address, length))
    o += size
base = next(s[1] for s in segments if s[0] == '__TEXT')
def offset(address):
    for _, vm, _, fileoff, filesize in segments:
        if vm <= address < vm+filesize: return fileoff+address-vm
    raise ValueError(f'Unmapped {address:x}')
def ptr(address):
    v = u64(offset(address))
    if v == 0: return 0
    try:
        offset(v); return v
    except ValueError: pass
    if v >> 63: raise ValueError('Bound import pointer')
    return base + (v & ((1<<36)-1))
def string(address):
    o = offset(address); end = data.index(b'\0', o)
    return data[o:end].decode('utf-8', errors='replace')
classes = []
for name, address, length in sections:
    if name != '__objc_classlist': continue
    for slot in range(address, address+length, 8):
        try:
            cls = ptr(slot)
            ro = ptr(cls+32) & ~7
            name = string(ptr(ro+24))
            methods = []
            table = ptr(ro+32)
            if table:
                header, count = struct.unpack_from('<II', data, offset(table))
                stride = header & 0xffff
                for i in range(count):
                    entry = table+8+i*stride
                    if header & 0x80000000:
                        sel = entry+s32(offset(entry))
                        if not header & 0x40000000: sel = ptr(sel)
                        imp = entry+8+s32(offset(entry+8))
                    else:
                        sel = ptr(entry); imp = ptr(entry+16)
                    methods.append({'selector': string(sel), 'implementation': hex(imp)})
            classes.append({'name':name, 'address':hex(cls), 'instance_methods':methods})
        except (ValueError,struct.error,IndexError) as e:
            classes.append({'slot':hex(slot), 'limitation':str(e)})
print(json.dumps({'kind':'supplemental-offline-macho-inspection','canonical_rea_evidence':False,'base':hex(base),'classes':classes}, indent=2))
