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
global CombatCheckInterval := 250   ; ms between in-combat checks (smaller = more responsive)

; Optional: combat = drastic change in watch region vs previous check; no drastic change for 3s = out of combat
global WatchRegionX1 := 0            ; top-left of area to watch (set with Ctrl+Shift+Y / U)
global WatchRegionY1 := 0
global WatchRegionX2 := 0            ; bottom-right
global WatchRegionY2 := 0
global LastSample := Map()          ; previous frame's colors (compared each tick, no fixed baseline)
global WatchSampleStep := 6         ; sample every N pixels
global ChangePctThreshold := 0.05     ; this fraction of pixels must change drastically = in combat (e.g. 5%)
global DrasticChangeThreshold := 25 ; per-channel; pixel "drastically changed" if diff > this (ignores small wobble)
global ChangeDetectionOutDelay := 3000 ; ms with no drastic change = out of combat (3 seconds)

; Play area – only search/click inside this rect (0,0,0,0 = full screen)
global PlayAreaX1 := 0              ; top-left X
global PlayAreaY1 := 0              ; top-left Y
global PlayAreaX2 := 0              ; bottom-right X
global PlayAreaY2 := 0              ; bottom-right Y
global PlayAreaOverlayGuis := []    ; up to 8 small red-line windows
global CornerMarkSize := 30         ; px length of each leg of the L (play area)
global WatchRegionOverlayGuis := [] ; up to 8 small yellow-line windows (combat check area)
global WatchCornerMarkSize := 12   ; px length of each leg (smaller than play area)

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
    global InCombatCheckX, InCombatCheckY, InCombatCheckColor, InCombatCheckBox
    global InCombatCheck2X, InCombatCheck2Y, InCombatCheck2Color
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global WatchRegionX1, WatchRegionY1, WatchRegionX2, WatchRegionY2
    global RunDurationMinutes
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
            WatchRegionX1 := Integer(IniRead(ConfigPath, "WatchRegion", "X1", "0"))
            WatchRegionY1 := Integer(IniRead(ConfigPath, "WatchRegion", "Y1", "0"))
            WatchRegionX2 := Integer(IniRead(ConfigPath, "WatchRegion", "X2", "0"))
            WatchRegionY2 := Integer(IniRead(ConfigPath, "WatchRegion", "Y2", "0"))
            RunDurationMinutes := Integer(IniRead(ConfigPath, "Settings", "RunDurationMinutes", "0"))
            if (RunDurationMinutes < 0)
                RunDurationMinutes := 0
        }
    } catch {
        TargetColor := ""
    }
}
LoadConfig()

; --- Status menu (small, top-right, always on top) ---
global StatusGui := ""

BuildStatusGui() {
    global StatusGui, RunDurationMinutes
    StatusGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow")
    StatusGui.BackColor := "1e1e1e"
    StatusGui.SetFont("s9 cD0D0D0", "Segoe UI")
    StatusGui.Add("Text", "vStatusText", "Auto Fighter  |  Paused  |  Out of combat")
    StatusGui.Add("Text", "vTimerText", "Pause in: —")
    StatusGui.Add("Text", "vSetText", "Color —  Play —  Combat —  Watch —")
    StatusGui.Add("Text", "vPlayAreaText", "Play area: —")
    StatusGui.Add("Text", "Section", "Run (min):")
    StatusGui.Add("Edit", "vRunMinutes xs+58 ys-2 w44", String(RunDurationMinutes))
    StatusGui["RunMinutes"].SetFont("cBlack")
    StatusGui.Add("Text", "xs+106 ys-2", "0 = unlimited")
    StatusGui.MarginX := 12
    StatusGui.MarginY := 8
    x := A_ScreenWidth - 320
    y := 10
    StatusGui.Show("x" x " y" y " NoActivate")
}

