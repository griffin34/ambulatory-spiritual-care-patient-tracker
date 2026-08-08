# Excel UserForms — Build Checklist

`LoginForm` is done (see `excel/src/LoginForm.frm`). Every other interactive
dialog in the Excel companion app is also a UserForm.

Earlier notes here claimed UserForm layout couldn't be created by script at
all. That's outdated: `Designer.Controls.Add`, moving/resizing existing
controls (`.Top`/`.Left`), setting `.Caption`, and resizing the form itself
(`VBComponent.Properties("Height"/"Width").Value`) are all scriptable via COM
— reconfirmed 2026-07-15 (add a control, set its properties, `wb.Save()`,
`VBComponents(name).Export(path)` to overwrite the `.frm`/`.frx`, then a fresh
`Workbooks.Open` of the saved file shows the control persisted correctly).
Whatever blocked this for the original author isn't reproducible in the
current environment — if a future session hits a strange automation error
building UserForms, don't assume it's this same hard wall; retest before
falling back to manual VBA IDE work.

For any remaining forms below that still need building from scratch, doing
it by hand in the VBA IDE per the tables below is still the more reliable
mechanical path (the design spec is at
`docs/superpowers/specs/2026-04-13-ambulatory-patients-excel-design.md`), but
know that scripted edits to an *existing* form's layout are a viable option
now, not just its code.

This file lists every remaining form, its controls, and the exact steps to
build and commit it, so building one is mechanical rather than a design
exercise.

## Forms remaining

| # | Form | Purpose | Opens from |
|---|------|---------|------------|
| 1 | `PatientDetailForm` | Patient profile, status history, appointment list | WorkQueue "View Patient" / row double-click |
| 2 | `AddEditPatientForm` | Add or edit a patient's demographic/referral fields | WorkQueue "+ Add Patient"; `PatientDetailForm` "Edit" |
| 3 | `AddEditAppointmentForm` | Add or edit an appointment | `PatientDetailForm` "+ Add Appointment" / "Edit"; Appointments sheet |
| 4 | `AddUserForm` | Create a user account (also used for first-run admin setup) | Admin sheet "+ Add User"; first run with zero users |
| 5 | `ResetPasswordForm` | Reset a user's password | Admin sheet "Reset PW" |
| 6 | `ImportMappingForm` | Column mapping preview before an Electron-export import | Admin sheet "Import from Electron Export" |
| 7 | `PurgeConfirmForm` | Confirm a retention purge, pick the archive path | Startup purge check (admin only) |

## Naming convention

Prefix every control name by type, `camelCase` after the prefix:

| Prefix | Control type |
|--------|--------------|
| `lbl` | Label |
| `txt` | TextBox |
| `cbo` | ComboBox |
| `lst` | ListBox |
| `chk` | CheckBox |
| `opt` | OptionButton |
| `fra` | Frame |
| `btn` | CommandButton |

(`LoginForm` predates this convention and uses `Title`/`emailLabel`/
`passwordLabel` for its three labels — leave it as-is, don't rename working
code; just follow the convention for everything new.)

## Default font

Every control's Font property is **Tahoma, Regular, 8pt** unless a control's
property table explicitly lists a `Font:` entry — that's the VBA Toolbox
default (verified against `LoginForm.emailLabel`, which was never touched).
Don't set Font on a control unless its row says to.

## General steps (repeat per form)

1. **Insert the form.** In the VBA editor (Alt+F11), right-click the project
   → **Insert → UserForm**.
2. **Set form-level properties** from the table in that form's section below,
   via the Properties window (**F4**). Do this first — `(Name)` in particular,
   since renaming later doesn't rename the exported filename.
3. **Add controls** from the Toolbox (**View → Toolbox**), in the order
   listed, setting each control's properties in F4 immediately after placing
   it. Properties are listed alphabetically, matching the Properties window's
   Alphabetic tab (`(Name)` always sorts first).
4. **Add the code-behind** — double-click the form background to open its
   code window, paste the code from that form's section.
5. **Save** (Ctrl+S, keep macro-enabled format).
6. **Export**, from the Immediate window (Ctrl+G) or by right-clicking the
   component in the Project Explorer → **Export File...** — save as
   `excel/src/<FormName>.frm` (the matching `.frx` is written alongside it
   automatically).
