#!/usr/bin/env python3
"""Filter QFIL rawprogram XMLs: drop GPT entries and empty-filename partitions.
Usage: python3 filter_rawprogram.py <images_dir>
Effect: rewrites rawprogram0-5.xml in place (flasher looks for images in same dir)
"""
import re, os, sys

def main():
    img_dir = sys.argv[1] if len(sys.argv) > 1 else 'ROM/images'
    if not os.path.isdir(img_dir):
        print(f'Directory not found: {img_dir}')
        sys.exit(1)

    for f in sorted(os.listdir(img_dir)):
        if not f.startswith('rawprogram') or not f.endswith('.xml'):
            continue
        path = os.path.join(img_dir, f)
        data = open(path, encoding='utf-8').read()
        lines = data.split('\n')
        kept = []
        removed = []
        for line in lines:
            # Drop GPT entries (contain QFIL placeholder NUM_DISK_SECTORS,
            # which qdl-rs doesn't understand)
            if 'label="PrimaryGPT"' in line or 'label="BackupGPT"' in line:
                removed.append('GPT: ' + re.search(r'label="[^"]*"', line).group(0))
                continue
            # Drop empty-filename partitions (modemst/fsg/fsc/persist/devinfo
            # etc. are device-specific and must NOT be overwritten)
            if 'filename=""' in line:
                removed.append('empty-file: ' + re.search(r'label="[^"]*"', line).group(0))
                continue
            kept.append(line)
        open(path, 'w', encoding='utf-8').write('\n'.join(kept))
        print(f'{f}: removed {len(removed)} entries')
        for r in removed:
            print(f'  - {r}')

    print('\n[OK] Filtering done. Flash with:')
    print('  qdl-rs -l devprg -s ufs flasher -p rawprogram0.xml rawprogram1.xml rawprogram2.xml rawprogram4.xml')

if __name__ == '__main__':
    main()
