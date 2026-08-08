# excel/build.py
import datetime
import os
import sys

# Bumped whenever SHEET_HEADERS or seed data structure changes. Drives the
# default output filename (AmbulatoryPatients-v{N}.xlsm) so a new build never
# collides with a coordinator's existing file on disk, and is recorded into
# _data_settings (see SEED_SETTINGS) so it's discoverable from inside the file
# too. Not load-bearing for modUpgrade's in-app import -- that merges by
# column name and self-migrates regardless of what version a file claims.
EXCEL_BUILD_VERSION = 1

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
        'id', 'name', 'username', 'email', 'password_hash', 'role', 'is_active', 'created_at',
        'security_question', 'security_answer_hash',
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
    ('excel_build_version', str(EXCEL_BUILD_VERSION)),
]

# Default consultants: (name, is_chaplain, is_active)
SEED_CONSULTANTS = [
    ('Frances', 1, 1),
]

# ─── Build (requires Excel for Mac or Windows + xlwings) ─────────────────────

def _default_output_path():
    """Pure (no xlwings/COM) so tests can check the versioned filename directly."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, 'dist', f'AmbulatoryPatients-v{EXCEL_BUILD_VERSION}.xlsm')


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
        output_path = _default_output_path()
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
        # Once VBA is imported and the sheet code-behind is wired (below), this
        # function's own cell writes (e.g. _build_admin_sheet's default
        # category dropdown value) would otherwise fire real Worksheet_Change
        # handlers mid-build -- e.g. Admin.cls's handler calls
        # modAdmin.RefreshLovTable, which looks up the tblLov ListObject before
        # this function has created it yet, throwing a blocking native
        # "Run-time error 9: Subscript out of range" dialog. No VBA business
        # logic should run while build.py is just constructing structure.
        app.api.EnableEvents = False
        wb = app.books.add()
        _setup_sheets(wb)
        _write_headers(wb)
        # Text-format date/timestamp columns (and _data_settings' value column)
        # BEFORE seeding any values into them -- otherwise a numeric-looking
        # seed string (e.g. SEED_SETTINGS' '12'/'1') gets silently coerced into
        # a real number under the default General format at write time, same
        # failure mode _format_date_columns_as_text exists to prevent for dates.
        _format_date_columns_as_text(wb)
        _seed_data(wb)
        _import_vba(wb, src_dir)
        for filename, component_name in _SHEET_CODE_FILES.items():
            _configure_sheet_code(wb, component_name, filename, src_dir)
        _build_workqueue_sheet(wb)
        _build_appointments_sheet(wb)
        _build_admin_sheet(wb)
        _build_reports_sheet(wb)
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


def _col_letter(idx):
    """Convert a 1-based column index to its Excel column letter (A, B, ..., Z)."""
    return chr(64 + idx)


def _format_date_columns_as_text(wb):
    """Format every date/timestamp-ish column as Text ('@') so ISO strings
    ('YYYY-MM-DD' / 'YYYY-MM-DD HH:MM:SS') written by VBA are stored literally,
    matching the data model's documented String type -- instead of Excel
    silently auto-converting them to locale-dependent Date serials, which
    would break every downstream string-based date comparison/sort/filter
    (CStr() of a real Date value renders in the system locale's short-date
    format, not necessarily ISO).
    """
    for sheet_name, cols in SHEET_HEADERS.items():
        ws = wb.sheets[sheet_name]
        for idx, col_name in enumerate(cols, 1):
            lower = col_name.lower()
            if 'date' in lower or lower.endswith('_at') or lower == 'time' or lower == 'timestamp':
                col_letter = _col_letter(idx)
                ws.range(f'{col_letter}:{col_letter}').api.NumberFormat = '@'
    # _data_settings' generic 'value' column holds last_purge_date (Phase 5) too.
    wb.sheets['_data_settings'].range('B:B').api.NumberFormat = '@'


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


# ThisWorkbook and every worksheet's own code module always exist in a new
# workbook and can't be Import()ed like a normal component — their code is
# merged into the existing module separately by _configure_sheet_code().
_SHEET_CODE_FILES = {
    'ThisWorkbook.cls': 'ThisWorkbook',
    'WorkQueue.cls': 'WorkQueue',
    'Appointments.cls': 'Appointments',
    'Reports.cls': 'Reports',
    'Admin.cls': 'Admin',
}


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
            and f not in _SHEET_CODE_FILES
        )
        print('\n  ⚠️  VBA import skipped (Mac/appscript limitation).')
        print('  Open the saved workbook in Excel, then in the VBA editor (⌥F11):')
        print('    File → Import File — import each of these in order:')
        for f in vba_files:
            print(f'      {os.path.join(src_dir, f)}')
        print('  Then manually paste the code from each of these into its matching')
        print('  built-in module (ThisWorkbook, and each sheet\'s own code module):')
        for f in sorted(_SHEET_CODE_FILES):
            print(f'      {os.path.join(src_dir, f)}')
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
        if filename in _SHEET_CODE_FILES:
            continue
        ext = os.path.splitext(filename)[1].lower()
        if ext in ('.bas', '.cls', '.frm'):
            filepath = os.path.abspath(os.path.join(src_dir, filename))
            vbp.VBComponents.Import(filepath)
            print(f'  Imported: {filename}')


def _configure_sheet_code(wb, component_name, filename, src_dir):
    """Inject a .cls file's code body into an already-existing built-in code module.

    ThisWorkbook and every worksheet's own code module always exist and can't be
    replaced via VBComponents.Import(), so their code is copied in line-by-line
    instead, skipping the exported .cls header (VERSION/BEGIN/END/Attribute lines)
    which only applies to standalone import.
    """
    path = os.path.join(src_dir, filename)
    if not os.path.isfile(path):
        print(f'  {filename} not found, skipping {component_name} code injection')
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

    # `component_name` is either the literal 'ThisWorkbook' or a worksheet's tab
    # name -- a fresh sheet's actual VBA CodeName (e.g. 'Sheet9') is auto-assigned
    # by Excel and unrelated to its tab name, so it has to be looked up dynamically.
    if component_name == 'ThisWorkbook':
        vba_component_name = 'ThisWorkbook'
    else:
        vba_component_name = wb.sheets[component_name].api.CodeName

    cm = vbp.VBComponents(vba_component_name).CodeModule
    if cm.CountOfLines > 0:
        cm.DeleteLines(1, cm.CountOfLines)
    cm.AddFromString(body)
    print(f'  Configured: {component_name}')


# Status Workflow colors from the design spec, keyed by the human-readable label
# shown in the WorkQueue table (VBA's StatusLabel()/StatusInternal() map these to
# the current_status internal values).
STATUS_COLORS = {
    'Ready to Schedule': '#C6EFCE',
    'Scheduled': '#FFEB9C',
    'Completed': '#9DC3E6',
    'Dropped': '#FFC7CE',
    'On Hold': '#D9D9D9',
    'Deleted': '#BFBFBF',
}


def _hex_to_bgr(hex_color):
    """Convert a '#RRGGBB' string to the BGR-packed integer Excel's Interior.Color expects."""
    hex_color = hex_color.lstrip('#')
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)
    return r + g * 256 + b * 65536


