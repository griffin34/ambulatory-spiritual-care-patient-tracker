Attribute VB_Name = "modAdmin"
Option Explicit

' Creates a new user account with a hashed password and appends it to _data_users.
' username is the sign-in credential (modAuth.ValidateLogin); email is informational only.
' Returns False (no row added) if username collides case-insensitively with an
' existing user -- mirrors SetUsername's uniqueness guarantee, since a
' duplicate username would make one of the two accounts' login ambiguous.
Public Function CreateUser(name As String, username As String, email As String, password As String, role As String) As Boolean
    Dim ws As Worksheet
    Set ws = modUtils.DataSheet("_data_users")
    If UsernameTaken(ws, username, 0) Then Exit Function

    Dim newRow As Long
    newRow = modUtils.LastDataRow(ws) + 1

    ws.Cells(newRow, 1).Value = modUtils.NextId(ws)
    ws.Cells(newRow, 2).Value = name
    ws.Cells(newRow, 3).Value = Trim(username)
    ws.Cells(newRow, 4).Value = email
    ws.Cells(newRow, 5).Value = modAuth.HashPassword(password)
    ws.Cells(newRow, 6).Value = role
    ws.Cells(newRow, 7).Value = 1
    ws.Cells(newRow, 8).Value = modUtils.NowISO()
    modUtils.AutoSave
    CreateUser = True
End Function

' True if another row in _data_users already has this username (case-
' insensitive), excluding excludeUserId (pass 0 when checking a brand-new
' user, since no existing row can equal that). Shared by CreateUser and
' SetUsername so the uniqueness rule only lives in one place.
Private Function UsernameTaken(ws As Worksheet, username As String, excludeUserId As Long) As Boolean
    Dim trimmed As String: trimmed = Trim(username)
    If trimmed = "" Then Exit Function

    Dim cUsername As Long: cUsername = modUtils.ColIndex(ws, "username")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, 1).Value <> excludeUserId And _
           LCase(CStr(ws.Cells(i, cUsername).Value)) = LCase(trimmed) Then
            UsernameTaken = True
            Exit Function
        End If
    Next i
End Function

' Returns a user's display name, or "" if not found / userId<=0.
Public Function GetUserName(userId As Long) As String
    If userId <= 0 Then Exit Function
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim r As Long: r = modUtils.FindById(ws, userId)
    If r = 0 Then Exit Function
    GetUserName = CStr(ws.Cells(r, modUtils.ColIndex(ws, "name")).Value)
End Function

' ── User management ────────────────────────────────────────────────────────
Public Function ListUsers() As Collection
    Dim result As New Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cId As Long: cId = modUtils.ColIndex(ws, "id")
    Dim cName As Long: cName = modUtils.ColIndex(ws, "name")
    Dim cUsername As Long: cUsername = modUtils.ColIndex(ws, "username")
    Dim cEmail As Long: cEmail = modUtils.ColIndex(ws, "email")
    Dim cRole As Long: cRole = modUtils.ColIndex(ws, "role")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim i As Long
    For i = 2 To last
        Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
        d("id") = ws.Cells(i, cId).Value
        d("name") = ws.Cells(i, cName).Value
        d("username") = ws.Cells(i, cUsername).Value
        d("email") = ws.Cells(i, cEmail).Value
        d("role") = ws.Cells(i, cRole).Value
        d("is_active") = ws.Cells(i, cActive).Value
        result.Add d
    Next i
    Set ListUsers = result
End Function

Public Sub SetUserActive(userId As Long, isActive As Boolean)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim r As Long: r = modUtils.FindById(ws, userId)
    If r = 0 Then Exit Sub
    ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = IIf(isActive, 1, 0)
End Sub

Public Sub ResetPassword(userId As Long, newPassword As String)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim r As Long: r = modUtils.FindById(ws, userId)
    If r = 0 Then Exit Sub
    ws.Cells(r, modUtils.ColIndex(ws, "password_hash")).Value = modAuth.HashPassword(newPassword)
    modUtils.AutoSave
