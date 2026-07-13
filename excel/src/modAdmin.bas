Attribute VB_Name = "modAdmin"
Option Explicit

' Creates a new user account with a hashed password and appends it to _data_users.
Public Sub CreateUser(name As String, email As String, password As String, role As String)
    Dim ws As Worksheet
    Set ws = modUtils.DataSheet("_data_users")
    Dim newRow As Long
    newRow = modUtils.LastDataRow(ws) + 1

    ws.Cells(newRow, 1).Value = modUtils.NextId(ws)
    ws.Cells(newRow, 2).Value = name
    ws.Cells(newRow, 3).Value = email
    ws.Cells(newRow, 4).Value = modAuth.HashPassword(password)
    ws.Cells(newRow, 5).Value = role
    ws.Cells(newRow, 6).Value = 1
    ws.Cells(newRow, 7).Value = modUtils.NowISO()
End Sub

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
    Dim cEmail As Long: cEmail = modUtils.ColIndex(ws, "email")
    Dim cRole As Long: cRole = modUtils.ColIndex(ws, "role")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim i As Long
    For i = 2 To last
        Dim d As Object: Set d = CreateObject("Scripting.Dictionary")
        d("id") = ws.Cells(i, cId).Value
        d("name") = ws.Cells(i, cName).Value
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
End Sub

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

Public Sub UpdateLovRow(lovId As Long, newValue As String, newSortOrder As Long)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_lov")
    Dim r As Long: r = modUtils.FindById(ws, lovId)
    If r = 0 Then Exit Sub
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
            ws.Cells(i, modUtils.ColIndex(ws, "is_active")).Value = 1
            ws.Cells(i, modUtils.ColIndex(ws, "sort_order")).Value = sortOrder
            Exit Sub
        End If
    Next i

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

Public Sub RefreshAdmin()
    RefreshUsersTable
    RefreshLovTable
End Sub

Public Sub RefreshUsersTable()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Admin")
    Dim tbl As ListObject: Set tbl = ws.ListObjects("tblUsers")
    If Not tbl.DataBodyRange Is Nothing Then tbl.DataBodyRange.Delete

    Dim users As Collection: Set users = ListUsers()
    If users.Count = 0 Then Exit Sub
    Dim r As Long: r = 1
    Dim u As Object
    For Each u In users
        tbl.ListRows.Add
        tbl.DataBodyRange(r, 1).Value = u("id")
        tbl.DataBodyRange(r, 2).Value = u("name")
        tbl.DataBodyRange(r, 3).Value = u("email")
        tbl.DataBodyRange(r, 4).Value = u("role")
        tbl.DataBodyRange(r, 5).Value = IIf(u("is_active") = 1, "Active", "Inactive")
        r = r + 1
    Next u
End Sub

Public Sub RefreshLovTable()
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Admin")
    Dim tbl As ListObject: Set tbl = ws.ListObjects("tblLov")
    If Not tbl.DataBodyRange Is Nothing Then tbl.DataBodyRange.Delete

    Dim categoryLabel As String: categoryLabel = CStr(ws.Range("I2").Value)
    Dim category As String: category = CategoryInternal(categoryLabel)
    If category = "" Then Exit Sub

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
    If userId = 0 Then Exit Sub
    ResetPasswordForm.UserId = userId
    ResetPasswordForm.Show
End Sub

Public Sub UI_DeactivateSelectedUser()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim userId As Long: userId = SelectedIdInTable("tblUsers")
    If userId = 0 Then Exit Sub
    SetUserActive userId, False
    RefreshUsersTable
End Sub

Public Sub UI_ActivateSelectedUser()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim userId As Long: userId = SelectedIdInTable("tblUsers")
    If userId = 0 Then Exit Sub
    SetUserActive userId, True
    RefreshUsersTable
End Sub

Public Sub UI_DeactivateSelectedLov()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim categoryLabel As String: categoryLabel = CStr(modUtils.DataSheet("Admin").Range("I2").Value)
    Dim category As String: category = CategoryInternal(categoryLabel)
    Dim lovId As Long: lovId = SelectedIdInTable("tblLov")
    If lovId = 0 Then Exit Sub
    If category = "consultants" Then
        SetConsultantActive lovId, False
    Else
        DeactivateLov lovId
    End If
    RefreshLovTable
End Sub

Public Sub UI_RestoreSelectedLov()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim categoryLabel As String: categoryLabel = CStr(modUtils.DataSheet("Admin").Range("I2").Value)
    Dim category As String: category = CategoryInternal(categoryLabel)
    Dim lovId As Long: lovId = SelectedIdInTable("tblLov")
    If lovId = 0 Then Exit Sub
    If category = "consultants" Then
        SetConsultantActive lovId, True
    Else
        RestoreLov lovId
    End If
    RefreshLovTable
End Sub

Public Sub UI_AddLovValue()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("Admin")
    Dim categoryLabel As String: categoryLabel = CStr(ws.Range("I2").Value)
    Dim category As String: category = CategoryInternal(categoryLabel)
    Dim newLovValue As String: newLovValue = Trim(CStr(ws.Range("I3").Value))
    If newLovValue = "" Then Exit Sub

    If category = "consultants" Then
        Dim chaplainText As String: chaplainText = UCase(Trim(CStr(ws.Range("M3").Value)))
        Dim isChaplain As Boolean: isChaplain = (chaplainText = "Y" Or chaplainText = "YES")
        UpsertConsultant 0, newLovValue, isChaplain
    Else
        Dim sortOrder As Long
        If IsNumeric(ws.Range("K3").Value) Then sortOrder = CLng(ws.Range("K3").Value)
        UpsertLov category, newLovValue, sortOrder
    End If

    ws.Range("I3").Value = ""
    ws.Range("K3").Value = ""
    ws.Range("M3").Value = ""
    RefreshLovTable
End Sub
