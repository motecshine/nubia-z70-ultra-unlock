#!/usr/bin/env python3
"""修改 GPT: 删除指定分区 (设置 type GUID 为 0, 重算 CRC)
用法: python3 gpt_edit.py <输入bin> <输出bin> <分区名1> [分区名2 ...]
"""
import sys, struct, zlib

SECTOR = 4096  # UFS 扇区大小

def crc32(data):
    return zlib.crc32(data) & 0xFFFFFFFF

def main():
    inp, outp = sys.argv[1], sys.argv[2]
    names_to_remove = sys.argv[3:]
    data = bytearray(open(inp, 'rb').read())

    # GPT Header 在扇区 1
    hdr_off = SECTOR
    assert data[hdr_off:hdr_off+8] == b'EFI PART', '不是有效 GPT 头'
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
            # type GUID 清零 = 未使用分区
            data[e:e+16] = b'\x00' * 16
            removed.append(name)
            print(f'[✓] 已删除分区: {name} (entry {i})')

    if not removed:
        print('[!] 未找到任何目标分区, 不修改')
        return

    # 重算分区表 CRC32 (覆盖 entry 数组全部 entry_count*entry_size 字节)
    entries_data = bytes(data[entries_off : entries_off + entry_count * entry_size])
    new_entries_crc = crc32(entries_data)
    struct.pack_into('<I', data, hdr_off+88, new_entries_crc)
    print(f'[i] 分区表 CRC32 -> {new_entries_crc:08x}')

    # 重算 GPT 头 CRC32 (header CRC 字段清零后计算)
    hdr_size = struct.unpack_from('<I', data, hdr_off+12)[0]
    hdr = bytearray(data[hdr_off : hdr_off + hdr_size])
    struct.pack_into('<I', hdr, 16, 0)  # 清零 CRC 字段
    new_hdr_crc = crc32(bytes(hdr))
    struct.pack_into('<I', data, hdr_off+16, new_hdr_crc)
    print(f'[i] GPT 头 CRC32 -> {new_hdr_crc:08x}')

    open(outp, 'wb').write(data)
    print(f'[✓] 已写入 {outp}')

if __name__ == '__main__':
    main()
