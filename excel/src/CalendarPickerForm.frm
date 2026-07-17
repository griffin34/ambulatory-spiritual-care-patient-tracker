VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} CalendarPickerForm 
   Caption         =   "Select Date"
   ClientHeight    =   3840
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   3984
   OleObjectBlob   =   "CalendarPickerForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "CalendarPickerForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Public SelectedDate As String   ' ISO "YYYY-MM-DD"; "" if the user cancelled
Public InitialDate As String    ' set by caller before .Show (optional)

Private mYear As Integer
Private mMonth As Integer
Private mDayHandlers As Collection   ' clsDayBtn instances -- keeps their WithEvents alive

Private Sub UserForm_Initialize()
    ' Only the one-time control creation belongs here -- BuildGrid must run
    ' exactly once per instance. InitialDate is read in UserForm_Activate
    ' instead (see the comment there for why).
    BuildGrid
End Sub

' Reading InitialDate has to happen here, not UserForm_Initialize --
' Initialize fires the moment the caller's very first reference to this
' predeclared instance is evaluated (e.g. "CalendarPickerForm.InitialDate = x"
' instantiates the object *before* performing that assignment), so
' InitialDate would still be "" at that point. UserForm_Activate fires on
' .Show, safely after the caller has already finished setting InitialDate.
Private Sub UserForm_Activate()
    Dim baseDate As Date
    If Trim(InitialDate) <> "" And modUtils.IsValidIsoDate(Trim(InitialDate)) Then
        baseDate = CDate(InitialDate)
    Else
        baseDate = Date
    End If
    mYear = Year(baseDate)
    mMonth = Month(baseDate)
    RenderMonth
End Sub

' Creates the 6x7 day-button grid at runtime -- a UserForm can add controls
' to itself while running (Me.Controls.Add), so the grid doesn't need to be
' laid out by hand at design time.
Private Sub BuildGrid()
    Set mDayHandlers = New Collection
    Dim r As Integer, c As Integer, idx As Integer
    Dim btn As MSForms.CommandButton
    Dim handler As clsDayBtn
    idx = 0
    For r = 0 To 5
        For c = 0 To 6
            idx = idx + 1
            Set btn = Me.Controls.Add("Forms.CommandButton.1", "btnCalDay" & idx, True)
            btn.Left = 8 + c * 27
            btn.Top = 48 + r * 24
            btn.Width = 25
            btn.Height = 20
            btn.Caption = ""
            btn.Visible = False
            Set handler = New clsDayBtn
            Set handler.btn = btn
            Set handler.Owner = Me
            mDayHandlers.Add handler
        Next c
    Next r
End Sub

Private Sub RenderMonth()
    lblMonthYear.Caption = Format(DateSerial(mYear, mMonth, 1), "mmmm yyyy")
    Dim startWeekday As Integer: startWeekday = Weekday(DateSerial(mYear, mMonth, 1)) ' 1=Sunday
    Dim daysInMonth As Integer: daysInMonth = Day(DateSerial(mYear, mMonth + 1, 0))

    Dim i As Integer, dayNum As Integer
    dayNum = 1 - (startWeekday - 1)
    For i = 1 To mDayHandlers.Count
        Dim h As clsDayBtn: Set h = mDayHandlers(i)
        If dayNum >= 1 And dayNum <= daysInMonth Then
            h.btn.Caption = CStr(dayNum)
            h.DayValue = dayNum
            h.btn.Visible = True
        Else
            h.btn.Caption = ""
            h.DayValue = 0
            h.btn.Visible = False
        End If
        dayNum = dayNum + 1
    Next i
    ' Runtime-added CommandButtons don't reliably accept clicks until the form
    ' repaints after being (re)rendered -- confirmed by testing.
    Me.Repaint
End Sub

Public Sub NotifyDaySelected(d As Integer)
    SelectedDate = Format(DateSerial(mYear, mMonth, d), "yyyy-mm-dd")
    ' Hide, NOT Unload -- this is the predeclared default instance
    ' (CalendarPickerForm), and Unload destroys it outright. The caller reads
    ' SelectedDate from CalendarPickerForm right after .Show returns; if the
    ' instance were already destroyed, that reference would silently create a
    ' BRAND NEW instance, resetting SelectedDate back to "" before the caller
    ' ever sees it. The caller unloads it explicitly once done reading.
    Me.Hide
End Sub

Private Sub btnPrev_Click()
    mMonth = mMonth - 1
    If mMonth < 1 Then
        mMonth = 12
        mYear = mYear - 1
    End If
    RenderMonth
End Sub

Private Sub btnNext_Click()
    mMonth = mMonth + 1
    If mMonth > 12 Then
        mMonth = 1
        mYear = mYear + 1
    End If
    RenderMonth
End Sub

Private Sub btnCancel_Click()
    SelectedDate = ""
    Me.Hide
End Sub

