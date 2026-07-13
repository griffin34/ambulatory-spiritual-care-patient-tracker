Attribute VB_Name = "modAppointments"
Option Explicit

' ── Reads ───────────────────────────────────────────────────────────────────
Public Function GetAppointment(appointmentId As Long) As Object
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_appointments")
    Dim r As Long: r = modUtils.FindById(ws, appointmentId)
    Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
    If r = 0 Then
        Set GetAppointment = d
        Exit Function
    End If

    d("id") = ws.Cells(r, modUtils.ColIndex(ws, "id")).Value
    d("patient_id") = ws.Cells(r, modUtils.ColIndex(ws, "patient_id")).Value
    d("date") = ws.Cells(r, modUtils.ColIndex(ws, "date")).Value
    d("time") = ws.Cells(r, modUtils.ColIndex(ws, "time")).Value
    d("type_id") = ws.Cells(r, modUtils.ColIndex(ws, "type_id")).Value
    d("consultant_id") = ws.Cells(r, modUtils.ColIndex(ws, "consultant_id")).Value
    d("type") = modUtils.LovValueForId(CLng(d("type_id")))
    d("consultant_name") = ConsultantNameForId(CLng(d("consultant_id")))
    d("is_last_appointment") = ws.Cells(r, modUtils.ColIndex(ws, "is_last_appointment")).Value
    d("status") = ws.Cells(r, modUtils.ColIndex(ws, "status")).Value
    d("notes") = ws.Cells(r, modUtils.ColIndex(ws, "notes")).Value
    Set GetAppointment = d
End Function

Public Function GetForPatient(patientId As Long) As Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_appointments")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cPid As Long: cPid = modUtils.ColIndex(ws, "patient_id")
    Dim cId As Long: cId = modUtils.ColIndex(ws, "id")
    Dim cApptDate As Long: cApptDate = modUtils.ColIndex(ws, "date")
    Dim cApptTime As Long: cApptTime = modUtils.ColIndex(ws, "time")
    Dim cTypeId As Long: cTypeId = modUtils.ColIndex(ws, "type_id")
    Dim cConsultantId As Long: cConsultantId = modUtils.ColIndex(ws, "consultant_id")
    Dim cIsLast As Long: cIsLast = modUtils.ColIndex(ws, "is_last_appointment")
    Dim cStatus As Long: cStatus = modUtils.ColIndex(ws, "status")
    Dim cNotes As Long: cNotes = modUtils.ColIndex(ws, "notes")

    Dim rows As New Collection
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cPid).Value = patientId Then
            Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
            d("id") = ws.Cells(i, cId).Value
            d("date") = ws.Cells(i, cApptDate).Value
            d("time") = ws.Cells(i, cApptTime).Value
            d("type") = modUtils.LovValueForId(CLng(ws.Cells(i, cTypeId).Value))
            d("consultant_name") = ConsultantNameForId(CLng(ws.Cells(i, cConsultantId).Value))
            d("status") = ws.Cells(i, cStatus).Value
            d("is_last_appointment") = ws.Cells(i, cIsLast).Value
            d("notes") = ws.Cells(i, cNotes).Value
            rows.Add d
        End If
    Next i

    ' DESC by date then time
    Dim result As New Collection
    Dim n As Long: n = rows.Count
    If n = 0 Then
        Set GetForPatient = result
        Exit Function
    End If
    Dim arr() As Object: ReDim arr(1 To n)
    For i = 1 To n: Set arr(i) = rows(i): Next i
    Dim j As Long
    For i = 1 To n - 1
        For j = 1 To n - i
            Dim keyA As String: keyA = CStr(arr(j)("date")) & " " & CStr(arr(j)("time"))
            Dim keyB As String: keyB = CStr(arr(j + 1)("date")) & " " & CStr(arr(j + 1)("time"))
            If keyA < keyB Then
                Dim tmp As Object: Set tmp = arr(j): Set arr(j) = arr(j + 1): Set arr(j + 1) = tmp
            End If
        Next j
    Next i
    For i = 1 To n: result.Add arr(i): Next i
    Set GetForPatient = result
