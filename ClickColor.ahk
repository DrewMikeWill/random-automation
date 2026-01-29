#Requires AutoHotkey v2.0

; --- State ---
global TargetColor := ""              ; 0xRRGGBB, highlight color to click
global IsRunning := false
global ColorVariation := 20           ; color tolerance for highlight (0–255, raise if not matching)
global ConfigPath := A_ScriptDir "\ClickColor.ini"

; In-combat detection – BOTH indicators must be present to be in combat
global InCombatCheckX := 0
global InCombatCheckY := 0
global InCombatCheckColor := ""
global InCombatCheck2X := 0
global InCombatCheck2Y := 0
global InCombatCheck2Color := ""
global InCombatCheckVariation := 10   ; tolerance for indicator colors
global InCombatCheckBox := 25         ; check ±25 px around each set point
global InCombat := false
global LastInCombatSeen := 0
global OutOfCombatDelay := 2000      ; ms without both indicators = out of combat

; Play area – only search/click inside this rect (0,0,0,0 = full screen)
global PlayAreaX1 := 0              ; top-left X
global PlayAreaY1 := 0              ; top-left Y
global PlayAreaX2 := 0              ; bottom-right X
global PlayAreaY2 := 0              ; bottom-right Y

; Targeting (keep blob small/coarse so each attempt is fast – was 70/2 = 20+ sec per click)
global BlobScanSize := 24            ; small box around first hit for centroid (px)
global BlobScanStep := 4             ; coarse step = fewer PixelGetColor calls
global MinBlobPixels := 3            ; else click first pixel found
global AttackInterval := 5000       ; ms between attack attempts when out of combat (5 seconds)
global RadiusStep := 120             ; px step when searching for color (larger = find faster)
global InwardOffset := 15           ; nudge click this many px toward play-area center (stops "clicking through" NPCs)

CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

; --- Load config ---
LoadConfig() {
    global TargetColor, ConfigPath
    global InCombatCheckX, InCombatCheckY, InCombatCheckColor, InCombatCheckBox
    global InCombatCheck2X, InCombatCheck2Y, InCombatCheck2Color
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    try {
        if FileExist(ConfigPath) {
            c := IniRead(ConfigPath, "Settings", "Color", "")
            if (c != "")
                TargetColor := "0x" c
            InCombatCheckX := Integer(IniRead(ConfigPath, "InCombat", "X", "0"))
            InCombatCheckY := Integer(IniRead(ConfigPath, "InCombat", "Y", "0"))
            ic := IniRead(ConfigPath, "InCombat", "Color", "")
            if (ic != "")
                InCombatCheckColor := "0x" ic
            ib := IniRead(ConfigPath, "InCombat", "Box", "")
            if (ib != "")
                InCombatCheckBox := Integer(ib)
            InCombatCheck2X := Integer(IniRead(ConfigPath, "InCombat2", "X", "0"))
            InCombatCheck2Y := Integer(IniRead(ConfigPath, "InCombat2", "Y", "0"))
            ic2 := IniRead(ConfigPath, "InCombat2", "Color", "")
            if (ic2 != "")
                InCombatCheck2Color := "0x" ic2
            PlayAreaX1 := Integer(IniRead(ConfigPath, "PlayArea", "X1", "0"))
            PlayAreaY1 := Integer(IniRead(ConfigPath, "PlayArea", "Y1", "0"))
            PlayAreaX2 := Integer(IniRead(ConfigPath, "PlayArea", "X2", "0"))
            PlayAreaY2 := Integer(IniRead(ConfigPath, "PlayArea", "Y2", "0"))
        }
    } catch {
        TargetColor := ""
    }
}
LoadConfig()

; --- Hotkeys ---
^+q:: StartClicker()
^+w:: PauseClicker()
^+x:: ExitClicker()
^+c:: SetColorUnderCursor()          ; set highlight color (monster)
^+e:: SetInCombatCheck()             ; set in-combat indicator 1 (cursor position + color)
^+r:: SetInCombatCheck2()            ; set in-combat indicator 2 (both must be present)
^+b:: SetPlayAreaTopLeft()           ; set play area top-left corner
^+n:: SetPlayAreaBottomRight()      ; set play area bottom-right corner

