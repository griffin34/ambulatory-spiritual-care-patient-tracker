# excel/build.py
import os
import sys

# ─── Sheet definitions ────────────────────────────────────────────────────────

DATA_SHEETS = [
    '_data_users',
    '_data_patients',
    '_data_status_history',
    '_data_appointments',
    '_data_consultants',
    '_data_lov',
    '_data_audit',
    '_data_settings',
]

UI_SHEETS = ['WorkQueue', 'Appointments', 'Reports', 'Admin']

SHEET_HEADERS = {
    '_data_users': [
        'id', 'name', 'email', 'password_hash', 'role', 'is_active', 'created_at',
    ],
    '_data_patients': [
        'id', 'mrn', 'last_name', 'first_name', 'middle_name', 'phone',
        'date_of_referral', 'referral_source_id', 'religion_id', 'language_id',
        'current_status', 'is_active', 'created_at',
    ],
    '_data_status_history': [
        'id', 'patient_id', 'status', 'changed_by', 'changed_at',
    ],
    '_data_appointments': [
        'id', 'patient_id', 'date', 'time', 'type_id', 'consultant_id',
        'is_last_appointment', 'status', 'notes', 'created_at',
    ],
    '_data_consultants': [
        'id', 'name', 'is_chaplain', 'is_active',
    ],
    '_data_lov': [
        'id', 'category', 'value', 'is_active', 'sort_order',
    ],
    '_data_audit': [
        'id', 'user_id', 'action', 'entity', 'entity_id', 'timestamp',
    ],
    '_data_settings': [
        'key', 'value',
    ],
}

# Default list-of-values: (category, value, sort_order)
SEED_LOV = [
    ('referral_source', 'Physician Referral', 1),
    ('referral_source', 'Social Worker', 2),
    ('referral_source', 'Family Request', 3),
    ('referral_source', 'Nursing Staff', 4),
    ('referral_source', 'Self Referral', 5),
    ('religion', 'Catholic', 1),
    ('religion', 'Protestant', 2),
    ('religion', 'Jewish', 3),
    ('religion', 'Muslim', 4),
    ('religion', 'Buddhist', 5),
    ('religion', 'Hindu', 6),
    ('religion', 'None / No Preference', 7),
    ('religion', 'Other', 8),
    ('language', 'English', 1),
    ('language', 'Spanish', 2),
    ('language', 'Arabic', 3),
    ('language', 'Tagalog', 4),
    ('language', 'Other', 5),
    ('appointment_type', 'In Person', 1),
    ('appointment_type', 'Video', 2),
    ('appointment_type', 'Phone', 3),
    ('appointment_type', 'Bedside', 4),
]

# Default settings: (key, value-as-string)
SEED_SETTINGS = [
    ('retention_months', '12'),
    ('purge_frequency', 'quarterly'),
    ('last_purge_date', ''),
]

# Default consultants: (name, is_chaplain, is_active)
SEED_CONSULTANTS = [
    ('Frances', 1, 1),
]

# ─── Build (requires Excel for Mac or Windows + xlwings) ─────────────────────

def build_workbook(output_path=None, src_dir=None):
    """Create AmbulatoryPatients.xlsm via xlwings (Mac or Windows).

    One-time setup in Excel:
      Mac:     Excel → Preferences → Security →
               check 'Trust access to the VBA project object model'
      Windows: File → Options → Trust Center → Trust Center Settings →
               Macro Settings → check 'Trust access to the VBA project object model'
    """
    import xlwings as xw

    here = os.path.dirname(os.path.abspath(__file__))
    if output_path is None:
        output_path = os.path.join(here, 'dist', 'AmbulatoryPatients.xlsm')
    if src_dir is None:
        src_dir = os.path.join(here, 'src')

    output_path = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    if os.path.exists(output_path):
        os.remove(output_path)

    app = None
    wb = None
    try:
        app = xw.App(visible=False)
        app.display_alerts = False
        wb = app.books.add()
        _setup_sheets(wb)
        _write_headers(wb)
        _seed_data(wb)
        _import_vba(wb, src_dir)
        _configure_workbook(wb)
        wb.api.SaveAs(output_path, FileFormat=52)  # 52 = xlOpenXMLMacroEnabled
        print(f'Built: {output_path}')
    finally:
        if wb is not None:
            wb.close()
        if app is not None:
            app.quit()


