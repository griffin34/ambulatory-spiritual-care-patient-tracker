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

# Always-visible placeholder sheet. Excel refuses to hide the last remaining
# visible sheet in a workbook, so Workbook_Open hides the 4 UI sheets behind
# this one instead of trying to hide every non-data sheet.
ANCHOR_SHEET = 'Splash'

SHEET_HEADERS = {
    '_data_users': [
        'id', 'name', 'email', 'password_hash', 'role', 'is_active', 'created_at',
    ],
    '_data_patients': [
        'id', 'mrn', 'last_name', 'first_name', 'middle_name', 'phone',
        'date_of_referral', 'referral_source_id', 'religion_id', 'language_id',
        'current_status', 'is_active',
        'sdat_begin_score', 'sdat_begin_date', 'sdat_end_score', 'sdat_end_date',
        'sdat_pct_improvement', 'notes',
        'created_at',
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
        _configure_thisworkbook(wb, src_dir)
        _configure_workbook(wb)
        _save_workbook(wb, output_path)
        print(f'Built: {output_path}')
    finally:
        if wb is not None:
            wb.close()
        if app is not None:
            app.quit()


def _setup_sheets(wb):
    """Create data sheets, then UI sheets, then the anchor sheet, in that order."""
    while len(wb.sheets) > 1:
        wb.sheets[-1].delete()
    wb.sheets[0].name = DATA_SHEETS[0]
    for name in DATA_SHEETS[1:]:
        wb.sheets.add(name=name, after=wb.sheets[-1])
    for name in UI_SHEETS:
        wb.sheets.add(name=name, after=wb.sheets[-1])
    wb.sheets.add(name=ANCHOR_SHEET, after=wb.sheets[-1])
    anchor = wb.sheets[ANCHOR_SHEET]
    anchor.range('A1').value = 'Ambulatory Patient Tracking'
    anchor.range('A1').font.bold = True
    anchor.range('A1').font.size = 14


def _write_headers(wb):
    """Write bold column headers to all data sheets."""
    for sheet_name, cols in SHEET_HEADERS.items():
        ws = wb.sheets[sheet_name]
        for col_idx, col_name in enumerate(cols, 1):
            ws.cells(1, col_idx).value = col_name
            ws.cells(1, col_idx).font.bold = True


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


# ThisWorkbook always exists in a new workbook and can't be Import()ed like a
# normal component — its code is merged into the existing module separately
# by _configure_thisworkbook().
_THISWORKBOOK_FILENAME = 'ThisWorkbook.cls'


def _import_vba(wb, src_dir):
    """Import .bas, .cls, and .frm source files from src_dir into the VBA project.

    Requires COM access (Windows) or a COM bridge (Windows via xlwings).
    On Mac, VBProject is not accessible via appscript — prints instructions instead.
    """
    if not os.path.isdir(src_dir):
        print(f'  src/ not found, skipping VBA import: {src_dir}')
        return
    try:
        vbp = wb.api.VBProject
    except AttributeError:
        # Mac: appscript does not expose VBProject — manual import required.
        vba_files = sorted(
            f for f in os.listdir(src_dir)
            if os.path.splitext(f)[1].lower() in ('.bas', '.cls', '.frm')
            and f != _THISWORKBOOK_FILENAME
        )
        print('\n  ⚠️  VBA import skipped (Mac/appscript limitation).')
        print('  Open the saved workbook in Excel, then in the VBA editor (⌥F11):')
        print('    File → Import File — import each of these in order:')
        for f in vba_files:
            print(f'      {os.path.join(src_dir, f)}')
        print(f'  Then manually paste the code from {_THISWORKBOOK_FILENAME} into ThisWorkbook.')
        print()
        return
    except Exception:
        raise RuntimeError(
            'Cannot access VBA project.\n'
            '  Mac:     Excel → Preferences → Security → '
            'check "Trust access to the VBA project object model"\n'
            '  Windows: File → Options → Trust Center → Trust Center Settings → '
            'Macro Settings → check "Trust access to the VBA project object model"'
        )
    for filename in sorted(os.listdir(src_dir)):
        if filename == _THISWORKBOOK_FILENAME:
            continue
        ext = os.path.splitext(filename)[1].lower()
        if ext in ('.bas', '.cls', '.frm'):
            filepath = os.path.abspath(os.path.join(src_dir, filename))
            vbp.VBComponents.Import(filepath)
            print(f'  Imported: {filename}')


def _configure_thisworkbook(wb, src_dir):
    """Inject ThisWorkbook.cls's code body into the workbook's built-in ThisWorkbook module.

    ThisWorkbook always exists and can't be replaced via VBComponents.Import(), so
    its code is copied in line-by-line instead, skipping the exported .cls header
    (VERSION/BEGIN/END/Attribute lines) which only applies to standalone import.
    """
    path = os.path.join(src_dir, _THISWORKBOOK_FILENAME)
    if not os.path.isfile(path):
        print(f'  {_THISWORKBOOK_FILENAME} not found, skipping ThisWorkbook code injection')
        return
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()

    body_start = 0
    for i, line in enumerate(lines):
        if line.strip().startswith('Attribute VB_'):
            body_start = i + 1
    body = ''.join(lines[body_start:]).lstrip('\n')

    try:
        vbp = wb.api.VBProject
    except AttributeError:
        return  # Mac path already printed instructions in _import_vba
    cm = vbp.VBComponents('ThisWorkbook').CodeModule
    if cm.CountOfLines > 0:
        cm.DeleteLines(1, cm.CountOfLines)
    cm.AddFromString(body)
    print(f'  Configured: ThisWorkbook')


def _save_workbook(wb, output_path):
    """Save the workbook as .xlsm using platform-appropriate API."""
    try:
        # Windows COM: SaveAs with explicit FileFormat=52 (xlOpenXMLMacroEnabled)
        wb.api.SaveAs(output_path, FileFormat=52)
    except AttributeError:
        # Mac appscript: use xlwings save() — file extension determines format
        wb.save(output_path)


def _configure_workbook(wb):
    """Very-hide all data sheets, hide the UI sheets, and activate the anchor sheet.

    Data sheets are set fully xlSheetVeryHidden (2) so they can't be revealed via
    the right-click Unhide menu, only from VBA. UI sheets start hidden too — they
    only become visible after a successful login (see ThisWorkbook/LoginForm) —
    leaving Splash as the sole visible sheet, which is required: Excel refuses to
    leave a workbook with zero visible sheets.
    """
    for name in DATA_SHEETS:
        try:
            wb.sheets[name].api.Visible = 2  # xlSheetVeryHidden
        except AttributeError:
            wb.sheets[name].visible = False  # Mac: no very-hidden via appscript
    for name in UI_SHEETS:
        wb.sheets[name].visible = False
    try:
        wb.sheets[ANCHOR_SHEET].activate()
    except Exception:
        pass  # Mac invisible app cannot activate sheets; anchor is still first visible


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else None
    build_workbook(out)