7. **Verify line endings before committing** — run `file excel/src/<FormName>.frm`
   in a shell; it must say `CRLF line terminators`. If a text editor stripped
   them, VBA's importer will silently misparse the `Begin`/`End` designer
   header and throw a compile error on the next rebuild. Don't hand-edit
   `.frm` files outside the VBA IDE.
8. **Rebuild and confirm the import.** `python build.py` from `excel/` should
   print `Imported: <FormName>.frm` with no errors, and the resulting
   `.xlsm` should open without a compile-error dialog.
9. **Commit** `excel/src/<FormName>.frm`, `excel/src/<FormName>.frx`, and the
   rebuilt `excel/dist/AmbulatoryPatients-v<N>.xlsm` (filename carries
   `EXCEL_BUILD_VERSION` from `build.py`) together.

Module-level variables mentioned per form (e.g. `PatientId`) are how the
caller passes context into the form before calling `.Show` — e.g.
`PatientDetailForm.PatientId = 42: PatientDetailForm.Show`.

Code-behind below calls into backing modules (`modPatients`, `modAppointments`,
`modAdmin`, `modExport`, `modPurge`) that don't exist yet — those are Plans
3–7. Calls into them are marked `' TODO(planN):` — build the form now, wire
the TODOs up when that module lands, and the form will compile standalone in
the meantime (the TODO lines are commented out, not calls to undefined
functions).

---

## 1. PatientDetailForm

**Form properties**

| Property | Value |
|---|---|
| (Name) | `PatientDetailForm` |
| Caption | `Patient Detail` |
| Height | 560 |
| StartUpPosition | `1 - CenterOwner` |
| Width | 560 |

**Controls — left panel (patient info)**

| Control | Type | Properties (alphabetical) |
|---|---|---|
| `lblPatientName` | Label | Caption: *(blank, set at runtime)*; Font: Bold, 14pt; Height 20; Left 10; Top 10; Width 260 |
| `lblMrnCaption` | Label | Caption: `MRN:`; Height 16; Left 10; Top 36; Width 60 |
| `lblMrn` | Label | Caption: *(blank)*; Height 16; Left 75; Top 36; Width 120 |
| `lblPhoneCaption` | Label | Caption: `Phone:`; Height 16; Left 10; Top 56; Width 60 |
| `lblPhone` | Label | Caption: *(blank)*; Height 16; Left 75; Top 56; Width 120 |
| `lblReferralDateCaption` | Label | Caption: `Referred:`; Height 16; Left 10; Top 76; Width 60 |
| `lblReferralDate` | Label | Caption: *(blank)*; Height 16; Left 75; Top 76; Width 120 |
| `lblReferralSourceCaption` | Label | Caption: `Source:`; Height 16; Left 10; Top 96; Width 60 |
| `lblReferralSource` | Label | Caption: *(blank)*; Height 16; Left 75; Top 96; Width 180 |
| `lblReligionCaption` | Label | Caption: `Religion:`; Height 16; Left 10; Top 116; Width 60 |
| `lblReligion` | Label | Caption: *(blank)*; Height 16; Left 75; Top 116; Width 180 |
| `lblLanguageCaption` | Label | Caption: `Language:`; Height 16; Left 10; Top 136; Width 60 |
| `lblLanguage` | Label | Caption: *(blank)*; Height 16; Left 75; Top 136; Width 180 |
| `lblStatusBadge` | Label | BackColor: *(set at runtime per status)*; Caption: *(blank, set at runtime)*; Height 20; Left 10; TextAlign: `2 - fmTextAlignCenter`; Top 164; Width 120 |
| `lblStatusHistoryHeader` | Label | Caption: `Status History`; Font: Bold; Height 16; Left 10; Top 224; Width 260 |
| `cboChangeStatus` | ComboBox | Height 20; Left 140; Style: `2 - fmStyleDropDownList`; Top 164; Width 120 |
| `lstStatusHistory` | ListBox | ColumnCount: `3`; ColumnWidths: `80 pt;90 pt;80 pt`; Height 130; Left 10; Top 244; Width 260 |
| `btnApplyStatus` | CommandButton | Caption: `Apply`; Height 20; Left 270; Top 164; Width 60 |
| `btnEditPatient` | CommandButton | Caption: `Edit Patient...`; Height 22; Left 10; Top 194; Width 120 |

