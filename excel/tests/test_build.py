import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from build import DATA_SHEETS, UI_SHEETS, SHEET_HEADERS, SEED_LOV, SEED_SETTINGS


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
        'id', 'name', 'email', 'password_hash', 'role', 'is_active', 'created_at',
    ]


def test_patients_headers():
    assert SHEET_HEADERS['_data_patients'] == [
        'id', 'mrn', 'last_name', 'first_name', 'middle_name', 'phone',
        'date_of_referral', 'referral_source_id', 'religion_id', 'language_id',
        'current_status', 'is_active', 'created_at',
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
