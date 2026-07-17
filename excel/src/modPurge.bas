Attribute VB_Name = "modPurge"
Option Explicit

' Session state for the currently-pending purge confirmation -- lets
' PurgeConfirmForm.btnConfirm_Click read the computed stale-ID list without
' needing a new public property on the already-built form (same pattern
' modAuth uses for its session globals).
Public gPendingStaleIds As Collection

' ── Frequency label mapping ────────────────────────────────────────────────
Public Function FrequencyInternal(displayLabel As String) As String
    Select Case displayLabel
        Case "Monthly": FrequencyInternal = "monthly"
        Case "Quarterly": FrequencyInternal = "quarterly"
        Case "Every 6 Months": FrequencyInternal = "biannual"
        Case "Yearly": FrequencyInternal = "yearly"
        Case Else: FrequencyInternal = "quarterly"
    End Select
End Function

Public Function FrequencyLabel(internalValue As String) As String
    Select Case internalValue
        Case "monthly": FrequencyLabel = "Monthly"
        Case "quarterly": FrequencyLabel = "Quarterly"
        Case "biannual": FrequencyLabel = "Every 6 Months"
        Case "yearly": FrequencyLabel = "Yearly"
        Case Else: FrequencyLabel = "Quarterly"
    End Select
End Function

' ── Detection ───────────────────────────────────────────────────────────────
Public Function CheckPurgeDue() As Boolean
    Dim lastPurge As String: lastPurge = modUtils.GetSetting("last_purge_date")
    If lastPurge = "" Then
        CheckPurgeDue = True
        Exit Function
    End If

    Dim frequency As String: frequency = modUtils.GetSetting("purge_frequency")
    Dim months As Long
    Select Case frequency
        Case "monthly": months = 1
        Case "quarterly": months = 3
        Case "biannual": months = 6
        Case "yearly": months = 12
        Case Else: months = 3
    End Select

    Dim y As Long, m As Long, d As Long
    y = CLng(Left(lastPurge, 4)): m = CLng(Mid(lastPurge, 6, 2)): d = CLng(Mid(lastPurge, 9, 2))
    Dim dueDate As Date: dueDate = DateAdd("m", months, DateSerial(y, m, d))
    CheckPurgeDue = (Date >= dueDate)
End Function

' Last activity = latest of (latest appointment date, latest status-history
' changed_at). Scans ALL patients regardless of current_status (including
' already-deleted) since retention purge is an independent policy, not scoped
' to the delete workflow.
Public Function FindStalePatientIds() As Collection
    Dim result As New Collection
    Dim retentionMonths As Long: retentionMonths = CLng(modUtils.GetSetting("retention_months"))
    Dim cutoffIso As String: cutoffIso = modUtils.DateISO(DateAdd("m", -retentionMonths, Date))

    Dim patientsWs As Worksheet: Set patientsWs = modUtils.DataSheet("_data_patients")
    Dim last As Long: last = modUtils.LastDataRow(patientsWs)
    Dim cId As Long: cId = modUtils.ColIndex(patientsWs, "id")
    Dim cCreated As Long: cCreated = modUtils.ColIndex(patientsWs, "created_at")
    Dim cReferral As Long: cReferral = modUtils.ColIndex(patientsWs, "date_of_referral")

    Dim i As Long
    For i = 2 To last
        Dim pid As Long: pid = CLng(patientsWs.Cells(i, cId).Value)
        Dim lastActivity As String: lastActivity = LastActivityDate(pid)
        If lastActivity = "" Then
            ' Fallback for a patient with neither appointments nor status
            ' history (shouldn't normally happen -- Save always writes an
            ' initial history row -- but guards legacy/imported data).
            lastActivity = Left(CStr(patientsWs.Cells(i, cCreated).Value), 10)
            If lastActivity = "" Then lastActivity = CStr(patientsWs.Cells(i, cReferral).Value)
        End If
        If lastActivity <> "" And lastActivity < cutoffIso Then
            result.Add pid
        End If
    Next i
    Set FindStalePatientIds = result
End Function

Private Function LastActivityDate(patientId As Long) As String
    Dim best As String: best = ""

    Dim apptWs As Worksheet: Set apptWs = modUtils.DataSheet("_data_appointments")
    Dim last As Long: last = modUtils.LastDataRow(apptWs)
    Dim cPid As Long: cPid = modUtils.ColIndex(apptWs, "patient_id")
    Dim cApptDate As Long: cApptDate = modUtils.ColIndex(apptWs, "date")
    Dim i As Long
    For i = 2 To last
        If CLng(apptWs.Cells(i, cPid).Value) = patientId Then
            Dim d As String: d = CStr(apptWs.Cells(i, cApptDate).Value)
            If d > best Then best = d
        End If
    Next i

    Dim histWs As Worksheet: Set histWs = modUtils.DataSheet("_data_status_history")
    last = modUtils.LastDataRow(histWs)
    Dim cHPid As Long: cHPid = modUtils.ColIndex(histWs, "patient_id")
    Dim cChangedAt As Long: cChangedAt = modUtils.ColIndex(histWs, "changed_at")
    For i = 2 To last
        If CLng(histWs.Cells(i, cHPid).Value) = patientId Then
            Dim ca As String: ca = Left(CStr(histWs.Cells(i, cChangedAt).Value), 10)
            If ca > best Then best = ca
        End If
    Next i

    LastActivityDate = best
End Function

