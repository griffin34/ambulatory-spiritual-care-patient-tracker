Attribute VB_Name = "modAdmin"
Option Explicit

' Creates a new user account with a hashed password and appends it to _data_users.
' username is the sign-in credential (modAuth.ValidateLogin); email is informational only.
' Returns False (no row added) if username collides case-insensitively with an
' existing user -- mirrors SetUsername's uniqueness guarantee, since a
' duplicate username would make one of the two accounts' login ambiguous.
' securityQuestion/securityAnswer are optional (blank/blank is fine -- self-
' service password recovery (modAuth.VerifySecurityAnswer) just stays
' unavailable for that account until they're set). When provided, the answer
' is hashed via modAuth.HashPassword(modAuth.NormalizeAnswer(...)) so
' VerifySecurityAnswer's re-hash of a submitted answer matches.
Public Function CreateUser(name As String, username As String, email As String, password As String, role As String, _
    Optional securityQuestion As String = "", Optional securityAnswer As String = "") As Boolean
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
    ws.Cells(newRow, 9).Value = Trim(securityQuestion)
    ws.Cells(newRow, 10).Value = IIf(Trim(securityAnswer) = "", "", modAuth.HashPassword(modAuth.NormalizeAnswer(securityAnswer)))
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

' ── Self-service password recovery ─────────────────────────────────────────────
' Returns "" if the username doesn't match an active user, or if that user has
' no security question set -- both cases ForgotPasswordForm treats the same
' ("no recovery available for that account").
Public Function GetSecurityQuestion(username As String) As String
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    If last < 2 Then Exit Function

    Dim cUsername As Long: cUsername = modUtils.ColIndex(ws, "username")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim cQuestion As Long: cQuestion = modUtils.ColIndex(ws, "security_question")

    Dim i As Long
    For i = 2 To last
        If LCase(CStr(ws.Cells(i, cUsername).Value)) = LCase(Trim(username)) And _
           ws.Cells(i, cActive).Value = 1 Then
            GetSecurityQuestion = CStr(ws.Cells(i, cQuestion).Value)
            Exit Function
        End If
    Next i
End Function

' Returns a user's currently-set security question by id, "" if none set or
' the id doesn't exist. Unlike GetSecurityQuestion (username lookup, gated on
' is_active, for the anonymous login-time flow), this is for populating
' SecurityQuestionForm where the caller already knows the user is valid --
' e.g. an admin editing a deactivated account's question, which GetSecurityQuestion
' would otherwise refuse to reveal.
Public Function GetSecurityQuestionById(userId As Long) As String
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim r As Long: r = modUtils.FindById(ws, userId)
    If r = 0 Then Exit Function
    GetSecurityQuestionById = CStr(ws.Cells(r, modUtils.ColIndex(ws, "security_question")).Value)
End Function

' Sets (or, if both blank, clears) a user's security question/answer after
' account creation -- the only way an account created before this feature
' existed (which is every account as of this build) can gain self-service
' Forgot Password access. Mirrors CreateUser's both-or-neither validation and
' answer-hashing (modAuth.NormalizeAnswer + HashPassword) exactly, so
' modAuth.VerifySecurityAnswer's re-hash of a submitted answer still matches.
' Returns False (no change made) if userId doesn't exist or exactly one of
' question/answer is blank.
Public Function SetSecurityQuestion(userId As Long, question As String, answer As String) As Boolean
    If (Trim(question) = "") <> (Trim(answer) = "") Then Exit Function
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim r As Long: r = modUtils.FindById(ws, userId)
    If r = 0 Then Exit Function
    ws.Cells(r, modUtils.ColIndex(ws, "security_question")).Value = Trim(question)
    ws.Cells(r, modUtils.ColIndex(ws, "security_answer_hash")).Value = _
        IIf(Trim(answer) = "", "", modAuth.HashPassword(modAuth.NormalizeAnswer(answer)))
    modUtils.AutoSave
    SetSecurityQuestion = True
End Function

' Opens SecurityQuestionForm for the CURRENT session's own account -- any
' logged-in user (admin or coordinator) can set/change their own security
' question, unlike UI_SetSelectedUserSecurityQuestion below which is admin-only.
Public Sub UI_OpenMySecurityQuestion()
    If Not modAuth.IsLoggedIn() Then Exit Sub
    SecurityQuestionForm.UserId = modAuth.gUserId
    SecurityQuestionForm.Show
End Sub

Public Sub UI_SetSelectedUserSecurityQuestion()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    Dim userId As Long: userId = SelectedIdInTable("tblUsers")
    If userId = 0 Then
        MsgBox "Select a user row first.", vbExclamation
        Exit Sub
    End If
    SecurityQuestionForm.UserId = userId
    SecurityQuestionForm.Show
End Sub

' Counterpart to ResetPassword for a user who isn't logged in yet -- only acts
' on an ACTIVE user found by username (case-insensitive, matching
' modAuth.ValidateLogin's lookup). Returns False (no change made) if no such
' user exists, so ForgotPasswordForm can tell the caller apart from success.
Public Function ResetPasswordByUsername(username As String, newPassword As String) As Boolean
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    If last < 2 Then Exit Function

    Dim cUsername As Long: cUsername = modUtils.ColIndex(ws, "username")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim cHash As Long: cHash = modUtils.ColIndex(ws, "password_hash")

    Dim i As Long
    For i = 2 To last
        If LCase(CStr(ws.Cells(i, cUsername).Value)) = LCase(Trim(username)) And _
           ws.Cells(i, cActive).Value = 1 Then
            ws.Cells(i, cHash).Value = modAuth.HashPassword(newPassword)
            modUtils.AutoSave
            ResetPasswordByUsername = True
            Exit Function
        End If
    Next i
