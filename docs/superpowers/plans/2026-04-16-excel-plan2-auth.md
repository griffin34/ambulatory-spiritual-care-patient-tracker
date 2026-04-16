# Excel Plan 2: Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement SHA-256 password hashing, session state, and a login form so the workbook requires authentication on open.

**Architecture:** Four VBA components — `modSHA256` (pure-VBA SHA-256, no external dependencies), `modAuth` (module-level session globals + ValidateLogin), `LoginForm` (modal UserForm), and `ThisWorkbook` (Workbook_Open / Workbook_BeforeClose events). Python build script writes the `.bas` files; LoginForm and ThisWorkbook are entered manually in the VBA editor because UserForm `.frm`/`.frx` pairing and the `ThisWorkbook` class module cannot be imported the same way as standalone modules on Mac.

**Tech Stack:** VBA (Excel 2016+), Double-based 32-bit arithmetic to work around VBA's signed-Long limitations, xlwings Python build script for workbook scaffolding.

**Spec reference:** `docs/superpowers/specs/2026-04-13-ambulatory-patients-excel-design.md` — Authentication section, On Open section, Session State section.

**Mac build constraint:** `build.py` writes `.bas` files to `excel/src/` but cannot import VBA on Mac (appscript limitation). After running `python3 build.py`, manually import new `.bas` files in the VBA editor (`⌥F11` → File → Import File).

---

## File Map

| File | Action | Notes |
|------|--------|-------|
| `excel/src/modSHA256.bas` | Create | Pure-VBA SHA-256, no COM |
| `excel/src/modAuth.bas` | Create | Session globals + ValidateLogin |
| LoginForm (in VBA editor) | Create manually | Modal login UserForm |
| ThisWorkbook (in VBA editor) | Edit manually | Workbook_Open + BeforeClose |
| `excel/dist/AmbulatoryPatients.xlsm` | Rebuild | python3 build.py + manual import |

---

### Task 1: modSHA256 — Pure VBA SHA-256

**Files:**
- Create: `excel/src/modSHA256.bas`

**Why Double arithmetic:** VBA `Long` is signed 32-bit. Multiplying by 16777216 (`&H1000000`) overflows for inputs ≥ 128. All 32-bit arithmetic in this module uses `Double` (53-bit mantissa, exact for integers up to 2^53) via helper functions `U()`, `L()`, `A32()`, `RR()`, `RS()`.

**Naming clash:** VBA is case-insensitive. SHA-256 has both Σ (capital, used in rounds) and σ (lowercase, used in message schedule). They are named `RndSig0`/`RndSig1` and `SchSig0`/`SchSig1` here to avoid the clash.

- [ ] **Step 1: Create `excel/src/modSHA256.bas`**

Write this file exactly:

