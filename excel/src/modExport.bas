Attribute VB_Name = "modExport"
Option Explicit

Private Const VALID_STATUSES As String = "ready_to_schedule,scheduled,completed,dropped,on_hold"
Private Const VALID_APPT_STATUSES As String = "scheduled,completed,no_show,cancelled,rescheduled"

' ── Generic range export (shared by every "Export" button) ────────────────
Public Sub ExportRangeToXlsx(dataRange As Range, suggestedFileName As String)
    Dim fileName As Variant
    fileName = Application.GetSaveAsFilename(InitialFileName:=suggestedFileName, FileFilter:="Excel Workbook (*.xlsx), *.xlsx")
    If fileName = False Then Exit Sub

    Dim newWb As Workbook: Set newWb = Application.Workbooks.Add
    dataRange.Copy
    newWb.Sheets(1).Range("A1").PasteSpecial xlPasteAll
    Application.CutCopyMode = False
    newWb.SaveAs fileName, FileFormat:=51 ' xlOpenXMLWorkbook
    newWb.Close SaveChanges:=False
    MsgBox "Exported to " & fileName, vbInformation
End Sub

' ── Excel -> Electron migration ────────────────────────────────────────────
' Matches Electron's REAL importer (src/main/ipc/excel.js's single flat sheet
' `patients_and_appointments`), not the design spec's originally-stated
' multi-sheet format -- that multi-sheet format was never built on the
' Electron side, so following the spec literally would produce a migration
' feature that can't actually round-trip. Each active patient with N>=1
' appointments emits N rows (patient fields repeated + that appointment's
' fields); a patient with 0 appointments emits exactly 1 row with blank
' appt_* fields -- the exact inverse of how excel.js's importHistorical
' re-groups rows back into patients by MRN/name.
Public Sub ExportForImport(archivePath As String)
    Dim newWb As Workbook: Set newWb = Application.Workbooks.Add
    Dim destWs As Worksheet: Set destWs = newWb.Sheets(1)
    destWs.Name = "patients_and_appointments"

    Dim headers As Variant
    headers = Array("last_name", "first_name", "middle_name", "mrn", "phone", _
        "date_of_referral", "referral_source", "religion", "language", "current_status", _
        "appt_date", "appt_time", "appt_type", "consultant", "appt_status", _
        "is_last_appointment", "notes")
    Dim c As Long
    For c = 0 To UBound(headers)
        destWs.Cells(1, c + 1).Value = headers(c)
    Next c
    destWs.Rows(1).Font.Bold = True
    destWs.Columns(6).NumberFormat = "@"  ' date_of_referral
    destWs.Columns(11).NumberFormat = "@" ' appt_date
    destWs.Columns(12).NumberFormat = "@" ' appt_time

    Dim patientsWs As Worksheet: Set patientsWs = modUtils.DataSheet("_data_patients")
    Dim lastP As Long: lastP = modUtils.LastDataRow(patientsWs)
    Dim cActive As Long: cActive = modUtils.ColIndex(patientsWs, "is_active")
    Dim cId As Long: cId = modUtils.ColIndex(patientsWs, "id")

    Dim outRow As Long: outRow = 2
    Dim p As Long
    For p = 2 To lastP
        If patientsWs.Cells(p, cActive).Value = 1 Then
            Dim pid As Long: pid = CLng(patientsWs.Cells(p, cId).Value)
            Dim appts As Collection: Set appts = modAppointments.GetForPatient(pid)
            If appts.Count = 0 Then
                WriteExportRow destWs, outRow, patientsWs, p, Nothing
                outRow = outRow + 1
            Else
                Dim a As Object
                For Each a In appts
                    WriteExportRow destWs, outRow, patientsWs, p, a
                    outRow = outRow + 1
                Next a
            End If
        End If
    Next p

    newWb.SaveAs archivePath, FileFormat:=51
    newWb.Close SaveChanges:=False
End Sub

' `appt` is Nothing for a patient with no appointments (columns 11-16 stay blank).
Private Sub WriteExportRow(destWs As Worksheet, destRow As Long, patientsWs As Worksheet, patientRow As Long, appt As Object)
    destWs.Cells(destRow, 1).Value = patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "last_name")).Value
    destWs.Cells(destRow, 2).Value = patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "first_name")).Value
    destWs.Cells(destRow, 3).Value = patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "middle_name")).Value
    destWs.Cells(destRow, 4).Value = patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "mrn")).Value
    destWs.Cells(destRow, 5).Value = patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "phone")).Value
    destWs.Cells(destRow, 6).Value = patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "date_of_referral")).Value
    destWs.Cells(destRow, 7).Value = modUtils.LovValueForId(CLng(patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "referral_source_id")).Value))
    destWs.Cells(destRow, 8).Value = modUtils.LovValueForId(CLng(patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "religion_id")).Value))
    destWs.Cells(destRow, 9).Value = modUtils.LovValueForId(CLng(patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "language_id")).Value))
    destWs.Cells(destRow, 10).Value = patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "current_status")).Value

    If Not appt Is Nothing Then
        destWs.Cells(destRow, 11).Value = appt("date")
        destWs.Cells(destRow, 12).Value = appt("time")
        destWs.Cells(destRow, 13).Value = appt("type")
        destWs.Cells(destRow, 14).Value = appt("consultant_name")
        destWs.Cells(destRow, 15).Value = appt("status")
        destWs.Cells(destRow, 16).Value = IIf(appt("is_last_appointment") = 1, 1, 0)
    End If

    destWs.Cells(destRow, 17).Value = patientsWs.Cells(patientRow, modUtils.ColIndex(patientsWs, "notes")).Value
