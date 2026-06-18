#!/usr/bin/env python3
"""
Write a GPT partition table with arbitrary sector size to a raw disk image.

Usage: gpt4k.py <image> <sector_size> <part_spec> [part_spec ...]
  part_spec: "start_lba:size_sectors:type_guid:name"

This exists because sfdisk ignores sector-size on regular files and always
uses 512 bytes, but the IQ-9075 UFS has 4096-byte physical sectors and
UEFI reads GPT at LBA1 = byte 4096.
"""

import struct
import sys
import uuid
import zlib

def guid_to_mixed_endian(guid_str):
    """Convert a GUID string to mixed-endian bytes (as stored in GPT)."""
    u = uuid.UUID(guid_str)
    # GPT stores GUIDs in mixed endian: first 3 fields LE, last 2 BE
    fields = u.fields  # (time_low, time_mid, time_hi, clock_seq_hi, clock_seq_low, node)
    return struct.pack('<IHH', fields[0], fields[1], fields[2]) + \
           struct.pack('>BB', fields[3], fields[4]) + \
           struct.pack('>Q', fields[5])[2:]  # node is 6 bytes

def make_protective_mbr(sector_size, total_sectors):
    """Create a protective MBR for GPT."""
    mbr = bytearray(sector_size)
    # Partition entry 1 at offset 446
    entry = bytearray(16)
    entry[0] = 0x00  # not bootable
    entry[1:4] = b'\x00\x00\x00'  # CHS start (ignored)
    entry[4] = 0xEE  # GPT protective
    entry[5:8] = b'\x00\x00\x00'  # CHS end (ignored)
    # LBA start = 1
    struct.pack_into('<I', entry, 8, 1)
    # Size: min(total_sectors - 1, 0xFFFFFFFF)
    size = min(total_sectors - 1, 0xFFFFFFFF)
    struct.pack_into('<I', entry, 12, size)
    mbr[446:462] = entry
    # Boot signature
    mbr[510] = 0x55
    mbr[511] = 0xAA
    return bytes(mbr)

def make_gpt_header(sector_size, total_sectors, disk_guid, num_parts, entries_crc32, my_lba, alt_lba, first_usable, last_usable, entries_lba):
    """Create a GPT header."""
    hdr = bytearray(92)
    # Signature
    hdr[0:8] = b'EFI PART'
    # Revision 1.0
    struct.pack_into('<I', hdr, 8, 0x00010000)
    # Header size = 92
    struct.pack_into('<I', hdr, 12, 92)
    # CRC32 (fill later)
    struct.pack_into('<I', hdr, 16, 0)
    # Reserved
    struct.pack_into('<I', hdr, 20, 0)
    # My LBA
    struct.pack_into('<Q', hdr, 24, my_lba)
    # Alternate LBA
    struct.pack_into('<Q', hdr, 32, alt_lba)
    # First usable LBA
    struct.pack_into('<Q', hdr, 40, first_usable)
    # Last usable LBA
    struct.pack_into('<Q', hdr, 48, last_usable)
    # Disk GUID
    hdr[56:72] = guid_to_mixed_endian(disk_guid)
    # Partition entries start LBA
    struct.pack_into('<Q', hdr, 72, entries_lba)
    # Number of partition entries
    struct.pack_into('<I', hdr, 80, num_parts)
    # Size of partition entry (128 bytes)
    struct.pack_into('<I', hdr, 84, 128)
    # CRC32 of partition entries
    struct.pack_into('<I', hdr, 88, entries_crc32)

    # Compute header CRC32
    crc = zlib.crc32(bytes(hdr)) & 0xFFFFFFFF
    struct.pack_into('<I', hdr, 16, crc)

    # Pad to sector size
    padded = bytearray(sector_size)
    padded[0:92] = hdr
    return bytes(padded)

