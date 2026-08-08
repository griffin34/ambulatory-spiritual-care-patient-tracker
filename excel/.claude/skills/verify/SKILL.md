---
name: verify
description: Drive the built AmbulatoryPatients.xlsm end-to-end via COM to observe real Workbook_Open/UserForm behavior, without screenshots or stealing window focus.
---

# Verifying the Excel/VBA add-in

Build first: `cd excel && python build.py` (packages `src/*.bas`/`*.frm` into
`dist/AmbulatoryPatients-v<N>.xlsm`, where `<N>` is `build.py`'s `EXCEL_BUILD_VERSION`).

**Always test on a copy** (e.g. in the scratchpad dir), never the tracked
`dist/AmbulatoryPatients-v<N>.xlsm` — the test flow creates users, logs in, and toggles sheet
visibility, and that state must not end up as the shipped artifact.

## Driving it: pure COM, no UI automation

`win32com.client` (pywin32, already available) is enough. Avoid pywinauto / screenshots /
`SetForegroundWindow` / `SetWindowPos(HWND_TOPMOST)` — this is a single-desktop machine, so
anything that grabs focus or screenshots the full screen touches the user's actual live
desktop (confirmed: a full-screen grab once captured their open browser tab). Stick to the
COM object model, which works regardless of what's on screen:

```python
app = win32com.client.DispatchEx("Excel.Application")  # isolated instance
app.Visible = True
app.DisplayAlerts = False

import threading
result = {}
def open_wb():
    result['wb'] = app.Workbooks.Open(path)
t = threading.Thread(target=open_wb)
t.start()   # Workbooks.Open() blocks for as long as a modal UserForm.Show is up
```

- **Modal UserForms block the Open() call.** `Workbook_Open` → `AddUserForm.Show` / `LoginForm.Show`
  is modal, so `Workbooks.Open()` doesn't return until the form closes. Run it in a background
  thread and drive the rest from the main thread — COM calls to the same Application still get
  dispatched while a modal form's nested message loop is pumping.
- **To close/unload a shown modal form without clicking:** find its window and
  `win32gui.PostMessage(hwnd, win32con.WM_CLOSE, 0, 0)`. This is the standard "user hit the X"
  path (`vbFormControlMenu` in `QueryClose`), so beware forms that special-case it — `LoginForm`'s
  `QueryClose` treats the system-close as "cancel the form close, close the whole workbook instead."
- **To exercise business logic without fighting the form's private click handlers:**
  `Public Sub`s are directly callable — `app.Run("modAdmin.CreateUser", name, email, pw, role)` —
  but `Application.Run` cannot call `Private` subs or a UserForm's inherited methods
  (`app.Run("AddUserForm.Hide")` fails with "macro may not be available"). For the UI side-effects
  a form's click handler performs (e.g. toggling sheet `.Visible`), just replicate them directly
  via COM properties (`ws.Visible = -1`) after calling the public logic Sub — no need to drive the
  form pixel-by-pixel.
- **Reconnecting from a second script/process to a workbook already opened by an earlier one:**
  `win32com.client.GetObject(path)` returns the live `Workbook`; `.Application` gets you the
  `Application` from there. Cleaner than trying to reuse a `DispatchEx` handle across processes.
- **Detecting a VBA runtime error (vs. success) after a reopen:** don't rely on `Workbooks.Open()`
  returning — if the flow reaches a further modal form (e.g. `LoginForm`) that in itself proves
  `Workbook_Open` completed with no unhandled error. Confirm no error dialog exists via
  `win32gui.EnumWindows` looking for class `#32770` (standard message-box class) — an unhandled
  VBA runtime error pops one of these and hangs the Open() call until dismissed.
- **Testing `Workbook_BeforeClose` logic (e.g. an autosave-on-close safety net): don't call
  `wb.Close()` from the external COM client.** It reliably hangs (confirmed) — some reentrancy
  between the out-of-process `Close()` call and `BeforeClose` calling `ThisWorkbook.Save`
  internally deadlocks the STA thread, even though nothing is visibly wrong (no dialog, Excel's
  UI looks idle). Instead simulate the real "user clicked X" path: find the `XLMAIN` window for
  that workbook (`win32gui.EnumWindows`, match class `XLMAIN` and title substring) and
  `PostMessage(hwnd, WM_CLOSE, 0, 0)` it, then poll for the window to disappear. This is what
  real usage actually goes through and does NOT hang.
- **Editing a UserForm's code OR layout without hand-editing `.frm` files:** open the built
  `.xlsm` via COM with `EnableEvents = False` (so no modal form pops while you're doing this).
  For code: `vbp.VBComponents("FormName").CodeModule`, `DeleteLines`/`AddFromString` the new
  code. For layout: `comp.Designer.Controls.Add("Forms.TextBox.1")` (then set `.Name`/`.Top`/
  `.Left`/`.Width`/`.Height`/`.Caption`), move/relabel existing controls the same way
  (`designer.Controls("txtFoo").Top = ...`), and resize the form itself via
  `comp.Properties("Height").Value = ...` (not `Designer.Height`, which throws
  `AttributeError` through pywin32's dynamic dispatch — go through `VBComponent.Properties`
  instead). Despite `excel/FORMS.md`'s older claim that layout automation is blocked entirely,
  all of this is scriptable and persists correctly (confirmed: add a control, `wb.Save()`,
  `vbp.VBComponents(name).Export(path)` to overwrite `excel/src/FormName.frm`/`.frx` — preserves
  CRLF, unlike hand-editing, see `excel/FORMS.md`'s warning about that — then a fresh
  `Workbooks.Open` shows the change intact). Don't assume the old wall still applies; retest
  before falling back to asking for manual VBA IDE work.
- **`comp.Properties("Height"/"Width").Value = N` does NOT reliably produce a form with that
  much usable content area — verify the actual result, don't trust the number you set.**
  Confirmed twice: setting Height=100 on a brand-new form (`VBComponents.Add(3)`) produced an
  actual `ClientHeight` of only 80pt in the exported `.frm` (controls positioned past 80pt were
  literally clipped/invisible at runtime — this is what caused a real reported bug, a picker
  form's OK/Cancel buttons being invisible). On an *existing* form the same call was sometimes
  reliable (e.g. `+= 26` landed exactly) and sometimes not (a `Height`/`Width` read of 559.8
  correspoded to a `ClientHeight`/`ClientWidth` of ~590–610 in the file). There's no consistent
  offset to compensate by — after setting a size, re-open the exported `.frm` and read the actual
  `ClientHeight`/`ClientWidth` (twips ÷ 18 = points) to confirm it's large enough for your
  controls' max `Top+Height`/`Left+Width`, or better, actually `.Show` the form and measure the
  real rendered F3-Server child rect (`GetWindowRect`) against a known reference scale from
  another already-verified form on the same machine. If a form has a genuinely `Public
  PatientId`/similar context property, remember you need a real row for it to `.Show` without
  erroring (e.g. `modPatients.Save 0, "MRN1", "Doe", "Jane", "", "5551234567", "2026-07-01", 0,
  0, 0` before `PatientDetailForm.PatientId = 1: PatientDetailForm.Show`).
- **A form can have more than one "F3 Server" child** (`PatientDetailForm` had two). When
  measuring rendered size via `EnumChildWindows`, don't blindly take the first match — pick the
  largest (`max(f3, key=lambda h: GetWindowRect(h) width)`) as the main content surface.
- **`Application.Run` cannot call a `Function` defined on a UserForm's own module and get its
  return value back** (confirmed: `app.Run("TimePickerForm.DebugComboState")` throws "macro may
  not be available", even though the identical pattern works fine for a `Sub`, and works fine for
  a `Function` in a standard module like `modUtils`). To read a running form's internal state
  from outside, have the VBA itself write the value into a worksheet cell instead (see the note
  below on reading live state), or wrap the read in a `Sub` in a standard module that both pokes
  the form and writes the result to a cell in one call.
- **Cross-thread COM gotcha:** create the `Application` object and call it from the *same*
  thread. Creating `app = DispatchEx(...)` on the main thread and then calling `app.Workbooks.Open`
  from a background thread throws `CoInitialize has not been called` or `marshalled for a
  different thread`. Instead, do the `pythoncom.CoInitialize()` + `DispatchEx(...)` + `.Open(...)`
  all inside the background thread's own function, and reconnect from the main thread via
  `win32com.client.GetObject(path)` instead of touching the background thread's `app` object.
- **Reading a live form's state (not the static Designer) while a test is mid-flight:** you
  can't read a shown UserForm's control values or Public variables directly through COM (no
  handle to the running instance). Instead have the VBA code itself write into a cell (e.g.
  `ThisWorkbook.Sheets("_data_settings").Cells(N, 1).Value = "MARKER"`), then read that cell
  from a **separate** `win32com.client.GetObject(path)` connection to the *same still-open*
  process — reading via a fresh `DispatchEx`+`Open(path)` instead gets you the stale on-disk
  snapshot from the last save, not live in-memory state (this cost real debugging time: a whole
  round of "nothing happened" turned out to be reading the wrong copy).
- **Dynamically-created controls (`Me.Controls.Add` at runtime, e.g. building a calendar-grid
  popup) may not accept clicks until you `Me.Repaint` after adding/showing them.** Confirmed:
  statically Designer-placed buttons receive `PostMessage`-simulated clicks on the F3 Server
  child window fine with no repaint, but a grid of buttons added via `Controls.Add` inside
  `UserForm_Initialize` silently ate every click until `Me.Repaint` was added at the end of the
  render routine — after that, identical clicks worked immediately. If a runtime-added control
  seems unresponsive, try this before assuming the event wiring (e.g. a `WithEvents` class
  wrapper) is broken.
- **A `PostMessage`-simulated click that never registers isn't necessarily a bug in the
  form** — it can also just be this test technique failing for that particular window (tried:
  longer delays, retries, confirming `UserForm_Activate` really ran via a marker, forcing real
  OS foreground/activation via `AttachThreadInput`+`SetForegroundWindow` — none of it explained
  one specific case where a plain, already-proven-correct `btnCancel`-style handler never fired
  under simulated clicks, while the same technique worked fine on other forms). Don't escalate
  to genuine hardware input (`SendInput`/`mouse_event`, or moving the real cursor) to chase
  this down — that's a real click on the user's live single-desktop machine and is far too
  invasive for a verification step; it will also likely get blocked. When simulated clicks won't
  register on an otherwise-correct, conventionally-wired control, prefer falling back to code
  review (compare the handler against other working buttons in the same project) over more
  aggressive automation.

## Cleanup

Always end by closing/quitting the `DispatchEx`'d Application (`app.Quit()`) and deleting the
scratch copy of the workbook — check `tasklist | grep -i excel` to confirm no stray EXCEL.EXE
survives the test.
