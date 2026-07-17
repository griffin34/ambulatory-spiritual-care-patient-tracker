Attribute VB_Name = "modPatients"
Option Explicit

' ── Status label mapping (internal snake_case <-> display label) ──────────────
Public Function StatusLabel(internalValue As String) As String
    Select Case LCase(internalValue)
        Case "ready_to_schedule": StatusLabel = "Ready to Schedule"
        Case "scheduled": StatusLabel = "Scheduled"
        Case "completed": StatusLabel = "Completed"
        Case "dropped": StatusLabel = "Dropped"
        Case "on_hold": StatusLabel = "On Hold"
        Case "deleted": StatusLabel = "Deleted"
        Case Else: StatusLabel = internalValue
    End Select
End Function

Public Function StatusInternal(label As String) As String
    Select Case label
        Case "Ready to Schedule": StatusInternal = "ready_to_schedule"
        Case "Scheduled": StatusInternal = "scheduled"
        Case "Completed": StatusInternal = "completed"
        Case "Dropped": StatusInternal = "dropped"
        Case "On Hold": StatusInternal = "on_hold"
        Case "Deleted": StatusInternal = "deleted"
        Case Else: StatusInternal = ""
    End Select
End Function

' All status labels a user may pick from the general Change Status dropdown --
' "deleted" is deliberately excluded, only reachable via the Delete action.
Public Function AllStatusLabelsExceptDeleted() As Collection
    Dim result As New Collection
    result.Add "Ready to Schedule"
    result.Add "Scheduled"
    result.Add "Completed"
    result.Add "Dropped"
    result.Add "On Hold"
    Set AllStatusLabelsExceptDeleted = result
End Function

' ── Reads ───────────────────────────────────────────────────────────────────
Public Function GetPatient(patientId As Long) As Object
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim r As Long: r = modUtils.FindById(ws, patientId)
    Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
    If r = 0 Then
        Set GetPatient = d
        Exit Function
    End If

    d("id") = ws.Cells(r, modUtils.ColIndex(ws, "id")).Value
    d("mrn") = ws.Cells(r, modUtils.ColIndex(ws, "mrn")).Value
    d("last_name") = ws.Cells(r, modUtils.ColIndex(ws, "last_name")).Value
    d("first_name") = ws.Cells(r, modUtils.ColIndex(ws, "first_name")).Value
    d("middle_name") = ws.Cells(r, modUtils.ColIndex(ws, "middle_name")).Value
    d("phone") = ws.Cells(r, modUtils.ColIndex(ws, "phone")).Value
    d("date_of_referral") = ws.Cells(r, modUtils.ColIndex(ws, "date_of_referral")).Value
    d("referral_source_id") = ws.Cells(r, modUtils.ColIndex(ws, "referral_source_id")).Value
    d("religion_id") = ws.Cells(r, modUtils.ColIndex(ws, "religion_id")).Value
    d("language_id") = ws.Cells(r, modUtils.ColIndex(ws, "language_id")).Value
    d("referral_source") = modUtils.LovValueForId(CLng(d("referral_source_id")))
    d("religion") = modUtils.LovValueForId(CLng(d("religion_id")))
    d("language") = modUtils.LovValueForId(CLng(d("language_id")))
    d("current_status") = ws.Cells(r, modUtils.ColIndex(ws, "current_status")).Value
    d("is_active") = ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value
    d("sdat_begin_score") = ws.Cells(r, modUtils.ColIndex(ws, "sdat_begin_score")).Value
    d("sdat_begin_date") = ws.Cells(r, modUtils.ColIndex(ws, "sdat_begin_date")).Value
    d("sdat_end_score") = ws.Cells(r, modUtils.ColIndex(ws, "sdat_end_score")).Value
    d("sdat_end_date") = ws.Cells(r, modUtils.ColIndex(ws, "sdat_end_date")).Value
    d("sdat_pct_improvement") = ws.Cells(r, modUtils.ColIndex(ws, "sdat_pct_improvement")).Value
    d("notes") = ws.Cells(r, modUtils.ColIndex(ws, "notes")).Value
    Set GetPatient = d