End Sub

' Renames a user's sign-in username. Returns False (no change made) if another
' active or inactive row already uses that username (case-insensitive) --
' username is the sole login credential (modAuth.ValidateLogin), so collisions
' would make one of the two accounts unreachable.
Public Function SetUsername(userId As Long, newUsername As String) As Boolean
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim trimmed As String: trimmed = Trim(newUsername)
    If trimmed = "" Then Exit Function
    If UsernameTaken(ws, trimmed, userId) Then Exit Function

    Dim r As Long: r = modUtils.FindById(ws, userId)
    If r = 0 Then Exit Function
    ws.Cells(r, modUtils.ColIndex(ws, "username")).Value = trimmed
    modUtils.AutoSave
    SetUsername = True
End Function

' ── List of Values management ──────────────────────────────────────────────
' Unlike the Electron app's listLovs (active rows only), Admin needs inactive
' rows too so they can be Restored -- same precedent as PatientDetailForm's
' Deleted filter.
Public Function ListLovAll(category As String) As Collection
    Dim result As New Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_lov")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cId As Long: cId = modUtils.ColIndex(ws, "id")
    Dim cCategory As Long: cCategory = modUtils.ColIndex(ws, "category")
    Dim cValue As Long: cValue = modUtils.ColIndex(ws, "value")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim cSort As Long: cSort = modUtils.ColIndex(ws, "sort_order")
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cCategory).Value = category Then
            Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
            d("id") = ws.Cells(i, cId).Value
            d("value") = ws.Cells(i, cValue).Value
            d("sort_order") = ws.Cells(i, cSort).Value
            d("is_active") = ws.Cells(i, cActive).Value
            result.Add d
        End If
    Next i
    Set ListLovAll = result
End Function

' Shifts every OTHER row in `category` whose sort_order >= newSortOrder up by
' one, so assigning that position to a (re)inserted/edited value doesn't
' collide with -- or silently tie with -- whatever already sat there. E.g.
' inserting at position 1 pushes the existing 1,2,3.. down to 2,3,4..
' excludeRow lets an edit-in-place skip re-shifting the row being set itself.
Private Sub ShiftSortOrdersFrom(category As String, newSortOrder As Long, excludeRow As Long)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_lov")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cCategory As Long: cCategory = modUtils.ColIndex(ws, "category")
    Dim cSort As Long: cSort = modUtils.ColIndex(ws, "sort_order")
    Dim i As Long
    For i = 2 To last
        If i <> excludeRow And ws.Cells(i, cCategory).Value = category Then
            If CLng(ws.Cells(i, cSort).Value) >= newSortOrder Then
                ws.Cells(i, cSort).Value = CLng(ws.Cells(i, cSort).Value) + 1
            End If
        End If
    Next i
End Sub

Public Sub UpdateLovRow(lovId As Long, newValue As String, newSortOrder As Long)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_lov")
    Dim r As Long: r = modUtils.FindById(ws, lovId)
    If r = 0 Then Exit Sub
    Dim category As String: category = CStr(ws.Cells(r, modUtils.ColIndex(ws, "category")).Value)
    ShiftSortOrdersFrom category, newSortOrder, r
    ws.Cells(r, modUtils.ColIndex(ws, "value")).Value = newValue
    ws.Cells(r, modUtils.ColIndex(ws, "sort_order")).Value = newSortOrder
End Sub