def _setup_sheets(wb):
    """Create data sheets then UI sheets in the specified order."""
    while len(wb.sheets) > 1:
        wb.sheets[-1].delete()
    wb.sheets[0].name = DATA_SHEETS[0]
    for name in DATA_SHEETS[1:]:
        wb.sheets.add(name=name, after=wb.sheets[-1])
    for name in UI_SHEETS:
        wb.sheets.add(name=name, after=wb.sheets[-1])


def _write_headers(wb):
    """Write bold column headers to all data sheets."""
    for sheet_name, cols in SHEET_HEADERS.items():
        ws = wb.sheets[sheet_name]
        for col_idx, col_name in enumerate(cols, 1):
            ws.cells(1, col_idx).value = col_name
            ws.cells(1, col_idx).api.Font.Bold = True


def _seed_data(wb):
    """Write default rows to _data_lov, _data_settings, _data_consultants."""
    # _data_lov
    lov_ws = wb.sheets['_data_lov']
    for row_idx, (category, value, sort_order) in enumerate(SEED_LOV, 2):
        lov_ws.cells(row_idx, 1).value = row_idx - 1  # id
        lov_ws.cells(row_idx, 2).value = category
        lov_ws.cells(row_idx, 3).value = value
        lov_ws.cells(row_idx, 4).value = 1             # is_active
        lov_ws.cells(row_idx, 5).value = sort_order

    # _data_settings
    settings_ws = wb.sheets['_data_settings']
    for row_idx, (key, value) in enumerate(SEED_SETTINGS, 2):
        settings_ws.cells(row_idx, 1).value = key
        settings_ws.cells(row_idx, 2).value = value

    # _data_consultants
    cons_ws = wb.sheets['_data_consultants']
    for row_idx, (name, is_chaplain, is_active) in enumerate(SEED_CONSULTANTS, 2):
        cons_ws.cells(row_idx, 1).value = row_idx - 1  # id
        cons_ws.cells(row_idx, 2).value = name
        cons_ws.cells(row_idx, 3).value = is_chaplain
        cons_ws.cells(row_idx, 4).value = is_active


def _import_vba(wb, src_dir):
    """Import .bas, .cls, and .frm source files from src_dir into the VBA project."""
    if not os.path.isdir(src_dir):
        print(f'  src/ not found, skipping VBA import: {src_dir}')
        return
    try:
        vbp = wb.api.VBProject
    except Exception:
        raise RuntimeError(
            'Cannot access VBA project.\n'
            '  Mac:     Excel → Preferences → Security → '
            'check "Trust access to the VBA project object model"\n'
            '  Windows: File → Options → Trust Center → Trust Center Settings → '
            'Macro Settings → check "Trust access to the VBA project object model"'
        )
    for filename in sorted(os.listdir(src_dir)):
        ext = os.path.splitext(filename)[1].lower()
        if ext in ('.bas', '.cls', '.frm'):
            filepath = os.path.abspath(os.path.join(src_dir, filename))
            vbp.VBComponents.Import(filepath)
            print(f'  Imported: {filename}')


def _configure_workbook(wb):
    """Hide all data sheets (xlVeryHidden) and activate WorkQueue."""
    XL_VERY_HIDDEN = -2
    for name in DATA_SHEETS:
        wb.sheets[name].api.Visible = XL_VERY_HIDDEN
    wb.sheets['WorkQueue'].activate()


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else None
    build_workbook(out)