**Controls — right panel (appointments)**

| Control | Type | Properties (alphabetical) |
|---|---|---|
| `lblAppointmentsHeader` | Label | Caption: `Appointments`; Font: Bold; Height 16; Left 290; Top 10; Width 260 |
| `lstAppointments` | ListBox | ColumnCount: `7`; ColumnWidths: `55 pt;40 pt;55 pt;70 pt;55 pt;25 pt;90 pt`; Height 320; Left 290; Top 30; Width 260 |
| `btnAddAppointment` | CommandButton | Caption: `+ Add Appointment`; Height 22; Left 290; Top 356; Width 130 |
| `btnEditAppointment` | CommandButton | Caption: `Edit Appointment`; Height 22; Left 425; Top 356; Width 125 |

**Controls — bottom panel (SDAT, notes, delete/restore)**

Added for v1.1 parity: SDAT and Notes are each editable in place with their
own Save button (no need to open `AddEditPatientForm`), matching the
Electron app's pencil-icon cards. `deleted` is only reachable via
`btnDeletePatient` — it's deliberately excluded from `cboChangeStatus`.

| Control | Type | Properties (alphabetical) |
|---|---|---|
| `lblSdatHeader` | Label | Caption: `SDAT`; Font: Bold; Height 16; Left 10; Top 390; Width 260 |
| `lblSdatBeginCaption` | Label | Caption: `Begin Score:`; Height 16; Left 10; Top 410; Width 70 |
| `lblSdatBeginDateCaption` | Label | Caption: `Date:`; Height 16; Left 130; Top 410; Width 35 |
| `lblSdatEndCaption` | Label | Caption: `End Score:`; Height 16; Left 255; Top 410; Width 65 |
| `lblSdatEndDateCaption` | Label | Caption: `Date:`; Height 16; Left 365; Top 410; Width 35 |
| `lblSdatPctImprovement` | Label | Caption: *(blank, set at runtime)*; Height 16; Left 10; Top 434; Width 200 |
| `lblNotesHeader` | Label | Caption: `Notes`; Font: Bold; Height 16; Left 10; Top 460; Width 260 |
| `txtSdatBeginScore` | TextBox | Height 20; Left 85; Top 408; Width 40 |
| `txtSdatBeginDate` | TextBox | Height 20; Left 168; Top 408; Width 80 |
| `txtSdatEndScore` | TextBox | Height 20; Left 322; Top 408; Width 40 |
| `txtSdatEndDate` | TextBox | Height 20; Left 403; Top 408; Width 80 |
| `txtNotes` | TextBox | Height 40; Left 10; MaxLength: `256`; MultiLine: `True`; ScrollBars: `2 - fmScrollBarsVertical`; Top 478; Width 400 |
| `btnSaveSdat` | CommandButton | Caption: `Save SDAT`; Height 20; Left 220; Top 432; Width 90 |
| `btnSaveNotes` | CommandButton | Caption: `Save Notes`; Height 20; Left 420; Top 478; Width 90 |
| `btnDeletePatient` | CommandButton | Caption: `Delete Patient`; Height 22; Left 10; Top 524; Width 110 |
| `btnRestorePatient` | CommandButton | Caption: `Restore Patient`; Height 22; Left 10; Top 524; Visible: `False`; Width 110 |

**Module-level variables**

```vba
Public PatientId As Long
```

**Code-behind**

