#!/usr/bin/env python3
"""Edit GPT: remove partitions by name (zero type GUID, recompute CRCs)
Usage: python3 gpt_edit.py <input.bin> <output.bin> <partition1> [partition2 ...]
"""
import sys, struct, zlib

SECTOR = 4096  # UFS sector size

def crc32(data):
    return zlib.crc32(data) & 0xFFFFFFFF

def main():
    inp, outp = sys.argv[1], sys.argv[2]
    names_to_remove = sys.argv[3:]
    data = bytearray(open(inp, 'rb').read())

    # GPT header is in sector 1
    hdr_off = SECTOR
    assert data[hdr_off:hdr_off+8] == b'EFI PART', 'Not a valid GPT header'
    entry_lba = struct.unpack_from('<Q', data, hdr_off+72)[0]
    entry_count = struct.unpack_from('<I', data, hdr_off+80)[0]
    entry_size = struct.unpack_from('<I', data, hdr_off+84)[0]
    entries_off = entry_lba * SECTOR
    print(f'[i] entry_lba={entry_lba} count={entry_count} size={entry_size}')

    removed = []
    for i in range(entry_count):
        e = entries_off + i * entry_size
        name_raw = bytes(data[e+56:e+128])
        name = name_raw.decode('utf-16-le', errors='ignore').rstrip('\x00')
        if name in names_to_remove:
            # Zero type GUID = unused partition
            data[e:e+16] = b'\x00' * 16
            removed.append(name)
            print(f'[OK] Removed partition: {name} (entry {i})')

    if not removed:
        print('[!] No target partitions found, no changes made')
        return

    # Recompute partition entry array CRC32
    entries_data = bytes(data[entries_off : entries_off + entry_count * entry_size])
    new_entries_crc = crc32(entries_data)
    struct.pack_into('<I', data, hdr_off+88, new_entries_crc)
    print(f'[i] Entry array CRC32 -> {new_entries_crc:08x}')

    # Recompute GPT header CRC32 (with CRC field zeroed)
    hdr_size = struct.unpack_from('<I', data, hdr_off+12)[0]
    hdr = bytearray(data[hdr_off : hdr_off + hdr_size])
    struct.pack_into('<I', hdr, 16, 0)  # zero CRC field
    new_hdr_crc = crc32(bytes(hdr))
    struct.pack_into('<I', data, hdr_off+16, new_hdr_crc)
    print(f'[i] GPT header CRC32 -> {new_hdr_crc:08x}')

    open(outp, 'wb').write(data)
    print(f'[OK] Written to {outp}')

if __name__ == '__main__':
    main()