End Function

' ── Break-glass recovery code ───────────────────────────────────────────────────
' 12 chars from an alphabet that excludes visually-ambiguous characters
' (0/O, 1/I/L), formatted as "XXXX-XXXX-XXXX" for easier transcription.
Public Function GenerateRecoveryCode() As String
    Const alphabet As String = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
    Randomize
    Dim result As String
    Dim i As Long
    For i = 1 To 12
        If i > 1 And (i - 1) Mod 4 = 0 Then result = result & "-"
        result = result & Mid(alphabet, Int(Rnd() * Len(alphabet)) + 1, 1)
    Next i
    GenerateRecoveryCode = result
End Function

' Generates a new recovery code, stores only its hash (modAuth.HashRecoveryCode
' normalizes + hashes the same way modAuth.VerifyRecoveryCode re-hashes a
' submitted code), and returns the PLAINTEXT code -- the only moment it's ever
' visible again; like a password, it cannot be retrieved later, only rotated.
Public Function RotateRecoveryCode() As String
    Dim code As String: code = GenerateRecoveryCode()
    modUtils.SetSetting "recovery_code_hash", modAuth.HashRecoveryCode(code)
    modUtils.AutoSave
    RotateRecoveryCode = code
End Function

' Break-glass reset: sets a new password AND reactivates the account in one
' step, since the whole point of the recovery-code path is regaining access
' even to an account that's been deactivated as well as locked out.
Public Sub RecoverAccount(userId As Long, newPassword As String)
    Dim ws As Worksheet: Set ws = modUtils.DataSheet("_data_users")
    Dim r As Long: r = modUtils.FindById(ws, userId)
    If r = 0 Then Exit Sub
    ws.Cells(r, modUtils.ColIndex(ws, "password_hash")).Value = modAuth.HashPassword(newPassword)
    ws.Cells(r, modUtils.ColIndex(ws, "is_active")).Value = 1
    modUtils.AutoSave
End Sub

Public Sub UI_RotateRecoveryCode()
    If Not modAuth.IsAdmin() Then MsgBox "Admin access required.", vbExclamation: Exit Sub
    If modUtils.GetSetting("recovery_code_hash") <> "" Then
        If MsgBox("This will invalidate the current recovery code. Continue?", _
            vbQuestion + vbYesNo, "Rotate Recovery Code") <> vbYes Then Exit Sub
    End If
    Dim code As String: code = RotateRecoveryCode()
    MsgBox "New recovery code -- write this down now, it cannot be shown again, only rotated:" & _
        vbCrLf & vbCrLf & code, vbInformation, "Recovery Code"
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