UpdateStatusGui() {
    global StatusGui, IsRunning, InCombat, RunDurationMinutes, RunStartTime, ConfigPath
    global TargetColor, PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global InCombatCheckColor, InCombatCheck2Color, WatchRegionX1, WatchRegionY1, WatchRegionX2, WatchRegionY2
    if !StatusGui
        return
    ; Auto-stop when run duration reached
    if (IsRunning && RunDurationMinutes > 0 && RunStartTime > 0) {
        elapsedMs := A_TickCount - RunStartTime
        elapsedMin := elapsedMs / 60000
        if (elapsedMin >= RunDurationMinutes) {
            PauseClicker()
            ToolTip("Run duration reached (" RunDurationMinutes " min).")
            SetTimer(() => ToolTip(), 3000)
            return
        }
        ; Show countdown: Pause in: mm:ss
        remainingMs := (RunDurationMinutes * 60000) - elapsedMs
        remainingSec := Max(0, Round(remainingMs / 1000))
        timerMin := remainingSec // 60
        timerSec := remainingSec - (timerMin * 60)
        try
            StatusGui["TimerText"].Value := "Pause in: " timerMin ":" (timerSec < 10 ? "0" : "") timerSec
        catch
            {}
    } else {
        try
            StatusGui["TimerText"].Value := "Pause in: —"
        catch
            {}
    }
    runText := IsRunning ? "Running" : "Paused"
    combatText := InCombat ? "In combat" : "Out of combat"
    try
        StatusGui["StatusText"].Value := "Auto Fighter  |  " runText "  |  " combatText
    catch
        {}
    ; Which variables are set
    c := (TargetColor != "") ? "Color ✓" : "Color —"
    playSet := (PlayAreaX2 > PlayAreaX1 && PlayAreaY2 > PlayAreaY1)
    p := playSet ? "Play ✓" : "Play —"
    combatSet := (InCombatCheckColor != "" && InCombatCheck2Color != "")
    cb := combatSet ? "Combat ✓" : "Combat —"
    watchSet := (WatchRegionX2 > WatchRegionX1 && WatchRegionY2 > WatchRegionY1)
    w := watchSet ? "Watch ✓" : "Watch —"
    try
        StatusGui["SetText"].Value := c "  " p "  " cb "  " w
    catch
        {}
    ; Play area corners
    if (playSet)
        try
            StatusGui["PlayAreaText"].Value := "Play: (" PlayAreaX1 "," PlayAreaY1 ") → (" PlayAreaX2 "," PlayAreaY2 ")"
        catch
            {}
    else
        try
            StatusGui["PlayAreaText"].Value := "Play area: —"
        catch
            {}
}

; Build and show status window; refresh every 500 ms
BuildStatusGui()
BuildPlayAreaOverlay()
BuildWatchRegionOverlay()
SetTimer(UpdateStatusGui, 500)

; --- Hotkeys ---
^+q:: StartClicker()
^+w:: PauseClicker()
^+x:: ExitClicker()
^+c:: SetColorUnderCursor()          ; set highlight color (monster)
^+e:: SetInCombatCheck()             ; set in-combat indicator 1 (cursor position + color)
^+r:: SetInCombatCheck2()            ; set in-combat indicator 2 (both must be present)
^+b:: SetPlayAreaTopLeft()           ; set play area top-left corner
^+n:: SetPlayAreaBottomRight()      ; set play area bottom-right corner
^+y:: SetWatchRegionTopLeft()       ; set watch region top-left (drastic change = in combat)
^+u:: SetWatchRegionBottomRight()   ; set watch region bottom-right

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

; --- Watch region: drastic change vs previous check = in combat; no change for 3s = out of combat ---
SetWatchRegionTopLeft() {
    global WatchRegionX1, WatchRegionY1, ConfigPath
    MouseGetPos(&mx, &my)
    WatchRegionX1 := mx
    WatchRegionY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "WatchRegion", "X1")
        IniWrite(String(my), ConfigPath, "WatchRegion", "Y1")
    } catch
        {}
    ToolTip("Watch region TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildWatchRegionOverlay()
}

SetWatchRegionBottomRight() {
    global WatchRegionX2, WatchRegionY2, ConfigPath
    MouseGetPos(&mx, &my)
    WatchRegionX2 := mx
    WatchRegionY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "WatchRegion", "X2")
        IniWrite(String(my), ConfigPath, "WatchRegion", "Y2")
    } catch
        {}
    ToolTip("Watch region BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildWatchRegionOverlay()
}

