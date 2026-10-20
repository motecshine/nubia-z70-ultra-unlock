#!/usr/bin/env python3
"""过滤 QFIL rawprogram XML: 剔除 GPT 条目和空文件名分区(危险分区)
用法: python3 filter_rawprogram.py <images目录>
效果: 在原目录生成过滤后的 rawprogram0-5.xml (直接覆盖, 因为 flasher 在同目录找镜像)
"""
import re, os, sys

def main():
    img_dir = sys.argv[1] if len(sys.argv) > 1 else 'ROM/images'
    if not os.path.isdir(img_dir):
        print(f'目录不存在: {img_dir}')
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
            # 剔除 GPT 条目 (含 QFIL 占位符 NUM_DISK_SECTORS, qdl-rs 不识别)
            if 'label="PrimaryGPT"' in line or 'label="BackupGPT"' in line:
                removed.append('GPT: ' + re.search(r'label="[^"]*"', line).group(0))
                continue
            # 剔除空文件名分区 (modemst/fsg/fsc/persist/devinfo 等设备专属分区)
            if 'filename=""' in line:
                removed.append('空文件: ' + re.search(r'label="[^"]*"', line).group(0))
                continue
            kept.append(line)
        open(path, 'w', encoding='utf-8').write('\n'.join(kept))
        print(f'{f}: 移除 {len(removed)} 条')
        for r in removed:
            print(f'  - {r}')

    print('\n✅ 过滤完成。直接用 qdl-rs flasher 刷入即可:')
    print('  qdl-rs -l devprg -s ufs flasher -p rawprogram0.xml rawprogram1.xml rawprogram2.xml rawprogram4.xml')

if __name__ == '__main__':
    main()
