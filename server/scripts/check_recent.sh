#!/bin/bash
# Simple script to check recent uploads without dependencies

echo "=========================================="
echo "RECENT ZERO-BYTE FILES (last 5):"
echo "=========================================="
find /mnt/data/media -type f -size 0 -printf '%T+ %p\n' | sort -r | head -5

echo ""
echo "=========================================="
echo "RECENT NON-ZERO FILES (last 5):"
echo "=========================================="
find /mnt/data/media -type f ! -size 0 -printf '%T+ %s %p\n' | sort -r | head -5

echo ""
echo "=========================================="
echo "STATISTICS:"
echo "=========================================="
echo "Total files: $(find /mnt/data/media -type f | wc -l)"
echo "Zero-byte files: $(find /mnt/data/media -type f -size 0 | wc -l)"
echo "Non-zero files: $(find /mnt/data/media -type f ! -size 0 | wc -l)"