```vba
Attribute VB_Name = "modSHA256"
Option Explicit

' Pure-VBA SHA-256. No .NET, no COM, no external references.
' Handles ASCII email + password strings (StrConv ANSI).
' Returns a 64-character lowercase hex digest.

Public Function SHA256(sData As String) As String
    Dim mLen As Long: mLen = Len(sData)
    Dim b() As Byte
    If mLen > 0 Then b = StrConv(sData, vbFromUnicode)

    Dim h(7) As Long
    Call InitHash(h)

    Dim padded() As Byte
    padded = PadMsg(b, mLen)

    Call ProcessBlocks(padded, h)

    Dim i As Long, s As String
    For i = 0 To 7
        s = s & Right("00000000" & Hex(h(i)), 8)
    Next i
    SHA256 = LCase(s)
End Function

' ── Initial hash values (sqrt of first 8 primes, fractional part) ─────────────
Private Sub InitHash(h() As Long)
    h(0) = &H6A09E667: h(1) = &HBB67AE85: h(2) = &H3C6EF372: h(3) = &HA54FF53A
    h(4) = &H510E527F: h(5) = &H9B05688C: h(6) = &H1F83D9AB: h(7) = &H5BE0CD19
End Sub

' ── Padding: append 0x80, zeros, then 64-bit big-endian bit length ────────────
Private Function PadMsg(b() As Byte, mLen As Long) As Byte()
    Dim pLen As Long
    pLen = (((mLen + 9) + 63) \ 64) * 64

    Dim p() As Byte
    ReDim p(pLen - 1)

    Dim i As Long
    If mLen > 0 Then
        For i = 0 To mLen - 1
            p(i) = b(i)
        Next i
    End If
    p(mLen) = &H80

    ' Append 64-bit big-endian bit length (only low 32 bits needed for passwords)
    Dim bitLen As Long: bitLen = mLen * 8
    p(pLen - 4) = CByte((bitLen \ &H1000000) And &HFF)
    p(pLen - 3) = CByte((bitLen \ &H10000) And &HFF)
    p(pLen - 2) = CByte((bitLen \ &H100) And &HFF)
    p(pLen - 1) = CByte(bitLen And &HFF)

    PadMsg = p
End Function

' ── Block processing ──────────────────────────────────────────────────────────
Private Sub ProcessBlocks(p() As Byte, h() As Long)
    Dim k(63) As Long
    Call InitK(k)

    Dim numBlks As Long: numBlks = (UBound(p) + 1) \ 64
    Dim w(63) As Long
    Dim a As Long, b As Long, c As Long, d As Long
    Dim e As Long, f As Long, g As Long, hh As Long
    Dim t1 As Long, t2 As Long
    Dim blk As Long, i As Long, off As Long, o As Long

    For blk = 0 To numBlks - 1
        off = blk * 64
        ' Load 16 big-endian 32-bit words from bytes — use Double to avoid Long overflow
        For i = 0 To 15
            o = off + i * 4
            w(i) = L(CDbl(p(o)) * 16777216# + CDbl(p(o + 1)) * 65536# + _
                     CDbl(p(o + 2)) * 256# + CDbl(p(o + 3)))
        Next i
        ' Expand to 64 words
        For i = 16 To 63
            w(i) = A32(A32(A32(SchSig1(w(i - 2)), w(i - 7)), SchSig0(w(i - 15))), w(i - 16))
        Next i

        a = h(0): b = h(1): c = h(2): d = h(3)
        e = h(4): f = h(5): g = h(6): hh = h(7)

        For i = 0 To 63
            t1 = A32(A32(A32(A32(hh, RndSig1(e)), Ch(e, f, g)), k(i)), w(i))
            t2 = A32(RndSig0(a), Maj(a, b, c))
            hh = g: g = f: f = e
            e = A32(d, t1)
            d = c: c = b: b = a
            a = A32(t1, t2)
        Next i

        h(0) = A32(h(0), a): h(1) = A32(h(1), b)
        h(2) = A32(h(2), c): h(3) = A32(h(3), d)
        h(4) = A32(h(4), e): h(5) = A32(h(5), f)
        h(6) = A32(h(6), g): h(7) = A32(h(7), hh)
    Next blk
End Sub

' ── Round constants (cube roots of first 64 primes, fractional parts) ─────────
Private Sub InitK(k() As Long)
    k(0) =&H428A2F98: k(1) =&H71374491: k(2) =&HB5C0FBCF: k(3) =&HE9B5DBA5
    k(4) =&H3956C25B: k(5) =&H59F111F1: k(6) =&H923F82A4: k(7) =&HAB1C5ED5
    k(8) =&HD807AA98: k(9) =&H12835B01: k(10)=&H243185BE: k(11)=&H550C7DC3
    k(12)=&H72BE5D74: k(13)=&H80DEB1FE: k(14)=&H9BDC06A7: k(15)=&HC19BF174
    k(16)=&HE49B69C1: k(17)=&HEFBE4786: k(18)=&H0FC19DC6: k(19)=&H240CA1CC
    k(20)=&H2DE92C6F: k(21)=&H4A7484AA: k(22)=&H5CB0A9DC: k(23)=&H76F988DA
    k(24)=&H983E5152: k(25)=&HA831C66D: k(26)=&HB00327C8: k(27)=&HBF597FC7
    k(28)=&HC6E00BF3: k(29)=&HD5A79147: k(30)=&H06CA6351: k(31)=&H14292967
    k(32)=&H27B70A85: k(33)=&H2E1B2138: k(34)=&H4D2C6DFC: k(35)=&H53380D13
    k(36)=&H650A7354: k(37)=&H766A0ABB: k(38)=&H81C2C92E: k(39)=&H92722C85
    k(40)=&HA2BFE8A1: k(41)=&HA81A664B: k(42)=&HC24B8B70: k(43)=&HC76C51A3
    k(44)=&HD192E819: k(45)=&HD6990624: k(46)=&HF40E3585: k(47)=&H106AA070
    k(48)=&H19A4C116: k(49)=&H1E376C08: k(50)=&H2748774C: k(51)=&H34B0BCB5
    k(52)=&H391C0CB3: k(53)=&H4ED8AA4A: k(54)=&H5B9CCA4F: k(55)=&H682E6FF3
    k(56)=&H748F82EE: k(57)=&H78A5636F: k(58)=&H84C87814: k(59)=&H8CC70208
    k(60)=&H90BEFFFA: k(61)=&HA4506CEB: k(62)=&HBE0A62DC: k(63)=&HC67178F2
End Sub

' ── 32-bit arithmetic via Double (avoids signed Long overflow) ─────────────────
' Long → unsigned Double [0, 4294967295]
Private Function U(x As Long) As Double
    If x < 0 Then U = CDbl(x) + 4294967296# Else U = CDbl(x)
End Function

' unsigned Double → signed Long (mod 2^32)
Private Function L(v As Double) As Long
    v = v - Int(v / 4294967296#) * 4294967296#
    If v >= 2147483648# Then L = CLng(v - 4294967296#) Else L = CLng(v)
End Function

' 32-bit addition (discards carry)
Private Function A32(a As Long, b As Long) As Long
    A32 = L(U(a) + U(b))
End Function

' Right rotate by n bits
Private Function RR(x As Long, n As Long) As Long
    Dim u As Double: u = U(x)
    Dim pw As Double: pw = 2# ^ n
    RR = L(Int(u / pw) + (u - Int(u / pw) * pw) * (4294967296# / pw))
End Function

' Logical right shift by n bits
Private Function RS(x As Long, n As Long) As Long
    RS = L(Int(U(x) / (2# ^ n)))
End Function

' ── SHA-256 logical functions ─────────────────────────────────────────────────
Private Function Ch(x As Long, y As Long, z As Long) As Long
    Ch = (x And y) Xor (Not x And z)
End Function

Private Function Maj(x As Long, y As Long, z As Long) As Long
    Maj = (x And y) Xor (x And z) Xor (y And z)
End Function

' Round functions (Σ — capital sigma)
Private Function RndSig0(x As Long) As Long   ' Σ0 = ROTR(2) XOR ROTR(13) XOR ROTR(22)
    RndSig0 = RR(x, 2) Xor RR(x, 13) Xor RR(x, 22)
End Function

Private Function RndSig1(x As Long) As Long   ' Σ1 = ROTR(6) XOR ROTR(11) XOR ROTR(25)
    RndSig1 = RR(x, 6) Xor RR(x, 11) Xor RR(x, 25)
End Function

' Schedule functions (σ — lowercase sigma)
Private Function SchSig0(x As Long) As Long   ' σ0 = ROTR(7) XOR ROTR(18) XOR SHR(3)
    SchSig0 = RR(x, 7) Xor RR(x, 18) Xor RS(x, 3)
End Function

Private Function SchSig1(x As Long) As Long   ' σ1 = ROTR(17) XOR ROTR(19) XOR SHR(10)
    SchSig1 = RR(x, 17) Xor RR(x, 19) Xor RS(x, 10)
End Function
```

