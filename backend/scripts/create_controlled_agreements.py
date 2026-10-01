import argparse
import hashlib
from pathlib import Path

import pymupdf

CONTROLLED_TEXT = """CONTROLLED SYNTHETIC TENANCY AGREEMENT

This document is generated for software testing. It is not a real agreement.
Property: Unit 8, Sunrise Demo Residence, Cyberjaya, Selangor.
Tenant: Nur Amina Test. Landlord: Demo Property Services.

1. RENT
The tenant shall pay RM 1,450 on or before the fifth day of each month.

2. DEPOSIT
The tenant shall pay a security deposit of RM 2,900.
It is refundable after lawful deductions for unpaid rent or documented damage.

3. MAINTENANCE
The tenant shall promptly report water leaks and electrical faults.
The landlord shall arrange building-system repairs, while the tenant keeps the unit clean.

4. TERMINATION
Either party may terminate the tenancy with thirty days written notice,
subject to outstanding rent and the terms of this agreement.
"""


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create ignored native-text and scanned controlled agreement PDFs."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("calibration/agreements/documents"),
    )
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def _insert_controlled_text(page: pymupdf.Page) -> None:
    remaining = page.insert_textbox(
        pymupdf.Rect(54, 54, 541, 788),
        CONTROLLED_TEXT,
        fontsize=11,
        fontname="helv",
        lineheight=1.3,
    )
    if remaining < 0:
        raise RuntimeError("Controlled agreement text did not fit on the page.")


def _native_pdf() -> bytes:
    document = pymupdf.open()
    try:
        page = document.new_page(width=595, height=842)
        _insert_controlled_text(page)
        return document.tobytes(garbage=4, deflate=True)
    finally:
        document.close()


def _scanned_pdf() -> bytes:
    source = pymupdf.open()
    try:
        source_page = source.new_page(width=595, height=842)
        _insert_controlled_text(source_page)
        image = source_page.get_pixmap(matrix=pymupdf.Matrix(2, 2), alpha=False).tobytes(
            "png"
        )
    finally:
        source.close()

    document = pymupdf.open()
    try:
        page = document.new_page(width=595, height=842)
        page.insert_image(page.rect, stream=image)
        return document.tobytes(garbage=4, deflate=True)
    finally:
        document.close()


def _write(path: Path, data: bytes, *, force: bool) -> None:
    if path.exists() and not force:
        raise FileExistsError(f"Refusing to overwrite {path}; pass --force to replace it.")
    path.write_bytes(data)


def _validate(native_path: Path, scanned_path: Path) -> None:
    with pymupdf.open(native_path) as native:
        native_text = "".join(page.get_text("text") for page in native)
    with pymupdf.open(scanned_path) as scanned:
        scanned_text = "".join(page.get_text("text") for page in scanned)
    if "1. RENT" not in native_text or "4. TERMINATION" not in native_text:
        raise RuntimeError("Native controlled PDF did not retain the expected embedded text.")
    if scanned_text.strip():
        raise RuntimeError("Scanned controlled PDF unexpectedly contains embedded text.")


def main() -> None:
    args = _arguments()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    native_path = output_dir / "native-text.pdf"
    scanned_path = output_dir / "scanned.pdf"
    _write(native_path, _native_pdf(), force=args.force)
    _write(scanned_path, _scanned_pdf(), force=args.force)
    _validate(native_path, scanned_path)
    for path in (native_path, scanned_path):
        digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
        print(f"Created {path.name}: {path.stat().st_size} bytes, SHA-256 {digest}")


if __name__ == "__main__":
    main()