End Function

Public Function GetStatusHistory(patientId As Long) As Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_status_history")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cPid As Long: cPid = modUtils.ColIndex(ws, "patient_id")
    Dim cStatus As Long: cStatus = modUtils.ColIndex(ws, "status")
    Dim cChangedBy As Long: cChangedBy = modUtils.ColIndex(ws, "changed_by")
    Dim cChangedAt As Long: cChangedAt = modUtils.ColIndex(ws, "changed_at")

    Dim rows As New Collection
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cPid).Value = patientId Then
            Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
            d("status") = StatusLabel(CStr(ws.Cells(i, cStatus).Value))
            d("changed_by_name") = modAdmin.GetUserName(CLng(ws.Cells(i, cChangedBy).Value))
            d("changed_at") = ws.Cells(i, cChangedAt).Value
            rows.Add d
        End If
    Next i

    Dim result As New Collection
    Dim n As Long: n = rows.Count
    If n = 0 Then
        Set GetStatusHistory = result
        Exit Function
    End If

    ' DESC by changed_at -- ISO timestamps sort correctly as plain strings.
    Dim arr() As Object: ReDim arr(1 To n)
    For i = 1 To n: Set arr(i) = rows(i): Next i
    Dim j As Long
    For i = 1 To n - 1
        For j = 1 To n - i
            If CStr(arr(j)("changed_at")) < CStr(arr(j + 1)("changed_at")) Then
                Dim tmp As Object: Set tmp = arr(j): Set arr(j) = arr(j + 1): Set arr(j + 1) = tmp
            End If
        Next j
    Next i
    For i = 1 To n: result.Add arr(i): Next i
    Set GetStatusHistory = result
End Function

' Mirrors src/main/ipc/patients.js's listPatients filter logic exactly:
' statusFilter="deleted" -> only current_status=deleted rows; a specific status
' -> that status AND is_active=1; "" (All) -> is_active=1 (excludes deleted).
Public Function ListForWorkQueue(statusFilter As String, referralSourceId As Long, searchText As String) As Collection
    Dim result As New Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cId As Long: cId = modUtils.ColIndex(ws, "id")
    Dim cMrn As Long: cMrn = modUtils.ColIndex(ws, "mrn")
    Dim cLast As Long: cLast = modUtils.ColIndex(ws, "last_name")
    Dim cFirst As Long: cFirst = modUtils.ColIndex(ws, "first_name")
    Dim cReferralDate As Long: cReferralDate = modUtils.ColIndex(ws, "date_of_referral")
    Dim cReferralSrc As Long: cReferralSrc = modUtils.ColIndex(ws, "referral_source_id")
    Dim cLanguage As Long: cLanguage = modUtils.ColIndex(ws, "language_id")
    Dim cStatus As Long: cStatus = modUtils.ColIndex(ws, "current_status")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")

    Dim search As String: search = LCase(Trim(searchText))
    Dim i As Long
    For i = 2 To last
        Dim status As String: status = CStr(ws.Cells(i, cStatus).Value)
        Dim isActive As Boolean: isActive = (ws.Cells(i, cActive).Value = 1)
        Dim keep As Boolean: keep = True

        If statusFilter = "deleted" Then
            If status <> "deleted" Then keep = False
        ElseIf statusFilter <> "" Then
            If status <> statusFilter Or Not isActive Then keep = False
        Else
            If Not isActive Then keep = False
        End If

        If keep And referralSourceId > 0 Then
            If ws.Cells(i, cReferralSrc).Value <> referralSourceId Then keep = False
        End If

        If keep And search <> "" Then
            Dim ln As String: ln = LCase(CStr(ws.Cells(i, cLast).Value))
            Dim fn As String: fn = LCase(CStr(ws.Cells(i, cFirst).Value))
            Dim mrn As String: mrn = LCase(CStr(ws.Cells(i, cMrn).Value))
            If InStr(ln, search) = 0 And InStr(fn, search) = 0 And InStr(mrn, search) = 0 Then
                keep = False
            End If
        End If

        If keep Then
            Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
            Dim pid As Long: pid = CLng(ws.Cells(i, cId).Value)
            d("id") = pid
            d("last_name") = ws.Cells(i, cLast).Value
            d("first_name") = ws.Cells(i, cFirst).Value
            d("mrn") = ws.Cells(i, cMrn).Value
            d("date_of_referral") = ws.Cells(i, cReferralDate).Value
            d("referral_source") = modUtils.LovValueForId(CLng(ws.Cells(i, cReferralSrc).Value))
            d("language") = modUtils.LovValueForId(CLng(ws.Cells(i, cLanguage).Value))
            d("status_label") = StatusLabel(status)
            d("next_appointment") = NextScheduledAppointmentText(pid)
            result.Add d
        End If
    Next i

    Set ListForWorkQueue = result
