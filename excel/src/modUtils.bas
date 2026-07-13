Attribute VB_Name = "modUtils"
Option Explicit

' Returns the next auto-increment ID for a data sheet.
' Uses Max over column A so the result is correct even if rows are sorted
' or deleted (e.g., after a purge). Column A holds integer IDs; row 1 is header.
Public Function NextId(ws As Worksheet) As Long
    Dim maxId As Long
    On Error Resume Next
    maxId = Application.WorksheetFunction.Max(ws.Columns(1))
    On Error GoTo 0
    NextId = maxId + 1
    If NextId <= 1 Then NextId = 1
End Function

' Returns the last occupied row number in column A.
' Returns 1 (the header row) when the sheet has no data rows.
Public Function LastDataRow(ws As Worksheet) As Long
    LastDataRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
End Function

' Returns an ISO timestamp string (yyyy-mm-dd hh:mm:ss) for the current local time.
Public Function NowISO() As String
    NowISO = Format(Now, "yyyy-mm-dd hh:mm:ss")
End Function

' Returns an ISO date string (yyyy-mm-dd) for a given Date value.
Public Function DateISO(d As Date) As String
    DateISO = Format(d, "yyyy-mm-dd")
End Function

' Returns the column index (1-based) for a header name in row 1.
' Returns 0 if the column is not found.
Public Function ColIndex(ws As Worksheet, colName As String) As Long
    Dim i As Long
    Dim lastCol As Long
    lastCol = ws.Cells(1, ws.Columns.Count).End(xlToLeft).Column
    For i = 1 To lastCol
        If ws.Cells(1, i).Value = colName Then
            ColIndex = i
            Exit Function
        End If
    Next i
    ColIndex = 0
End Function

' Gets a cell value by row index and column name.
' Returns Null if the column name is not found in row 1.
Public Function GetVal(ws As Worksheet, rowIdx As Long, colName As String) As Variant
    Dim c As Long
    c = ColIndex(ws, colName)
    If c = 0 Then
        GetVal = Null
    Else
        GetVal = ws.Cells(rowIdx, c).Value
    End If
End Function

' Sets a cell value by row index and column name.
' No-op if the column name is not found in row 1.
Public Sub SetVal(ws As Worksheet, rowIdx As Long, colName As String, val As Variant)
    Dim c As Long
    c = ColIndex(ws, colName)
    If c > 0 Then ws.Cells(rowIdx, c).Value = val
End Sub

' Finds the row number whose column-A value equals id.
' Returns 0 if not found.
Public Function FindById(ws As Worksheet, id As Long) As Long
    Dim i As Long
    Dim last As Long
    last = LastDataRow(ws)
    For i = 2 To last
        If ws.Cells(i, 1).Value = id Then
            FindById = i
            Exit Function
        End If
    Next i
    FindById = 0
End Function

' Returns a data sheet by name.
' Data sheets are xlVeryHidden and cannot be accessed via the tab bar.
Public Function DataSheet(sheetName As String) As Worksheet
    Set DataSheet = ThisWorkbook.Sheets(sheetName)
End Function

' Returns True if a value is Null, Empty, or a blank/whitespace string.
Public Function IsBlank(v As Variant) As Boolean
    If IsNull(v) Or IsEmpty(v) Then
        IsBlank = True
    Else
        IsBlank = Len(Trim(CStr(v))) = 0
    End If
End Function

' Returns a setting value from _data_settings by key.
' Returns "" if the key is not found.
Public Function GetSetting(key As String) As String
    Dim ws As Worksheet
    Dim i As Long
    Dim last As Long
    Set ws = DataSheet("_data_settings")
    last = LastDataRow(ws)
    For i = 2 To last
        If ws.Cells(i, 1).Value = key Then
            GetSetting = CStr(ws.Cells(i, 2).Value)
            Exit Function
        End If
    Next i
    GetSetting = ""
End Function

' Updates a setting value in _data_settings.
' Appends a new row if the key does not already exist.
Public Sub SetSetting(key As String, value As String)
    Dim ws As Worksheet
    Dim i As Long
    Dim last As Long
    Set ws = DataSheet("_data_settings")
    last = LastDataRow(ws)
    For i = 2 To last
        If ws.Cells(i, 1).Value = key Then
            ws.Cells(i, 2).Value = value
            Exit Sub
        End If
    Next i
    Dim newRow As Long
    newRow = IIf(last < 2, 2, last + 1)
    ws.Cells(newRow, 1).Value = key
    ws.Cells(newRow, 2).Value = value
End Sub

