Attribute VB_Name = "modUpgrade"
Option Explicit

' Data sheet names to merge column-by-column when importing from a prior file.
' _data_settings is handled separately by MergeSettings (key/value, not columnar).
Private Function DataSheetNamesForMerge() As Variant
    DataSheetNamesForMerge = Array("_data_users", "_data_patients", "_data_status_history", _
        "_data_appointments", "_data_consultants", "_data_lov", "_data_audit")
End Function

Public Sub UI_UpgradeFromOldWorkbook()
    If modAuth.IsLoggedIn() And Not modAuth.IsAdmin() Then
        MsgBox "Admin access required.", vbExclamation
        Exit Sub
    End If

    Dim path As Variant
    path = Application.GetOpenFilename("Excel Macro-Enabled Workbook (*.xlsm), *.xlsm", , _
        "Select the previous Ambulatory Patients file to import")
    If path = False Then Exit Sub

    If StrComp(CStr(path), ThisWorkbook.FullName, vbTextCompare) = 0 Then
        MsgBox "That's the file that's already open. Choose a different (older) file.", vbExclamation
        Exit Sub
    End If

    Dim report As String
    report = UpgradeFromWorkbookPath(CStr(path))
    MsgBox report, vbInformation, "Import from Previous File"

    ' Coordinators only ever land on a new build's features by way of this
    ' import (each build ships as a new, blank-data file -- see
    ' EXCEL_BUILD_VERSION's comment in build.py), so this is the one place
    ' that plays the role Electron's WhatsNewModal fills after an in-place
    ' update: show what's new once, then remember it's been seen.
    If ShouldShowWhatsNew() Then
        Dim notes As String
        notes = ReleaseNotesForVersion(modUtils.GetSetting("excel_build_version"))
        If notes <> "" Then MsgBox notes, vbInformation, "What's New"
        MarkVersionSeen
    End If
End Sub

' ── "What's New" (mirrors the Electron app's RELEASE_NOTES/WhatsNewModal,
'    version-gated via a stored "last seen" setting instead of app_meta) ──────
' True if the build version recorded in this file (build.py's
' EXCEL_BUILD_VERSION, seeded into _data_settings at build time) differs from
' the version the current user last acknowledged -- including never having
' acknowledged any version yet.
Public Function ShouldShowWhatsNew() As Boolean
    ShouldShowWhatsNew = (modUtils.GetSetting("excel_build_version") <> modUtils.GetSetting("last_seen_build_version"))
End Function

' Records the current build version as seen, so ShouldShowWhatsNew won't
' prompt again until the file itself moves to a newer build.
Public Sub MarkVersionSeen()
    modUtils.SetSetting "last_seen_build_version", modUtils.GetSetting("excel_build_version")
    modUtils.AutoSave
End Sub

' Single source of truth for the in-app "What's New" text, keyed by
' EXCEL_BUILD_VERSION. "" for a version with no authored notes (including any
' version not listed here) -- callers skip showing the dialog in that case.
' Version 1 covers the whole app in one entry, not just its most recent
' changes -- as of this build nothing has shipped to real users yet, so
' there's no prior version for anyone to have actually seen "what's new" from.
Private Function ReleaseNotesForVersion(version As String) As String
    ' Built up across several statements, not one long concatenation -- VBA
    ' caps a single logical statement at 24 line-continuations, and this text
    ' needs more room than that.
    Dim notes As String
    Select Case version
        Case "1"
            notes = "Welcome to the Ambulatory Patient Tracker (Excel edition):" & vbCrLf & vbCrLf
            notes = notes & "- Work Queue: filter, search, and sort patients by status, referral " & _
                "source, or name/MRN, and track them through the full referral-to-" & _
                "appointment workflow." & vbCrLf & vbCrLf
            notes = notes & "- Patient detail: demographics, referral info, status history, SDAT " & _
                "distress tracking with automatic % improvement, and a notes field -- " & _
                "each editable in place." & vbCrLf & vbCrLf
            notes = notes & "- Appointments: a day-by-day schedule with quick navigation, and full " & _
                "add/edit for type, consultant, status, and notes." & vbCrLf & vbCrLf
            notes = notes & "- Reports: Referrals by Source, First Appointments, Patients Dropped, " & _
                "and SDAT Improvement -- each with a date range, a chart, and an " & _
                "exportable data table." & vbCrLf & vbCrLf
            notes = notes & "- Admin: manage user accounts and roles, edit lists of values " & _
                "(referral sources, religions, languages, consultants, appointment " & _
                "types), and configure data retention / purge." & vbCrLf & vbCrLf
            notes = notes & "- Soft delete & restore for patient records deleted in error." & vbCrLf & vbCrLf
            notes = notes & "- Export to Excel from every screen, plus two-way migration with the " & _
                "Electron app (Admin > Export for Import / Import from Electron " & _
                "Export)." & vbCrLf & vbCrLf
            notes = notes & "- Password recovery: set a security question when an account is " & _
                "created so a forgotten password can be reset from the login screen " & _
                "(Forgot password?) without an admin. A one-time recovery code, " & _
                "generated with the first admin account and rotatable later from the " & _
                "Admin sheet, can regain access to any account -- even a deactivated " & _
                "one -- if every admin is ever locked out (Admin locked out? Use " & _
                "recovery code)."
            ReleaseNotesForVersion = notes
    End Select