End Function

Private Function NextScheduledAppointmentText(patientId As Long) As String
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_appointments")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cPid As Long: cPid = modUtils.ColIndex(ws, "patient_id")
    Dim cApptDate As Long: cApptDate = modUtils.ColIndex(ws, "date")
    Dim cTime As Long: cTime = modUtils.ColIndex(ws, "time")
    Dim cStatus As Long: cStatus = modUtils.ColIndex(ws, "status")
    Dim today As String: today = modUtils.DateISO(Date)

    Dim bestDate As String: bestDate = ""
    Dim bestTime As String: bestTime = ""
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cPid).Value = patientId And CStr(ws.Cells(i, cStatus).Value) = "scheduled" Then
            Dim d As String: d = CStr(ws.Cells(i, cApptDate).Value)
            If d >= today Then
                If bestDate = "" Or d < bestDate Then
                    bestDate = d
                    bestTime = CStr(ws.Cells(i, cTime).Value)
                End If
            End If
        End If
    Next i

    If bestDate = "" Then
        NextScheduledAppointmentText = ""
    Else
        NextScheduledAppointmentText = bestDate & " " & bestTime
    End If
End Function

Public Function CountsByStatus() As Object
    Dim counts As Object: Set counts = CreateObject("Scripting.Dictionary")
    Dim statuses As Variant: statuses = Array("ready_to_schedule", "scheduled", "completed", "dropped", "on_hold")
    Dim s As Variant
    For Each s In statuses
        counts(CStr(s)) = 0
    Next s
    counts("total_active") = 0

    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cStatus As Long: cStatus = modUtils.ColIndex(ws, "current_status")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cActive).Value = 1 Then
            Dim st As String: st = CStr(ws.Cells(i, cStatus).Value)
            If counts.Exists(st) Then counts(st) = counts(st) + 1
            counts("total_active") = counts("total_active") + 1
        End If
    Next i
    Set CountsByStatus = counts
End Function

' ── Writes ──────────────────────────────────────────────────────────────────
Public Sub Save(patientId As Long, mrn As String, lastName As String, firstName As String, _
                 middleName As String, phone As String, referralDate As String, _
                 referralSourceId As Long, religionId As Long, languageId As Long)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim r As Long
    Dim newId As Long

    If patientId = 0 Then
        r = modUtils.LastDataRow(ws) + 1
        newId = modUtils.NextId(ws)
        ws.Cells(r, modUtils.ColIndex(ws, "id")).Value = newId
        ws.Cells(r, modUtils.ColIndex(ws, "current_status")).Value = "ready_to_schedule"
        ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = 1
        ws.Cells(r, modUtils.ColIndex(ws, "created_at")).Value = modUtils.NowISO()
    Else
        r = modUtils.FindById(ws, patientId)
        If r = 0 Then Exit Sub
        newId = patientId
    End If

    ws.Cells(r, modUtils.ColIndex(ws, "mrn")).Value = mrn
    ws.Cells(r, modUtils.ColIndex(ws, "last_name")).Value = lastName
    ws.Cells(r, modUtils.ColIndex(ws, "first_name")).Value = firstName
    ws.Cells(r, modUtils.ColIndex(ws, "middle_name")).Value = middleName
    ws.Cells(r, modUtils.ColIndex(ws, "phone")).Value = phone
    ws.Cells(r, modUtils.ColIndex(ws, "date_of_referral")).Value = referralDate
    ws.Cells(r, modUtils.ColIndex(ws, "referral_source_id")).Value = referralSourceId
    ws.Cells(r, modUtils.ColIndex(ws, "religion_id")).Value = religionId
    ws.Cells(r, modUtils.ColIndex(ws, "language_id")).Value = languageId

    If patientId = 0 Then
        AppendStatusHistory newId, "ready_to_schedule"
    End If
    modUtils.AutoSave
