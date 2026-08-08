import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from build import (
    DATA_SHEETS, UI_SHEETS, SHEET_HEADERS, SEED_LOV, SEED_SETTINGS, SEED_CONSULTANTS,
    ANCHOR_SHEET, EXCEL_BUILD_VERSION, _default_output_path,
)


def test_data_sheets_order():
    assert DATA_SHEETS == [
        '_data_users', '_data_patients', '_data_status_history',
        '_data_appointments', '_data_consultants', '_data_lov',
        '_data_audit', '_data_settings',
    ]


def test_ui_sheets_order():
    assert UI_SHEETS == ['WorkQueue', 'Appointments', 'Reports', 'Admin']


def test_all_data_sheets_have_headers():
    for name in DATA_SHEETS:
        assert name in SHEET_HEADERS, f'Missing headers for {name}'
        assert len(SHEET_HEADERS[name]) > 0, f'Empty headers for {name}'


def test_users_headers():
    assert SHEET_HEADERS['_data_users'] == [
        'id', 'name', 'username', 'email', 'password_hash', 'role', 'is_active', 'created_at',
        'security_question', 'security_answer_hash',
    ]


def test_patients_headers():
    assert SHEET_HEADERS['_data_patients'] == [
        'id', 'mrn', 'last_name', 'first_name', 'middle_name', 'phone',
        'date_of_referral', 'referral_source_id', 'religion_id', 'language_id',
        'current_status', 'is_active',
        'sdat_begin_score', 'sdat_begin_date', 'sdat_end_score', 'sdat_end_date',
        'sdat_pct_improvement', 'notes',
        'created_at',
    ]


def test_status_history_headers():
    assert SHEET_HEADERS['_data_status_history'] == [
        'id', 'patient_id', 'status', 'changed_by', 'changed_at',
    ]


def test_appointments_headers():
    assert SHEET_HEADERS['_data_appointments'] == [
        'id', 'patient_id', 'date', 'time', 'type_id', 'consultant_id',
        'is_last_appointment', 'status', 'notes', 'created_at',
    ]


def test_consultants_headers():
    assert SHEET_HEADERS['_data_consultants'] == [
        'id', 'name', 'is_chaplain', 'is_active',
    ]


def test_lov_headers():
    assert SHEET_HEADERS['_data_lov'] == [
        'id', 'category', 'value', 'is_active', 'sort_order',
    ]


def test_audit_headers():
    assert SHEET_HEADERS['_data_audit'] == [
        'id', 'user_id', 'action', 'entity', 'entity_id', 'timestamp',
    ]


def test_settings_headers():
    assert SHEET_HEADERS['_data_settings'] == ['key', 'value']


def test_seed_lov_covers_all_categories():
    categories = {row[0] for row in SEED_LOV}
    assert categories == {'referral_source', 'religion', 'language', 'appointment_type'}


def test_seed_lov_row_shape():
    for row in SEED_LOV:
        assert len(row) == 3, f'Expected (category, value, sort_order), got {row}'
        assert isinstance(row[0], str)
        assert isinstance(row[1], str)
        assert isinstance(row[2], int)


def test_seed_settings_required_keys():
    keys = {row[0] for row in SEED_SETTINGS}
    assert 'retention_months' in keys
    assert 'purge_frequency' in keys
    assert 'last_purge_date' in keys


def test_seed_settings_defaults():
    d = {row[0]: row[1] for row in SEED_SETTINGS}
    assert d['retention_months'] == '12'
    assert d['purge_frequency'] == 'quarterly'
    assert d['last_purge_date'] == ''


def test_seed_consultants_shape():
    for row in SEED_CONSULTANTS:
        assert len(row) == 3, f'Expected (name, is_chaplain, is_active), got {row}'
        assert isinstance(row[0], str)
        assert row[1] in (0, 1)
        assert row[2] in (0, 1)


def test_seed_consultants_default():
    assert SEED_CONSULTANTS[0] == ('Frances', 1, 1)


def test_no_orphan_header_keys():
    for key in SHEET_HEADERS:
        assert key in DATA_SHEETS, f'SHEET_HEADERS has orphan key not in DATA_SHEETS: {key}'


def test_no_duplicate_columns():
    for sheet_name, cols in SHEET_HEADERS.items():
        assert len(cols) == len(set(cols)), f'Duplicate column in {sheet_name}: {cols}'


def test_anchor_sheet_distinct_from_data_and_ui_sheets():
    # Excel refuses to hide the last remaining visible sheet in a workbook, so
    # Workbook_Open hides all UI sheets behind this always-visible anchor sheet
    # instead. It must never collide with a data or UI sheet name.
    assert ANCHOR_SHEET not in DATA_SHEETS
    assert ANCHOR_SHEET not in UI_SHEETS


def test_excel_build_version_recorded_in_seed_settings():
    d = {row[0]: row[1] for row in SEED_SETTINGS}
    assert d['excel_build_version'] == str(EXCEL_BUILD_VERSION)


def test_default_output_path_is_versioned():
    # A new build must never share a filename with a pre-versioning
    # (or older-versioned) file already sitting on a coordinator's machine --
    # see modUpgrade's in-app import for how an old file actually gets merged in.
    path = _default_output_path()
    assert os.path.basename(path) == f'AmbulatoryPatients-v{EXCEL_BUILD_VERSION}.xlsm'