```vba
Option Explicit

Private Sub UserForm_Activate()
    LoadPatient
End Sub

Private Sub LoadPatient()
    ' TODO(plan3): replace with modPatients.GetPatient(PatientId) and
    ' populate lblPatientName/lblMrn/lblPhone/lblReferralDate/
    ' lblReferralSource/lblReligion/lblLanguage/lblStatusBadge from it.
    ' TODO(plan3): populate cboChangeStatus from the status list EXCLUDING
    ' "deleted", select current_status.
    ' TODO(plan3): populate lstStatusHistory via modPatients.GetStatusHistory.
    ' TODO(plan4): populate lstAppointments via modAppointments.GetForPatient.
    ' TODO(plan3): populate txtSdatBeginScore/txtSdatBeginDate/txtSdatEndScore/
    ' txtSdatEndDate/txtNotes and lblSdatPctImprovement from the patient row.
    ' TODO(plan3): toggle btnDeletePatient/btnRestorePatient.Visible based on
    ' whether current_status = "deleted".
End Sub

Private Sub btnApplyStatus_Click()
    ' TODO(plan3): modPatients.ChangeStatus PatientId, cboChangeStatus.Value
    ' then LoadPatient to refresh the badge and history list.
End Sub

Private Sub btnEditPatient_Click()
    AddEditPatientForm.PatientId = PatientId
    AddEditPatientForm.Show
    LoadPatient
End Sub

Private Sub btnAddAppointment_Click()
    AddEditAppointmentForm.PatientId = PatientId
    AddEditAppointmentForm.AppointmentId = 0
    AddEditAppointmentForm.Show
    LoadPatient
End Sub

Private Sub btnEditAppointment_Click()
    If lstAppointments.ListIndex = -1 Then Exit Sub
    ' TODO(plan4): AddEditAppointmentForm.AppointmentId = <id from selected row>
    AddEditAppointmentForm.PatientId = PatientId
    AddEditAppointmentForm.Show
    LoadPatient
End Sub

Private Sub btnSaveSdat_Click()
    Dim beginScore As Variant, endScore As Variant
    beginScore = ParsedScore(txtSdatBeginScore.Text)
    endScore = ParsedScore(txtSdatEndScore.Text)
    If beginScore = "invalid" Or endScore = "invalid" Then
        MsgBox "SDAT scores must be a whole number between 0 and 40, or blank.", vbExclamation
        Exit Sub
    End If
    ' TODO(plan3): modPatients.SaveSdat PatientId, beginScore, txtSdatBeginDate.Text, _
    '     endScore, txtSdatEndDate.Text
    ' (modPatients recomputes and stores sdat_pct_improvement, same as patients.js)
    LoadPatient
End Sub

' Returns a Long 0-40, Empty for a blank string, or the string "invalid".
Private Function ParsedScore(s As String) As Variant
    If Trim(s) = "" Then
        ParsedScore = Empty
    ElseIf Not IsNumeric(s) Then
        ParsedScore = "invalid"
    ElseIf CLng(s) <> CDbl(s) Or CLng(s) < 0 Or CLng(s) > 40 Then
        ParsedScore = "invalid"
    Else
        ParsedScore = CLng(s)
    End If
End Function

Private Sub btnSaveNotes_Click()
    If Len(txtNotes.Text) > 256 Then
        MsgBox "Notes must be 256 characters or fewer.", vbExclamation
        Exit Sub
    End If
    ' TODO(plan3): modPatients.SaveNotes PatientId, txtNotes.Text
    LoadPatient
End Sub

Private Sub btnDeletePatient_Click()
    If MsgBox("Delete this patient? This can be undone from the Deleted filter.", _
              vbQuestion + vbYesNo, "Confirm Delete") <> vbYes Then Exit Sub
    ' TODO(plan3): modPatients.Delete PatientId
    LoadPatient
End Sub

Private Sub btnRestorePatient_Click()
    ' TODO(plan3): modPatients.Restore PatientId (sets current_status = "on_hold")
    LoadPatient
End Sub
```

---

## 2. AddEditPatientForm

**Form properties**

| Property | Value |
|---|---|
| (Name) | `AddEditPatientForm` |
| Caption | `Add / Edit Patient` |
| Height | 320 |
| StartUpPosition | `1 - CenterOwner` |
| Width | 340 |

**Controls**