End Sub

Private Sub AppendStatusHistory(patientId As Long, status As String)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_status_history")
    Dim r As Long: r = modUtils.LastDataRow(ws) + 1
    ws.Cells(r, 1).Value = modUtils.NextId(ws)
    ws.Cells(r, modUtils.ColIndex(ws, "patient_id")).Value = patientId
    ws.Cells(r, modUtils.ColIndex(ws, "status")).Value = status
    ws.Cells(r, modUtils.ColIndex(ws, "changed_by")).Value = modAuth.gUserId
    ws.Cells(r, modUtils.ColIndex(ws, "changed_at")).Value = modUtils.NowISO()
End Sub

Public Sub ChangeStatus(patientId As Long, newStatus As String)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim r As Long: r = modUtils.FindById(ws, patientId)
    If r = 0 Then Exit Sub
    ws.Cells(r, modUtils.ColIndex(ws, "current_status")).Value = newStatus
    If newStatus = "deleted" Then
        ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = 0
    End If
    AppendStatusHistory patientId, newStatus
    modUtils.AutoSave
End Sub

Public Sub Delete(patientId As Long)
    ChangeStatus patientId, "deleted"
End Sub

Public Sub Restore(patientId As Long)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim r As Long: r = modUtils.FindById(ws, patientId)
    If r = 0 Then Exit Sub
    ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = 1
    ChangeStatus patientId, "on_hold"
End Sub

' Mirrors patients.js's computeSdatPct exactly: null if either score is missing
' or beginScore=0; else Math.round((begin-end)*1000/begin)/10.
Public Sub SaveSdat(patientId As Long, beginScore As Variant, beginDate As String, _
                     endScore As Variant, endDate As String)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim r As Long: r = modUtils.FindById(ws, patientId)
    If r = 0 Then Exit Sub
    ws.Cells(r, modUtils.ColIndex(ws, "sdat_begin_score")).Value = beginScore
    ws.Cells(r, modUtils.ColIndex(ws, "sdat_begin_date")).Value = beginDate
    ws.Cells(r, modUtils.ColIndex(ws, "sdat_end_score")).Value = endScore
    ws.Cells(r, modUtils.ColIndex(ws, "sdat_end_date")).Value = endDate
    ws.Cells(r, modUtils.ColIndex(ws, "sdat_pct_improvement")).Value = ComputeSdatPct(beginScore, endScore)
    modUtils.AutoSave
End Sub

Private Function ComputeSdatPct(beginScore As Variant, endScore As Variant) As Variant
    If Trim(beginScore & "") = "" Or Trim(endScore & "") = "" Then
        ComputeSdatPct = Null
        Exit Function
    End If
    Dim b As Double: b = CDbl(beginScore)
    Dim e As Double: e = CDbl(endScore)
    If b = 0 Then
        ComputeSdatPct = Null
        Exit Function
    End If
    ComputeSdatPct = modUtils.RoundHalfUp((b - e) * 1000 / b, 0) / 10
End Function

Public Sub SaveNotes(patientId As Long, notes As String)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_patients")
    Dim r As Long: r = modUtils.FindById(ws, patientId)
    If r = 0 Then Exit Sub
    If Len(notes) > 256 Then notes = Left(notes, 256)
    ws.Cells(r, modUtils.ColIndex(ws, "notes")).Value = notes
    modUtils.AutoSave
End Sub

' ── WorkQueue sheet UI entry points ────────────────────────────────────────
Public Sub UI_OpenAddPatient()
    AddEditPatientForm.PatientId = 0
    AddEditPatientForm.Show
    RefreshWorkQueue
End Sub

