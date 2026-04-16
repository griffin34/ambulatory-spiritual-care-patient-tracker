# Excel VBA Workbook — Plan 1 of 7: Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Python build script that produces `AmbulatoryPatients.xlsm` with correct sheet structure, column headers, and default seed data — no interactive VBA logic yet, just a correctly-structured, openable workbook.

**Architecture:** Data definitions live as pure Python constants in `excel/build.py` (unit-testable without Excel). A `build_workbook()` function uses COM automation to create the workbook on Windows. VBA source files live as plain text in `excel/src/` (version-controlled). The built `.xlsm` is committed to `excel/dist/` for distribution.

**Tech Stack:** Python 3.10+, pywin32 2.0+, pytest 8+, Excel 2016+ on Windows (required to run the build)

---

## One-Time Build Machine Setup

Before running `build.py`, enable VBA project object model access in Excel:
> Excel → File → Options → Trust Center → Trust Center Settings → Macro Settings → check **"Trust access to the VBA project object model"** → OK

---

## File Structure

```
excel/
├── build.py                  # Data definitions + COM build function
├── requirements.txt          # pywin32, pytest
├── src/
│   └── modUtils.bas         # Shared VBA helpers (first module)
├── tests/
│   ├── __init__.py
│   └── test_build.py        # Unit tests (no COM, no Excel required)
└── dist/
    └── .gitkeep             # Output directory; AmbulatoryPatients.xlsm committed here
```

---

### Task 1: Project scaffold

**Files:**
- Create: `excel/requirements.txt`
- Create: `excel/tests/__init__.py`
- Create: `excel/dist/.gitkeep`
- Modify: `.gitattributes` (project root)
- Modify: `.gitignore` (project root)

- [ ] **Step 1: Create excel/requirements.txt**

```
pywin32>=306
pytest>=8.0
```

- [ ] **Step 2: Create excel/tests/__init__.py**

Empty file.

- [ ] **Step 3: Create excel/dist/.gitkeep**

Empty file. The built `.xlsm` will be saved here and committed.

- [ ] **Step 4: Add .gitattributes at the project root**

If `.gitattributes` doesn't exist, create it. If it exists, append these lines:

```
*.xlsm binary
*.xls binary
*.xlsx binary
```

This prevents git from mangling the binary file on checkout.

- [ ] **Step 5: Update .gitignore**

Add to `.gitignore`:

```
# Excel build artifacts
excel/__pycache__/
excel/.pytest_cache/
excel/tests/__pycache__/
```

- [ ] **Step 6: Commit**

```bash
git add excel/requirements.txt excel/tests/__init__.py excel/dist/.gitkeep .gitattributes .gitignore
git commit -m "feat(excel): scaffold excel/ project structure"
```

---

### Task 2: Data definitions and unit tests

**Files:**
- Create: `excel/build.py` (constants only — no COM imports at module level)
- Create: `excel/tests/test_build.py`

- [ ] **Step 1: Write the failing tests**

Create `excel/tests/test_build.py`:

```python
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
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd excel
pytest tests/test_build.py -v
```

Expected: `ModuleNotFoundError: No module named 'build'`

- [ ] **Step 3: Create excel/build.py with data constants**

```python
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
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd excel
pytest tests/test_build.py -v
```

Expected: 15 tests pass.

- [ ] **Step 5: Commit**

```bash
git add excel/build.py excel/tests/test_build.py
git commit -m "feat(excel): data definitions and unit tests"
```

---

### Task 3: Build script — COM workbook creation

**Files:**
- Modify: `excel/build.py` (append build functions after the constants)

- [ ] **Step 1: Append build functions to excel/build.py**

Add the following after the `SEED_CONSULTANTS` constant (do not replace anything above):

```python
# ─── Build (requires Windows + Excel + pywin32) ───────────────────────────────

def build_workbook(output_path=None, src_dir=None):
    """Create AmbulatoryPatients.xlsm via Excel COM automation.

    Run on Windows with Excel installed. One-time setup required:
    Excel → Options → Trust Center → Trust Center Settings →
    Macro Settings → check 'Trust access to the VBA project object model'.
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

    excel = win32.Dispatch('Excel.Application')
    excel.Visible = False
    excel.DisplayAlerts = False

    wb = None
    try:
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
    vbp = wb.VBProject
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
```

