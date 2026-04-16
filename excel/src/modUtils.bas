Attribute VB_Name = "modUtils"
Option Explicit

' Returns the next auto-increment ID for a data sheet.
' Column A holds integer IDs; row 1 is the header row.
Public Function NextId(ws As Worksheet) As Long
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
    If lastRow <= 1 Then
        NextId = 1
    Else
        NextId = CLng(ws.Cells(lastRow, 1).Value) + 1
    End If
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
Public Function ColIndex(ws As Worksheet, colName As String) As Integer
    Dim i As Integer
    For i = 1 To 50
        If ws.Cells(1, i).Value = "" Then Exit For
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
    Dim c As Integer
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
    Dim c As Integer
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