Public Sub UI_ViewSelectedPatient()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("WorkQueue")
    Dim tbl As ListObject: Set tbl = ws.ListObjects("tblWorkQueue")
    If tbl.DataBodyRange Is Nothing Then
        MsgBox "No patients to view.", vbExclamation
        Exit Sub
    End If
    If Intersect(Application.ActiveCell, tbl.DataBodyRange) Is Nothing Then
        MsgBox "Select a patient row first.", vbExclamation
        Exit Sub
    End If
    Dim rowOffset As Long: rowOffset = Application.ActiveCell.Row - tbl.DataBodyRange.Row + 1
    Dim pid As Long: pid = tbl.DataBodyRange(rowOffset, 1).Value
    PatientDetailForm.PatientId = pid
    PatientDetailForm.Show
    RefreshWorkQueue
End Sub

Public Sub UI_ExportWorkQueue()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("WorkQueue")
    Dim tbl As ListObject: Set tbl = ws.ListObjects("tblWorkQueue")
    If tbl.DataBodyRange Is Nothing Then
        MsgBox "No data to export.", vbExclamation
        Exit Sub
    End If
    Dim lastRow As Long: lastRow = 4 + tbl.ListRows.Count
    modExport.ExportRangeToXlsx ws.Range(ws.Cells(4, 2), ws.Cells(lastRow, 9)), "WorkQueue.xlsx"
End Sub

Public Sub RefreshWorkQueue()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("WorkQueue")

    Application.EnableEvents = False

    ws.Range("P2:P50").ClearContents
    Dim sources As Collection: Set sources = modUtils.ActiveLovValues("referral_source")
    Dim i As Long
    For i = 1 To sources.Count
        ws.Cells(1 + i, 16).Value = sources(i) ' column P = 16
    Next i

    Dim statusLabel As String: statusLabel = CStr(ws.Range("C1").Value)
    Dim statusFilter As String
    If statusLabel = "" Or statusLabel = "All" Then
        statusFilter = ""
    Else
        statusFilter = StatusInternal(statusLabel)
    End If

    Dim srcLabel As String: srcLabel = CStr(ws.Range("E1").Value)
    Dim referralSourceId As Long
    If srcLabel = "" Or srcLabel = "All" Then
        referralSourceId = 0
    Else
        referralSourceId = modUtils.LovIdForValue("referral_source", srcLabel)
    End If

    Dim searchText As String: searchText = CStr(ws.Range("G1").Value)
    Dim results As Collection: Set results = ListForWorkQueue(statusFilter, referralSourceId, searchText)

    Dim tbl As ListObject: Set tbl = ws.ListObjects("tblWorkQueue")
    modUtils.UnprotectForRefresh ws
    If Not tbl.DataBodyRange Is Nothing Then
        tbl.DataBodyRange.Delete
    End If

    If results.Count > 0 Then
        Dim r As Long: r = 1
        Dim d As Object
        For Each d In results
            tbl.ListRows.Add
            tbl.DataBodyRange(r, 1).Value = d("id")
            tbl.DataBodyRange(r, 2).Value = d("last_name")
            tbl.DataBodyRange(r, 3).Value = d("first_name")
            tbl.DataBodyRange(r, 4).Value = d("mrn")
            tbl.DataBodyRange(r, 5).Value = d("date_of_referral")
            tbl.DataBodyRange(r, 6).Value = d("referral_source")
            tbl.DataBodyRange(r, 7).Value = d("language")
            tbl.DataBodyRange(r, 8).Value = d("next_appointment")
            tbl.DataBodyRange(r, 9).Value = d("status_label")
            r = r + 1
        Next d
    End If
    modUtils.ReprotectAfterRefresh ws

    Dim counts As Object: Set counts = CountsByStatus()
    ws.Range("B2").Value = "Total Active: " & counts("total_active") & _
        "   Ready to Schedule: " & counts("ready_to_schedule") & _
        "   Scheduled: " & counts("scheduled") & _
        "   Completed: " & counts("completed") & _
        "   Dropped: " & counts("dropped") & _
        "   On Hold: " & counts("on_hold")

    Application.EnableEvents = True
End Sub