| Control | Type | Properties (alphabetical) |
|---|---|---|
| `lblMrn` | Label | Caption: `MRN:`; Height 16; Left 10; Top 12; Width 90 |
| `lblLastName` | Label | Caption: `Last Name:`; Height 16; Left 10; Top 38; Width 90 |
| `lblFirstName` | Label | Caption: `First Name:`; Height 16; Left 10; Top 64; Width 90 |
| `lblMiddleName` | Label | Caption: `Middle Name:`; Height 16; Left 10; Top 90; Width 90 |
| `lblPhone` | Label | Caption: `Phone:`; Height 16; Left 10; Top 116; Width 90 |
| `lblReferralDate` | Label | Caption: `Referral Date:`; Height 16; Left 10; Top 142; Width 90 |
| `lblReferralDateHint` | Label | Caption: `(YYYY-MM-DD)`; Font: Italic, 8pt; Height 16; Left 235; Top 142; Width 75 |
| `lblReferralSource` | Label | Caption: `Referral Source:`; Height 16; Left 10; Top 168; Width 90 |
| `lblReligion` | Label | Caption: `Religion:`; Height 16; Left 10; Top 194; Width 90 |
| `lblLanguage` | Label | Caption: `Language:`; Height 16; Left 10; Top 220; Width 90 |
| `lblError` | Label | Caption: *(blank)*; ForeColor: red; Height 16; Left 10; TextAlign: `2 - fmTextAlignCenter`; Top 246; Visible: `False`; Width 300 |
| `txtMrn` | TextBox | Height 20; Left 110; Top 10; Width 200 |
| `txtLastName` | TextBox | Height 20; Left 110; Top 36; Width 200 |
| `txtFirstName` | TextBox | Height 20; Left 110; Top 62; Width 200 |
| `txtMiddleName` | TextBox | Height 20; Left 110; Top 88; Width 200 |
| `txtPhone` | TextBox | Height 20; Left 110; Top 114; Width 200 |
| `txtReferralDate` | TextBox | Height 20; Left 110; Top 140; Width 120 |
| `cboReferralSource` | ComboBox | Height 20; Left 110; Style: `2 - fmStyleDropDownList`; Top 166; Width 200 |
| `cboReligion` | ComboBox | Height 20; Left 110; Style: `2 - fmStyleDropDownList`; Top 192; Width 200 |
| `cboLanguage` | ComboBox | Height 20; Left 110; Style: `2 - fmStyleDropDownList`; Top 218; Width 200 |
| `btnSave` | CommandButton | Caption: `Save`; Default: `True`; Height 24; Left 140; Top 268; Width 80 |
| `btnCancel` | CommandButton | Caption: `Cancel`; Height 24; Left 230; Top 268; Width 80 |

**Module-level variables**

```vba
Public PatientId As Long   ' 0 = new patient
```

**Code-behind**

```vba
Option Explicit

Private Sub UserForm_Activate()
    ' TODO(plan3): populate cboReferralSource/cboReligion/cboLanguage from
    ' modUtils.DataSheet("_data_lov") rows for each category.
    If PatientId > 0 Then
        ' TODO(plan3): load modPatients.GetPatient(PatientId) into the fields.
        Me.Caption = "Edit Patient"
    Else
        Me.Caption = "Add Patient"
    End If
End Sub

Private Sub btnSave_Click()
    If Trim(txtLastName.Text) = "" Or Trim(txtFirstName.Text) = "" Then
        ShowError "First and last name are required."
        Exit Sub
    End If
    ' TODO(plan3): validate txtReferralDate as YYYY-MM-DD.
    ' TODO(plan3): modPatients.Save PatientId, txtMrn.Text, txtLastName.Text, ...
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub
```

---

## 3. AddEditAppointmentForm

**Form properties**

| Property | Value |
|---|---|
| (Name) | `AddEditAppointmentForm` |
| Caption | `Add / Edit Appointment` |
| Height | 320 |
| StartUpPosition | `1 - CenterOwner` |
| Width | 320 |

**Controls**