' Returns active _data_lov values for a category, sorted by sort_order ascending.
Public Function ActiveLovValues(category As String) As Collection
    Dim result As New Collection
    Dim ws As Worksheet: Set ws = DataSheet("_data_lov")
    Dim last As Long: last = LastDataRow(ws)
    Dim cCategory As Long: cCategory = ColIndex(ws, "category")
    Dim cValue As Long: cValue = ColIndex(ws, "value")
    Dim cActive As Long: cActive = ColIndex(ws, "is_active")
    Dim cSort As Long: cSort = ColIndex(ws, "sort_order")

    Dim values As Collection: Set values = New Collection
    Dim sorts As Collection: Set sorts = New Collection
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cCategory).Value = category And ws.Cells(i, cActive).Value = 1 Then
            values.Add CStr(ws.Cells(i, cValue).Value)
            sorts.Add CLng(ws.Cells(i, cSort).Value)
        End If
    Next i

    Dim n As Long: n = values.Count
    If n = 0 Then
        Set ActiveLovValues = result
        Exit Function
    End If
    Dim order() As Long: ReDim order(1 To n)
    For i = 1 To n: order(i) = i: Next i
    Dim j As Long, tmp As Long
    For i = 1 To n - 1
        For j = 1 To n - i
            If sorts(order(j)) > sorts(order(j + 1)) Then
                tmp = order(j): order(j) = order(j + 1): order(j + 1) = tmp
            End If
        Next j
    Next i
    For i = 1 To n
        result.Add values(order(i))
    Next i
    Set ActiveLovValues = result
End Function

' Fills a ComboBox with active _data_lov values for the given category.
Public Sub PopulateLovCombo(cbo As MSForms.ComboBox, category As String)
    Dim values As Collection: Set values = ActiveLovValues(category)
    cbo.Clear
    Dim v As Variant
    For Each v In values
        cbo.AddItem CStr(v)
    Next v
End Sub

' Returns the _data_lov row id matching category+value (case-insensitive), or 0.
Public Function LovIdForValue(category As String, value As String) As Long
    Dim ws As Worksheet: Set ws = DataSheet("_data_lov")
    Dim last As Long: last = LastDataRow(ws)
    Dim cCategory As Long: cCategory = ColIndex(ws, "category")
    Dim cValue As Long: cValue = ColIndex(ws, "value")
    Dim i As Long
    For i = 2 To last
        If ws.Cells(i, cCategory).Value = category And _
           LCase(CStr(ws.Cells(i, cValue).Value)) = LCase(value) Then
            LovIdForValue = ws.Cells(i, 1).Value
            Exit Function
        End If
    Next i
    LovIdForValue = 0
End Function

' Returns the _data_lov value string for a given row id, or "" if not found / id<=0.
Public Function LovValueForId(id As Long) As String
    If id <= 0 Then Exit Function
    Dim ws As Worksheet: Set ws = DataSheet("_data_lov")
    Dim r As Long: r = FindById(ws, id)
    If r = 0 Then Exit Function
    LovValueForId = CStr(ws.Cells(r, ColIndex(ws, "value")).Value)
End Function

' Validates a "YYYY-MM-DD" string, rejecting non-existent calendar dates
' (e.g. 2026-02-30). An empty string is valid (field is optional).
Public Function IsValidIsoDate(s As String) As Boolean
    If Trim(s) = "" Then
        IsValidIsoDate = True
        Exit Function
    End If
    If Len(s) <> 10 Then Exit Function
    If Mid(s, 5, 1) <> "-" Or Mid(s, 8, 1) <> "-" Then Exit Function
    If Not IsNumeric(Left(s, 4)) Then Exit Function
    If Not IsNumeric(Mid(s, 6, 2)) Then Exit Function
    If Not IsNumeric(Mid(s, 9, 2)) Then Exit Function
    Dim y As Long, m As Long, d As Long
    y = CLng(Left(s, 4)): m = CLng(Mid(s, 6, 2)): d = CLng(Mid(s, 9, 2))
    Dim dt As Date
    On Error Resume Next
    dt = DateSerial(y, m, d)
    IsValidIsoDate = (Err.Number = 0) And (Format(dt, "yyyy-mm-dd") = s)
    On Error GoTo 0
End Function

' Deletes a single worksheet row. Call bottom-to-top when deleting multiple
' rows in a loop so row indices don't shift under you mid-loop. Safe to use
' freely on the single-table `_data_*` sheets (nothing else shares them), but
' would risk the "would move cells in a table" error if the sheet had another
' ListObject positioned below the deleted row.
Public Sub DeleteRow(ws As Worksheet, rowIdx As Long)
    ws.Rows(rowIdx).Delete
End Sub

' Rounds half-away-from-zero to the given number of decimals. VBA's native Round()
' uses banker's rounding, which doesn't match JS Math.round() -- use this instead
' anywhere mirroring Electron business logic that calls Math.round().
Public Function RoundHalfUp(x As Double, decimals As Long) As Double
    Dim factor As Double: factor = 10 ^ decimals
    If x >= 0 Then
        RoundHalfUp = Int(x * factor + 0.5) / factor
    Else
        RoundHalfUp = -Int(-x * factor + 0.5) / factor
    End If
End Function