' Mirrors admin.js's upsertLov: reactivates+updates a matching (category,value)
' row if one exists (case-insensitive), else inserts a new row. VBA has no
' ON CONFLICT, so this is done by hand with a manual scan.
Public Sub UpsertLov(category As String, newLovValue As String, sortOrder As Long)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_lov")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cCategory As Long: cCategory = modUtils.ColIndex(ws, "category")
    Dim cValue As Long: cValue = modUtils.ColIndex(ws, "value")
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cCategory).Value = category And _
           LCase(CStr(ws.Cells(i, cValue).Value)) = LCase(newLovValue) Then
            ShiftSortOrdersFrom category, sortOrder, i
            ws.Cells(i, modUtils.ColIndex(ws, "is_active")).Value = 1
            ws.Cells(i, modUtils.ColIndex(ws, "sort_order")).Value = sortOrder
            Exit Sub
        End If
    Next i

    ShiftSortOrdersFrom category, sortOrder, 0
    Dim r As Long: r = last + 1
    ws.Cells(r, modUtils.ColIndex(ws, "id")).Value = modUtils.NextId(ws)
    ws.Cells(r, cCategory).Value = category
    ws.Cells(r, cValue).Value = newLovValue
    ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = 1
    ws.Cells(r, modUtils.ColIndex(ws, "sort_order")).Value = sortOrder
End Sub

Public Sub DeactivateLov(lovId As Long)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_lov")
    Dim r As Long: r = modUtils.FindById(ws, lovId)
    If r = 0 Then Exit Sub
    ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = 0
End Sub

Public Sub RestoreLov(lovId As Long)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_lov")
    Dim r As Long: r = modUtils.FindById(ws, lovId)
    If r = 0 Then Exit Sub
    ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = 1
End Sub

' ── Consultants (structurally distinct from _data_lov: no sort_order, has
'    is_chaplain) -- Admin's LoV section routes to these instead when the
'    selected category is "Consultants". ─────────────────────────────────────
Public Function ListConsultants() As Collection
    Dim result As New Collection
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_consultants")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cId As Long: cId = modUtils.ColIndex(ws, "id")
    Dim cName As Long: cName = modUtils.ColIndex(ws, "name")
    Dim cChaplain As Long: cChaplain = modUtils.ColIndex(ws, "is_chaplain")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim i As Long
    For i = 2 To last
        Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
        d("id") = ws.Cells(i, cId).Value
        d("name") = ws.Cells(i, cName).Value
        d("is_chaplain") = ws.Cells(i, cChaplain).Value
        d("is_active") = ws.Cells(i, cActive).Value
        result.Add d
    Next i
    Set ListConsultants = result
End Function

Public Sub UpsertConsultant(consultantId As Long, consultantName As String, isChaplain As Boolean)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_consultants")
    Dim r As Long

    If consultantId = 0 Then
        Dim last As Long: last = modUtils.LastDataRow(ws)
        Dim cName As Long: cName = modUtils.ColIndex(ws, "name")
        Dim i As Long
        For i = 2 To last
            If LCase(CStr(ws.Cells(i, cName).Value)) = LCase(consultantName) Then
                ws.Cells(i, modUtils.ColIndex(ws, "is_active")).Value = 1
                ws.Cells(i, modUtils.ColIndex(ws, "is_chaplain")).Value = IIf(isChaplain, 1, 0)
                Exit Sub
            End If
        Next i
        r = last + 1
        ws.Cells(r, modUtils.ColIndex(ws, "id")).Value = modUtils.NextId(ws)
    Else
        r = modUtils.FindById(ws, consultantId)
        If r = 0 Then Exit Sub
    End If

    ws.Cells(r, modUtils.ColIndex(ws, "name")).Value = consultantName
    ws.Cells(r, modUtils.ColIndex(ws, "is_chaplain")).Value = IIf(isChaplain, 1, 0)
    ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = 1
End Sub

Public Sub SetConsultantActive(consultantId As Long, isActive As Boolean)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_consultants")
    Dim r As Long: r = modUtils.FindById(ws, consultantId)
    If r = 0 Then Exit Sub
    ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = IIf(isActive, 1, 0)
End Sub

