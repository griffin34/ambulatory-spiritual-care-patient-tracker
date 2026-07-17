Attribute VB_Name = "modReports"
Option Explicit

' ── Referrals by Source ────────────────────────────────────────────────────
Public Function ReferralsBySource(fromIso As String, toIso As String) As Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cReferralDate As Long: cReferralDate = modUtils.ColIndex(ws, "date_of_referral")
    Dim cReferralSrc As Long: cReferralSrc = modUtils.ColIndex(ws, "referral_source_id")

    Dim counts As Object: Set counts = CreateObject("Scripting.Dictionary")
    Dim total As Long: total = 0
    Dim i As Long
    For i = 2 To last
        Dim d As String: d = CStr(ws.Cells(i, cReferralDate).Value)
        If d >= fromIso And d <= toIso Then
            Dim srcLabel As String: srcLabel = modUtils.LovValueForId(CLng(ws.Cells(i, cReferralSrc).Value))
            If srcLabel = "" Then srcLabel = "Unknown"
            If Not counts.Exists(srcLabel) Then counts(srcLabel) = 0
            counts(srcLabel) = counts(srcLabel) + 1
            total = total + 1
        End If
    Next i

    Dim rows As New Collection
    Dim key As Variant
    For Each key In counts.Keys
        Dim dd As Object: Set dd = CreateObject("Scripting.Dictionary")
        dd("source") = key
        dd("count") = counts(key)
        If total > 0 Then
            dd("percent") = modUtils.RoundHalfUp(CDbl(counts(key)) / CDbl(total) * 100, 0)
        Else
            dd("percent") = 0
        End If
        rows.Add dd
    Next key

    ' DESC by count, mirroring reports.js's ORDER BY count DESC.
    Dim result As New Collection
    Dim n As Long: n = rows.Count
    If n = 0 Then
        Set ReferralsBySource = result
        Exit Function
    End If
    Dim arr() As Object: ReDim arr(1 To n)
    For i = 1 To n: Set arr(i) = rows(i): Next i
    Dim a As Long, b As Long
    For a = 1 To n - 1
        For b = 1 To n - a
            If arr(b)("count") < arr(b + 1)("count") Then
                Dim tmp As Object: Set tmp = arr(b): Set arr(b) = arr(b + 1): Set arr(b + 1) = tmp
            End If
        Next b
    Next a
    For i = 1 To n: result.Add arr(i): Next i
    Set ReferralsBySource = result
End Function

