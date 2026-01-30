#Requires AutoHotkey v2.0

; --- State ---
global TargetColor := ""              ; 0xRRGGBB, highlight color to click
global IsRunning := false
global ColorVariation := 20           ; color tolerance for highlight (0–255, raise if not matching)
global ConfigPath := A_ScriptDir "\Fight.ini"

; In-combat detection – area + color (like Cook cooking status: color exists in area = in combat)
global InCombatAreaX1 := 0
global InCombatAreaY1 := 0
global InCombatAreaX2 := 0
global InCombatAreaY2 := 0
global InCombatColor := ""
global InCombatVariation := 10
global InCombat := false
global LastInCombatSeen := 0
global OutOfCombatDelay := 2000      ; ms without color in area = out of combat
global CombatCheckInterval := 250   ; ms between in-combat checks
global InCombatAreaOverlayGuis := []
global InCombatCornerSize := 12

; Play area – only search/click inside this rect (0,0,0,0 = full screen)
global PlayAreaX1 := 0              ; top-left X
global PlayAreaY1 := 0              ; top-left Y
global PlayAreaX2 := 0              ; bottom-right X
global PlayAreaY2 := 0              ; bottom-right Y
global PlayAreaOverlayGuis := []    ; up to 8 small red-line windows
global CornerMarkSize := 30         ; px length of each leg of the L (play area)

; Targeting
global AttackInterval := 5000       ; ms between attack attempts when out of combat (5 seconds)
global RadiusStep := 120             ; px step when searching for color (larger = find faster)
global ClickJitter := 2            ; small ±2 px random (0 = none)
global ClickDelayMs := 35         ; ms over target before click (game needs to see hover)
global BoundsScanStep := 2        ; step when finding highlight edges (bounding box)
global BoundsMaxDist := 50       ; max px from first pixel when finding edges (keeps one NPC)

; Run duration (0 = unlimited)
global RunDurationMinutes := 0
global RunStartTime := 0

CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

; --- Load config ---
LoadConfig() {
    global TargetColor, ConfigPath
    global InCombatAreaX1, InCombatAreaY1, InCombatAreaX2, InCombatAreaY2, InCombatColor
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global RunDurationMinutes
    try {
        if FileExist(ConfigPath) {
            c := IniRead(ConfigPath, "Settings", "Color", "")
            if (c != "")
                TargetColor := "0x" c
            InCombatAreaX1 := Integer(IniRead(ConfigPath, "InCombat", "X1", "0"))
            InCombatAreaY1 := Integer(IniRead(ConfigPath, "InCombat", "Y1", "0"))
            InCombatAreaX2 := Integer(IniRead(ConfigPath, "InCombat", "X2", "0"))
            InCombatAreaY2 := Integer(IniRead(ConfigPath, "InCombat", "Y2", "0"))
            ic := IniRead(ConfigPath, "InCombat", "Color", "")
            if (ic != "")
                InCombatColor := "0x" ic
            PlayAreaX1 := Integer(IniRead(ConfigPath, "PlayArea", "X1", "0"))
            PlayAreaY1 := Integer(IniRead(ConfigPath, "PlayArea", "Y1", "0"))
            PlayAreaX2 := Integer(IniRead(ConfigPath, "PlayArea", "X2", "0"))
            PlayAreaY2 := Integer(IniRead(ConfigPath, "PlayArea", "Y2", "0"))
            RunDurationMinutes := Integer(IniRead(ConfigPath, "Settings", "RunDurationMinutes", "0"))
            if (RunDurationMinutes < 0)
                RunDurationMinutes := 0
        }
    } catch {
        TargetColor := ""
    }
}
LoadConfig()

; --- Status GUI (Cook-style: dark theme, Action/Debug Edit, config checkmarks) ---
global StatusGui := ""
global FightStatusAction := ""
global FightDebugLine := ""