End Function

' All appointments for a given ISO date, joined with patient name/mrn.
Public Function ForDay(dayIso As String) As Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_appointments")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cPid As Long: cPid = modUtils.ColIndex(ws, "patient_id")
    Dim cId As Long: cId = modUtils.ColIndex(ws, "id")
    Dim cApptDate As Long: cApptDate = modUtils.ColIndex(ws, "date")
    Dim cApptTime As Long: cApptTime = modUtils.ColIndex(ws, "time")
    Dim cTypeId As Long: cTypeId = modUtils.ColIndex(ws, "type_id")
    Dim cConsultantId As Long: cConsultantId = modUtils.ColIndex(ws, "consultant_id")
    Dim cIsLast As Long: cIsLast = modUtils.ColIndex(ws, "is_last_appointment")
    Dim cStatus As Long: cStatus = modUtils.ColIndex(ws, "status")
    Dim cNotes As Long: cNotes = modUtils.ColIndex(ws, "notes")

    Dim patientsWs As Worksheet: Set patientsWs = modUtils.DataSheet("_data_patients")
    Dim cPatLast As Long: cPatLast = modUtils.ColIndex(patientsWs, "last_name")
    Dim cPatFirst As Long: cPatFirst = modUtils.ColIndex(patientsWs, "first_name")

    Dim rows As New Collection
    Dim i As Long
    For i = 2 To last
        If CStr(ws.Cells(i, cApptDate).Value) = dayIso Then
            Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
            Dim pid As Long: pid = CLng(ws.Cells(i, cPid).Value)
            Dim pr As Long: pr = modUtils.FindById(patientsWs, pid)
            Dim patName As String
            If pr > 0 Then
                patName = CStr(patientsWs.Cells(pr, cPatFirst).Value) & " " & CStr(patientsWs.Cells(pr, cPatLast).Value)
            Else
                patName = "(unknown)"
            End If

            d("id") = ws.Cells(i, cId).Value
            d("time") = ws.Cells(i, cApptTime).Value
            d("patient_name") = patName
            d("consultant_name") = ConsultantNameForId(CLng(ws.Cells(i, cConsultantId).Value))
            d("type") = modUtils.LovValueForId(CLng(ws.Cells(i, cTypeId).Value))
            d("status") = ws.Cells(i, cStatus).Value
            d("is_last_appointment") = ws.Cells(i, cIsLast).Value
            d("notes") = ws.Cells(i, cNotes).Value
            rows.Add d
        End If
    Next i

    ' ASC by time
    Dim result As New Collection
    Dim n As Long: n = rows.Count
    If n = 0 Then
        Set ForDay = result
        Exit Function
    End If
    Dim arr() As Object: ReDim arr(1 To n)
    For i = 1 To n: Set arr(i) = rows(i): Next i
    Dim j As Long
    For i = 1 To n - 1
        For j = 1 To n - i
            If CStr(arr(j)("time")) > CStr(arr(j + 1)("time")) Then
                Dim tmp As Object: Set tmp = arr(j): Set arr(j) = arr(j + 1): Set arr(j + 1) = tmp
            End If
        Next j
    Next i
    For i = 1 To n: result.Add arr(i): Next i
    Set ForDay = result
End Function

Public Function CountsByStatusForDay(dayIso As String) As Object
    Dim counts As Object: Set counts = CreateObject("Scripting.Dictionary")
    Dim statuses As Variant: statuses = Array("scheduled", "completed", "no_show", "cancelled", "rescheduled")
    Dim s As Variant
    For Each s In statuses
        counts(CStr(s)) = 0
    Next s

    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_appointments")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cApptDate As Long: cApptDate = modUtils.ColIndex(ws, "date")
    Dim cStatus As Long: cStatus = modUtils.ColIndex(ws, "status")
    Dim i As Long
    For i = 2 To last
        If CStr(ws.Cells(i, cApptDate).Value) = dayIso Then
            Dim st As String: st = CStr(ws.Cells(i, cStatus).Value)
            If counts.Exists(st) Then counts(st) = counts(st) + 1
        End If
    Next i
    Set CountsByStatusForDay = counts