; --- Start ---
StartClicker() {
    global TargetColor, IsRunning
    if (TargetColor = "") {
        MsgBox("No highlight color set. Move cursor over the monster highlight and press Ctrl+Shift+C.", "ClickColor", "Icon!")
        return
    }
    if IsRunning
        return
    IsRunning := true
    SetTimer(UpdateInCombatState, 500)
    SetTimer(TryAttackWhenOutOfCombat, AttackInterval)
    ToolTip("Auto fighter: Running")
    SetTimer(() => ToolTip(), 2000)
}

; --- Pause ---
PauseClicker() {
    global IsRunning
    IsRunning := false
    SetTimer(UpdateInCombatState, 0)
    SetTimer(TryAttackWhenOutOfCombat, 0)
    ToolTip("Auto fighter: Paused")
    SetTimer(() => ToolTip(), 2000)
}

; --- Quit ---
ExitClicker() {
    global IsRunning
    IsRunning := false
    SetTimer(UpdateInCombatState, 0)
    SetTimer(TryAttackWhenOutOfCombat, 0)
    ToolTip()
    ExitApp()
}

; --- Set highlight color (monster) ---
SetColorUnderCursor() {
    global TargetColor, ConfigPath
    MouseGetPos(&mx, &my)
    TargetColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(TargetColor, 3), ConfigPath, "Settings", "Color")
    catch
        {}  ; ignore write error
    ToolTip("Highlight color set: " TargetColor)
    SetTimer(() => ToolTip(), 2000)
}