' ── First Appointments ─────────────────────────────────────────────────────
' Per-patient earliest appointment with status IN (completed, scheduled),
' tie-broken by date/time/id, filtered by that appointment's date being in
' range -- mirrors reports.js's correlated-subquery logic (no direct SQL
' equivalent in VBA, so it's a single pass keeping a running best-per-patient).
Public Function FirstAppointments(fromIso As String, toIso As String) As Collection
    Dim apptWs As Worksheet: Set apptWs = modUtils.DataSheet("_data_appointments")
    Dim last As Long: last = modUtils.LastDataRow(apptWs)
    Dim cPid As Long: cPid = modUtils.ColIndex(apptWs, "patient_id")
    Dim cApptDate As Long: cApptDate = modUtils.ColIndex(apptWs, "date")
    Dim cApptTime As Long: cApptTime = modUtils.ColIndex(apptWs, "time")
    Dim cApptId As Long: cApptId = modUtils.ColIndex(apptWs, "id")
    Dim cConsultantId As Long: cConsultantId = modUtils.ColIndex(apptWs, "consultant_id")
    Dim cStatus As Long: cStatus = modUtils.ColIndex(apptWs, "status")

    Dim bestDate As Object: Set bestDate = CreateObject("Scripting.Dictionary")
    Dim bestKey As Object: Set bestKey = CreateObject("Scripting.Dictionary")
    Dim bestConsultant As Object: Set bestConsultant = CreateObject("Scripting.Dictionary")

    Dim i As Long
    For i = 2 To last
        Dim status As String: status = CStr(apptWs.Cells(i, cStatus).Value)
        If status = "completed" Or status = "scheduled" Then
            Dim pidKey As String: pidKey = CStr(CLng(apptWs.Cells(i, cPid).Value))
            Dim d As String: d = CStr(apptWs.Cells(i, cApptDate).Value)
            Dim t As String: t = CStr(apptWs.Cells(i, cApptTime).Value)
            Dim apptId As Long: apptId = CLng(apptWs.Cells(i, cApptId).Value)
            Dim sortKey As String: sortKey = d & " " & t & " " & Format(apptId, "0000000000")
            If Not bestKey.Exists(pidKey) Then
                bestKey(pidKey) = sortKey
                bestDate(pidKey) = d
                bestConsultant(pidKey) = CLng(apptWs.Cells(i, cConsultantId).Value)
            ElseIf sortKey < CStr(bestKey(pidKey)) Then
                bestKey(pidKey) = sortKey
                bestDate(pidKey) = d
                bestConsultant(pidKey) = CLng(apptWs.Cells(i, cConsultantId).Value)
            End If
        End If
    Next i

    Dim patientsWs As Worksheet: Set patientsWs = modUtils.DataSheet("_data_patients")
    Dim cLast As Long: cLast = modUtils.ColIndex(patientsWs, "last_name")
    Dim cFirst As Long: cFirst = modUtils.ColIndex(patientsWs, "first_name")

    Dim result As New Collection
    Dim key As Variant
    For Each key In bestDate.Keys
        Dim apptDate As String: apptDate = CStr(bestDate(key))
        If apptDate >= fromIso And apptDate <= toIso Then
            Dim pr As Long: pr = modUtils.FindById(patientsWs, CLng(key))
            Dim patName As String
            If pr > 0 Then
                patName = CStr(patientsWs.Cells(pr, cFirst).Value) & " " & CStr(patientsWs.Cells(pr, cLast).Value)
            Else
                patName = "(unknown)"
            End If
            Dim dd As Object: Set dd = CreateObject("Scripting.Dictionary")
            dd("patient_name") = patName
            dd("first_appt_date") = apptDate
            dd("consultant_name") = ConsultantNameForReport(CLng(bestConsultant(key)))
            result.Add dd
        End If
    Next key

    Set FirstAppointments = result
End Function

Private Function ConsultantNameForReport(consultantId As Long) As String
    If consultantId <= 0 Then Exit Function
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_consultants")
    Dim r As Long: r = modUtils.FindById(ws, consultantId)
    If r = 0 Then Exit Function
    ConsultantNameForReport = CStr(ws.Cells(r, modUtils.ColIndex(ws, "name")).Value)
End Function

' ── Patients Dropped ───────────────────────────────────────────────────────
Public Function PatientsDropped(fromIso As String, toIso As String) As Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_status_history")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cPid As Long: cPid = modUtils.ColIndex(ws, "patient_id")
    Dim cStatus As Long: cStatus = modUtils.ColIndex(ws, "status")
    Dim cChangedBy As Long: cChangedBy = modUtils.ColIndex(ws, "changed_by")
    Dim cChangedAt As Long: cChangedAt = modUtils.ColIndex(ws, "changed_at")

    Dim patientsWs As Worksheet: Set patientsWs = modUtils.DataSheet("_data_patients")
    Dim cLast As Long: cLast = modUtils.ColIndex(patientsWs, "last_name")
    Dim cFirst As Long: cFirst = modUtils.ColIndex(patientsWs, "first_name")

    Dim rows As New Collection
    Dim i As Long
    For i = 2 To last
        If CStr(ws.Cells(i, cStatus).Value) = "dropped" Then
            Dim changedAt As String: changedAt = CStr(ws.Cells(i, cChangedAt).Value)
            Dim datePart As String: datePart = Left(changedAt, 10)
            If datePart >= fromIso And datePart <= toIso Then
                Dim pid As Long: pid = CLng(ws.Cells(i, cPid).Value)
                Dim pr As Long: pr = modUtils.FindById(patientsWs, pid)
                Dim patName As String
                If pr > 0 Then
                    patName = CStr(patientsWs.Cells(pr, cFirst).Value) & " " & CStr(patientsWs.Cells(pr, cLast).Value)
                Else
                    patName = "(unknown)"
                End If
                Dim dd As Object: Set dd = CreateObject("Scripting.Dictionary")
                dd("patient_name") = patName
                dd("dropped_date") = datePart
                dd("changed_at") = changedAt
                dd("changed_by_name") = modAdmin.GetUserName(CLng(ws.Cells(i, cChangedBy).Value))
                rows.Add dd
            End If
        End If
    Next i

    ' DESC by changed_at
    Dim result As New Collection
    Dim n As Long: n = rows.Count
    If n = 0 Then
        Set PatientsDropped = result
        Exit Function
    End If
    Dim arr() As Object: ReDim arr(1 To n)
    For i = 1 To n: Set arr(i) = rows(i): Next i
    Dim a As Long, b As Long
    For a = 1 To n - 1
        For b = 1 To n - a
            If CStr(arr(b)("changed_at")) < CStr(arr(b + 1)("changed_at")) Then
                Dim tmp As Object: Set tmp = arr(b): Set arr(b) = arr(b + 1): Set arr(b + 1) = tmp
            End If
        Next b
    Next a
    For i = 1 To n: result.Add arr(i): Next i
    Set PatientsDropped = result