def _add_button(ws, cell, caption, macro, width=110, height=20):
    """Add a Forms-control button anchored at `cell`'s top-left corner, wired to `macro`.

    Placement is forced to xlFreeFloating (3) -- Buttons().Add() defaults to
    xlMoveAndSize (1), which RESIZES the button whenever the underlying row/
    column is resized. That default is what caused the row-height fix to grow
    the button right along with the row instead of just giving it more room.
    """
    anchor = ws.range(cell).api
    btn = ws.api.Buttons().Add(anchor.Left, anchor.Top, width, height)
    btn.Caption = caption
    btn.OnAction = macro
    btn.Placement = 3  # xlFreeFloating -- fixed size/position, ignores row/column resizes
    return btn


def _add_button_after(ws, prev_btn, caption, macro, width=110, height=20, gap=10):
    """Add a button positioned relative to a previously-created button's real,
    measured Left/Width/Top -- not another cell anchor.

    Confirmed on WorkQueue's row-1 toolbar: cell-anchored buttons placed via
    _add_button can end up overlapping their neighbors even though each one
    individually gets its own coded width -- e.g. the Search/+Add Patient/
    View Patient/Export/Logout button chain, where every consecutive pair
    overlapped by 14-22pt despite each _add_button call looking correct in
    isolation (traced to H1's own button ending up 159pt wide instead of the
    coded 110pt default, for reasons that didn't resolve to any single
    column-width change in this function -- Placement=xlFreeFloating should
    make a button's position/size immune to later row/column resizes, but
    empirically did not here). Chaining off the prior button's real, just-
    measured geometry sidesteps the problem entirely regardless of cause.
    """
    left = prev_btn.Left + prev_btn.Width + gap
    btn = ws.api.Buttons().Add(left, prev_btn.Top, width, height)
    btn.Caption = caption
    btn.OnAction = macro
    btn.Placement = 3  # xlFreeFloating
    return btn