End Function

' Reads every _data_* sheet out of the workbook at `path` and merges it into
' this workbook by column name, preserving ids. Split out from
' UI_UpgradeFromOldWorkbook so it can be called directly (e.g. via
' Application.Run in a headless test) without going through the file picker,
' which cannot be driven programmatically.
Public Function UpgradeFromWorkbookPath(path As String) As String
    Dim prevEvents As Boolean: prevEvents = Application.EnableEvents
    Dim prevScreen As Boolean: prevScreen = Application.ScreenUpdating
    Dim oldWb As Workbook

    On Error GoTo Fail
    ' Suppress Workbook_Open (and any other auto-run event) on the workbook
    ' we're about to open -- a real built .xlsm fires a blocking first-run/
    ' login prompt otherwise.
    Application.EnableEvents = False
    Application.ScreenUpdating = False

    Set oldWb = Workbooks.Open(path, UpdateLinks:=0, ReadOnly:=True)

    If Not AnyDataSheetPresent(oldWb) Then
        oldWb.Close SaveChanges:=False
        Set oldWb = Nothing
        Application.EnableEvents = prevEvents
        Application.ScreenUpdating = prevScreen
        UpgradeFromWorkbookPath = "That file doesn't look like an Ambulatory Patients workbook -- no data found to import."
        Exit Function
    End If

    Dim report As String
    Dim names As Variant: names = DataSheetNamesForMerge()
    Dim i As Long
    For i = LBound(names) To UBound(names)
        report = report & MergeSheet(oldWb, CStr(names(i))) & vbCrLf
    Next i
    report = report & MergeSettings(oldWb) & vbCrLf

    oldWb.Close SaveChanges:=False
    Set oldWb = Nothing

    Application.EnableEvents = prevEvents
    Application.ScreenUpdating = prevScreen

    modPatients.RefreshWorkQueue
    modAppointments.RefreshAppointments
    modAdmin.RefreshAdmin
    modUtils.AutoSave

    UpgradeFromWorkbookPath = report
    Exit Function

Fail:
    Dim errDesc As String: errDesc = Err.Description
    If Not oldWb Is Nothing Then
        On Error Resume Next
        oldWb.Close SaveChanges:=False
        On Error GoTo 0
    End If
    Application.EnableEvents = prevEvents
    Application.ScreenUpdating = prevScreen
    UpgradeFromWorkbookPath = "Import failed: " & errDesc
End Function

Private Function AnyDataSheetPresent(wb As Workbook) As Boolean
    Dim names As Variant: names = DataSheetNamesForMerge()
    Dim i As Long
    Dim ws As Worksheet
    For i = LBound(names) To UBound(names)
        Set ws = Nothing
        On Error Resume Next
        Set ws = wb.Sheets(CStr(names(i)))
        On Error GoTo 0
        If Not ws Is Nothing Then
            AnyDataSheetPresent = True
            Exit Function
        End If
    Next i
    Set ws = Nothing
    On Error Resume Next
    Set ws = wb.Sheets("_data_settings")
    On Error GoTo 0
    AnyDataSheetPresent = Not ws Is Nothing
End Function