| Control | Type | Properties (alphabetical) |
|---|---|---|
| `lblDate` | Label | Caption: `Date:`; Height 16; Left 10; Top 12; Width 90 |
| `lblTime` | Label | Caption: `Time:`; Height 16; Left 10; Top 38; Width 90 |
| `lblType` | Label | Caption: `Type:`; Height 16; Left 10; Top 64; Width 90 |
| `lblConsultant` | Label | Caption: `Consultant:`; Height 16; Left 10; Top 90; Width 90 |
| `lblStatus` | Label | Caption: `Status:`; Height 16; Left 10; Top 142; Width 90 |
| `lblNotes` | Label | Caption: `Notes:`; Height 16; Left 10; Top 168; Width 90 |
| `lblError` | Label | Caption: *(blank)*; ForeColor: red; Height 16; Left 10; TextAlign: `2 - fmTextAlignCenter`; Top 250; Visible: `False`; Width 280 |
| `txtDate` | TextBox | Height 20; Left 110; Top 10; Width 120 |
| `txtTime` | TextBox | Height 20; Left 110; Top 36; Width 80 |
| `txtNotes` | TextBox | EnterKeyBehavior: `True`; Height 60; Left 10; MultiLine: `True`; ScrollBars: `2 - fmScrollBarsVertical`; Top 186; Width 280 |
| `cboType` | ComboBox | Height 20; Left 110; Style: `2 - fmStyleDropDownList`; Top 62; Width 180 |
| `cboConsultant` | ComboBox | Height 20; Left 110; Style: `2 - fmStyleDropDownList`; Top 88; Width 180 |
| `cboStatus` | ComboBox | Height 20; Left 110; Style: `2 - fmStyleDropDownList`; Top 140; Width 180 |
| `chkLastAppointment` | CheckBox | Caption: `This is the last appointment`; Height 18; Left 10; Top 116; Width 220 |
| `btnSave` | CommandButton | Caption: `Save`; Default: `True`; Height 24; Left 120; Top 272; Width 80 |
| `btnCancel` | CommandButton | Caption: `Cancel`; Height 24; Left 210; Top 272; Width 80 |

**Module-level variables**

```vba
Public PatientId As Long
Public AppointmentId As Long   ' 0 = new appointment
```

**Code-behind**

```vba
Option Explicit

Private Sub UserForm_Activate()
    ' TODO(plan4): populate cboType from _data_lov category=appointment_type,
    ' cboConsultant from _data_consultants, cboStatus from the fixed list
    ' (scheduled/completed/no_show/cancelled).
    If AppointmentId > 0 Then
        ' TODO(plan4): load modAppointments.Get(AppointmentId) into the fields.
        Me.Caption = "Edit Appointment"
    Else
        Me.Caption = "Add Appointment"
    End If
End Sub

Private Sub btnSave_Click()
    If Trim(txtDate.Text) = "" Then
        ShowError "Date is required."
        Exit Sub
    End If
    ' TODO(plan4): validate txtDate/txtTime, then
    ' modAppointments.Save AppointmentId, PatientId, txtDate.Text, ...
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub
```

---

## 4. AddUserForm

Also used for first-run setup — see `ThisWorkbook.Workbook_Open`, which
currently shows an informational `MsgBox` instead when `_data_users` is
empty. Plan 6 should replace that `MsgBox` with
`AddUserForm.FirstRunMode = True: AddUserForm.Show`.

**Form properties**

| Property | Value |
|---|---|
| (Name) | `AddUserForm` |
| Caption | `Add User` |
| Height | 280 |
| StartUpPosition | `1 - CenterOwner` |
| Width | 300 |

**Controls**

| Control | Type | Properties (alphabetical) |
|---|---|---|
| `lblName` | Label | Caption: `Name:`; Height 16; Left 10; Top 12; Width 90 |
| `lblEmail` | Label | Caption: `Email:`; Height 16; Left 10; Top 38; Width 90 |
| `lblPassword` | Label | Caption: `Password:`; Height 16; Left 10; Top 64; Width 90 |
| `lblConfirmPassword` | Label | Caption: `Confirm Password:`; Height 16; Left 10; Top 90; Width 90 |
| `lblRole` | Label | Caption: `Role:`; Height 16; Left 10; Top 116; Width 90 |
| `lblError` | Label | Caption: *(blank)*; ForeColor: red; Height 16; Left 10; TextAlign: `2 - fmTextAlignCenter`; Top 150; Visible: `False`; Width 270 |
| `txtName` | TextBox | Height 20; Left 100; Top 10; Width 180 |
| `txtEmail` | TextBox | Height 20; Left 100; Top 36; Width 180 |
| `txtPassword` | TextBox | Height 20; Left 100; PasswordChar: `*`; Top 62; Width 180 |
| `txtConfirmPassword` | TextBox | Height 20; Left 100; PasswordChar: `*`; Top 88; Width 180 |
| `cboRole` | ComboBox | Height 20; Left 100; Style: `2 - fmStyleDropDownList`; Top 114; Width 180 |
| `btnSave` | CommandButton | Caption: `Save`; Default: `True`; Height 24; Left 110; Top 180; Width 80 |
| `btnCancel` | CommandButton | Caption: `Cancel`; Height 24; Left 200; Top 180; Width 80 |

