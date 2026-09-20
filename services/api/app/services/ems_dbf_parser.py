import struct
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import PurePath
from typing import Literal

from fastapi import HTTPException

ParseStatus = Literal["parsed", "withheld_by_minimization", "unsupported"]

SUPPORTED_DBF_VERSIONS = {0x03, 0x83, 0x8B}
MINIMIZED_EXTENSIONS = {".ad1", ".ad2", ".ven", ".dbt"}
PROFILE_EXTENSIONS = {".pfh", ".pfl", ".pfm", ".pfo", ".pfp", ".pft", ".stl"}


@dataclass(frozen=True)
class DbfField:
    name: str
    field_type: str
    length: int
    decimal_count: int


@dataclass(frozen=True)
class ParsedEmsFile:
    parse_status: ParseStatus
    payload: dict[str, object]


def _invalid(message: str) -> HTTPException:
    return HTTPException(status_code=422, detail=message)


def _parse_dbf(data: bytes) -> list[dict[str, object | None]]:
    if len(data) < 33 or data[0] not in SUPPORTED_DBF_VERSIONS:
        raise _invalid("Connector file is not a supported dBASE EMS table")

    record_count = struct.unpack_from("<I", data, 4)[0]
    header_length = struct.unpack_from("<H", data, 8)[0]
    record_length = struct.unpack_from("<H", data, 10)[0]
    if record_count > 20_000 or header_length < 33 or record_length < 2:
        raise _invalid("Connector dBASE header is outside supported limits")
    if header_length > len(data) or header_length + record_count * record_length > len(data):
        raise _invalid("Connector dBASE table is truncated")

    fields: list[DbfField] = []
    descriptor_offset = 32
    while descriptor_offset < header_length:
        if data[descriptor_offset] == 0x0D:
            break
        if descriptor_offset + 32 > header_length:
            raise _invalid("Connector dBASE field descriptor is truncated")
        descriptor = data[descriptor_offset : descriptor_offset + 32]
        name = descriptor[:11].split(b"\0", 1)[0].decode("ascii", errors="strict")
        field_type = chr(descriptor[11])
        length = descriptor[16]
        decimal_count = descriptor[17]
        if not name or field_type not in {"C", "N", "D", "L", "M", "F"} or length < 1:
            raise _invalid("Connector dBASE field descriptor is unsupported")
        fields.append(DbfField(name, field_type, length, decimal_count))
        if len(fields) > 256:
            raise _invalid("Connector dBASE table has too many fields")
        descriptor_offset += 32
    else:
        raise _invalid("Connector dBASE field terminator is missing")

    if 1 + sum(field.length for field in fields) > record_length:
        raise _invalid("Connector dBASE record length does not match its schema")

    records: list[dict[str, object | None]] = []
    for record_index in range(record_count):
        start = header_length + record_index * record_length
        raw_record = data[start : start + record_length]
        if raw_record[0] == 0x2A:
            continue
        if raw_record[0] != 0x20:
            raise _invalid("Connector dBASE record marker is invalid")

        values: dict[str, object | None] = {}
        offset = 1
        for field in fields:
            raw_value = raw_record[offset : offset + field.length]
            offset += field.length
            values[field.name] = _decode_field(field, raw_value)
        records.append(values)
    return records


def _decode_field(field: DbfField, raw_value: bytes) -> object | None:
    if field.field_type == "M":
        return None
    value = raw_value.rstrip(b" \x00").lstrip(b" ")
    if not value:
        return None
    if field.field_type in {"C", "D"}:
        return value.decode("cp1252", errors="replace")
    if field.field_type == "L":
        marker = value[:1].upper()
        if marker in {b"T", b"Y"}:
            return True
        if marker in {b"F", b"N"}:
            return False
        return None
    if field.field_type in {"N", "F"}:
        try:
            number = Decimal(value.decode("ascii"))
        except (InvalidOperation, UnicodeDecodeError) as exc:
            raise _invalid(f"Connector numeric field {field.name} is invalid") from exc
        return int(number) if field.decimal_count == 0 else format(number, "f")
    raise _invalid(f"Connector field type {field.field_type} is unsupported")


def _first(records: list[dict[str, object | None]], table_name: str) -> dict[str, object | None]:
    if not records:
        raise _invalid(f"Connector {table_name} table contains no active record")
    return records[0]


def _text(record: dict[str, object | None], key: str) -> str | None:
    value = record.get(key)
    return str(value).strip() if value is not None and str(value).strip() else None