SetGuiText(ctrl, str) {
    try
        ctrl.Text := str
    catch {
        try
            ctrl.Value := str
        catch {
        }
    }
}

BuildStatusGui() {
    global StatusGui, RunDurationMinutes
    StatusGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow")
    StatusGui.BackColor := "1e1e1e"
    StatusGui.SetFont("s9 cD0D0D0", "Segoe UI")
    StatusGui.MarginX := 12
    StatusGui.MarginY := 6
    StatusGui.Add("Text", "Section", "Auto Fighter")
    StatusGui.Add("Text", "vStatusText xs", "Paused  |  Out of combat")
    StatusGui.Add("Edit", "vActionText xs ReadOnly r1 w470 Background1e1e1e", "Action: —")
    StatusGui["ActionText"].SetFont("cA0D0A0")
    StatusGui.Add("Edit", "vDebugText xs ReadOnly r1 w470 Background1e1e1e", "Debug: —")
    StatusGui["DebugText"].SetFont("c808080")
    StatusGui.Add("Text", "vTimerText xs", "Time left: --")
    StatusGui.Add("Text", "xs Section", "Run (min):")
    StatusGui.Add("Edit", "vRunMinutes x+6 yp-2 w44", String(RunDurationMinutes))
    StatusGui["RunMinutes"].SetFont("cBlack")
    StatusGui.Add("Text", "x+6 yp+2", "0 = unlimited")
    StatusGui.Add("Text", "xs Section y+8", "Configuration:")
    StatusGui.Add("Text", "vTargetRow xs y+2", "[—] Target color     Ctrl+Shift+C")
    StatusGui.Add("Text", "vPlayAreaRow xs", "[—] Play area        Ctrl+Shift+B (TL)  Ctrl+Shift+N (BR)")
    StatusGui.Add("Text", "vInCombatRow xs", "[—] In-combat       Ctrl+Shift+E (TL)  Ctrl+Shift+R (BR)  Ctrl+Shift+V (color)")
    StatusGui.Add("Text", "xs y+8", "Hotkeys:")
    StatusGui.Add("Text", "vHotkeysRow xs y+2", "Start Ctrl+Shift+Q  |  Pause Ctrl+Shift+W  |  Exit Ctrl+Shift+X")
    StatusGui.Show("x" (A_ScreenWidth - 520) " y10 NoActivate w500")
}