def _add_button_below(ws, prev_btn, caption, macro, width=110, height=20, gap=10):
    """Same idea as _add_button_after, but stacks a button below a previously-
    created one (same Left, Top computed from the real measured bottom edge)
    instead of beside it. Use this instead of a cell anchor one row down when
    that row's real RowHeight won't be finalized until later in the same
    build function -- a cell anchor placed too early computes against
    whatever height the row still has at that moment, not its final one."""
    top = prev_btn.Top + prev_btn.Height + gap
    btn = ws.api.Buttons().Add(prev_btn.Left, top, width, height)
    btn.Caption = caption
    btn.OnAction = macro
    btn.Placement = 3  # xlFreeFloating
    return btn


def _add_pick_date_button(ws, cell, macro, width=20):
    """Adds a small '...' date-picker button overlapping the right edge of a
    date input cell, wired to `macro` (a modReports.UI_Pick* Sub that shows
    CalendarPickerForm and writes the result back into this same cell).

    Overlapping the cell's own right edge -- rather than a neighboring column
    -- avoids restructuring the Reports sheet's already tightly-packed
    per-section column layout (each section's From/To/Run/Export controls
    already fill A:F with no free column to anchor a new button on).
    """
    anchor = ws.range(cell).api
    btn = ws.api.Buttons().Add(anchor.Left + anchor.Width - width, anchor.Top, width, anchor.Height)
    btn.Caption = '...'
    btn.OnAction = macro
    btn.Placement = 3  # xlFreeFloating
    return btn


def _protect_sheet(ws, unlocked_ranges=None):
    """Lock the whole sheet except explicitly-unlocked input cells, then protect
    it so a stray click-and-type can't corrupt hidden ID columns, table bodies,
    or other structural cells. Call this LAST in each sheet-build function --
    after every table/button/validation is already in place -- since sheet
    protection can interfere with further build-time COM structural changes.

    VBA's own writes (RefreshWorkQueue, etc.) are unaffected at build time, but
    the UserInterfaceOnly flag that allows that does NOT persist across a save/
    reopen -- ThisWorkbook.Workbook_Open re-applies it every session.
    """
    if unlocked_ranges:
        for addr in unlocked_ranges:
            ws.range(addr).api.Locked = False
    ws.api.Protect(DrawingObjects=True, Contents=True, Scenarios=True,
                    AllowFiltering=True, AllowSorting=True)


def _build_workqueue_sheet(wb):
    """Build the WorkQueue sheet: filter row, stats cell, patient table, buttons.

    Column layout: A=ID (hidden), B=Last Name, C=First Name, D=MRN, E=Referral Date,
    F=Referral Source, G=Language, H=Next Appointment, I=Status. Row 1 holds filter
    controls + action buttons, row 2 the stats summary, row 4 the table header
    (row 5+ = data, rewritten wholesale by modPatients.RefreshWorkQueue on every
    load). Column P (hidden) is a helper range feeding the Referral Source dropdown's
    dynamic list, since that list is admin-editable and can't be hardcoded.
    """
    ws = wb.sheets['WorkQueue']

    # Column D also backs the table's short 'MRN' header below, so it never
    # gets auto-widened the way E/F/G do (their table headers -- 'Referral
    # Date'/'Referral Source'/'Language' -- are long enough to pull it in).
    # Without this, 'Referral Source:' truncates to 'Referral Sc' because E1
    # (the dropdown) is non-blank and blocks overflow.
    ws.range('D:D').api.ColumnWidth = 17  # ~101pt, fits 'Referral Source:' (16 chars)

    # Filter row is shifted one column right of the table's natural start
    # (B.. instead of A..) because tblWorkQueue's ID column below is A, and
    # EntireColumn.Hidden hides ALL rows in that column -- a label placed
    # directly in A (as this row originally was) silently disappears along
    # with the ID column. Column A stays completely empty/hidden here so
    # nothing sits on it; since it's 0-width, B visually sits flush against
    # the sheet's left edge exactly as if it were still the first column.
    ws.range('B1').value = 'Status:'
    ws.range('D1').value = 'Referral Source:'
    ws.range('F1').value = 'Search:'

    status_list = 'All,' + ','.join(STATUS_COLORS.keys())
    ws.range('C1').api.Validation.Add(3, 1, Formula1=status_list)  # xlValidateList
    ws.range('C1').value = 'All'

    ws.range('E1').api.Validation.Add(3, 1, Formula1='=$P$2:$P$50')
    ws.range('E1').value = 'All'

    ws.range('G1').value = ''

    # Only the first button anchors to a real cell (H1) -- every button after
    # it chains off the previous one's real measured position via
    # _add_button_after, not another cell reference (see that helper's
    # docstring for why: cell-anchored placement silently overlapped here).
    search_btn = _add_button(ws, 'H1', 'Search', 'modPatients.RefreshWorkQueue')
    add_patient_btn = _add_button_after(ws, search_btn, '+ Add Patient', 'modPatients.UI_OpenAddPatient')
    view_patient_btn = _add_button_after(ws, add_patient_btn, 'View Patient', 'modPatients.UI_ViewSelectedPatient')
    export_btn = _add_button_after(ws, view_patient_btn, 'Export', 'modPatients.UI_ExportWorkQueue', width=70)
    logout_btn = _add_button_after(ws, export_btn, 'Logout', 'modAuth.UI_Logout', width=70)
    _add_button_after(ws, logout_btn, 'Security Question', 'modAdmin.UI_OpenMySecurityQuestion', width=140)

    ws.range('1:1').api.RowHeight = 22  # buttons are 20pt tall -- default row height (~15pt) let them overhang into row 2

    ws.range('B2').value = 'Total Active: 0'

    headers = ['ID', 'Last Name', 'First Name', 'MRN', 'Referral Date',
               'Referral Source', 'Language', 'Next Appointment', 'Status']
    ws.range('A4').value = headers
    tbl = ws.api.ListObjects.Add(1, ws.range('A4:I4').api, None, 1)  # xlSrcRange, xlYes
    tbl.Name = 'tblWorkQueue'
    tbl.ListColumns('ID').Range.EntireColumn.Hidden = True

    # Text format so the ISO date strings RefreshWorkQueue writes here don't
    # get silently re-parsed into locale-dependent Date serials on write.
    ws.range('E:E').api.NumberFormat = '@'  # Referral Date
    ws.range('H:H').api.NumberFormat = '@'  # Next Appointment

    cf_range = ws.range('I5:I2000').api
    for label, hexcolor in STATUS_COLORS.items():
        fc = cf_range.FormatConditions.Add(1, 3, f'"{label}"')  # xlCellValue, xlEqual
        fc.Interior.Color = _hex_to_bgr(hexcolor)

    ws.range('P1').value = 'Referral Source Helper (do not edit)'
    ws.range('P:P').api.EntireColumn.Hidden = True

    _protect_sheet(ws, unlocked_ranges=['C1', 'E1', 'G1'])