End Function

' ── SDAT Improvement ────────────────────────────────────────────────────────
Public Function SdatImprovement(fromIso As String, toIso As String) As Collection
    Dim result As New Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cLast As Long: cLast = modUtils.ColIndex(ws, "last_name")
    Dim cFirst As Long: cFirst = modUtils.ColIndex(ws, "first_name")
    Dim cBeginScore As Long: cBeginScore = modUtils.ColIndex(ws, "sdat_begin_score")
    Dim cBeginDate As Long: cBeginDate = modUtils.ColIndex(ws, "sdat_begin_date")
    Dim cEndScore As Long: cEndScore = modUtils.ColIndex(ws, "sdat_end_score")
    Dim cEndDate As Long: cEndDate = modUtils.ColIndex(ws, "sdat_end_date")
    Dim cPct As Long: cPct = modUtils.ColIndex(ws, "sdat_pct_improvement")

    Dim i As Long
    For i = 2 To last
        Dim beginScoreV As Variant: beginScoreV = ws.Cells(i, cBeginScore).Value
        Dim endScoreV As Variant: endScoreV = ws.Cells(i, cEndScore).Value
        If Trim(beginScoreV & "") <> "" And Trim(endScoreV & "") <> "" Then
            Dim endDate As String: endDate = CStr(ws.Cells(i, cEndDate).Value)
            If endDate >= fromIso And endDate <= toIso Then
                Dim dd As Object: Set dd = CreateObject("Scripting.Dictionary")
                dd("patient_name") = CStr(ws.Cells(i, cFirst).Value) & " " & CStr(ws.Cells(i, cLast).Value)
                dd("begin_score") = beginScoreV
                dd("begin_date") = ws.Cells(i, cBeginDate).Value
                dd("end_score") = endScoreV
                dd("end_date") = endDate
                dd("pct_improvement") = ws.Cells(i, cPct).Value
                result.Add dd
            End If
        End If
    Next i

    Set SdatImprovement = result
End Function

' Overall total row: NOT the average of per-row percentages -- recomputed
' from summed scores, matching reports.js/Reports.jsx's total-row formula:
' A=Sum(begin), B=Sum(end), overall = A<>0 ? round((A-B)/A*1000)/10 : 0.
Public Function SdatOverallImprovement(rows As Collection) As Double
    Dim sumBegin As Double: sumBegin = 0
    Dim sumEnd As Double: sumEnd = 0
    Dim d As Object
    For Each d In rows
        sumBegin = sumBegin + CDbl(d("begin_score"))
        sumEnd = sumEnd + CDbl(d("end_score"))
    Next d
    If sumBegin = 0 Then
        SdatOverallImprovement = 0
    Else
        SdatOverallImprovement = modUtils.RoundHalfUp((sumBegin - sumEnd) * 1000 / sumBegin, 0) / 10
    End If
End Function