; --- Set in-combat indicator 1 ---
SetInCombatCheck() {
    global InCombatCheckX, InCombatCheckY, InCombatCheckColor, ConfigPath, InCombatCheckBox
    MouseGetPos(&mx, &my)
    InCombatCheckX := mx
    InCombatCheckY := my
    InCombatCheckColor := PixelGetColor(mx, my, "RGB")
    try {
        IniWrite(SubStr(InCombatCheckColor, 3), ConfigPath, "InCombat", "Color")
        IniWrite(String(mx), ConfigPath, "InCombat", "X")
        IniWrite(String(my), ConfigPath, "InCombat", "Y")
        IniWrite(String(InCombatCheckBox), ConfigPath, "InCombat", "Box")
    } catch
        {}  ; ignore write error
    ToolTip("Combat indicator 1 set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

; --- Set in-combat indicator 2 (both 1 and 2 must be present = in combat) ---
SetInCombatCheck2() {
    global InCombatCheck2X, InCombatCheck2Y, InCombatCheck2Color, ConfigPath, InCombatCheckBox
    MouseGetPos(&mx, &my)
    InCombatCheck2X := mx
    InCombatCheck2Y := my
    InCombatCheck2Color := PixelGetColor(mx, my, "RGB")
    try {
        IniWrite(SubStr(InCombatCheck2Color, 3), ConfigPath, "InCombat2", "Color")
        IniWrite(String(mx), ConfigPath, "InCombat2", "X")
        IniWrite(String(my), ConfigPath, "InCombat2", "Y")
    } catch
        {}  ; ignore write error
    ToolTip("Combat indicator 2 set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

; --- Set play area (only search/click inside this rect) ---
SetPlayAreaTopLeft() {
    global PlayAreaX1, PlayAreaY1, ConfigPath
    MouseGetPos(&mx, &my)
    PlayAreaX1 := mx
    PlayAreaY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "PlayArea", "X1")
        IniWrite(String(my), ConfigPath, "PlayArea", "Y1")
    } catch
        {}
    ToolTip("Play area TOP-LEFT set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetPlayAreaBottomRight() {
    global PlayAreaX2, PlayAreaY2, ConfigPath
    MouseGetPos(&mx, &my)
    PlayAreaX2 := mx
    PlayAreaY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "PlayArea", "X2")
        IniWrite(String(my), ConfigPath, "PlayArea", "Y2")
    } catch
        {}
    ToolTip("Play area BOTTOM-RIGHT set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

; --- Every 500 ms: in combat only when BOTH exact pixels match the set colors ---
; Only checks the exact coordinates you set (Ctrl+Shift+E and Ctrl+Shift+R) – no search box.
UpdateInCombatState() {
    global InCombat, LastInCombatSeen, OutOfCombatDelay
    global InCombatCheckX, InCombatCheckY, InCombatCheckColor
    global InCombatCheck2X, InCombatCheck2Y, InCombatCheck2Color
    global InCombatCheckVariation
    if (InCombatCheckColor = "" || InCombatCheck2Color = "")
        return
    ; Exact pixel at indicator 1
    try
        c1 := PixelGetColor(InCombatCheckX, InCombatCheckY, "RGB")
    catch
        c1 := 0
    ; Exact pixel at indicator 2
    try
        c2 := PixelGetColor(InCombatCheck2X, InCombatCheck2Y, "RGB")
    catch
        c2 := 0
    match1 := ColorsMatch(c1, InCombatCheckColor, InCombatCheckVariation)
    match2 := ColorsMatch(c2, InCombatCheck2Color, InCombatCheckVariation)
    if (match1 && match2) {
        InCombat := true
        LastInCombatSeen := A_TickCount
    } else if (A_TickCount - LastInCombatSeen > OutOfCombatDelay) {
        InCombat := false
    }
}

; --- When out of combat: find color and click (only inside play area, kept fast) ---
TryAttackWhenOutOfCombat() {
    global InCombat, TargetColor, ColorVariation
    global BlobScanSize, BlobScanStep, MinBlobPixels, RadiusStep, InwardOffset
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    if InCombat || (TargetColor = "")
        return
    ; Use play area if set, else full screen
    paX1 := PlayAreaX1
    paY1 := PlayAreaY1
    paX2 := PlayAreaX2
    paY2 := PlayAreaY2
    if (paX2 <= paX1 || paY2 <= paY1) {
        paX1 := 0
        paY1 := 0
        paX2 := A_ScreenWidth
        paY2 := A_ScreenHeight
    }
    cx := (paX1 + paX2) // 2
    cy := (paY1 + paY2) // 2
    ; Find first matching pixel from center outward (larger step = fewer slow PixelSearch calls)
    radius := 0
    maxR := Max(paX2 - paX1, paY2 - paY1) // 2 + RadiusStep
    foundX := 0
    foundY := 0
    while (radius <= maxR) {
        x1 := Max(paX1, cx - radius)
        y1 := Max(paY1, cy - radius)
        x2 := Min(paX2, cx + radius)
        y2 := Min(paY2, cy + radius)
        if PixelSearch(&foundX, &foundY, x1, y1, x2, y2, Integer(TargetColor), ColorVariation) {
            break
        }
        radius += RadiusStep
    }
    if (radius > maxR)
        return
    ; Small fast blob scan for centroid (24x24 box, step 4 = ~49 PixelGetColor calls only)
    bx1 := Max(paX1, foundX - BlobScanSize)
    by1 := Max(paY1, foundY - BlobScanSize)
    bx2 := Min(paX2, foundX + BlobScanSize)
    by2 := Min(paY2, foundY + BlobScanSize)
    sumX := 0
    sumY := 0
    count := 0
    y := by1
    while (y <= by2) {
        x := bx1
        while (x <= bx2) {
            try {
                c := PixelGetColor(x, y, "RGB")
                if ColorsMatch(c, TargetColor, ColorVariation) {
                    sumX += x
                    sumY += y
                    count++
                }
            } catch
                continue
            x += BlobScanStep
        }
        y += BlobScanStep
    }
    if (count >= MinBlobPixels) {
        clickX := sumX // count
        clickY := sumY // count
    } else {
        clickX := foundX
        clickY := foundY
    }
    ; Nudge click toward play-area center so it lands on NPC body, not through the outline
    centerX := (paX1 + paX2) // 2
    centerY := (paY1 + paY2) // 2
    dx := centerX - clickX
    dy := centerY - clickY
    len := Sqrt(dx*dx + dy*dy)
    if (len > 0) {
        nudge := Min(InwardOffset, len)
        clickX += Round(dx * nudge / len)
        clickY += Round(dy * nudge / len)
    }
    Click(clickX, clickY)
}

; Compare two 0xRRGGBB colors within variation per channel
ColorsMatch(c1, c2, variation) {
    c1 := Integer(c1)
    c2 := Integer(c2)
    r1 := (c1 >> 16) & 0xFF
    g1 := (c1 >> 8) & 0xFF
    b1 := c1 & 0xFF
    r2 := (c2 >> 16) & 0xFF
    g2 := (c2 >> 8) & 0xFF
    b2 := c2 & 0xFF
    return (Abs(r1 - r2) <= variation && Abs(g1 - g2) <= variation && Abs(b1 - b2) <= variation)
}