End Sub

' ── Electron -> Excel migration ────────────────────────────────────────────
' VBA has no xlsx-parsing library, so the picked file is opened directly and
' read from Sheets(1) BY POSITION, not by name -- Electron's own importer
' also takes workbook.SheetNames[0], ignoring the sheet's name.
Public Function PreviewImport(filePath As String) As Collection
    Dim result As New Collection
    Dim srcWb As Workbook: Set srcWb = Application.Workbooks.Open(filePath, ReadOnly:=True)
    Dim srcWs As Worksheet: Set srcWs = srcWb.Sheets(1)

    Dim last As Long: last = srcWs.Cells(srcWs.Rows.Count, 1).End(xlUp).Row
    Dim r As Long
    For r = 2 To last
        Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
        d("last_name") = srcWs.Cells(r, 1).Value
        d("first_name") = srcWs.Cells(r, 2).Value
        d("mrn") = srcWs.Cells(r, 4).Value
        d("appt_date") = srcWs.Cells(r, 11).Value
        d("current_status") = srcWs.Cells(r, 10).Value
        result.Add d
    Next r

    srcWb.Close SaveChanges:=False
    Set PreviewImport = result
End Function

' Re-implements excel.js's importHistorical: groups rows into patients by
' MRN-or-name (multiple source rows for the same patient share one patient
' record, one row per appointment), resolves LoV/consultant names to IDs
' (auto-creating any that don't already exist), and either Merges (skips
' rows whose MRN already exists in the sheet) or Replaces (wipes
' _data_patients/_data_appointments/_data_status_history ONLY -- not
' _data_users/_data_consultants/_data_lov/_data_settings/_data_audit, since
' literally wiping those would log out the importing admin mid-import and
' destroy the very LoV/consultant rows the import needs to resolve FKs
' against; an intentional, flagged deviation from the spec's literal wording
' for "Replace", consistent with the multi-sheet-vs-flat-sheet decision above).
Public Sub RunImport(filePath As String, mode As String)
    Dim srcWb As Workbook: Set srcWb = Application.Workbooks.Open(filePath, ReadOnly:=True)
    Dim srcWs As Worksheet: Set srcWs = srcWb.Sheets(1)
    Dim last As Long: last = srcWs.Cells(srcWs.Rows.Count, 1).End(xlUp).Row

    Application.EnableEvents = False
    ' Suppress the per-row AutoSave that modPatients.Save/ChangeStatus/
    ' SaveNotes and modAppointments.Save would otherwise each trigger --
    ' saving the workbook on every imported row would be very slow for a
    ' large import. One AutoSave at the end covers the whole batch.
    modUtils.gSuppressAutoSave = True

    If mode = "replace" Then
        WipeDataRows modUtils.DataSheet("_data_patients")
        WipeDataRows modUtils.DataSheet("_data_appointments")
        WipeDataRows modUtils.DataSheet("_data_status_history")
    End If

    Dim patientIdByKey As Object: Set patientIdByKey = CreateObject("Scripting.Dictionary")
    If mode = "merge" Then
        PopulateExistingPatientKeys patientIdByKey
    End If

    Dim r As Long
    For r = 2 To last
        Dim lastName As String: lastName = Trim(CStr(srcWs.Cells(r, 1).Value))
        Dim firstName As String: firstName = Trim(CStr(srcWs.Cells(r, 2).Value))
        If lastName = "" And firstName = "" Then GoTo ContinueImportLoop

        Dim mrn As String: mrn = Trim(CStr(srcWs.Cells(r, 4).Value))
        Dim rowKey As String
        If mrn <> "" Then
            rowKey = "mrn:" & LCase(mrn)
        Else
            rowKey = "name:" & LCase(firstName) & "|" & LCase(lastName)
        End If

        Dim pid As Long
        If patientIdByKey.Exists(rowKey) Then
            pid = patientIdByKey(rowKey)
            If pid = 0 Then GoTo ContinueImportLoop ' merge-mode: MRN already present, skip
        Else
            Dim middleName As String: middleName = Trim(CStr(srcWs.Cells(r, 3).Value))
            Dim phone As String: phone = Trim(CStr(srcWs.Cells(r, 5).Value))
            Dim referralDate As String: referralDate = NormalizeDate(srcWs.Cells(r, 6))
            Dim referralSourceId As Long: referralSourceId = ResolveLovId("referral_source", Trim(CStr(srcWs.Cells(r, 7).Value)))
            Dim religionId As Long: religionId = ResolveLovId("religion", Trim(CStr(srcWs.Cells(r, 8).Value)))
            Dim languageId As Long: languageId = ResolveLovId("language", Trim(CStr(srcWs.Cells(r, 9).Value)))
            Dim rowStatus As String: rowStatus = Trim(CStr(srcWs.Cells(r, 10).Value))
            If InStr(1, "," & VALID_STATUSES & ",", "," & rowStatus & ",") = 0 Then rowStatus = "ready_to_schedule"
            Dim patientNotes As String: patientNotes = CStr(srcWs.Cells(r, 17).Value)

            modPatients.Save 0, mrn, lastName, firstName, middleName, phone, referralDate, _
                referralSourceId, religionId, languageId
            pid = LastCreatedPatientId()
            If rowStatus <> "ready_to_schedule" Then modPatients.ChangeStatus pid, rowStatus
            If patientNotes <> "" Then modPatients.SaveNotes pid, patientNotes

            patientIdByKey(rowKey) = pid
        End If

        Dim apptDate As String: apptDate = NormalizeDate(srcWs.Cells(r, 11))
        If apptDate <> "" Then
            Dim apptTime As String: apptTime = NormalizeTime(srcWs.Cells(r, 12))
            Dim apptTypeId As Long: apptTypeId = ResolveLovId("appointment_type", Trim(CStr(srcWs.Cells(r, 13).Value)))
            Dim consultantId As Long: consultantId = ResolveConsultantId(Trim(CStr(srcWs.Cells(r, 14).Value)))
            Dim apptStatus As String: apptStatus = Trim(CStr(srcWs.Cells(r, 15).Value))
            If InStr(1, "," & VALID_APPT_STATUSES & ",", "," & apptStatus & ",") = 0 Then apptStatus = "scheduled"
            Dim isLast As Boolean: isLast = (Trim(CStr(srcWs.Cells(r, 16).Value)) = "1")

            modAppointments.Save 0, pid, apptDate, apptTime, apptTypeId, consultantId, isLast, apptStatus, ""
        End If

ContinueImportLoop:
    Next r

    srcWb.Close SaveChanges:=False
    Application.EnableEvents = True
    modUtils.gSuppressAutoSave = False
    modUtils.AutoSave
End Sub

Private Sub WipeDataRows(ws As Worksheet)
    Dim last As Long: last = modUtils.LastDataRow(ws)
    If last >= 2 Then ws.Rows("2:" & last).Delete
End Sub

Private Sub PopulateExistingPatientKeys(dict As Object)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cMrn As Long: cMrn = modUtils.ColIndex(ws, "mrn")
    Dim i As Long
    For i = 2 To last
        Dim mrn As String: mrn = Trim(CStr(ws.Cells(i, cMrn).Value))
        If mrn <> "" Then dict("mrn:" & LCase(mrn)) = 0 ' 0 = sentinel: skip, already present
    Next i
End Sub

Private Function LastCreatedPatientId() As Long
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    LastCreatedPatientId = CLng(ws.Cells(modUtils.LastDataRow(ws), 1).Value)
End Function

Private Function NormalizeDate(cell As Range) As String
    Dim v As Variant: v = cell.Value
    If IsEmpty(v) Or Trim(v & "") = "" Then
        NormalizeDate = ""
    ElseIf VarType(v) = vbDate Then
        NormalizeDate = modUtils.DateISO(CDate(v))
    Else
        NormalizeDate = Trim(CStr(v))
    End If
End Function

' Same defensive normalization as NormalizeDate, but for a time-of-day cell
' (VBA's vbDate VarType also covers time-only serials -- a bare CStr() of one
' renders in the system locale's time format, not necessarily "HH:MM").
Private Function NormalizeTime(cell As Range) As String
    Dim v As Variant: v = cell.Value
    If IsEmpty(v) Or Trim(v & "") = "" Then
        NormalizeTime = ""
    ElseIf VarType(v) = vbDate Then
        NormalizeTime = Format(CDate(v), "hh:nn")
    Else
        NormalizeTime = Trim(CStr(v))
    End If