- [ ] **Step 2: Run unit tests — confirm no regressions**

```bash
cd excel
pytest tests/test_build.py -v
```

Expected: 15 tests pass (the build functions don't run at import time).

- [ ] **Step 3: Manual integration test (Windows with Excel)**

```bash
cd excel
pip install -r requirements.txt
python build.py
```

Expected output:
```
Built: C:\...\excel\dist\AmbulatoryPatients.xlsm
```

Open `excel/dist/AmbulatoryPatients.xlsm`. Verify:
- **Tabs visible:** WorkQueue, Appointments, Reports, Admin (4 tabs, no others)
- **Data sheets hidden:** Right-click any tab → Unhide → confirm the list shows `_data_users`, `_data_patients`, `_data_status_history`, `_data_appointments`, `_data_consultants`, `_data_lov`, `_data_audit`, `_data_settings` (all 8)
- **Seed data present:** In VBA editor (Alt+F11), open Immediate window and run: `?ThisWorkbook.Sheets("_data_lov").Cells(2,3).Value` → should return `Physician Referral`
- **VBA project:** Under Modules — empty for now (modUtils comes in Task 4)

- [ ] **Step 4: Commit the build script and the built workbook**

```bash
git add excel/build.py excel/dist/AmbulatoryPatients.xlsm
git commit -m "feat(excel): COM build script and initial workbook"
```

---

### Task 4: modUtils VBA module

**Files:**
- Create: `excel/src/modUtils.bas`

- [ ] **Step 1: Create excel/src/modUtils.bas**

```vba
Attribute VB_Name = "modUtils"
Option Explicit

' Returns the next auto-increment ID for a data sheet.
' Column A holds integer IDs; row 1 is the header row.
Public Function NextId(ws As Worksheet) As Long
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
    If lastRow <= 1 Then
        NextId = 1
    Else
        NextId = CLng(ws.Cells(lastRow, 1).Value) + 1
    End If
End Function

' Returns the last occupied row number in column A.
' Returns 1 (the header row) when the sheet has no data rows.
Public Function LastDataRow(ws As Worksheet) As Long
    LastDataRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
End Function

' Returns an ISO timestamp string (yyyy-mm-dd hh:mm:ss) for the current local time.
Public Function NowISO() As String
    NowISO = Format(Now, "yyyy-mm-dd hh:mm:ss")
End Function

' Returns an ISO date string (yyyy-mm-dd) for a given Date value.
Public Function DateISO(d As Date) As String
    DateISO = Format(d, "yyyy-mm-dd")
End Function

' Returns the column index (1-based) for a header name in row 1.
' Returns 0 if the column is not found.
Public Function ColIndex(ws As Worksheet, colName As String) As Integer
    Dim i As Integer
    For i = 1 To 50
        If ws.Cells(1, i).Value = "" Then Exit For
        If ws.Cells(1, i).Value = colName Then
            ColIndex = i
            Exit Function
        End If
    Next i
    ColIndex = 0
End Function

' Gets a cell value by row index and column name.
' Returns Null if the column name is not found in row 1.
Public Function GetVal(ws As Worksheet, rowIdx As Long, colName As String) As Variant
    Dim c As Integer
    c = ColIndex(ws, colName)
    If c = 0 Then
        GetVal = Null
    Else
        GetVal = ws.Cells(rowIdx, c).Value
    End If
End Function

' Sets a cell value by row index and column name.
' No-op if the column name is not found in row 1.
Public Sub SetVal(ws As Worksheet, rowIdx As Long, colName As String, val As Variant)
    Dim c As Integer
    c = ColIndex(ws, colName)
    If c > 0 Then ws.Cells(rowIdx, c).Value = val
End Sub

' Finds the row number whose column-A value equals id.
' Returns 0 if not found.
Public Function FindById(ws As Worksheet, id As Long) As Long
    Dim i As Long
    Dim last As Long
    last = LastDataRow(ws)
    For i = 2 To last
        If ws.Cells(i, 1).Value = id Then
            FindById = i
            Exit Function
        End If
    Next i
    FindById = 0
End Function

' Returns a data sheet by name.
' Data sheets are xlVeryHidden and cannot be accessed via the tab bar.
Public Function DataSheet(sheetName As String) As Worksheet
    Set DataSheet = ThisWorkbook.Sheets(sheetName)
End Function

' Returns True if a value is Null, Empty, or a blank/whitespace string.
Public Function IsBlank(v As Variant) As Boolean
    If IsNull(v) Or IsEmpty(v) Then
        IsBlank = True
    Else
        IsBlank = Len(Trim(CStr(v))) = 0
    End If
End Function

' Returns a setting value from _data_settings by key.
' Returns "" if the key is not found.
Public Function GetSetting(key As String) As String
    Dim ws As Worksheet
    Dim i As Long
    Dim last As Long
    Set ws = DataSheet("_data_settings")
    last = LastDataRow(ws)
    For i = 2 To last
        If ws.Cells(i, 1).Value = key Then
            GetSetting = CStr(ws.Cells(i, 2).Value)
            Exit Function
        End If
    Next i
    GetSetting = ""
End Function

' Updates a setting value in _data_settings.
' Appends a new row if the key does not already exist.
Public Sub SetSetting(key As String, value As String)
    Dim ws As Worksheet
    Dim i As Long
    Dim last As Long
    Set ws = DataSheet("_data_settings")
    last = LastDataRow(ws)
    For i = 2 To last
        If ws.Cells(i, 1).Value = key Then
            ws.Cells(i, 2).Value = value
            Exit Sub
        End If
    Next i
    Dim newRow As Long
    newRow = IIf(last < 2, 2, last + 1)
    ws.Cells(newRow, 1).Value = key
    ws.Cells(newRow, 2).Value = value
End Sub
```

- [ ] **Step 2: Rebuild the workbook (Windows)**

```bash
cd excel
python build.py
```

- [ ] **Step 3: Verify modUtils is present in the workbook**

Open `excel/dist/AmbulatoryPatients.xlsm`. Press **Alt+F11**.

In the Project Explorer (left panel), expand **Modules**. Confirm `modUtils` is listed.

Click `modUtils` and verify all functions are present: `NextId`, `LastDataRow`, `NowISO`, `DateISO`, `ColIndex`, `GetVal`, `SetVal`, `FindById`, `DataSheet`, `IsBlank`, `GetSetting`, `SetSetting`.

In the Immediate window (Ctrl+G), test:
```
?modUtils.GetSetting("retention_months")
```
Expected output: `12`

- [ ] **Step 4: Commit**

```bash
git add excel/src/modUtils.bas excel/dist/AmbulatoryPatients.xlsm
git commit -m "feat(excel): add modUtils VBA module with sheet and settings helpers"
```

---

## Self-Review

**Spec coverage check:**
- ✅ All 8 data sheets defined with correct column names matching the spec exactly
- ✅ All 4 visible UI sheets created
- ✅ `is_chaplain` on `_data_consultants` — included (added post-spec in Electron migration; starting correctly here)
- ✅ `_data_settings` seeded with `retention_months=12`, `purge_frequency=quarterly`, `last_purge_date=` (empty)
- ✅ `_data_lov` seeded with all four categories: referral_source, religion, language, appointment_type
- ✅ Default consultant "Frances" seeded in `_data_consultants`
- ✅ modUtils provides all primitives needed by later plans: NextId, GetVal/SetVal, FindById, DataSheet, GetSetting/SetSetting
- ✅ Data sheets set to xlVeryHidden (cannot be unhidden via UI without VBA)
- ⏭ Auth (LoginForm, modSHA256, modAuth, ThisWorkbook_Open) → Plan 2
- ⏭ WorkQueue + Patient management → Plan 3
- ⏭ Appointments → Plan 4
- ⏭ Reports → Plan 5
- ⏭ Admin + Purge → Plan 6
- ⏭ Export/Import → Plan 7

**Placeholder scan:** No TBD/TODO present. All code complete.

**Type consistency:** `DataSheet()`, `NextId()`, `LastDataRow()`, `ColIndex()`, `GetVal()`, `SetVal()`, `FindById()`, `GetSetting()`, `SetSetting()`, `NowISO()`, `DateISO()`, `IsBlank()` — names consistent throughout. Later plans must use these exact names.