**Module-level variables**

```vba
Public FirstRunMode As Boolean   ' set by caller before .Show
```

**Code-behind**

```vba
Option Explicit

Private Sub UserForm_Activate()
    cboRole.AddItem "admin"
    cboRole.AddItem "coordinator"
    If FirstRunMode Then
        Me.Caption = "Create Admin Account"
        cboRole.Value = "admin"
        cboRole.Enabled = False
        btnCancel.Visible = False
    Else
        Me.Caption = "Add User"
        cboRole.Value = "coordinator"
    End If
End Sub

Private Sub btnSave_Click()
    If Trim(txtName.Text) = "" Or Trim(txtEmail.Text) = "" Then
        ShowError "Name and email are required."
        Exit Sub
    End If
    If txtPassword.Text = "" Or txtPassword.Text <> txtConfirmPassword.Text Then
        ShowError "Passwords must match and cannot be blank."
        Exit Sub
    End If
    ' TODO(plan6): modAdmin.CreateUser txtName.Text, txtEmail.Text, _
    '     txtPassword.Text, cboRole.Value
    If FirstRunMode Then
        ' TODO(plan6): log the new admin in immediately (modAuth.ValidateLogin)
        ' and proceed to LoginForm's post-login sheet setup, then Unload Me.
    End If
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub
```

---

## 5. ResetPasswordForm

**Form properties**

| Property | Value |
|---|---|
| (Name) | `ResetPasswordForm` |
| Caption | `Reset Password` |
| Height | 220 |
| StartUpPosition | `1 - CenterOwner` |
| Width | 280 |

**Controls**

| Control | Type | Properties (alphabetical) |
|---|---|---|
| `lblUserName` | Label | Caption: *(blank, set at runtime)*; Font: Bold; Height 16; Left 10; Top 10; Width 250 |
| `lblNewPassword` | Label | Caption: `New Password:`; Height 16; Left 10; Top 40; Width 100 |
| `lblConfirmPassword` | Label | Caption: `Confirm Password:`; Height 16; Left 10; Top 66; Width 100 |
| `lblError` | Label | Caption: *(blank)*; ForeColor: red; Height 16; Left 10; TextAlign: `2 - fmTextAlignCenter`; Top 96; Visible: `False`; Width 250 |
| `txtNewPassword` | TextBox | Height 20; Left 115; PasswordChar: `*`; Top 38; Width 150 |
| `txtConfirmPassword` | TextBox | Height 20; Left 115; PasswordChar: `*`; Top 64; Width 150 |
| `btnSave` | CommandButton | Caption: `Reset`; Default: `True`; Height 24; Left 90; Top 130; Width 80 |
| `btnCancel` | CommandButton | Caption: `Cancel`; Height 24; Left 180; Top 130; Width 80 |

**Module-level variables**

```vba
Public UserId As Long   ' set by caller before .Show
```

**Code-behind**

```vba
Option Explicit

Private Sub UserForm_Activate()
    ' TODO(plan6): lblUserName.Caption = modAdmin.GetUserName(UserId)
End Sub

Private Sub btnSave_Click()
    If txtNewPassword.Text = "" Or txtNewPassword.Text <> txtConfirmPassword.Text Then
        ShowError "Passwords must match and cannot be blank."
        Exit Sub
    End If
    ' TODO(plan6): modAdmin.ResetPassword UserId, txtNewPassword.Text
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub
```

---

## 6. ImportMappingForm