End Function

Private Function ConsultantNameForId(consultantId As Long) As String
    If consultantId <= 0 Then Exit Function
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_consultants")
    Dim r As Long: r = modUtils.FindById(ws, consultantId)
    If r = 0 Then Exit Function
    ConsultantNameForId = CStr(ws.Cells(r, modUtils.ColIndex(ws, "name")).Value)
End Function

' Fills a ComboBox with active consultant names.
Public Sub PopulateConsultantCombo(cbo As MSForms.ComboBox)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_consultants")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cName As Long: cName = modUtils.ColIndex(ws, "name")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    cbo.Clear
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cActive).Value = 1 Then
            cbo.AddItem CStr(ws.Cells(i, cName).Value)
        End If
    Next i
End Sub

Public Function ConsultantIdForName(consultantName As String) As Long
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_consultants")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cName As Long: cName = modUtils.ColIndex(ws, "name")
    Dim i As Long
    For i = 2 To last
        If LCase(CStr(ws.Cells(i, cName).Value)) = LCase(consultantName) Then
            ConsultantIdForName = ws.Cells(i, 1).Value
            Exit Function
        End If
    Next i
    ConsultantIdForName = 0
End Function

' ── Writes ──────────────────────────────────────────────────────────────────
Public Sub Save(appointmentId As Long, patientId As Long, apptDate As String, apptTime As String, _
                 typeId As Long, consultantId As Long, isLast As Boolean, status As String, notes As String)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_appointments")
    Dim r As Long

    If appointmentId = 0 Then
        r = modUtils.LastDataRow(ws) + 1
        ws.Cells(r, modUtils.ColIndex(ws, "id")).Value = modUtils.NextId(ws)
        ws.Cells(r, modUtils.ColIndex(ws, "created_at")).Value = modUtils.NowISO()
    Else
        r = modUtils.FindById(ws, appointmentId)
        If r = 0 Then Exit Sub
    End If

    ws.Cells(r, modUtils.ColIndex(ws, "patient_id")).Value = patientId
    ws.Cells(r, modUtils.ColIndex(ws, "date")).Value = apptDate
    ws.Cells(r, modUtils.ColIndex(ws, "time")).Value = apptTime
    ws.Cells(r, modUtils.ColIndex(ws, "type_id")).Value = typeId
    ws.Cells(r, modUtils.ColIndex(ws, "consultant_id")).Value = consultantId
    ws.Cells(r, modUtils.ColIndex(ws, "is_last_appointment")).Value = IIf(isLast, 1, 0)
    ws.Cells(r, modUtils.ColIndex(ws, "status")).Value = status
    ws.Cells(r, modUtils.ColIndex(ws, "notes")).Value = notes
End Sub

' ── Appointments sheet UI entry points ─────────────────────────────────────
' AddEditAppointmentForm has no patient picker of its own -- it's designed to
' be opened from a patient context (PatientDetailForm sets PatientId before
' Show). From the day-view Appointments sheet there's no such context, so
' prompt for an MRN or last name instead of building a full picker UI.
Public Sub UI_OpenAddAppointment()
    Dim query As String
    query = Trim(InputBox("Enter the patient's MRN or last name:", "Add Appointment"))
    If query = "" Then Exit Sub

    Dim pid As Long: pid = FindActivePatientIdByMrnOrLastName(query)
    If pid = 0 Then
        MsgBox "No matching active patient found.", vbExclamation
        Exit Sub
    End If

    AddEditAppointmentForm.PatientId = pid
    AddEditAppointmentForm.AppointmentId = 0
    AddEditAppointmentForm.Show
    RefreshAppointments