End Function

Private Function ResolveLovId(category As String, lovValue As String) As Long
    If lovValue = "" Then Exit Function
    Dim id As Long: id = modUtils.LovIdForValue(category, lovValue)
    If id = 0 Then
        modAdmin.UpsertLov category, lovValue, 0
        id = modUtils.LovIdForValue(category, lovValue)
    End If
    ResolveLovId = id
End Function

Private Function ResolveConsultantId(consultantName As String) As Long
    If consultantName = "" Then Exit Function
    Dim id As Long: id = modAppointments.ConsultantIdForName(consultantName)
    If id = 0 Then
        modAdmin.UpsertConsultant 0, consultantName, False
        id = modAppointments.ConsultantIdForName(consultantName)
    End If
    ResolveConsultantId = id
End Function

' ── Admin sheet UI ──────────────────────────────────────────────────────────
Public Sub UI_ExportForImport()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim fileName As Variant
    fileName = Application.GetSaveAsFilename(InitialFileName:="ExportForElectron.xlsx", FileFilter:="Excel Workbook (*.xlsx), *.xlsx")
    If fileName = False Then Exit Sub
    ExportForImport CStr(fileName)
    MsgBox "Exported to " & fileName, vbInformation
End Sub

Public Sub UI_ImportFromElectron()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim fd As FileDialog: Set fd = Application.FileDialog(msoFileDialogFilePicker)
    fd.Filters.Clear
    fd.Filters.Add "Excel Workbook", "*.xlsx"
    If fd.Show <> -1 Then Exit Sub

    ImportMappingForm.SourceFilePath = fd.SelectedItems(1)
    ImportMappingForm.Show

    modAdmin.RefreshAdmin
    modPatients.RefreshWorkQueue
End Sub