Per spec: shown after the admin picks an Electron-export `.xlsx` file (the
file picker itself runs in `modExport` before this form is shown), previews
detected columns, then asks Replace vs. Merge before the import runs.

**Form properties**

| Property | Value |
|---|---|
| (Name) | `ImportMappingForm` |
| Caption | `Import from Electron Export` |
| Height | 360 |
| StartUpPosition | `1 - CenterOwner` |
| Width | 420 |

**Controls**

| Control | Type | Properties (alphabetical) |
|---|---|---|
| `lblInstructions` | Label | Caption: `Review the detected columns below, then choose how to apply this import.`; Height 32; Left 10; Top 10; Width 400 |
| `lblProgress` | Label | Caption: *(blank)*; Height 16; Left 10; Top 282; Width 400 |
| `lstPreview` | ListBox | ColumnCount: `5`; ColumnWidths: `80 pt;80 pt;80 pt;80 pt;80 pt`; Height 180; Left 10; Top 46; Width 400 |
| `optReplace` | OptionButton | Caption: `Replace all data`; Height 18; Left 10; Top 236; Width 200 |
| `optMerge` | OptionButton | Caption: `Merge (skip MRNs already present)`; Height 18; Left 10; Top 256; Value: `True`; Width 260 |
| `btnImport` | CommandButton | Caption: `Import`; Default: `True`; Height 24; Left 230; Top 306; Width 80 |
| `btnCancel` | CommandButton | Caption: `Cancel`; Height 24; Left 320; Top 306; Width 80 |

**Module-level variables**

```vba
Public SourceFilePath As String   ' set by caller before .Show
```

**Code-behind**

```vba
Option Explicit

Private Sub UserForm_Activate()
    ' TODO(plan7): populate lstPreview from modExport.PreviewImport(SourceFilePath)
End Sub

Private Sub btnImport_Click()
    lblProgress.Caption = "Importing..."
    Me.Repaint
    ' TODO(plan7): modExport.RunImport SourceFilePath, IIf(optReplace.Value, "replace", "merge")
    lblProgress.Caption = "Done."
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub
```

---

## 7. PurgeConfirmForm

**Form properties**

| Property | Value |
|---|---|
| (Name) | `PurgeConfirmForm` |
| Caption | `Confirm Data Purge` |
| Height | 220 |
| StartUpPosition | `1 - CenterOwner` |
| Width | 380 |

**Controls**

| Control | Type | Properties (alphabetical) |
|---|---|---|
| `lblMessage` | Label | Caption: *(blank, set at runtime)*; Height 40; Left 10; Top 10; Width 360 |
| `lblArchivePath` | Label | Caption: `Archive to:`; Height 16; Left 10; Top 60; Width 70 |
| `txtArchivePath` | TextBox | Height 20; Left 85; Top 58; Width 200 |
| `btnBrowse` | CommandButton | Caption: `Browse...`; Height 20; Left 290; Top 58; Width 80 |
| `btnConfirm` | CommandButton | Caption: `Archive && Purge`; Default: `True`; Height 24; Left 190; Top 140; Width 90 |
| `btnCancel` | CommandButton | Caption: `Cancel`; Height 24; Left 290; Top 140; Width 80 |

**Module-level variables**

```vba
Public StaleCount As Long          ' set by caller before .Show
Public DefaultArchivePath As String
```

**Code-behind**

```vba
Option Explicit

Private Sub UserForm_Activate()
    lblMessage.Caption = StaleCount & " patient(s) have had no activity within " & _
        "the retention period and will be archived and removed."
    txtArchivePath.Text = DefaultArchivePath
End Sub

Private Sub btnBrowse_Click()
    Dim fd As FileDialog
    Set fd = Application.FileDialog(msoFileDialogSaveAs)
    fd.InitialFileName = txtArchivePath.Text
    If fd.Show = -1 Then
        txtArchivePath.Text = fd.SelectedItems(1)
    End If
End Sub

Private Sub btnConfirm_Click()
    ' TODO(plan6): modPurge.RunPurge txtArchivePath.Text
    ' (updates _data_settings.last_purge_date on success — leave it untouched
    ' on Cancel so the prompt reappears next open, per spec.)
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub
```
