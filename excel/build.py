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

# ─── Build (requires Windows + Excel + pywin32) ───────────────────────────────

def build_workbook(output_path=None, src_dir=None):
    """Create AmbulatoryPatients.xlsm via Excel COM automation.

    Run on Windows with Excel installed. One-time setup required:
    Excel -> Options -> Trust Center -> Trust Center Settings ->
    Macro Settings -> check 'Trust access to the VBA project object model'.
    """
    import win32com.client as win32

    here = os.path.dirname(os.path.abspath(__file__))
    if output_path is None:
        output_path = os.path.join(here, 'dist', 'AmbulatoryPatients.xlsm')
    if src_dir is None:
        src_dir = os.path.join(here, 'src')

    output_path = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    if os.path.exists(output_path):
        os.remove(output_path)

    excel = None
    wb = None
    try:
        excel = win32.Dispatch('Excel.Application')
        excel.Visible = False
        excel.DisplayAlerts = False
        wb = excel.Workbooks.Add()
        _setup_sheets(wb)
        _write_headers(wb)
        _seed_data(wb)
        _import_vba(wb, src_dir)
        _configure_workbook(wb)
        wb.SaveAs(output_path, FileFormat=52)  # 52 = xlOpenXMLMacroEnabled
        print(f'Built: {output_path}')
    finally:
        if wb is not None:
            wb.Close(False)
        if excel is not None:
            excel.Quit()


def _setup_sheets(wb):
    """Create data sheets then UI sheets in the specified order."""
    while wb.Sheets.Count > 1:
        wb.Sheets(wb.Sheets.Count).Delete()
    wb.Sheets(1).Name = DATA_SHEETS[0]
    for name in DATA_SHEETS[1:]:
        wb.Sheets.Add(After=wb.Sheets(wb.Sheets.Count)).Name = name
    for name in UI_SHEETS:
        wb.Sheets.Add(After=wb.Sheets(wb.Sheets.Count)).Name = name


def _write_headers(wb):
    """Write bold column headers to all data sheets."""
    for sheet_name, cols in SHEET_HEADERS.items():
        ws = wb.Sheets(sheet_name)
        for col_idx, col_name in enumerate(cols, 1):
            cell = ws.Cells(1, col_idx)
            cell.Value = col_name
            cell.Font.Bold = True


def _seed_data(wb):
    """Write default rows to _data_lov, _data_settings, _data_consultants."""
    # _data_lov
    lov_ws = wb.Sheets('_data_lov')
    for row_idx, (category, value, sort_order) in enumerate(SEED_LOV, 2):
        lov_ws.Cells(row_idx, 1).Value = row_idx - 1  # id
        lov_ws.Cells(row_idx, 2).Value = category
        lov_ws.Cells(row_idx, 3).Value = value
        lov_ws.Cells(row_idx, 4).Value = 1             # is_active
        lov_ws.Cells(row_idx, 5).Value = sort_order

    # _data_settings
    settings_ws = wb.Sheets('_data_settings')
    for row_idx, (key, value) in enumerate(SEED_SETTINGS, 2):
        settings_ws.Cells(row_idx, 1).Value = key
        settings_ws.Cells(row_idx, 2).Value = value

    # _data_consultants
    cons_ws = wb.Sheets('_data_consultants')
    for row_idx, (name, is_chaplain, is_active) in enumerate(SEED_CONSULTANTS, 2):
        cons_ws.Cells(row_idx, 1).Value = row_idx - 1  # id
        cons_ws.Cells(row_idx, 2).Value = name
        cons_ws.Cells(row_idx, 3).Value = is_chaplain
        cons_ws.Cells(row_idx, 4).Value = is_active


def _import_vba(wb, src_dir):
    """Import .bas, .cls, and .frm source files from src_dir into the VBA project."""
    if not os.path.isdir(src_dir):
        print(f'  src/ not found, skipping VBA import: {src_dir}')
        return
    try:
        vbp = wb.VBProject
    except Exception:
        raise RuntimeError(
            'Cannot access VBA project. In Excel: File -> Options -> Trust Center -> '
            'Trust Center Settings -> Macro Settings -> check '
            '"Trust access to the VBA project object model".'
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
        wb.Sheets(name).Visible = XL_VERY_HIDDEN
    wb.Sheets('WorkQueue').Activate()


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else None
    build_workbook(out)