' Merges one _data_* sheet from oldWb into the matching sheet in ThisWorkbook,
' mapped by column name (not position) so column reordering/additions are
' handled automatically. Ids are copied verbatim -- other sheets reference
' them as foreign keys (patient_id, user_id, consultant_id, lov ids,
' changed_by), so renumbering would silently break those links.
Private Function MergeSheet(oldWb As Workbook, sheetName As String) As String
    Dim oldWs As Worksheet
    Set oldWs = Nothing
    On Error Resume Next
    Set oldWs = oldWb.Sheets(sheetName)
    On Error GoTo 0
    If oldWs Is Nothing Then
        MergeSheet = sheetName & ": not present in old file, kept current defaults"
        Exit Function
    End If

    Dim oldLast As Long: oldLast = modUtils.LastDataRow(oldWs)
    If oldLast < 2 Then
        MergeSheet = sheetName & ": no rows in old file, kept current defaults"
        Exit Function
    End If

    Dim newWs As Worksheet: Set newWs = modUtils.DataSheet(sheetName)
    Dim newLastCol As Long: newLastCol = newWs.Cells(1, newWs.Columns.Count).End(xlToLeft).Column

    ' Clear whatever build.py freshly seeded/left in this sheet before writing
    ' the real imported rows.
    Dim existingLast As Long: existingLast = modUtils.LastDataRow(newWs)
    If existingLast >= 2 Then
        newWs.Range(newWs.Cells(2, 1), newWs.Cells(existingLast, newLastCol)).ClearContents
    End If

    Dim cUsername As Long: cUsername = 0
    Dim taken As Object
    If sheetName = "_data_users" Then
        cUsername = modUtils.ColIndex(newWs, "username")
        Set taken = CreateObject("Scripting.Dictionary")
        ' Pre-seed with every already-non-blank username in the OLD file so a
        ' blank-username row processed earlier in row order can never end up
        ' colliding with an explicit username that only appears later in the
        ' same file -- taken must be fully populated before any derivation
        ' happens, not built up incrementally as rows are visited.
        Dim oldUsernameCol As Long: oldUsernameCol = modUtils.ColIndex(oldWs, "username")
        If oldUsernameCol > 0 Then
            Dim seedRow As Long
            For seedRow = 2 To oldLast
                Dim existingUname As String: existingUname = Trim(CStr(oldWs.Cells(seedRow, oldUsernameCol).Value))
                If existingUname <> "" Then taken(LCase(existingUname)) = True
            Next seedRow
        End If
    End If

    Dim destRow As Long: destRow = 2
    Dim r As Long
    For r = 2 To oldLast
        Dim c As Long
        For c = 1 To newLastCol
            Dim colName As String: colName = CStr(newWs.Cells(1, c).Value)
            Dim oldCol As Long: oldCol = modUtils.ColIndex(oldWs, colName)
            If oldCol > 0 Then
                newWs.Cells(destRow, c).Value = oldWs.Cells(r, oldCol).Value
            End If
        Next c

        If cUsername > 0 Then
            Dim uname As String: uname = Trim(CStr(newWs.Cells(destRow, cUsername).Value))
            If uname = "" Then
                uname = DeriveUsername(newWs, destRow, taken)
                newWs.Cells(destRow, cUsername).Value = uname
            End If
            taken(LCase(uname)) = True
        End If

        destRow = destRow + 1
    Next r

    MergeSheet = sheetName & ": " & (oldLast - 1) & " row(s) imported"
End Function

' Derives a username for a _data_users row that came from an old file with no
' username column at all: the email's local-part, or failing that an
' alnum-only slug of the display name, de-duplicated within this one import.
Private Function DeriveUsername(ws As Worksheet, rowIdx As Long, taken As Object) As String
    Dim email As String: email = Trim(CStr(modUtils.GetVal(ws, rowIdx, "email")))
    Dim base As String

    If email <> "" And InStr(email, "@") > 0 Then
        base = LCase(Left(email, InStr(email, "@") - 1))
    End If
    If base = "" Then
        base = SlugAlnum(LCase(Trim(CStr(modUtils.GetVal(ws, rowIdx, "name")))))
    End If
    If base = "" Then base = "user"

    Dim candidate As String: candidate = base
    Dim n As Long: n = 2
    Do While taken.Exists(candidate)
        candidate = base & n
        n = n + 1
    Loop
    DeriveUsername = candidate
End Function

Private Function SlugAlnum(s As String) As String
    Dim i As Long, ch As String, result As String
    For i = 1 To Len(s)
        ch = Mid(s, i, 1)
        If (ch >= "a" And ch <= "z") Or (ch >= "0" And ch <= "9") Then result = result & ch
    Next i
    SlugAlnum = result
End Function

' _data_settings is key/value, not columnar, so it gets its own merge:
' every key the old file had wins over the current default (preserves the
' admin's real retention_months/purge_frequency/etc.), except
' excel_build_version -- that must always reflect the CURRENT build, never an
' imported older (or newer) file's value.
Private Function MergeSettings(oldWb As Workbook) As String
    Dim oldWs As Worksheet
    Set oldWs = Nothing
    On Error Resume Next
    Set oldWs = oldWb.Sheets("_data_settings")
    On Error GoTo 0
    If oldWs Is Nothing Then
        MergeSettings = "_data_settings: not present in old file, kept current defaults"
        Exit Function
    End If

    Dim oldLast As Long: oldLast = modUtils.LastDataRow(oldWs)
    If oldLast < 2 Then
        MergeSettings = "_data_settings: no rows in old file, kept current defaults"
        Exit Function
    End If

    Dim n As Long: n = 0
    Dim i As Long
    For i = 2 To oldLast
        Dim k As String: k = CStr(oldWs.Cells(i, 1).Value)
        If k <> "" And k <> "excel_build_version" Then
            modUtils.SetSetting k, CStr(oldWs.Cells(i, 2).Value)
            n = n + 1
        End If
    Next i
    MergeSettings = "_data_settings: " & n & " setting(s) carried over from old file"
End Function
