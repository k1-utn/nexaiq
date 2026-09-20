import struct
from collections.abc import Iterable

import pytest
from fastapi import HTTPException

from app.services.ems_dbf_parser import parse_ems_dbf

Field = tuple[str, str, int, int]


def build_dbf(fields: list[Field], records: Iterable[dict[str, object]]) -> bytes:
    rows = list(records)
    header_length = 32 + 32 * len(fields) + 1
    record_length = 1 + sum(field[2] for field in fields)
    header = bytearray(32)
    header[0] = 0x03
    struct.pack_into("<I", header, 4, len(rows))
    struct.pack_into("<H", header, 8, header_length)
    struct.pack_into("<H", header, 10, record_length)
    descriptors = bytearray()
    for name, field_type, length, decimals in fields:
        descriptor = bytearray(32)
        descriptor[: len(name)] = name.encode("ascii")
        descriptor[11] = ord(field_type)
        descriptor[16] = length
        descriptor[17] = decimals
        descriptors.extend(descriptor)

    encoded_rows = bytearray()
    for row in rows:
        encoded_rows.extend(b" ")
        for name, field_type, length, decimals in fields:
            value = row.get(name)
            if value is None:
                rendered = ""
            elif field_type == "L":
                rendered = "T" if bool(value) else "F"
            elif field_type in {"N", "F"}:
                rendered = f"{value:.{decimals}f}" if decimals else str(value)
            else:
                rendered = str(value)
            encoded = rendered.encode("cp1252")[:length]
            pad = b" " * (length - len(encoded))
            encoded_rows.extend(pad + encoded if field_type in {"N", "F"} else encoded + pad)
    return bytes(header + descriptors + b"\r" + encoded_rows + b"\x1a")


def test_parses_minimized_env_vehicle_and_line_tables() -> None:
    env = build_dbf(
        [
            ("EST_SYSTEM", "C", 1, 0),
            ("RO_ID", "C", 8, 0),
            ("ESTFILE_ID", "C", 20, 0),
            ("SUPP_NO", "C", 3, 0),
            ("EMS_VER", "C", 5, 0),
        ],
        [
            {
                "EST_SYSTEM": "M",
                "RO_ID": "TEST-100",
                "ESTFILE_ID": "FILE-100",
                "SUPP_NO": "1",
                "EMS_VER": "2.01",
            }
        ],
    )
    vehicle = build_dbf(
        [
            ("V_VIN", "C", 25, 0),
            ("V_MODEL_YR", "C", 2, 0),
            ("V_MAKEDESC", "C", 20, 0),
            ("V_MODEL", "C", 50, 0),
        ],
        [
            {
                "V_VIN": "TESTVIN00000000001",
                "V_MODEL_YR": "25",
                "V_MAKEDESC": "Toyota",
                "V_MODEL": "RAV4",
            }
        ],
    )
    lines = build_dbf(
        [
            ("LINE_NO", "N", 3, 0),
            ("LINE_DESC", "C", 40, 0),
            ("LBR_OP", "C", 4, 0),
            ("ACT_PRICE", "N", 9, 2),
            ("MOD_LB_HRS", "N", 5, 1),
        ],
        [
            {
                "LINE_NO": 12,
                "LINE_DESC": "Replace bumper cover",
                "LBR_OP": "RPL",
                "ACT_PRICE": 125.5,
                "MOD_LB_HRS": 2.3,
            }
        ],
    )

    env_payload = parse_ems_dbf("test.ENV", env).payload
    vehicle_payload = parse_ems_dbf("test.VEH", vehicle).payload
    line_payload = parse_ems_dbf("test.LIN", lines).payload

    assert env_payload["repair_order_reference"] == "TEST-100"
    assert vehicle_payload["year"] == 2025
    assert vehicle_payload["make"] == "Toyota"
    assert line_payload["lines"] == [
        {
            "source_line_number": 12,
            "line_indicator": None,
            "transaction_code": None,
            "operation_code": "RPL",
            "description": "Replace bumper cover",
            "part_type": None,
            "oem_part_number": None,
            "quantity": None,
            "labour_type": None,
            "hours": "2.3",
            "amount": "125.50",
            "normalized_source_text": "12 | RPL | Replace bumper cover | 2.3 | 125.50",
        }
    ]


def test_sensitive_tables_are_not_read_or_extracted() -> None:
    result = parse_ems_dbf("test.AD1", b"not even parsed")
    assert result.parse_status == "withheld_by_minimization"
    assert result.payload["reason"] == "customer_insurer_vendor_and_memo_fields_not_extracted"


def test_rejects_truncated_or_spoofed_dbf() -> None:
    with pytest.raises(HTTPException) as exc_info:
        parse_ems_dbf("test.LIN", b"not-a-dbf")
    assert exc_info.value.status_code == 422