End Sub

Private Function FindActivePatientIdByMrnOrLastName(query As String) As Long
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cMrn As Long: cMrn = modUtils.ColIndex(ws, "mrn")
    Dim cLast As Long: cLast = modUtils.ColIndex(ws, "last_name")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim q As String: q = LCase(query)
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cActive).Value = 1 Then
            If LCase(CStr(ws.Cells(i, cMrn).Value)) = q Or LCase(CStr(ws.Cells(i, cLast).Value)) = q Then
                FindActivePatientIdByMrnOrLastName = ws.Cells(i, 1).Value
                Exit Function
            End If
        End If
    Next i
    FindActivePatientIdByMrnOrLastName = 0
End Function

Public Sub UI_ExportDay()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Appointments")
    Dim tbl As ListObject: Set tbl = ws.ListObjects("tblAppointments")
    If tbl.DataBodyRange Is Nothing Then
        MsgBox "No data to export.", vbExclamation
        Exit Sub
    End If
    Dim lastRow As Long: lastRow = 4 + tbl.ListRows.Count
    modExport.ExportRangeToXlsx ws.Range(ws.Cells(4, 2), ws.Cells(lastRow, 8)), "Appointments.xlsx"
End Sub

Public Sub RefreshAppointments()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Appointments")
    Application.EnableEvents = False

    Dim dayIso As String: dayIso = CStr(ws.Range("B1").Value)
    If Trim(dayIso) = "" Then
        dayIso = modUtils.DateISO(Date)
        ws.Range("B1").Value = dayIso
    End If

    Dim results As Collection: Set results = ForDay(dayIso)

    Dim tbl As ListObject: Set tbl = ws.ListObjects("tblAppointments")
    If Not tbl.DataBodyRange Is Nothing Then
        tbl.DataBodyRange.Delete
    End If

    If results.Count > 0 Then
        Dim r As Long: r = 1
        Dim d As Object
        For Each d In results
            tbl.ListRows.Add
            tbl.DataBodyRange(r, 1).Value = d("id")
            tbl.DataBodyRange(r, 2).Value = d("time")
            tbl.DataBodyRange(r, 3).Value = d("patient_name")
            tbl.DataBodyRange(r, 4).Value = d("consultant_name")
            tbl.DataBodyRange(r, 5).Value = d("type")
            tbl.DataBodyRange(r, 6).Value = d("status")
            tbl.DataBodyRange(r, 7).Value = IIf(d("is_last_appointment") = 1, "Yes", "")
            tbl.DataBodyRange(r, 8).Value = d("notes")
            r = r + 1
        Next d
    End If

    Dim counts As Object: Set counts = CountsByStatusForDay(dayIso)
    ws.Range("C2").Value = "Scheduled: " & counts("scheduled") & _
        "   Completed: " & counts("completed") & _
        "   No Show: " & counts("no_show") & _
        "   Cancelled: " & counts("cancelled") & _
        "   Rescheduled: " & counts("rescheduled")

    Application.EnableEvents = True
End Sub

Public Sub UI_PrevDay()
    ShiftSelectedDate -1
End Sub

Public Sub UI_NextDay()
    ShiftSelectedDate 1
End Sub

Public Sub UI_Back14Days()
    ShiftSelectedDate -14
End Sub

Public Sub UI_Today()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Appointments")
    ws.Range("B1").Value = modUtils.DateISO(Date)
    RefreshAppointments
End Sub

Private Sub ShiftSelectedDate(byDays As Long)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Appointments")
    Dim current As String: current = CStr(ws.Range("B1").Value)
    Dim y As Long, m As Long, dd As Long
    y = CLng(Left(current, 4)): m = CLng(Mid(current, 6, 2)): dd = CLng(Mid(current, 9, 2))
    ws.Range("B1").Value = modUtils.DateISO(DateSerial(y, m, dd) + byDays)
    RefreshAppointments
End Sub