' Returns a single _data_lov row as a Dictionary (id/category/value/sort_order/
' is_active), or Nothing if lovId doesn't exist -- used to pre-fill AddEditLovForm.
Public Function FindLov(lovId As Long) As Object
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_lov")
    Dim r As Long: r = modUtils.FindById(ws, lovId)
    If r = 0 Then Exit Function
    Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
    d("id") = lovId
    d("category") = ws.Cells(r, modUtils.ColIndex(ws, "category")).Value
    d("value") = ws.Cells(r, modUtils.ColIndex(ws, "value")).Value
    d("sort_order") = ws.Cells(r, modUtils.ColIndex(ws, "sort_order")).Value
    d("is_active") = ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value
    Set FindLov = d
End Function

' Returns a single _data_consultants row as a Dictionary (id/name/is_chaplain/
' is_active), or Nothing if consultantId doesn't exist -- used to pre-fill
' AddEditLovForm for the Consultants category.
Public Function FindConsultantById(consultantId As Long) As Object
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_consultants")
    Dim r As Long: r = modUtils.FindById(ws, consultantId)
    If r = 0 Then Exit Function
    Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
    d("id") = consultantId
    d("name") = ws.Cells(r, modUtils.ColIndex(ws, "name")).Value
    d("is_chaplain") = ws.Cells(r, modUtils.ColIndex(ws, "is_chaplain")).Value
    d("is_active") = ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value
    Set FindConsultantById = d
End Function

' Default sort order offered when adding a new value: one past the highest
' currently in use for that category, so a plain "+ Add" appends to the end
' without triggering any ShiftSortOrdersFrom reshuffle. The user can still
' type an earlier number to insert it mid-list.
Public Function NextLovSortOrder(category As String) As Long
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_lov")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    Dim cCategory As Long: cCategory = modUtils.ColIndex(ws, "category")
    Dim cSort As Long: cSort = modUtils.ColIndex(ws, "sort_order")
    Dim maxSort As Long: maxSort = 0
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cCategory).Value = category Then
            If CLng(ws.Cells(i, cSort).Value) > maxSort Then maxSort = CLng(ws.Cells(i, cSort).Value)
        End If
    Next i
    NextLovSortOrder = maxSort + 1
End Function

' ── Admin sheet UI ──────────────────────────────────────────────────────────
Public Function CategoryInternal(displayLabel As String) As String
    Select Case displayLabel
        Case "Referral Sources": CategoryInternal = "referral_source"
        Case "Religions": CategoryInternal = "religion"
        Case "Languages": CategoryInternal = "language"
        Case "Consultants": CategoryInternal = "consultants"
        Case "Appointment Types": CategoryInternal = "appointment_type"
        Case Else: CategoryInternal = ""
    End Select
End Function