def _build_appointments_sheet(wb):
    """Build the Appointments sheet: date nav row, status summary, appointment table.

    Column layout: A=ID (hidden), B=Time, C=Patient, D=Consultant, E=Type,
    F=Status, G=Last Appt, H=Notes. B1 holds the currently selected date (ISO
    text), updated by the nav buttons and read by modAppointments.RefreshAppointments
    on every load/click; row 2 the status summary; row 4 the table header.
    """
    ws = wb.sheets['Appointments']

    # Default column width (~48pt) is narrower than these nav buttons (70-130pt)
    # -- widen before adding them so each button's column boundary clears its
    # full width, same fix as WorkQueue/Admin's button rows.
    ws.range('C:C').api.ColumnWidth = 16  # ~95pt, fits '< Prev Day' (90pt)
    ws.range('D:D').api.ColumnWidth = 16  # ~95pt, fits 'Next Day >' (90pt)
    ws.range('E:E').api.ColumnWidth = 13  # ~77pt, fits 'Today' (70pt)
    ws.range('F:F').api.ColumnWidth = 14  # ~83pt, fits '-14 Days' (80pt)
    ws.range('G:G').api.ColumnWidth = 23  # ~136pt, fits '+ Add Appointment' (130pt)

    # Text format before writing any values, so ISO date/time strings never
    # get silently re-parsed into locale-dependent Date/Time serials.
    ws.range('B:B').api.NumberFormat = '@'

    ws.range('A1').value = 'Date:'
    ws.range('B1').value = datetime.date.today().isoformat()

    _add_button(ws, 'C1', '< Prev Day', 'modAppointments.UI_PrevDay', width=90)
    _add_button(ws, 'D1', 'Next Day >', 'modAppointments.UI_NextDay', width=90)
    _add_button(ws, 'E1', 'Today', 'modAppointments.UI_Today', width=70)
    _add_button(ws, 'F1', '-14 Days', 'modAppointments.UI_Back14Days', width=80)
    _add_button(ws, 'G1', '+ Add Appointment', 'modAppointments.UI_OpenAddAppointment', width=130)
    _add_button(ws, 'I1', 'Export', 'modAppointments.UI_ExportDay', width=70)
    ws.range('1:1').api.RowHeight = 22  # buttons are 20pt tall -- default row height (~15pt) let them overhang into row 2

    ws.range('C2').value = 'Scheduled: 0   Completed: 0   No Show: 0   Cancelled: 0   Rescheduled: 0'

    headers = ['ID', 'Time', 'Patient', 'Consultant', 'Type', 'Status', 'Last Appt', 'Notes']
    ws.range('A4').value = headers
    tbl = ws.api.ListObjects.Add(1, ws.range('A4:H4').api, None, 1)  # xlSrcRange, xlYes
    tbl.Name = 'tblAppointments'
    tbl.ListColumns('ID').Range.EntireColumn.Hidden = True

    _protect_sheet(ws)  # nothing needs direct user entry -- the date is nav-button-driven only