UpdateStatusGui() {
    global StatusGui, IsRunning, RunDurationMinutes, RunStartTime, ConfigPath
    global InCombat, FightStatusAction, FightDebugLine
    global TargetColor, PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global InCombatAreaX1, InCombatAreaY1, InCombatAreaX2, InCombatAreaY2, InCombatColor
    if !StatusGui
        return
    try {
        runMin := Integer(StatusGui["RunMinutes"].Value)
        if (runMin < 0) runMin := 0
        if (IsRunning && runMin > 0 && RunStartTime > 0) {
            elapsed := A_TickCount - RunStartTime
            if (elapsed >= runMin * 60000) {
                PauseClicker()
                ToolTip("Run duration reached (" runMin " min).")
                SetTimer(() => ToolTip(), 3000)
                return
            }
            rem := (runMin * 60000) - elapsed
            sec := Max(0, Round(rem / 1000))
            SetGuiText(StatusGui["TimerText"], "Time left: " (sec // 60) ":" (Format("{:02}", Mod(sec, 60))))
        } else
            SetGuiText(StatusGui["TimerText"], "Time left: --")
    } catch {
        SetGuiText(StatusGui["TimerText"], "Time left: --")
    }
    runTxt := IsRunning ? "Running" : "Paused"
    combatTxt := InCombat ? "In combat" : "Out of combat"
    SetGuiText(StatusGui["StatusText"], runTxt "  |  " combatTxt)
    actionTxt := FightStatusAction != "" ? FightStatusAction : (IsRunning ? (InCombat ? "In combat — waiting" : "Searching for target") : "Idle")
    debugTxt := FightDebugLine != "" ? FightDebugLine : ("InCombat=" (InCombat ? "1" : "0"))
    StatusGui["ActionText"].Value := "Action: " actionTxt
    StatusGui["DebugText"].Value := "Debug: " debugTxt
    ; Config checkmarks
    tSet := (TargetColor != "")
    pSet := (PlayAreaX2 > PlayAreaX1 && PlayAreaY2 > PlayAreaY1)
    iSet := (InCombatAreaX2 > InCombatAreaX1 && InCombatAreaY2 > InCombatAreaY1 && InCombatColor != "")
    SetGuiText(StatusGui["TargetRow"], "[" (tSet ? "✓" : "—") "] Target color     Ctrl+Shift+C")
    SetGuiText(StatusGui["PlayAreaRow"], "[" (pSet ? "✓" : "—") "] Play area        Ctrl+Shift+B (TL)  Ctrl+Shift+N (BR)")
    SetGuiText(StatusGui["InCombatRow"], "[" (iSet ? "✓" : "—") "] In-combat       Ctrl+Shift+E (TL)  Ctrl+Shift+R (BR)  Ctrl+Shift+V (color)")
}

; Build and show status window; refresh every 500 ms
BuildStatusGui()
BuildPlayAreaOverlay()
BuildInCombatAreaOverlay()
SetTimer(UpdateStatusGui, 500)

; --- Hotkeys ---
^+q:: StartClicker()
^+w:: PauseClicker()
^+x:: ExitClicker()
^+c:: SetColorUnderCursor()          ; set highlight color (monster)
^+e:: SetInCombatAreaTL()            ; set in-combat area top-left
^+r:: SetInCombatAreaBR()            ; set in-combat area bottom-right
^+v:: SetInCombatColor()             ; set in-combat color (color in area = in combat)
^+b:: SetPlayAreaTopLeft()           ; set play area top-left corner
^+n:: SetPlayAreaBottomRight()      ; set play area bottom-right corner

; --- Start ---
StartClicker() {
    global TargetColor, IsRunning, RunDurationMinutes, RunStartTime, StatusGui, ConfigPath
    if (TargetColor = "") {
        MsgBox("No highlight color set. Move cursor over the monster highlight and press Ctrl+Shift+C.", "ClickColor", "Icon!")
        return
    }
    if IsRunning
        return
    ; Read run duration from UI and save
    try {
        RunDurationMinutes := Integer(StatusGui["RunMinutes"].Value)
        if (RunDurationMinutes < 0)
            RunDurationMinutes := 0
        IniWrite(String(RunDurationMinutes), ConfigPath, "Settings", "RunDurationMinutes")
    } catch
        {}
    RunStartTime := A_TickCount
    IsRunning := true
    SetTimer(UpdateInCombatState, CombatCheckInterval)
    SetTimer(TryAttackWhenOutOfCombat, AttackInterval)
    ToolTip("Auto fighter: Running" (RunDurationMinutes > 0 ? " (" RunDurationMinutes " min)" : ""))
    SetTimer(() => ToolTip(), 2000)
}

; --- Pause (resets run timer so next start gets full duration again) ---
PauseClicker() {
    global IsRunning, RunStartTime
    IsRunning := false
    RunStartTime := 0   ; reset so next start begins a fresh run
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

; --- Set in-combat area (top-left and bottom-right) and color; color in area = in combat ---
SetInCombatAreaTL() {
    global InCombatAreaX1, InCombatAreaY1, ConfigPath
    MouseGetPos(&mx, &my)
    InCombatAreaX1 := mx
    InCombatAreaY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "InCombat", "X1")
        IniWrite(String(my), ConfigPath, "InCombat", "Y1")
    } catch {
    }
    ToolTip("In-combat area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildInCombatAreaOverlay()
}

SetInCombatAreaBR() {
    global InCombatAreaX2, InCombatAreaY2, ConfigPath
    MouseGetPos(&mx, &my)
    InCombatAreaX2 := mx
    InCombatAreaY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "InCombat", "X2")
        IniWrite(String(my), ConfigPath, "InCombat", "Y2")
    } catch {
    }
    ToolTip("In-combat area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildInCombatAreaOverlay()
}

SetInCombatColor() {
    global InCombatColor, ConfigPath
    MouseGetPos(&mx, &my)
    InCombatColor := PixelGetColor(mx, my, "RGB")
    try IniWrite(SubStr(InCombatColor, 3), ConfigPath, "InCombat", "Color")
    catch {
    }
    ToolTip("In-combat color set at " mx "," my)
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
    BuildPlayAreaOverlay()
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
    BuildPlayAreaOverlay()
}

; --- Draw red L-shaped corner marks on screen for play area (8 small red windows, no TransColor) ---
BuildPlayAreaOverlay() {
    global PlayAreaOverlayGuis, PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2, CornerMarkSize
    for overlayWin in PlayAreaOverlayGuis {
        try
            overlayWin.Destroy()
        catch
            {}
    }
    PlayAreaOverlayGuis := []
    if (PlayAreaX2 <= PlayAreaX1 || PlayAreaY2 <= PlayAreaY1)
        return
    L := CornerMarkSize
    W := 4
    ; Each line is its own small always-on-top red window (click-through), so they stay visible
    line(x, y, w, h) {
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
        g.BackColor := "FF0000"
        g.Show("x" x " y" y " w" w " h" h " NoActivate")
        return g
    }
    ; Top-left L
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY1, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY1, L, W))
    ; Top-right L
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - W, PlayAreaY1, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - L, PlayAreaY1, L, W))
    ; Bottom-left L
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY2 - L, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY2 - W, L, W))
    ; Bottom-right L
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - W, PlayAreaY2 - L, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - L, PlayAreaY2 - W, L, W))
}