- [ ] **Step 2: Commit the source file**

```bash
cd /Users/jgriffin/dev/ambulatory-patients
git add excel/src/modSHA256.bas
git commit -m "feat(excel): add modSHA256 pure-VBA SHA-256 implementation"
```

- [ ] **Step 3: Rebuild the workbook and import the module**

```bash
cd /Users/jgriffin/dev/ambulatory-patients/excel
python3 build.py
```

Expected output includes:
```
  ⚠️  VBA import skipped (Mac/appscript limitation).
    ...excel/src/modSHA256.bas
Built: .../excel/dist/AmbulatoryPatients.xlsm
```

Then in Excel, open `excel/dist/AmbulatoryPatients.xlsm`, `⌥F11` → File → Import File → select `excel/src/modSHA256.bas` → Save.

- [ ] **Step 4: Verify SHA-256 against known test vectors**

In the VBA editor Immediate Window (`⌘G`):

```vba
? modSHA256.SHA256("")
```
Expected: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`

```vba
? modSHA256.SHA256("abc")
```
Expected: `ba7816bf8f01cfea414140de5dae2ec73b00361bbef0469fa72a39d8ca85e54d`

```vba
? Len(modSHA256.SHA256("test"))
```
Expected: `64`

If the empty-string vector passes but "abc" doesn't, the padding or block processing has a bug. If neither passes, the constants are likely wrong (re-check `InitHash` and `InitK` values against Task 1 Step 1).

---

### Task 2: modAuth — Session State and Login Validation

**Files:**
- Create: `excel/src/modAuth.bas`

Module-level `Public` variables hold the active session. They are **never** written to a sheet or saved — they reset to defaults whenever the workbook closes.

- [ ] **Step 1: Create `excel/src/modAuth.bas`**

```vba
Attribute VB_Name = "modAuth"
Option Explicit