' Singular, human-readable label for AddEditLovForm's caption ("Add Religion",
' "Edit Consultant"), distinct from CategoryInternal's plural sheet-dropdown text.
Public Function CategoryDisplayName(category As String) As String
    Select Case category
        Case "referral_source": CategoryDisplayName = "Referral Source"
        Case "religion": CategoryDisplayName = "Religion"
        Case "language": CategoryDisplayName = "Language"
        Case "consultants": CategoryDisplayName = "Consultant"
        Case "appointment_type": CategoryDisplayName = "Appointment Type"
        Case Else: CategoryDisplayName = "Value"
    End Select
End Function

Public Sub RefreshAdmin()
    RefreshUsersTable
    RefreshLovTable
End Sub

Public Sub RefreshUsersTable()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Admin")
    Dim tbl As ListObject: Set tbl = ws.ListObjects("tblUsers")
    modUtils.UnprotectForRefresh ws
    If Not tbl.DataBodyRange Is Nothing Then tbl.DataBodyRange.Delete

    Dim users As Collection: Set users = ListUsers()
    If users.Count = 0 Then
        modUtils.ReprotectAfterRefresh ws
        Exit Sub
    End If
    Dim r As Long: r = 1
    Dim u As Object
    For Each u In users
        tbl.ListRows.Add
        tbl.DataBodyRange(r, 1).Value = u("id")
        tbl.DataBodyRange(r, 2).Value = u("name")
        tbl.DataBodyRange(r, 3).Value = u("username")
        tbl.DataBodyRange(r, 4).Value = u("email")
        tbl.DataBodyRange(r, 5).Value = u("role")
        tbl.DataBodyRange(r, 6).Value = IIf(u("is_active") = 1, "Active", "Inactive")
        r = r + 1
    Next u
    modUtils.ReprotectAfterRefresh ws
End Sub

Public Sub RefreshLovTable()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Admin")
    Dim tbl As ListObject: Set tbl = ws.ListObjects("tblLov")
    modUtils.UnprotectForRefresh ws
    If Not tbl.DataBodyRange Is Nothing Then tbl.DataBodyRange.Delete

    Dim categoryLabel As String: categoryLabel = CStr(ws.Range("I2").Value)
    Dim category As String: category = CategoryInternal(categoryLabel)
    If category = "" Then
        modUtils.ReprotectAfterRefresh ws
        Exit Sub
    End If

    ' On error, both EnableEvents and the sheet's protection must still be
    ' restored -- an unhandled error here previously left EnableEvents stuck
    ' False app-wide AND (found while fixing that) left the Admin sheet
    ' permanently unprotected even on the success path, since this Sub had no
    ' matching modUtils.ReprotectAfterRefresh call after the populated case
    ' (only the "no category selected" early-exit above had one).
    On Error GoTo Fail
    Application.EnableEvents = False
    Dim r As Long: r = 1
    If category = "consultants" Then
        Dim cons As Collection: Set cons = ListConsultants()
        Dim c As Object
        For Each c In cons
            tbl.ListRows.Add
            tbl.DataBodyRange(r, 1).Value = c("id")
            tbl.DataBodyRange(r, 2).Value = c("name")
            tbl.DataBodyRange(r, 3).Value = ""
            tbl.DataBodyRange(r, 4).Value = IIf(c("is_active") = 1, "Active", "Inactive")
            tbl.DataBodyRange(r, 5).Value = IIf(c("is_chaplain") = 1, "Yes", "No")
            r = r + 1
        Next c
    Else
        Dim rows As Collection: Set rows = ListLovAll(category)
        Dim d As Object
        For Each d In rows
            tbl.ListRows.Add
            tbl.DataBodyRange(r, 1).Value = d("id")
            tbl.DataBodyRange(r, 2).Value = d("value")
            tbl.DataBodyRange(r, 3).Value = d("sort_order")
            tbl.DataBodyRange(r, 4).Value = IIf(d("is_active") = 1, "Active", "Inactive")
            tbl.DataBodyRange(r, 5).Value = ""
            r = r + 1
        Next d
    End If
    Application.EnableEvents = True
    modUtils.ReprotectAfterRefresh ws
    Exit Sub

Fail:
    Application.EnableEvents = True
    modUtils.ReprotectAfterRefresh ws
    MsgBox "Error refreshing list of values: " & Err.Description, vbExclamation
End Sub

Private Function SelectedIdInTable(tableName As String) As Long
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Admin")
    Dim tbl As ListObject: Set tbl = ws.ListObjects(tableName)
    If tbl.DataBodyRange Is Nothing Then Exit Function
    If Intersect(Application.ActiveCell, tbl.DataBodyRange) Is Nothing Then Exit Function
    Dim rowOffset As Long: rowOffset = Application.ActiveCell.Row - tbl.DataBodyRange.Row + 1
    SelectedIdInTable = tbl.DataBodyRange(rowOffset, 1).Value
End Function

Public Sub UI_OpenAddUser()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    AddUserForm.FirstRunMode = False
    AddUserForm.Show
    RefreshUsersTable
End Sub

Public Sub UI_ResetSelectedUserPassword()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim userId As Long: userId = SelectedIdInTable("tblUsers")
    If userId = 0 Then
        MsgBox "Select a user row first.", vbExclamation
        Exit Sub
    End If
    ResetPasswordForm.UserId = userId
    ResetPasswordForm.Show
End Sub

Public Sub UI_EditSelectedUsername()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim userId As Long: userId = SelectedIdInTable("tblUsers")
    If userId = 0 Then
        MsgBox "Select a user row first.", vbExclamation
        Exit Sub
    End If

    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim r As Long: r = modUtils.FindById(ws, userId)
    If r = 0 Then Exit Sub
    Dim current As String: current = CStr(ws.Cells(r, modUtils.ColIndex(ws, "username")).Value)

    Dim newUsername As String
    newUsername = InputBox("New username:", "Edit Username", current)
    If Trim(newUsername) = "" Then Exit Sub

    If Not SetUsername(userId, newUsername) Then
        MsgBox "That username is already taken.", vbExclamation
        Exit Sub
    End If
    RefreshUsersTable
End Sub

Public Sub UI_DeactivateSelectedUser()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim userId As Long: userId = SelectedIdInTable("tblUsers")
    If userId = 0 Then
        MsgBox "Select a user row first.", vbExclamation
        Exit Sub
    End If
    SetUserActive userId, False
    RefreshUsersTable
    modUtils.AutoSave
End Sub

Public Sub UI_ActivateSelectedUser()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim userId As Long: userId = SelectedIdInTable("tblUsers")
    If userId = 0 Then
        MsgBox "Select a user row first.", vbExclamation
        Exit Sub
    End If
    SetUserActive userId, True
    RefreshUsersTable
    modUtils.AutoSave
End Sub

Public Sub UI_DeactivateSelectedLov()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim categoryLabel As String: categoryLabel = CStr(modUtils.DataSheet("Admin").Range("I2").Value)
    Dim category As String: category = CategoryInternal(categoryLabel)
    Dim lovId As Long: lovId = SelectedIdInTable("tblLov")
    If lovId = 0 Then
        MsgBox "Select a value row first.", vbExclamation
        Exit Sub
    End If
    If category = "consultants" Then
        SetConsultantActive lovId, False
    Else
        DeactivateLov lovId
    End If
    RefreshLovTable
    modUtils.AutoSave
End Sub

Public Sub UI_RestoreSelectedLov()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim categoryLabel As String: categoryLabel = CStr(modUtils.DataSheet("Admin").Range("I2").Value)
    Dim category As String: category = CategoryInternal(categoryLabel)
    Dim lovId As Long: lovId = SelectedIdInTable("tblLov")
    If lovId = 0 Then
        MsgBox "Select a value row first.", vbExclamation
        Exit Sub
    End If
    If category = "consultants" Then
        SetConsultantActive lovId, True
    Else
        RestoreLov lovId
    End If
    RefreshLovTable
    modUtils.AutoSave
End Sub

Public Sub UI_OpenAddLov()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim categoryLabel As String: categoryLabel = CStr(modUtils.DataSheet("Admin").Range("I2").Value)
    Dim category As String: category = CategoryInternal(categoryLabel)
    If category = "" Then Exit Sub

    AddEditLovForm.Category = category
    AddEditLovForm.LovId = 0
    AddEditLovForm.Show
    RefreshLovTable
End Sub

Public Sub UI_OpenEditLov()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim categoryLabel As String: categoryLabel = CStr(modUtils.DataSheet("Admin").Range("I2").Value)
    Dim category As String: category = CategoryInternal(categoryLabel)
    If category = "" Then Exit Sub

    Dim lovId As Long: lovId = SelectedIdInTable("tblLov")
    If lovId = 0 Then
        MsgBox "Select a value row first.", vbExclamation
        Exit Sub
    End If

    AddEditLovForm.Category = category
    AddEditLovForm.LovId = lovId
    AddEditLovForm.Show
    RefreshLovTable
End Sub