' ── Week-label chart aggregation ────────────────────────────────────────────
' Literal per-date label, NOT real ISO-week bucketing -- this replicates
' Electron's Reports.jsx chart grouping exactly (format(parseISO(date),
' "'Wk of' MMM d")), which despite its name labels every *exact* date
' individually rather than normalizing to a real calendar-week start. Do NOT
' "fix" this into true week-grouping; that would break parity.
Private Function WeekLabel(isoDate As String) As String
    If Len(isoDate) <> 10 Then
        WeekLabel = "Wk of " & isoDate
        Exit Function
    End If
    Dim y As Long, m As Long, dNum As Long
    y = CLng(Left(isoDate, 4)): m = CLng(Mid(isoDate, 6, 2)): dNum = CLng(Mid(isoDate, 9, 2))
    WeekLabel = "Wk of " & Format(DateSerial(y, m, dNum), "mmm d")
End Function

' Builds a (label, count) aggregation, in first-seen order, from a Collection
' of dictionaries keyed by dateField.
Private Function GroupByWeekLabel(rows As Collection, dateField As String) As Collection
    Dim labels As New Collection
    Dim counts As Object: Set counts = CreateObject("Scripting.Dictionary")
    Dim d As Object
    For Each d In rows
        Dim lbl As String: lbl = WeekLabel(CStr(d(dateField)))
        If Not counts.Exists(lbl) Then
            counts(lbl) = 0
            labels.Add lbl
        End If
        counts(lbl) = counts(lbl) + 1
    Next d

    Dim result As New Collection
    Dim lblv As Variant
    For Each lblv In labels
        Dim dd As Object: Set dd = CreateObject("Scripting.Dictionary")
        dd("label") = lblv
        dd("count") = counts(CStr(lblv))
        result.Add dd
    Next lblv
    Set GroupByWeekLabel = result
End Function

Private Sub WriteWeekHelper(ws As Worksheet, topLeftCell As String, weekRows As Collection)
    Dim topRow As Long: topRow = ws.Range(topLeftCell).Row
    Dim topCol As Long: topCol = ws.Range(topLeftCell).Column
    ws.Range(ws.Cells(topRow + 1, topCol), ws.Cells(topRow + 200, topCol + 1)).ClearContents
    Dim r As Long: r = topRow + 1
    Dim d As Object
    For Each d In weekRows
        ws.Cells(r, topCol).Value = d("label")
        ws.Cells(r, topCol + 1).Value = d("count")
        r = r + 1
    Next d
End Sub

' ── Reports sheet UI ────────────────────────────────────────────────────────
' One shared range for all 4 reports now (was 4 independent per-section
' ranges) -- mirrors the Electron app's reports redesign. Default matches
' Electron's defaultRange(): the current calendar month, start to end (NOT
' "start of month to today" as this used to be).
Public Sub SetDefaultDateRangeIfBlank()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim firstOfMonth As String: firstOfMonth = Format(DateSerial(Year(Date), Month(Date), 1), "yyyy-mm-dd")
    Dim lastOfMonth As String: lastOfMonth = Format(DateSerial(Year(Date), Month(Date) + 1, 0), "yyyy-mm-dd")
    If Trim(ws.Range("M1").Value & "") = "" Then ws.Range("M1").Value = firstOfMonth
    If Trim(ws.Range("O1").Value & "") = "" Then ws.Range("O1").Value = lastOfMonth
End Sub

' Plain-range table write (NOT a ListObject -- see _build_reports_sheet's
' docstring for why: 4 stacked ListObjects on one sheet hit a real Excel
' row-insert restriction). Clears a fixed buffer below the header, then
' writes rows starting at topRow+1.
Private Sub WriteTableRows(ws As Worksheet, topLeftCell As String, numCols As Long, rows As Collection, fieldNames() As String)
    Dim topRow As Long: topRow = ws.Range(topLeftCell).Row
    Dim topCol As Long: topCol = ws.Range(topLeftCell).Column
    ws.Range(ws.Cells(topRow + 1, topCol), ws.Cells(topRow + 500, topCol + numCols - 1)).ClearContents
    If rows.Count = 0 Then Exit Sub
    Dim r As Long: r = topRow + 1
    Dim d As Object
    For Each d In rows
        Dim c As Long
        For c = 0 To UBound(fieldNames)
            ws.Cells(r, topCol + c).Value = d(fieldNames(c))
        Next c
        r = r + 1
    Next d
End Sub

' Scans down from a header row to find the last filled row (Trim(...) <> "")
' in the given column, so a later Export click (a separate macro invocation
' with no memory of the last Run's row count) can find the current extent.
Private Function LastFilledRowFrom(ws As Worksheet, headerRow As Long, col As Long) As Long
    Dim r As Long: r = headerRow
    Do While Trim(ws.Cells(r + 1, col).Value & "") <> ""
        r = r + 1
    Loop
    LastFilledRowFrom = r
End Function

Public Sub UI_RunReferralsBySource()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim rows As Collection: Set rows = ReferralsBySource(CStr(ws.Range("M1").Value), CStr(ws.Range("O1").Value))
    Dim fields(2) As String: fields(0) = "source": fields(1) = "count": fields(2) = "percent"
    WriteTableRows ws, "A4", 3, rows, fields

    Dim co As ChartObject: Set co = ws.ChartObjects("chtReferralsBySource")
    If rows.Count = 0 Then
        co.Visible = False
        ws.Range("E5").Value = "No results found for this date range."
    Else
        ws.Range("E5").Value = ""
        co.Chart.SetSourceData ws.Range("A4:C" & (4 + rows.Count))
        co.Visible = True
    End If
End Sub

Public Sub UI_RunFirstAppointments()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim rows As Collection: Set rows = FirstAppointments(CStr(ws.Range("M1").Value), CStr(ws.Range("O1").Value))
    Dim fields(2) As String: fields(0) = "patient_name": fields(1) = "first_appt_date": fields(2) = "consultant_name"
    WriteTableRows ws, "A20", 3, rows, fields

    Dim weekRows As Collection: Set weekRows = GroupByWeekLabel(rows, "first_appt_date")
    WriteWeekHelper ws, "J20", weekRows

    Dim co As ChartObject: Set co = ws.ChartObjects("chtFirstAppointments")
    If rows.Count = 0 Then
        co.Visible = False
        ws.Range("E21").Value = "No results found for this date range."
    Else
        ws.Range("E21").Value = ""
        co.Chart.SetSourceData ws.Range("J20:K" & (20 + weekRows.Count))
        co.Visible = True
    End If
End Sub

Public Sub UI_RunPatientsDropped()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim rows As Collection: Set rows = PatientsDropped(CStr(ws.Range("M1").Value), CStr(ws.Range("O1").Value))
    Dim fields(2) As String: fields(0) = "patient_name": fields(1) = "dropped_date": fields(2) = "changed_by_name"
    WriteTableRows ws, "A40", 3, rows, fields

    Dim weekRows As Collection: Set weekRows = GroupByWeekLabel(rows, "dropped_date")
    WriteWeekHelper ws, "J40", weekRows

    Dim co As ChartObject: Set co = ws.ChartObjects("chtPatientsDropped")
    If rows.Count = 0 Then
        co.Visible = False
        ws.Range("E41").Value = "No results found for this date range."
    Else
        ws.Range("E41").Value = ""
        co.Chart.SetSourceData ws.Range("J40:K" & (40 + weekRows.Count))
        co.Visible = True
    End If
End Sub

Public Sub UI_RunSdatImprovement()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim rows As Collection: Set rows = SdatImprovement(CStr(ws.Range("M1").Value), CStr(ws.Range("O1").Value))
    Dim fields(5) As String
    fields(0) = "patient_name": fields(1) = "begin_score": fields(2) = "begin_date"
    fields(3) = "end_score": fields(4) = "end_date": fields(5) = "pct_improvement"
    WriteTableRows ws, "A60", 6, rows, fields

    If rows.Count = 0 Then
        ws.Range("B79").Value = "No results found for this date range."
    Else
        ws.Range("B79").Value = Format(SdatOverallImprovement(rows), "0.0") & "%"
    End If
End Sub

' Matches the Electron app's reports redesign: one selector, one shared date
' range, one Run button. Running a single report clears the other three
' sections' results (mirrors the Electron page only ever showing cards for
' the report(s) actually run) instead of leaving stale data on screen.
Public Sub UI_RunSelectedReport()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim selected As String: selected = CStr(ws.Range("H1").Value)

    If selected = "All Reports" Or selected = "Referrals by Source" Then
        UI_RunReferralsBySource
    Else
        ClearReferralsBySource
    End If

    If selected = "All Reports" Or selected = "First Appointments" Then
        UI_RunFirstAppointments
    Else
        ClearFirstAppointments
    End If

    If selected = "All Reports" Or selected = "Patients Dropped" Then
        UI_RunPatientsDropped
    Else
        ClearPatientsDropped
    End If

    If selected = "All Reports" Or selected = "SDAT Improvement" Then
        UI_RunSdatImprovement
    Else
        ClearSdatImprovement
    End If
End Sub

Private Sub ClearReferralsBySource()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim fields(2) As String: fields(0) = "source": fields(1) = "count": fields(2) = "percent"
    WriteTableRows ws, "A4", 3, New Collection, fields
    ws.ChartObjects("chtReferralsBySource").Visible = False
    ws.Range("E5").Value = "Run the report to see results."
End Sub

Private Sub ClearFirstAppointments()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim fields(2) As String: fields(0) = "patient_name": fields(1) = "first_appt_date": fields(2) = "consultant_name"
    WriteTableRows ws, "A20", 3, New Collection, fields
    WriteWeekHelper ws, "J20", New Collection
    ws.ChartObjects("chtFirstAppointments").Visible = False
    ws.Range("E21").Value = "Run the report to see results."
End Sub

Private Sub ClearPatientsDropped()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim fields(2) As String: fields(0) = "patient_name": fields(1) = "dropped_date": fields(2) = "changed_by_name"
    WriteTableRows ws, "A40", 3, New Collection, fields
    WriteWeekHelper ws, "J40", New Collection
    ws.ChartObjects("chtPatientsDropped").Visible = False
    ws.Range("E41").Value = "Run the report to see results."
End Sub

Private Sub ClearSdatImprovement()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim fields(5) As String
    fields(0) = "patient_name": fields(1) = "begin_score": fields(2) = "begin_date"
    fields(3) = "end_score": fields(4) = "end_date": fields(5) = "pct_improvement"
    WriteTableRows ws, "A60", 6, New Collection, fields
    ws.Range("B79").Value = ""
End Sub

Public Sub UI_ExportReferralsBySource()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim lastRow As Long: lastRow = LastFilledRowFrom(ws, 4, 1)
    If lastRow = 4 Then MsgBox "No data to export -- run the report first.", vbExclamation: Exit Sub
    modExport.ExportRangeToXlsx ws.Range("A4:C" & lastRow), "ReferralsBySource.xlsx"
End Sub

Public Sub UI_ExportFirstAppointments()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim lastRow As Long: lastRow = LastFilledRowFrom(ws, 20, 1)
    If lastRow = 20 Then MsgBox "No data to export -- run the report first.", vbExclamation: Exit Sub
    modExport.ExportRangeToXlsx ws.Range("A20:C" & lastRow), "FirstAppointments.xlsx"
End Sub

Public Sub UI_ExportPatientsDropped()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim lastRow As Long: lastRow = LastFilledRowFrom(ws, 40, 1)
    If lastRow = 40 Then MsgBox "No data to export -- run the report first.", vbExclamation: Exit Sub
    modExport.ExportRangeToXlsx ws.Range("A40:C" & lastRow), "PatientsDropped.xlsx"
End Sub

Public Sub UI_ExportSdatImprovement()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    Dim lastRow As Long: lastRow = LastFilledRowFrom(ws, 60, 1)
    If lastRow = 60 Then MsgBox "No data to export -- run the report first.", vbExclamation: Exit Sub
    modExport.ExportRangeToXlsx ws.Range("A60:F" & lastRow), "SdatImprovement.xlsx"
End Sub

' Shows CalendarPickerForm pre-filled with a report's From/To cell and writes
' the picked date back into that same cell. The Reports sheet is re-protected
' with UserInterfaceOnly:=True on every open (see ThisWorkbook.Workbook_Open),
' so writing to these cells from VBA doesn't need an unprotect/reprotect dance.
Private Sub PickDateIntoCell(addr As String)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Reports")
    CalendarPickerForm.InitialDate = Trim(CStr(ws.Range(addr).Value))
    CalendarPickerForm.SelectedDate = ""
    CalendarPickerForm.Show
    If CalendarPickerForm.SelectedDate <> "" Then
        ws.Range(addr).Value = CalendarPickerForm.SelectedDate
    End If
    Unload CalendarPickerForm
End Sub

Public Sub UI_PickSharedFromDate()
    PickDateIntoCell "M1"
End Sub

Public Sub UI_PickSharedToDate()
    PickDateIntoCell "O1"
End Sub