; --- Draw small yellow L-shaped corner marks for watch region (combat check area) ---
BuildWatchRegionOverlay() {
    global WatchRegionOverlayGuis, WatchRegionX1, WatchRegionY1, WatchRegionX2, WatchRegionY2, WatchCornerMarkSize
    for overlayWin in WatchRegionOverlayGuis {
        try
            overlayWin.Destroy()
        catch
            {}
    }
    WatchRegionOverlayGuis := []
    if (WatchRegionX2 <= WatchRegionX1 || WatchRegionY2 <= WatchRegionY1)
        return
    L := WatchCornerMarkSize
    W := 2
    line(x, y, w, h) {
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
        g.BackColor := "FFFF00"
        g.Show("x" x " y" y " w" w " h" h " NoActivate")
        return g
    }
    WatchRegionOverlayGuis.Push(line(WatchRegionX1, WatchRegionY1, W, L))
    WatchRegionOverlayGuis.Push(line(WatchRegionX1, WatchRegionY1, L, W))
    WatchRegionOverlayGuis.Push(line(WatchRegionX2 - W, WatchRegionY1, W, L))
    WatchRegionOverlayGuis.Push(line(WatchRegionX2 - L, WatchRegionY1, L, W))
    WatchRegionOverlayGuis.Push(line(WatchRegionX1, WatchRegionY2 - L, W, L))
    WatchRegionOverlayGuis.Push(line(WatchRegionX1, WatchRegionY2 - W, L, W))
    WatchRegionOverlayGuis.Push(line(WatchRegionX2 - W, WatchRegionY2 - L, W, L))
    WatchRegionOverlayGuis.Push(line(WatchRegionX2 - L, WatchRegionY2 - W, L, W))
}

; --- In combat = (watch region set) drastic change vs last check, else two-pixel check ---
UpdateInCombatState() {
    global InCombat, LastInCombatSeen, OutOfCombatDelay
    global InCombatCheckX, InCombatCheckY, InCombatCheckColor
    global InCombatCheck2X, InCombatCheck2Y, InCombatCheck2Color
    global InCombatCheckVariation
    global LastSample, WatchRegionX1, WatchRegionY1, WatchRegionX2, WatchRegionY2
    global WatchSampleStep, ChangePctThreshold, DrasticChangeThreshold, ChangeDetectionOutDelay

    ; If watch region is set: compare current frame to previous frame; drastic change = in combat
    if (WatchRegionX2 > WatchRegionX1 && WatchRegionY2 > WatchRegionY1) {
        current := Map()
        y := WatchRegionY1
        while (y <= WatchRegionY2) {
            x := WatchRegionX1
            while (x <= WatchRegionX2) {
                key := x "," y
                try
                    current[key] := PixelGetColor(x, y, "RGB")
                catch
                    {}
                x += WatchSampleStep
            }
            y += WatchSampleStep
        }
        changed := 0
        total := 0
        for key, curColor in current {
            total++
            if LastSample.Has(key) {
                prevColor := LastSample[key]
                if !ColorsMatch(curColor, prevColor, DrasticChangeThreshold)
                    changed++
            }
        }
        ; Keep this frame as "previous" for next run (copy so we don't share reference)
        LastSample := Map()
        for k, v in current
            LastSample[k] := v
        if (total > 0) {
            pct := changed / total
            if (pct >= ChangePctThreshold) {
                InCombat := true
                LastInCombatSeen := A_TickCount
            } else if (A_TickCount - LastInCombatSeen > ChangeDetectionOutDelay) {
                InCombat := false
            }
        }
        return
    }

    ; Else: two exact-pixel indicators (both must match)
    if (InCombatCheckColor = "" || InCombatCheck2Color = "")
        return
    try
        c1 := PixelGetColor(InCombatCheckX, InCombatCheckY, "RGB")
    catch
        c1 := 0
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
    if (radius > maxR)
        return
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