def make_partition_entry(type_guid, unique_guid, start_lba, end_lba, name):
    """Create a 128-byte GPT partition entry."""
    entry = bytearray(128)
    entry[0:16] = guid_to_mixed_endian(type_guid)
    entry[16:32] = guid_to_mixed_endian(unique_guid)
    struct.pack_into('<Q', entry, 32, start_lba)
    struct.pack_into('<Q', entry, 40, end_lba)
    # Attributes = 0
    struct.pack_into('<Q', entry, 48, 0)
    # Name (UTF-16LE, max 36 chars)
    name_bytes = name[:36].encode('utf-16-le')
    entry[56:56+len(name_bytes)] = name_bytes
    return bytes(entry)

def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <image> <sector_size> <part_spec> [...]")
        sys.exit(1)

    image_path = sys.argv[1]
    sector_size = int(sys.argv[2])
    part_specs = sys.argv[3:]

    # Get image size
    with open(image_path, 'rb') as f:
        f.seek(0, 2)
        image_size = f.tell()
    total_sectors = image_size // sector_size

    # Parse partition specs
    partitions = []
    for spec in part_specs:
        parts = spec.split(':')
        start = int(parts[0])
        size = int(parts[1])
        type_guid = parts[2]
        name = parts[3] if len(parts) > 3 else ""
        partitions.append((start, size, type_guid, name))

    # GPT layout:
    # LBA 0: Protective MBR
    # LBA 1: Primary GPT header
    # LBA 2-5: Partition entries (128 entries * 128 bytes = 16384 bytes = 4 sectors at 4096)
    # LBA 6 .. last-5: Usable space
    # last-4 .. last-1: Backup partition entries
    # last: Backup GPT header

    num_entry_sectors = 4  # 4 * 4096 = 16384 bytes = 128 entries
    num_entries = 128
    first_usable = 2 + num_entry_sectors  # LBA 6
    last_usable = total_sectors - 1 - num_entry_sectors - 1  # leave room for backup entries + header

    disk_guid = str(uuid.uuid4())

    # Build partition entries
    entries_data = bytearray(num_entries * 128)
    for i, (start, size, type_guid, name) in enumerate(partitions):
        end_lba = start + size - 1
        unique_guid = str(uuid.uuid4())
        entry = make_partition_entry(type_guid, unique_guid, start, end_lba, name)
        entries_data[i*128:(i+1)*128] = entry

    entries_crc = zlib.crc32(bytes(entries_data)) & 0xFFFFFFFF

    # Build primary header (at LBA 1)
    primary_header = make_gpt_header(
        sector_size, total_sectors, disk_guid, num_entries, entries_crc,
        my_lba=1, alt_lba=total_sectors-1,
        first_usable=first_usable, last_usable=last_usable,
        entries_lba=2
    )

    # Build backup header (at last LBA)
    backup_header = make_gpt_header(
        sector_size, total_sectors, disk_guid, num_entries, entries_crc,
        my_lba=total_sectors-1, alt_lba=1,
        first_usable=first_usable, last_usable=last_usable,
        entries_lba=total_sectors - 1 - num_entry_sectors
    )

    # Write to image
    with open(image_path, 'r+b') as f:
        # LBA 0: Protective MBR
        mbr = make_protective_mbr(sector_size, total_sectors)
        f.seek(0)
        f.write(mbr)

        # LBA 1: Primary GPT header
        f.seek(sector_size)
        f.write(primary_header)

        # LBA 2-5: Partition entries
        f.seek(2 * sector_size)
        f.write(bytes(entries_data))

        # Backup partition entries (before last sector)
        backup_entries_lba = total_sectors - 1 - num_entry_sectors
        f.seek(backup_entries_lba * sector_size)
        f.write(bytes(entries_data))

        # Backup GPT header (last sector)
        f.seek((total_sectors - 1) * sector_size)
        f.write(backup_header)

    print(f"GPT written: {len(partitions)} partitions, sector_size={sector_size}, total_sectors={total_sectors}")

if __name__ == '__main__':
    main()
