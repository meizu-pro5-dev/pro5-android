#!/usr/bin/env python3
"""Build a fingerprint-enabled DTB while preserving the proven Flyme tree."""

import argparse
import hashlib
import pathlib
import struct
import subprocess
import tempfile


STOCK_SHA256 = "b45054fa87a5ffe114843953172d48d36408e1f93db35a6cbdfb0a8fc58a2165"


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError("expected exactly one DTB fragment: {!r}".format(old))
    return text.replace(old, new, 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dtc", required=True)
    parser.add_argument("--stock", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    stock_path = pathlib.Path(args.stock)
    stock = stock_path.read_bytes()
    if len(stock) < 8:
        raise RuntimeError("stock DTB is truncated")
    fdt_size = struct.unpack(">I", stock[4:8])[0]
    stock = stock[:fdt_size]
    if hashlib.sha256(stock).hexdigest() != STOCK_SHA256:
        raise RuntimeError("stock Flyme DTB hash does not match the device baseline")

    with tempfile.TemporaryDirectory(prefix="pro5-hybrid-dtb-") as tmp:
        tmp_path = pathlib.Path(tmp)
        stock_raw = tmp_path / "stock.dtb"
        hybrid_dts = tmp_path / "hybrid.dts"
        stock_raw.write_bytes(stock)
        source = subprocess.check_output(
            [args.dtc, "-q", "-I", "dtb", "-O", "dts", str(stock_raw)],
            text=True,
        )

        # Keep all boot-proven Flyme nodes and phandles. Change only SPI4 from
        # Flyme's unavailable secure fingerprint transport to the AP FPC1020
        # transport consumed by the Lineage libfprint HAL.
        source = replace_once(source, '\n\t\tsecure-mode;\n', "\n")
        source = replace_once(source, "securefpc_spidev@0", "fingerprint_spi@0")
        source = replace_once(source, 'compatible = "fpc,fpc_irq";',
                              'compatible = "fpc,fpc1020";')
        source = replace_once(source, "spi-max-frequency = <0xf42400>;",
                              "spi-max-frequency = <0x493e00>;")
        source = replace_once(source, "gx,gpio_reset", "fpc,gpio_reset")
        source = replace_once(source, "gx,gpio_irq", "fpc,gpio_irq")
        source = replace_once(
            source,
            "\t\t\tfpc,gpio_irq = <0xc 0x2 0xf>;",
            "\t\t\tfpc,gpio_irq = <0xc 0x2 0xf>;\n"
            "\t\t\tfpc,txout_boost_enable = <0x01>;",
        )
        hybrid_dts.write_text(source)
        subprocess.check_call([
            args.dtc, "-q", "-I", "dts", "-O", "dtb", "-o", args.output,
            str(hybrid_dts),
        ])

    output = pathlib.Path(args.output).read_bytes()
    for required in (b"Meizu, M86", b"fpc,fpc1020", b"fpc,gpio_irq"):
        if required not in output:
            raise RuntimeError("hybrid DTB omitted {!r}".format(required))
    # Match the complete FDT string-table entry for secure-mode. A plain
    # substring check also matches the unrelated #dma-secure-mode property.
    for forbidden in (b"fpc,fpc_irq", b"\x00secure-mode\x00"):
        if forbidden in output:
            raise RuntimeError("hybrid DTB retained {!r}".format(forbidden))
    print("hybrid_dtb_sha256={}".format(hashlib.sha256(output).hexdigest()))


if __name__ == "__main__":
    main()