def _money(record: dict[str, object | None], *keys: str) -> str | None:
    for key in keys:
        value = record.get(key)
        if value not in {None, "", "0", "0.0", "0.00"}:
            return str(value)
    return None


def _vehicle_year(value: str | None) -> int | None:
    if value is None or not value.isdigit():
        return None
    year = int(value)
    if len(value) == 2:
        return 2000 + year if year <= 79 else 1900 + year
    return year if 1886 <= year <= 2200 else None


def parse_ems_dbf(filename: str, data: bytes) -> ParsedEmsFile:
    extension = PurePath(filename).suffix.lower()
    if extension in MINIMIZED_EXTENSIONS:
        return ParsedEmsFile(
            "withheld_by_minimization",
            {
                "table": extension.removeprefix("."),
                "reason": "customer_insurer_vendor_and_memo_fields_not_extracted",
            },
        )
    if extension in PROFILE_EXTENSIONS:
        return ParsedEmsFile(
            "unsupported",
            {"table": extension.removeprefix("."), "reason": "not_required_for_initial_import"},
        )

    records = _parse_dbf(data)
    if extension == ".env":
        record = _first(records, "ENV")
        return ParsedEmsFile(
            "parsed",
            {
                "table": "env",
                "estimate_system": _text(record, "EST_SYSTEM"),
                "software_version": _text(record, "SW_VERSION"),
                "database_version": _text(record, "DB_VERSION"),
                "unique_file_id": _text(record, "UNQFILE_ID"),
                "repair_order_reference": _text(record, "RO_ID"),
                "estimate_file_reference": _text(record, "ESTFILE_ID"),
                "supplement_number": _text(record, "SUPP_NO"),
                "transaction_type": _text(record, "TRANS_TYPE"),
                "ems_version": _text(record, "EMS_VER"),
            },
        )
    if extension == ".veh":
        record = _first(records, "VEH")
        return ParsedEmsFile(
            "parsed",
            {
                "table": "veh",
                "vin": _text(record, "V_VIN"),
                "year": _vehicle_year(_text(record, "V_MODEL_YR")),
                "make_code": _text(record, "V_MAKECODE"),
                "make": _text(record, "V_MAKEDESC"),
                "model": _text(record, "V_MODEL"),
                "body_style": _text(record, "V_BSTYLE"),
                "trim": _text(record, "V_TRIMCODE"),
                "paint_codes": [
                    value
                    for value in (
                        _text(record, "PAINT_CD1"),
                        _text(record, "PAINT_CD2"),
                        _text(record, "PAINT_CD3"),
                    )
                    if value
                ],
                "primary_impact": _text(record, "IMPACT_1"),
            },
        )
    if extension == ".lin":
        lines: list[dict[str, object | None]] = []
        for record in records:
            description = _text(record, "LINE_DESC")
            if not description:
                continue
            line_number = record.get("LINE_NO")
            operation = _text(record, "LBR_OP") or _text(record, "TRAN_CODE")
            amount = _money(record, "ACT_PRICE", "LBR_AMT", "MISC_AMT", "DB_PRICE")
            hours = _money(record, "MOD_LB_HRS", "DB_HRS")
            source_fields = [
                str(value)
                for value in (line_number, operation, description, hours, amount)
                if value not in {None, ""}
            ]
            lines.append(
                {
                    "source_line_number": line_number,
                    "line_indicator": _text(record, "LINE_IND"),
                    "transaction_code": _text(record, "TRAN_CODE"),
                    "operation_code": operation,
                    "description": description,
                    "part_type": _text(record, "PART_TYPE"),
                    "oem_part_number": _text(record, "OEM_PARTNO"),
                    "quantity": record.get("PART_QTY"),
                    "labour_type": _text(record, "MOD_LBR_TY"),
                    "hours": hours,
                    "amount": amount,
                    "normalized_source_text": " | ".join(source_fields),
                }
            )
        return ParsedEmsFile("parsed", {"table": "lin", "lines": lines})
    if extension == ".ttl":
        record = _first(records, "TTL")
        return ParsedEmsFile(
            "parsed",
            {
                "table": "ttl",
                "gross_total": _money(record, "G_TTL_AMT"),
                "net_total": _money(record, "N_TTL_AMT"),
                "supplement_amount": _money(record, "SUPP_AMT", "N_SUPP_AMT"),
                "tax_amount": _money(record, "G_TAX", "GST_AMT"),
            },
        )
    return ParsedEmsFile(
        "unsupported",
        {"table": extension.removeprefix("."), "reason": "unrecognized_ems_table"},
    )