' ── Session state (module-level; cleared on Workbook_BeforeClose) ─────────────
Public gUserId   As Long     ' 0 = not logged in
Public gUserName As String
Public gUserRole As String   ' "admin" | "coordinator"

' ── Password hashing ──────────────────────────────────────────────────────────
Public Function HashPassword(plaintext As String) As String
    HashPassword = modSHA256.SHA256(plaintext)
End Function

' ── Login validation ──────────────────────────────────────────────────────────
' Scans _data_users for a matching active row.
' On success: populates session globals and returns True.
' On failure: returns False (globals unchanged).
Public Function ValidateLogin(email As String, password As String) As Boolean
    Dim ws As Worksheet
    Set ws = modUtils.DataSheet("_data_users")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    If last < 2 Then Exit Function    ' no users at all

    ' Cache column indices — avoid re-scanning headers in inner loop
    Dim cEmail  As Long: cEmail  = modUtils.ColIndex(ws, "email")
    Dim cHash   As Long: cHash   = modUtils.ColIndex(ws, "password_hash")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim cId     As Long: cId     = modUtils.ColIndex(ws, "id")
    Dim cName   As Long: cName   = modUtils.ColIndex(ws, "name")
    Dim cRole   As Long: cRole   = modUtils.ColIndex(ws, "role")

    Dim hashPw As String: hashPw = HashPassword(password)

    Dim i As Long
    For i = 2 To last
        If LCase(CStr(ws.Cells(i, cEmail).Value)) = LCase(email) And _
           ws.Cells(i, cActive).Value = 1 And _
           ws.Cells(i, cHash).Value = hashPw Then
            gUserId   = CLng(ws.Cells(i, cId).Value)
            gUserName = CStr(ws.Cells(i, cName).Value)
            gUserRole = LCase(CStr(ws.Cells(i, cRole).Value))
            ValidateLogin = True
            Exit Function
        End If
    Next i
    ValidateLogin = False
End Function

' ── Session management ────────────────────────────────────────────────────────
Public Sub Logout()
    gUserId   = 0
    gUserName = ""
    gUserRole = ""
End Sub

Public Function IsLoggedIn() As Boolean
    IsLoggedIn = (gUserId > 0)
End Function

Public Function IsAdmin() As Boolean
    IsAdmin = (gUserRole = "admin")
End Function
```

- [ ] **Step 2: Commit**

```bash
cd /Users/jgriffin/dev/ambulatory-patients
git add excel/src/modAuth.bas
git commit -m "feat(excel): add modAuth session state and login validation"
```

- [ ] **Step 3: Rebuild and import**

```bash
cd /Users/jgriffin/dev/ambulatory-patients/excel
python3 build.py
```

In Excel: `⌥F11` → File → Import File → select `excel/src/modAuth.bas` → Save.

- [ ] **Step 4: Test ValidateLogin via a seed user**

In the Immediate Window, run this sub to insert a test user row directly (copy-paste as a multi-line sub, or type each line):

```vba
Sub SeedTestUser()
    Dim ws As Worksheet
    Set ws = modUtils.DataSheet("_data_users")
    ws.Cells(2, 1).Value = 1
    ws.Cells(2, 2).Value = "Test Admin"
    ws.Cells(2, 3).Value = "admin@test.com"
    ws.Cells(2, 4).Value = modAuth.HashPassword("Password1")
    ws.Cells(2, 5).Value = "admin"
    ws.Cells(2, 6).Value = 1
    ws.Cells(2, 7).Value = modUtils.NowISO()