; --- Draw yellow L-shaped corners for in-combat area ---
BuildInCombatAreaOverlay() {
    global InCombatAreaOverlayGuis, InCombatAreaX1, InCombatAreaY1, InCombatAreaX2, InCombatAreaY2, InCombatCornerSize
    for g in InCombatAreaOverlayGuis {
        try
            g.Destroy()
        catch {
        }
    }
    InCombatAreaOverlayGuis := []
    if (InCombatAreaX2 <= InCombatAreaX1 || InCombatAreaY2 <= InCombatAreaY1)
        return
    L := InCombatCornerSize
    W := 2
    line(x, y, w, h) {
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
        g.BackColor := "FFFF00"
        g.Show("x" x " y" y " w" w " h" h " NoActivate")
        return g
    }
    InCombatAreaOverlayGuis.Push(line(InCombatAreaX1, InCombatAreaY1, W, L))
    InCombatAreaOverlayGuis.Push(line(InCombatAreaX1, InCombatAreaY1, L, W))
    InCombatAreaOverlayGuis.Push(line(InCombatAreaX2 - W, InCombatAreaY1, W, L))
    InCombatAreaOverlayGuis.Push(line(InCombatAreaX2 - L, InCombatAreaY1, L, W))
    InCombatAreaOverlayGuis.Push(line(InCombatAreaX1, InCombatAreaY2 - L, W, L))
    InCombatAreaOverlayGuis.Push(line(InCombatAreaX1, InCombatAreaY2 - W, L, W))
    InCombatAreaOverlayGuis.Push(line(InCombatAreaX2 - W, InCombatAreaY2 - L, W, L))
    InCombatAreaOverlayGuis.Push(line(InCombatAreaX2 - L, InCombatAreaY2 - W, L, W))
}