' ── Archive + hard delete ───────────────────────────────────────────────────
Public Sub ArchiveAndPurge(staleIds As Collection, archivePath As String)
    If staleIds Is Nothing Then Exit Sub
    If staleIds.Count = 0 Then Exit Sub

    Dim archiveWb As Workbook: Set archiveWb = Application.Workbooks.Add
    Dim pSheet As Worksheet: Set pSheet = archiveWb.Sheets(1)
    pSheet.Name = "patients"
    Dim aSheet As Worksheet: Set aSheet = archiveWb.Sheets.Add(After:=pSheet)
    aSheet.Name = "appointments"
    Dim hSheet As Worksheet: Set hSheet = archiveWb.Sheets.Add(After:=aSheet)
    hSheet.Name = "status_history"

    Dim patientsWs As Worksheet: Set patientsWs = modUtils.DataSheet("_data_patients")
    Dim apptWs As Worksheet: Set apptWs = modUtils.DataSheet("_data_appointments")
    Dim histWs As Worksheet: Set histWs = modUtils.DataSheet("_data_status_history")

    CopyHeaderRow patientsWs, pSheet
    CopyHeaderRow apptWs, aSheet
    CopyHeaderRow histWs, hSheet

    Dim staleSet As Object: Set staleSet = CreateObject("Scripting.Dictionary")
    Dim sid As Variant
    For Each sid In staleIds
        staleSet(CLng(sid)) = True
    Next sid

    ' Archive + hard-delete bottom-to-top so row indices don't shift under us.
    Dim r As Long
    Dim pDestRow As Long: pDestRow = 2
    For r = modUtils.LastDataRow(patientsWs) To 2 Step -1
        If staleSet.Exists(CLng(patientsWs.Cells(r, 1).Value)) Then
            CopyRow patientsWs, r, pSheet, pDestRow
            pDestRow = pDestRow + 1
            modUtils.DeleteRow patientsWs, r
        End If
    Next r

    Dim aDestRow As Long: aDestRow = 2
    Dim cApptPid As Long: cApptPid = modUtils.ColIndex(apptWs, "patient_id")
    For r = modUtils.LastDataRow(apptWs) To 2 Step -1
        If staleSet.Exists(CLng(apptWs.Cells(r, cApptPid).Value)) Then
            CopyRow apptWs, r, aSheet, aDestRow
            aDestRow = aDestRow + 1
            modUtils.DeleteRow apptWs, r
        End If
    Next r

    Dim hDestRow As Long: hDestRow = 2
    Dim cHistPid As Long: cHistPid = modUtils.ColIndex(histWs, "patient_id")
    For r = modUtils.LastDataRow(histWs) To 2 Step -1
        If staleSet.Exists(CLng(histWs.Cells(r, cHistPid).Value)) Then
            CopyRow histWs, r, hSheet, hDestRow
            hDestRow = hDestRow + 1
            modUtils.DeleteRow histWs, r
        End If
    Next r

    archiveWb.SaveAs archivePath, FileFormat:=51 ' xlOpenXMLWorkbook
    archiveWb.Close SaveChanges:=False

    modUtils.SetSetting "last_purge_date", modUtils.DateISO(Date)
    RefreshPurgeConfigDisplay
    modUtils.AutoSave
End Sub

Private Sub CopyHeaderRow(srcWs As Worksheet, destWs As Worksheet)
    Dim lastCol As Long: lastCol = srcWs.Cells(1, srcWs.Columns.Count).End(xlToLeft).Column
    srcWs.Range(srcWs.Cells(1, 1), srcWs.Cells(1, lastCol)).Copy destWs.Cells(1, 1)
End Sub

Private Sub CopyRow(srcWs As Worksheet, srcRow As Long, destWs As Worksheet, destRow As Long)
    Dim lastCol As Long: lastCol = srcWs.Cells(1, srcWs.Columns.Count).End(xlToLeft).Column
    srcWs.Range(srcWs.Cells(srcRow, 1), srcWs.Cells(srcRow, lastCol)).Copy destWs.Cells(destRow, 1)
End Sub

' ── Orchestration / UI ──────────────────────────────────────────────────────
' Called post-login (both LoginForm and AddUserForm's first-run path) when
' the logged-in user is an admin.
Public Sub RunPurgeCheck()
    If Not CheckPurgeDue() Then Exit Sub

    Dim staleIds As Collection: Set staleIds = FindStalePatientIds()
    If staleIds.Count = 0 Then
        ' Nothing stale -- advance last_purge_date anyway so a workbook with
        ' no stale data doesn't do a full patient scan on every single login.
        modUtils.SetSetting "last_purge_date", modUtils.DateISO(Date)
        Exit Sub
    End If

    Set gPendingStaleIds = staleIds
    PurgeConfirmForm.StaleCount = staleIds.Count
    PurgeConfirmForm.DefaultArchivePath = DefaultArchivePath()
    PurgeConfirmForm.Show
End Sub

' Admin sheet's manual "Run Purge Now" button -- skips the due-date gate;
' 0 stale records shows an informational message instead of silently no-op'ing
' (better UX for an explicit manual action).
Public Sub RunPurgeNow()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub

    Dim staleIds As Collection: Set staleIds = FindStalePatientIds()
    If staleIds.Count = 0 Then
        MsgBox "No stale records found -- nothing to purge.", vbInformation
        Exit Sub
    End If

    Set gPendingStaleIds = staleIds
    PurgeConfirmForm.StaleCount = staleIds.Count
    PurgeConfirmForm.DefaultArchivePath = DefaultArchivePath()
    PurgeConfirmForm.Show
End Sub

Private Function DefaultArchivePath() As String
    Dim folder As String: folder = ThisWorkbook.Path
    If folder = "" Then folder = Environ("USERPROFILE")
    DefaultArchivePath = folder & "\AmbulatoryPatients_Archive_" & Format(Date, "yyyy-mm") & ".xlsx"
End Function

Public Sub RefreshPurgeConfigDisplay()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Admin")
    ws.Range("C27").Value = modUtils.GetSetting("last_purge_date")
End Sub