End Sub
```

Run it: in Immediate Window type `SeedTestUser` and press Enter.

Then verify login:
```vba
? modAuth.ValidateLogin("admin@test.com", "Password1")
```
Expected: `True`

```vba
? modAuth.gUserName
```
Expected: `Test Admin`

```vba
? modAuth.ValidateLogin("admin@test.com", "wrongpassword")
```
Expected: `False`

```vba
? modAuth.gUserId
```
Expected: `1` (unchanged — failed login does not clear a successful session)

Then test logout:
```vba
modAuth.Logout
? modAuth.IsLoggedIn()
```
Expected: `False`

---

### Task 3: LoginForm — Modal Login UserForm

**Files:**
- Create in VBA editor: `LoginForm` (UserForm)

UserForms cannot be reliably created from a text `.frm` file on Mac (the binary `.frx` companion holds layout). Create the form manually in the VBA editor.

- [ ] **Step 1: Create the UserForm**

In the VBA editor (`⌥F11`): Insert → UserForm. A blank form appears.

In the Properties pane (View → Properties Window, or `F4`):
- `(Name)`: `LoginForm`
- `Caption`: `Ambulatory Patient Tracking — Login`
- `Width`: `300`
- `Height`: `200`
- `StartUpPosition`: `1 - CenterOwner`

- [ ] **Step 2: Add controls**

Use the Toolbox (View → Toolbox) to draw each control. Set properties in the Properties pane.

**Title label** (Label):
- `Caption`: `Ambulatory Patient Tracking`
- `Font.Bold`: `True`, `Font.Size`: `12`
- `Left`: `10`, `Top`: `12`, `Width`: `270`, `Height`: `20`
- `TextAlign`: `2 - fmTextAlignCenter`

**Email label** (Label):
- `Caption`: `Email:`
- `Left`: `20`, `Top`: `48`, `Width`: `50`, `Height`: `16`

**Email text box** (TextBox):
- `(Name)`: `txtEmail`
- `Left`: `75`, `Top`: `45`, `Width`: `195`, `Height`: `20`

**Password label** (Label):
- `Caption`: `Password:`
- `Left`: `20`, `Top`: `76`, `Width`: `50`, `Height`: `16`

**Password text box** (TextBox):
- `(Name)`: `txtPassword`
- `PasswordChar`: `*`
- `Left`: `75`, `Top`: `73`, `Width`: `195`, `Height`: `20`

**Login button** (CommandButton):
- `(Name)`: `btnLogin`
- `Caption`: `Log In`
- `Default`: `True`  ← pressing Enter triggers this button
- `Left`: `95`, `Top`: `108`, `Width`: `80`, `Height`: `24`

**Error label** (Label):
- `(Name)`: `lblError`
- `Caption`: *(empty)*
- `ForeColor`: `&H000000FF&`  (red — click the … button, set to red)
- `Visible`: `False`
- `Left`: `10`, `Top`: `140`, `Width`: `270`, `Height`: `16`
- `TextAlign`: `2 - fmTextAlignCenter`

- [ ] **Step 3: Add the code-behind**

Double-click the form background to open its code module. Replace all content with:

```vba
Option Explicit

Private Sub btnLogin_Click()
    Dim email As String
    Dim password As String
    email    = Trim(txtEmail.Text)
    password = txtPassword.Text

    If email = "" Or password = "" Then
        ShowError "Email and password are required."
        Exit Sub
    End If

    If modAuth.ValidateLogin(email, password) Then
        ' Success — show UI sheets and activate WorkQueue
        Dim ws As Worksheet
        For Each ws In ThisWorkbook.Sheets
            If Left(ws.Name, 5) <> "_data" Then
                ws.Visible = xlSheetVisible
            End If
        Next ws
        ThisWorkbook.Sheets("WorkQueue").Activate
        Unload Me
    Else
        ShowError "Invalid email or password."
        txtPassword.Text = ""
        txtPassword.SetFocus
    End If
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

Private Sub UserForm_QueryClose(Cancel As Integer, CloseMode As Integer)
    ' Clicking the X on the login form closes the workbook — there is no guest access.
    If CloseMode = vbFormControlMenu Then
        Cancel = True
        ThisWorkbook.Close SaveChanges:=False
    End If
End Sub
```

- [ ] **Step 4: Save the workbook**

`File → Save` (or `⌘S`) in Excel. Accept the macro-enabled format prompt if shown.

---

### Task 4: ThisWorkbook — Startup and Shutdown Events

**Files:**
- Edit in VBA editor: `ThisWorkbook` (existing class module in every workbook)

- [ ] **Step 1: Open ThisWorkbook module**

In the VBA editor Project Explorer (left panel), expand `AmbulatoryPatients.xlsm` → double-click `ThisWorkbook`.

- [ ] **Step 2: Replace content with**

```vba
Option Explicit