; True if target color exists anywhere in the area (PixelSearch with variation)
ColorInArea(x1, y1, x2, y2, targetColor, variation) {
    try
        return PixelSearch(&ox, &oy, x1, y1, x2, y2, Integer(targetColor), variation)
    catch
        return false
}

; --- In combat = color exists in the defined area (like Cook cooking status) ---
UpdateInCombatState() {
    global InCombat, LastInCombatSeen, OutOfCombatDelay, FightDebugLine
    global InCombatAreaX1, InCombatAreaY1, InCombatAreaX2, InCombatAreaY2, InCombatColor, InCombatVariation
    if (InCombatColor = "" || InCombatAreaX2 <= InCombatAreaX1 || InCombatAreaY2 <= InCombatAreaY1)
        return
    if (ColorInArea(InCombatAreaX1, InCombatAreaY1, InCombatAreaX2, InCombatAreaY2, InCombatColor, InCombatVariation)) {
        InCombat := true
        LastInCombatSeen := A_TickCount
    } else if (A_TickCount - LastInCombatSeen > OutOfCombatDelay) {
        InCombat := false
    }
    FightDebugLine := "InCombat=" (InCombat ? "1" : "0") " LastSeen=" (A_TickCount - LastInCombatSeen) "ms"
}

; --- When out of combat: find color and click (only inside play area, kept fast) ---
TryAttackWhenOutOfCombat() {
    global InCombat, TargetColor, ColorVariation, FightStatusAction
    global RadiusStep, ClickJitter, ClickDelayMs, BoundsScanStep, BoundsMaxDist
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    if InCombat || (TargetColor = "")
        return
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
    ; Find first matching pixel from center outward
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
    if (radius > maxR) {
        FightStatusAction := "Searching for target"
        return
    }
    ; Bounding box: from first pixel, find edges of same-colored region (OSRS AHK style – click inside the highlight)
    minX := foundX
    maxX := foundX
    minY := foundY
    maxY := foundY
    limitL := Max(paX1, foundX - BoundsMaxDist)
    limitR := Min(paX2, foundX + BoundsMaxDist)
    limitT := Max(paY1, foundY - BoundsMaxDist)
    limitB := Min(paY2, foundY + BoundsMaxDist)
    x := foundX - BoundsScanStep
    while (x >= limitL) {
        try {
            if ColorsMatch(PixelGetColor(x, foundY, "RGB"), TargetColor, ColorVariation)
                minX := x
            else
                break
        } catch
            break
        x -= BoundsScanStep
    }
    x := foundX + BoundsScanStep
    while (x <= limitR) {
        try {
            if ColorsMatch(PixelGetColor(x, foundY, "RGB"), TargetColor, ColorVariation)
                maxX := x
            else
                break
        } catch
            break
        x += BoundsScanStep
    }
    y := foundY - BoundsScanStep
    while (y >= limitT) {
        try {
            if ColorsMatch(PixelGetColor(foundX, y, "RGB"), TargetColor, ColorVariation)
                minY := y
            else
                break
        } catch
            break
        y -= BoundsScanStep
    }
    y := foundY + BoundsScanStep
    while (y <= limitB) {
        try {
            if ColorsMatch(PixelGetColor(foundX, y, "RGB"), TargetColor, ColorVariation)
                maxY := y
            else
                break
        } catch
            break
        y += BoundsScanStep
    }
    ; Click center of bounding box (guaranteed inside the highlight, not through it)
    clickX := (minX + maxX) // 2
    clickY := (minY + maxY) // 2
    if (ClickJitter > 0) {
        clickX += Random(-ClickJitter, ClickJitter)
        clickY += Random(-ClickJitter, ClickJitter)
    }
    clickX := Max(paX1, Min(paX2, clickX))
    clickY := Max(paY1, Min(paY2, clickY))
    MouseMove(clickX, clickY)
    if (ClickDelayMs > 0)
        Sleep(ClickDelayMs)
    Click()
    FightStatusAction := "Clicked target"
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