def _build_admin_sheet(wb):
    """Build the Admin sheet: User Management (left) and List of Values (right).

    Users: A=ID (hidden), B=Name, C=Username, D=Email, E=Role, F=Active. Buttons
    operate on whichever row is currently selected (ActiveCell), same pattern
    as WorkQueue.

    LoV: H=ID (hidden), I=Value, J=Sort Order, K=Active, L=Chaplain -- the last
    column is only meaningful when Category=Consultants (a structurally
    different sheet: no sort_order, has is_chaplain); it's simply blank/ignored
    for the other 4 categories rather than dynamically hiding a column, to keep
    the table structure uniform. The table itself is read-only display --
    Add/Edit open AddEditLovForm (which shows the Sort Order field or the
    Chaplain checkbox, never both) rather than editing cells directly.
    """
    ws = wb.sheets['Admin']

    # Default column width (~48pt) is narrower than several action buttons
    # (80-90pt) -- packing consecutive buttons into unwidened columns makes
    # each button visually overlap/obscure the next. Widen the columns that
    # carry a button before adding it so its column boundary clears the
    # button's full width (matches the RowHeight fix's reasoning, but for the
    # horizontal axis).
    ws.range('B:B').api.ColumnWidth = 17  # ~100pt, fits '+ Add User' (90pt)
    ws.range('C:C').api.ColumnWidth = 15  # ~89pt, fits 'Reset PW' (80pt)
    ws.range('D:D').api.ColumnWidth = 15  # ~89pt, fits 'Deactivate' (80pt)
    # E is the tblUsers Role data column -- not a button column, but left at
    # the 48pt default 'coordinator' (11 chars) clips.
    ws.range('E:E').api.ColumnWidth = 15  # ~89pt, fits 'coordinator'
    # F holds both the tblUsers Active data column below AND the 'Edit
    # Username' button in row 2 -- widened for the button (110pt), well past
    # what 'Inactive' (8 chars) alone would need.
    ws.range('F:F').api.ColumnWidth = 20  # ~118pt, fits 'Edit Username' button (110pt)
    # I is the category dropdown's own value cell -- longest option is
    # 'Appointment Types' (18 chars). Left at the 48pt default, that text
    # overflowed into J (blank cell, no value) and got visually covered by
    # the LoV row's Deactivate button sitting there, since the button's
    # opaque shape masks whatever the cell overflow renders underneath it.
    ws.range('I:I').api.ColumnWidth = 20  # ~118pt, fits 'Appointment Types' (18 chars)
    ws.range('J:J').api.ColumnWidth = 15  # ~89pt, fits 'Deactivate' (80pt)
    ws.range('K:K').api.ColumnWidth = 15  # ~89pt, fits 'Restore' (80pt) -- and clears room for 'Edit' in L
    ws.range('L:L').api.ColumnWidth = 12  # ~71pt, fits 'Edit' (60pt)

    ws.range('B1').value = 'User Management'
    ws.range('B1').font.bold = True
    add_user_btn = _add_button(ws, 'B2', '+ Add User', 'modAdmin.UI_OpenAddUser', width=90)
    _add_button(ws, 'C2', 'Reset PW', 'modAdmin.UI_ResetSelectedUserPassword', width=80)
    _add_button(ws, 'D2', 'Deactivate', 'modAdmin.UI_DeactivateSelectedUser', width=80)
    _add_button(ws, 'E2', 'Activate', 'modAdmin.UI_ActivateSelectedUser', width=80)
    _add_button(ws, 'F2', 'Edit Username', 'modAdmin.UI_EditSelectedUsername', width=110)

    # Positioned below the real +Add User button's own measured bottom edge,
    # not a 'B3' cell anchor -- row 2's RowHeight isn't widened to its final
    # 22pt until later in this function (near the LoV button block below), so
    # a cell anchor placed here would compute against row 2's still-default
    # (~14pt) height and end up overlapping row 2's buttons both vertically
    # AND horizontally (this button is wide enough to span under both +Add
    # User and Reset PW). Confirmed this exact failure for real -- same root
    # cause as _add_button_after's docstring, just the vertical axis.
    _add_button_below(ws, add_user_btn, 'Security Question', 'modAdmin.UI_SetSelectedUserSecurityQuestion', width=140)
    ws.range('3:3').api.RowHeight = 34  # tall enough that the button (below row 2's real bottom edge) can't reach into row 4's table header

    user_headers = ['ID', 'Name', 'Username', 'Email', 'Role', 'Active']
    ws.range('A4').value = user_headers
    users_tbl = ws.api.ListObjects.Add(1, ws.range('A4:F4').api, None, 1)  # xlSrcRange, xlYes
    users_tbl.Name = 'tblUsers'
    users_tbl.ListColumns('ID').Range.EntireColumn.Hidden = True

    # NOTE: these 3 labels live in column G, not H -- tblLov's ID column
    # (below) is H, and EntireColumn.Hidden hides ALL rows in that column,
    # not just the table body. Putting them in H made 'List of Values' /
    # 'Category:' / 'New Value:' silently disappear along with the ID column,
    # orphaning the '+ Add' button with no visible label pointing at it.
    # Column G has no other content anywhere on this sheet, and since H is
    # hidden (0 width) G sits visually flush against I, so this reads exactly
    # as if the label were still in H.
    ws.range('G1').value = 'List of Values'
    ws.range('G1').font.bold = True

    ws.range('G2').value = 'Category:'
    category_list = 'Referral Sources,Religions,Languages,Consultants,Appointment Types'
    ws.range('I2').api.Validation.Add(3, 1, Formula1=category_list)  # xlValidateList
    ws.range('I2').value = 'Referral Sources'
    _add_button(ws, 'J2', 'Deactivate', 'modAdmin.UI_DeactivateSelectedLov', width=80)
    _add_button(ws, 'K2', 'Restore', 'modAdmin.UI_RestoreSelectedLov', width=80)
    # Add/Edit open a popup form instead of typing directly into sheet cells
    # (the direct-cell-entry flow this replaced made it too easy to fat-finger
    # a wrong column, especially Sort Order, and offered no per-category field
    # set -- e.g. Chaplain Y/N only makes sense for Consultants). Kept in the
    # same row as Deactivate/Restore -- an earlier row-3 placement under the
    # category dropdown looked attached to the Users table on one side and
    # overlapped the dropdown on the other, from having near-zero clearance
    # on both axes.
    _add_button(ws, 'L2', 'Edit', 'modAdmin.UI_OpenEditLov', width=60)
    _add_button(ws, 'M2', '+ Add', 'modAdmin.UI_OpenAddLov', width=60)
    ws.range('2:2').api.RowHeight = 22  # buttons are 20pt tall -- default row height (~15pt) let them overhang into row 3

    lov_headers = ['ID', 'Value', 'Sort Order', 'Active', 'Chaplain']
    ws.range('H5').value = lov_headers
    lov_tbl = ws.api.ListObjects.Add(1, ws.range('H5:L5').api, None, 1)  # xlSrcRange, xlYes
    lov_tbl.Name = 'tblLov'
    lov_tbl.ListColumns('ID').Range.EntireColumn.Hidden = True

    # -- Purge Configuration (admin only -- enforced at runtime in
    #    modPurge.RunPurgeNow, same guard pattern as the other Admin-only
    #    UI_* subs, rather than visually hiding controls) -------------------
    ws.range('B25').value = 'Purge Configuration'
    ws.range('B25').font.bold = True
    ws.range('B26').value = 'Retention (months):'
    ws.range('C26').api.Validation.Add(3, 1, Formula1='6,12,18,24')  # xlValidateList
    ws.range('D26').value = 'Frequency:'
    ws.range('E26').api.Validation.Add(3, 1, Formula1='Monthly,Quarterly,Every 6 Months,Yearly')
    ws.range('B27').value = 'Last Purge Date:'
    ws.range('C27').api.NumberFormat = '@'
    _add_button(ws, 'F27', 'Run Purge Now', 'modPurge.RunPurgeNow', width=100)

    # -- Migration (admin only -- enforced at runtime in modExport's/modUpgrade's UI_* subs) --
    ws.range('B29').value = 'Migration'
    ws.range('B29').font.bold = True
    _add_button(ws, 'B30', 'Export for Import', 'modExport.UI_ExportForImport', width=130)
    _add_button(ws, 'D30', 'Import from Electron Export', 'modExport.UI_ImportFromElectron', width=170)
    ws.range('30:30').api.RowHeight = 22  # buttons are 20pt tall -- default row height (~15pt) let them overhang into row 31, now occupied by the button below
    _add_button(ws, 'B31', 'Import from Previous Excel File', 'modUpgrade.UI_UpgradeFromOldWorkbook', width=170)

    # -- Account Recovery (admin only -- enforced at runtime in modAdmin.UI_RotateRecoveryCode) --
    ws.range('B33').value = 'Account Recovery'
    ws.range('B33').font.bold = True
    _add_button(ws, 'B34', 'Rotate Recovery Code', 'modAdmin.UI_RotateRecoveryCode', width=150)

    # tblLov's Value/Sort Order/Chaplain columns are deliberately left locked
    # (read-only) -- editing now goes through AddEditLovForm (Edit button),
    # not direct cell entry.
    _protect_sheet(ws, unlocked_ranges=['I2', 'C26', 'E26'])