Private Sub Workbook_Open()
    ' 1. Hide all UI sheets — user must log in before seeing anything
    Dim ws As Worksheet
    For Each ws In ThisWorkbook.Sheets
        If Left(ws.Name, 5) <> "_data" Then
            ws.Visible = xlSheetHidden
        End If
    Next ws

    ' 2. First-run check: no users → show instructions, stay hidden
    Dim usersWs As Worksheet
    Set usersWs = modUtils.DataSheet("_data_users")
    If modUtils.LastDataRow(usersWs) < 2 Then
        MsgBox "First run: no user accounts exist." & vbCrLf & vbCrLf & _
               "An admin account must be created before the application can be used." & vbCrLf & _
               "This will be available in the Admin setup screen (Plan 6).", _
               vbInformation, "Ambulatory Patient Tracking — Setup Required"
        Exit Sub
    End If

    ' 3. Show login form (modal — execution blocks here until form is unloaded)
    LoginForm.Show
End Sub

Private Sub Workbook_BeforeClose(Cancel As Boolean)
    ' Clear session — never persist credentials in memory across sessions
    modAuth.Logout
End Sub
```

- [ ] **Step 3: Save the workbook**

`File → Save` (`⌘S`) in Excel.

---

### Task 5: End-to-End Validation

No new files. Manual testing only.

- [ ] **Step 1: Confirm the test user from Task 2 is still present**

In Immediate Window:
```vba
? modUtils.LastDataRow(modUtils.DataSheet("_data_users"))
```
Expected: `2` (header row + 1 data row).

If you rebuilt the workbook in Task 1 or 2, the test user row was lost (rebuild wipes the file). Re-run `SeedTestUser` from Task 2 Step 4.

- [ ] **Step 2: Close and reopen the workbook**

Close `AmbulatoryPatients.xlsm`. Reopen it from `excel/dist/`.

Expected:
- No tabs are visible during open
- LoginForm appears (modal)
- Tab bar is empty — you cannot click away from the form

- [ ] **Step 3: Test wrong credentials**

Enter `admin@test.com` / `wrongpassword` → click Log In.

Expected: red error label "Invalid email or password." Password field is cleared.

- [ ] **Step 4: Test correct credentials**

Enter `admin@test.com` / `Password1` → click Log In.

Expected:
- Form disappears
- All 4 tabs become visible: WorkQueue, Appointments, Reports, Admin
- WorkQueue is the active tab

- [ ] **Step 5: Test X button closes workbook**

Close and reopen the workbook. On the LoginForm, click the `✕` close button (top-left on Mac).

Expected: workbook closes (does not hang on the form, does not show an error).

- [ ] **Step 6: Verify session clears on close**

After a successful login in Step 4, in Immediate Window:
```vba
? modAuth.gUserId
```
Expected: `1`

Close and reopen, log in again, then:
```vba
? modAuth.IsAdmin()
```
Expected: `True`

Close without logging in (X on login form closes workbook). Reopen. Before logging in:
```vba
? modAuth.IsLoggedIn()
```
Expected: `False` (module-level variables reset on open)

- [ ] **Step 7: Commit the rebuilt workbook**

```bash
cd /Users/jgriffin/dev/ambulatory-patients
git add excel/dist/AmbulatoryPatients.xlsm
git commit -m "feat(excel): plan 2 auth — SHA-256, modAuth, LoginForm, ThisWorkbook"
```

---

## Self-Review Checklist

**Spec coverage:**
- ✅ SHA-256 hashing: `modSHA256.SHA256()` (Task 1)
- ✅ Login form: `LoginForm` with email + password (Task 3)
- ✅ Validate email + password against `_data_users` where `is_active = 1` (Task 2)
- ✅ Failed login shows error, no account lockout (Task 3 code-behind)
- ✅ Session state: `gUserId`, `gUserName`, `gUserRole` (Task 2)
- ✅ Session cleared in `Workbook_BeforeClose` (Task 4)
- ✅ On open: UI sheets hidden → login form → on success show UI + activate WorkQueue (Task 4)
- ✅ First-run: no users → skip LoginForm, show message (Task 4; AddUserForm deferred to Plan 6)
- ✅ `IsAdmin()` accessor for role check (Task 2)

**Intentional deferrals:**
- AddUserForm (first-run user creation) — Plan 6. First-run currently shows an informational message.
- Purge check on open — Plan 6.
- Admin-only UI gating — Plans 4–6 (each UI module checks `modAuth.IsAdmin()` as needed).
