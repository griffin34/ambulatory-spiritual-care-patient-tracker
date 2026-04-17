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