def _add_chart(ws, anchor_cell, source_range_addr, name, width=320, height=190):
    """Add a native clustered-column chart anchored at `anchor_cell`, sourced
    from `source_range_addr`, initially hidden (shown/populated by VBA once a
    report actually has rows -- see the 'No results found' placeholder pattern).
    """
    anchor = ws.range(anchor_cell).api
    co = ws.api.ChartObjects().Add(anchor.Left, anchor.Top, width, height)
    co.Name = name
    co.Chart.SetSourceData(ws.range(source_range_addr).api)
    co.Chart.ChartType = 51  # xlColumnClustered
    co.Visible = False
    return co


def _build_reports_sheet(wb):
    """Build the Reports sheet: one shared report selector + date range + Run
    button (rows 2-3, columns A-F -- mirrors the Electron app's reports
    redesign), above 4 stacked report sections (Referrals by Source, First
    Appointments, Patients Dropped, SDAT Improvement), each with just its own
    results area and Export button. Running "All Reports" populates all 4;
    running one specific report populates that section and clears the other
    3 (mirrors the Electron page only ever showing cards for the report(s)
    actually run). The first 3 sections also get a native Excel chart per the
    design spec; SDAT Improvement has none -- just a table plus a recomputed
    overall-total row.

    Result areas are plain formatted ranges (bold header + a fixed row buffer
    cleared/rewritten on every Run), NOT Excel Tables/ListObjects -- 4 real
    ListObjects stacked in the same columns on one sheet hit a genuine Excel
    limitation (confirmed: "Run-time error 1004: This won't work because it
    would move cells in a table on your worksheet") the moment an earlier
    table's ListRows.Add needs to insert a row, since Excel's row-insert always
    shifts the whole sheet width and refuses to implicitly relocate another
    Table. Plain ranges don't have this restriction.

    Row layout: Referrals by Source (1-15), First Appointments (17-35),
    Patients Dropped (37-55), SDAT Improvement (57-80). Columns J:K on the
    First Appointments/Patients Dropped sections hold a hidden week-label/
    count helper range that is the actual chart source -- the visible table
    is per-record, not pre-aggregated by week.
    """
    ws = wb.sheets['Reports']

    # Columns A-F are shared by all 4 stacked sections below: as the From/To
    # date row (B/D hold 10-char ISO dates, E/F host the Run/Export buttons)
    # AND as the SDAT Improvement results table's header row (A:F -- 'Begin
    # Score'/'Begin Date'/'End Score'/'End Date'/'% Improvement' are all wider
    # than the 48pt default). Widen once, before any section writes content,
    # so both the date inputs stop getting clipped/covered by the Run button
    # and the SDAT headers stop truncating.
    # 22 units (~130pt) -- room for real patient/source names AND fits the
    # 'Overall Improvement:' label (row 79) on its own; B79 always ends up
    # with real content once a report runs ('No results found.' or a percent),
    # so this can't rely on overflow into a blank neighbor the way a
    # once-off placeholder could.
    ws.range('A:A').api.ColumnWidth = 22
    ws.range('B:B').api.ColumnWidth = 16  # ~95pt, fits 'First Appt Date' (15 chars)
    ws.range('C:C').api.ColumnWidth = 12  # ~71pt, fits 'Begin Date'/'Consultant' + a 10-char date
    ws.range('D:D').api.ColumnWidth = 12  # ~71pt, fits 'End Score' + a 10-char date
    ws.range('E:E').api.ColumnWidth = 10  # ~59pt, fits 'End Date'
    ws.range('F:F').api.ColumnWidth = 14  # ~83pt, fits '% Improvement' + Export button (70pt)

    # J:K hold First Appointments/Patients Dropped's hidden week-label/count
    # helper range (written further down) -- unrelated to the shared report
    # controls below, just needs to happen before those two sections write
    # their J20/J40 helper headers.
    ws.range('J:K').api.EntireColumn.Hidden = True

    # -- Shared report controls (rows 2-3, columns A-F). Mirrors the Electron
    # app's reports redesign: one report selector (defaults to "All
    # Reports"), one shared date range, one Run button -- replacing what used
    # to be 4 independent per-section date ranges + Run buttons. Each section
    # below keeps only its own Export button, since export still acts on one
    # already-computed report at a time.
    #
    # This used to live at row 1, columns G onward ("free" space to the right
    # of the report tables' own A:F columns). That put it 490+pt from the
    # left edge, since A:F alone is that wide already (sized for the report
    # tables' own content -- patient names, dates, etc.) -- off the right
    # edge of a normal window, needing a horizontal scroll just to see the
    # report picker or Run button. Moved into rows 2-3 instead, which sit
    # blank between each section's title (row 1) and its own header row
    # (A4/A20/A40/A60) -- reusing the exact width the report tables already
    # need, not adding any. Row 2 stays out of column F specifically because
    # Referrals by Source's own Export button already lives at F2 (below).
    #
    # Row height set BEFORE anything in rows 2-3 is placed (including F2's
    # Export button below, which comes later in this function) -- confirmed
    # for real that doing this the other way round (default ~14pt height at
    # placement time, widened only afterward) lets a 20pt-tall button on row 3
    # reach up into row 2's buttons, since Buttons().Add() bakes in an
    # absolute pixel Top computed from whatever height the row has *at that
    # moment*, not its eventual final one.
    ws.range('2:3').api.RowHeight = 22
    ws.range('A2').value = 'Report:'
    report_list = 'All Reports,Referrals by Source,First Appointments,Patients Dropped,SDAT Improvement'
    ws.range('B2').api.Validation.Add(3, 1, Formula1=report_list)  # xlValidateList
    ws.range('B2').value = 'All Reports'
    ws.range('A3').value = 'From:'
    ws.range('B3').api.NumberFormat = '@'
    _add_pick_date_button(ws, 'B3', 'modReports.UI_PickSharedFromDate')
    ws.range('C3').value = 'To:'
    ws.range('D3').api.NumberFormat = '@'
    _add_pick_date_button(ws, 'D3', 'modReports.UI_PickSharedToDate')
    _add_button(ws, 'E3', 'Run', 'modReports.UI_RunSelectedReport', width=60)

    # -- Referrals by Source -------------------------------------------------
    ws.range('A1').value = 'Referrals by Source'
    ws.range('A1').font.bold = True
    _add_button(ws, 'F2', 'Export', 'modReports.UI_ExportReferralsBySource', width=70)
    ws.range('A4').value = ['Source', 'Count', 'Percent']
    ws.range('A4:C4').font.bold = True
    ws.range('E5').value = 'Run the report to see results.'
    _add_chart(ws, 'H4', 'A4:C4', 'chtReferralsBySource')

    # -- First Appointments ---------------------------------------------------
    ws.range('A17').value = 'First Appointments'
    ws.range('A17').font.bold = True
    _add_button(ws, 'F18', 'Export', 'modReports.UI_ExportFirstAppointments', width=70)
    ws.range('A20').value = ['Patient', 'First Appt Date', 'Consultant']
    ws.range('A20:C20').font.bold = True
    ws.range('B:B').api.NumberFormat = '@'
    ws.range('J20').value = ['Week', 'Count']
    ws.range('J:J').api.NumberFormat = '@'
    ws.range('E21').value = 'Run the report to see results.'
    _add_chart(ws, 'H20', 'J20:K20', 'chtFirstAppointments')

    # -- Patients Dropped -------------------------------------------------
    ws.range('A37').value = 'Patients Dropped'
    ws.range('A37').font.bold = True
    _add_button(ws, 'F38', 'Export', 'modReports.UI_ExportPatientsDropped', width=70)
    ws.range('A40').value = ['Patient', 'Dropped Date', 'Changed By']
    ws.range('A40:C40').font.bold = True
    ws.range('J40').value = ['Week', 'Count']
    ws.range('E41').value = 'Run the report to see results.'
    _add_chart(ws, 'H40', 'J40:K40', 'chtPatientsDropped')

    # -- SDAT Improvement (no chart per spec) --------------------------------
    ws.range('A57').value = 'SDAT Improvement'
    ws.range('A57').font.bold = True
    _add_button(ws, 'F58', 'Export', 'modReports.UI_ExportSdatImprovement', width=70)
    ws.range('A60').value = ['Patient', 'Begin Score', 'Begin Date', 'End Score', 'End Date', '% Improvement']
    ws.range('A60:F60').font.bold = True
    ws.range('C:C').api.NumberFormat = '@'
    ws.range('E:E').api.NumberFormat = '@'
    ws.range('A79').value = 'Overall Improvement:'
    ws.range('B79').value = ''

    _protect_sheet(ws, unlocked_ranges=['B2', 'B3', 'D3'])


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
