#!/usr/bin/env python3

"""Fail-closed audit for the locked Flyme m86 primary audio HALs."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import struct
import sys
from dataclasses import dataclass


EXPECTED_NEEDED = [
    "liblog.so",
    "libcutils.so",
    "libtinyalsa.so",
    "libaudioutils.so",
    "libexpat.so",
    "libhardware_legacy.so",
    "libdl.so",
    "libtfa9890.so",
    "libsitril-audio.so",
    "libc++.so",
    "libc.so",
    "libm.so",
]
EXPECTED_32_SHA256 = (
    "50e97ee55ac9408ecb0017e3dc0c0541e520e102cea0b8ec87682e51c6cadeac"
)
EXPECTED_64_SHA256 = (
    "c7c69dd92097c4e6ba1df2d76112912ef12c610d814d0bf2b6b26f2a26169aba"
)


class AuditError(RuntimeError):
    pass


@dataclass(frozen=True)
class Section:
    name: str
    section_type: int
    address: int
    offset: int
    size: int
    link: int
    entry_size: int


@dataclass(frozen=True)
class Symbol:
    name: str
    value: int
    size: int
    section_index: int


class Elf:
    def __init__(self, path: pathlib.Path) -> None:
        self.path = path
        self.payload = path.read_bytes()
        if self.payload[:4] != b"\x7fELF":
            raise AuditError(f"not an ELF file: {path}")
        self.elf_class = self.payload[4]
        if self.elf_class not in (1, 2):
            raise AuditError(f"unsupported ELF class {self.elf_class}: {path}")
        if self.payload[5] != 1:
            raise AuditError(f"only little-endian ELF is supported: {path}")
        self.word_size = 4 if self.elf_class == 1 else 8
        self.machine = struct.unpack_from("<H", self.payload, 18)[0]
        self.sections = self._read_sections()
        self.section_by_name = {section.name: section for section in self.sections}

    def _read_sections(self) -> list[Section]:
        if self.elf_class == 1:
            section_offset = struct.unpack_from("<I", self.payload, 32)[0]
            section_entry_size, section_count, names_index = struct.unpack_from(
                "<HHH", self.payload, 46
            )
            section_format = "<IIIIIIIIII"
        else:
            section_offset = struct.unpack_from("<Q", self.payload, 40)[0]
            section_entry_size, section_count, names_index = struct.unpack_from(
                "<HHH", self.payload, 58
            )
            section_format = "<IIQQQQIIQQ"
        expected_entry_size = struct.calcsize(section_format)
        if section_entry_size != expected_entry_size:
            raise AuditError(
                f"unexpected section entry size {section_entry_size}: {self.path}"
            )
        raw_sections = [
            struct.unpack_from(
                section_format,
                self.payload,
                section_offset + index * section_entry_size,
            )
            for index in range(section_count)
        ]
        if names_index >= len(raw_sections):
            raise AuditError(f"invalid section-name table: {self.path}")
        names_header = raw_sections[names_index]
        names_offset = names_header[4]
        names_size = names_header[5]
        names = self.payload[names_offset : names_offset + names_size]

        def section_name(offset: int) -> str:
            end = names.find(b"\0", offset)
            if end < 0:
                raise AuditError(f"unterminated section name: {self.path}")
            return names[offset:end].decode("ascii")

        return [
            Section(
                name=section_name(header[0]),
                section_type=header[1],
                address=header[3],
                offset=header[4],
                size=header[5],
                link=header[6],
                entry_size=header[9],
            )
            for header in raw_sections
        ]

    def _string(self, section: Section, offset: int) -> str:
        if offset >= section.size:
            raise AuditError(f"string offset outside {section.name}: {self.path}")
        start = section.offset + offset
        end = self.payload.find(b"\0", start, section.offset + section.size)
        if end < 0:
            raise AuditError(f"unterminated string in {section.name}: {self.path}")
        return self.payload[start:end].decode("utf-8")

    def dynamic(self) -> tuple[list[str], str]:
        dynamic = self.section_by_name.get(".dynamic")
        dynstr = self.section_by_name.get(".dynstr")
        if dynamic is None or dynstr is None:
            raise AuditError(f"missing dynamic sections: {self.path}")
        entry_format = "<II" if self.elf_class == 1 else "<QQ"
        entry_size = struct.calcsize(entry_format)
        if dynamic.entry_size != entry_size or dynamic.size % entry_size:
            raise AuditError(f"invalid dynamic entry layout: {self.path}")
        needed: list[str] = []
        soname = ""
        for offset in range(dynamic.offset, dynamic.offset + dynamic.size, entry_size):
            tag, value = struct.unpack_from(entry_format, self.payload, offset)
            if tag == 0:
                break
            if tag == 1:
                needed.append(self._string(dynstr, value))
            elif tag == 14:
                soname = self._string(dynstr, value)
        return needed, soname

    def symbols(self) -> list[Symbol]:
        dynsym = self.section_by_name.get(".dynsym")
        if dynsym is None or dynsym.link >= len(self.sections):
            raise AuditError(f"missing or invalid .dynsym: {self.path}")
        dynstr = self.sections[dynsym.link]
        entry_format = "<IIIBBH" if self.elf_class == 1 else "<IBBHQQ"
        entry_size = struct.calcsize(entry_format)
        if dynsym.entry_size != entry_size or dynsym.size % entry_size:
            raise AuditError(f"invalid symbol entry layout: {self.path}")
        symbols: list[Symbol] = []
        for offset in range(dynsym.offset, dynsym.offset + dynsym.size, entry_size):
            entry = struct.unpack_from(entry_format, self.payload, offset)
            if self.elf_class == 1:
                name_offset, value, size, _info, _other, section_index = entry
            else:
                name_offset, _info, _other, section_index, value, size = entry
            symbols.append(
                Symbol(
                    name=self._string(dynstr, name_offset),
                    value=value,
                    size=size,
                    section_index=section_index,
                )
            )
        return symbols

    def bytes_at_vaddr(self, address: int, size: int) -> bytes:
        for section in self.sections:
            if section.address <= address and address + size <= section.address + section.size:
                offset = section.offset + address - section.address
                return self.payload[offset : offset + size]
        raise AuditError(f"virtual address 0x{address:x} is not file-backed: {self.path}")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def audit(path: pathlib.Path, bits: int) -> list[str]:
    expected_hash = EXPECTED_32_SHA256 if bits == 32 else EXPECTED_64_SHA256
    expected_class = 1 if bits == 32 else 2
    expected_machine = 40 if bits == 32 else 183
    expected_undefined = 106 if bits == 32 else 98
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    require(digest == expected_hash, f"{bits}-bit primary HAL hash mismatch: {digest}")
    elf = Elf(path)
    require(elf.elf_class == expected_class, f"{bits}-bit primary HAL class mismatch")
    require(elf.machine == expected_machine, f"{bits}-bit primary HAL machine mismatch")
    needed, soname = elf.dynamic()
    require(needed == EXPECTED_NEEDED, f"{bits}-bit DT_NEEDED contract changed: {needed}")
    require(soname == "audio.primary.m86.so", f"{bits}-bit SONAME changed: {soname}")
    symbols = elf.symbols()
    undefined = [symbol for symbol in symbols if symbol.name and symbol.section_index == 0]
    require(
        len(undefined) == expected_undefined,
        f"{bits}-bit undefined-symbol count changed: {len(undefined)}",
    )
    hmi = [symbol for symbol in symbols if symbol.name == "HMI"]
    expected_hmi_size = 128 if bits == 32 else 248
    require(
        len(hmi) == 1 and hmi[0].size == expected_hmi_size,
        f"{bits}-bit HMI contract changed",
    )
    report = [
        f"primary{bits}_path={path}",
        f"primary{bits}_sha256={digest}",
        f"primary{bits}_elf={'ELF32-ARM' if bits == 32 else 'ELF64-AARCH64'}",
        f"primary{bits}_soname={soname}",
        f"primary{bits}_needed_count={len(needed)}",
        f"primary{bits}_undefined_count={len(undefined)}",
        f"primary{bits}_hmi_vaddr=0x{hmi[0].value:x}",
        f"primary{bits}_hmi_size={hmi[0].size}",
    ]
    if bits == 32:
        require(hmi[0].value == 0x11648, "32-bit HMI address changed")
        hmi_words = struct.unpack("<6I", elf.bytes_at_vaddr(hmi[0].value, 24))
        require(hmi_words[0] == 0x48574D54, "32-bit HMI tag changed")
        require(hmi_words[1] == 0x01000001, "32-bit HMI API version changed")
        require(hmi_words[5] == 0x11644, "32-bit HMI methods address changed")
        open_address = struct.unpack("<I", elf.bytes_at_vaddr(hmi_words[5], 4))[0]
        require(open_address == 0x4425, "32-bit HMI open entry changed")
        headset = [symbol for symbol in symbols if symbol.name == "adev_set_headset_volume"]
        require(
            len(headset) == 1 and headset[0].value == 0x41B1,
            "32-bit private headphone callback symbol changed",
        )
        report.extend(
            [
                f"primary32_hmi_methods_vaddr=0x{hmi_words[5]:x}",
                f"primary32_adev_open_thumb=0x{open_address:x}",
                "flyme_device_version=0x200",
                "flyme_device_allocation_size=0x140",
                "flyme_device_private_offsets=96,100,104",
                "flyme_device_set_parameters_offset=108",
                "flyme_device_legacy_dump_offset=136",
                "flyme_output_allocation_size=0xe0",
                "flyme_output_private_pcm_config_offset=116",
                "observed_update_source_metadata_alias=0x2",
                "flyme_input_allocation_size=176",
                "flyme_input_private_state_offset=68",
            ]
        )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("primary32", type=pathlib.Path)
    parser.add_argument("primary64", nargs="?", type=pathlib.Path)
    args = parser.parse_args()
    try:
        report = audit(args.primary32, 32)
        if args.primary64 is not None:
            report.extend(audit(args.primary64, 64))
    except (AuditError, OSError, struct.error, UnicodeDecodeError) as error:
        print(f"audio ABI audit failed: {error}", file=sys.stderr)
        return 1
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
