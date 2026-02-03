#Requires AutoHotkey v2.0
; Agility Bot - Draynor Village & Varrock Rooftop Courses
; Setup: 1) Play area. 2) For each step: set color (obstacle highlight). 3) Completion area+color (XP drop). 4) Optional: Mark of Grace, Nav tile.
; Varrock: can fall — if next step not found but nav tile visible, click nav to return. Optional: inventory area, food color, health-check pixel to eat when low.

; --- State ---
global IsRunning := false
global ConfigPath := A_ScriptDir "\Agility.ini"

; Play area – only search/click inside this rect
global PlayAreaX1 := 0
global PlayAreaY1 := 0
global PlayAreaX2 := 0
global PlayAreaY2 := 0
global PlayAreaOverlayGuis := []
global CornerMarkSize := 30

; Course: "Draynor" or "Varrock"
global SelectedCourse := "Draynor"
global CurrentStep := 1
global ConfigStep := 1
global AgilityStatusAction := ""
global AgilityDebugLine := ""

; Draynor: 7 obstacles; Varrock: 9 obstacles (can fall)
global DraynorSteps := ["Rough wall", "Tightrope 1", "Tightrope 2", "Narrow wall", "Jump-up Wall", "Jump Gap", "Crate"]
global VarrockSteps := ["Rough Wall", "Clothes Line", "Gap 1", "Balance Wall", "Gap 2", "Gap 3", "Gap 4", "Ledge", "Jump-off Edge"]
global StepColors := []        ; current course's colors (ref to StepColorsDraynor or StepColorsVarrock)
global StepColorsDraynor := []
global StepColorsVarrock := []
global StepColorVariation := 3
global StepColorVariationLedge := 3

; Completion detection: area + color (e.g. XP drop). When color appears = obstacle done. Required.
global CompletionAreaX1 := 0
global CompletionAreaY1 := 0
global CompletionAreaX2 := 0
global CompletionAreaY2 := 0
global CompletionColor := ""
global CompletionVariation := 15
global MarkOfGracePrimaryColor := ""   ; optional; must be present (identifies MoG area)
global MarkOfGraceSecondaryColor := "" ; optional; must be near primary; script clicks this
global MarkOfGraceVariation := 3
global MarkOfGraceNearPixels := 80     ; secondary must be within this many pixels of primary
global MarkOfGracePickupDelayMs := 1200  ; wait after clicking MoG (secondary) so pickup can complete
global NavTileColor := ""           ; optional; tile color to click to walk back to start (after lap)
global NavTileVariation := 3
global GapNavColor := ""           ; Varrock: tile to click when Gap 3 not visible (e.g. MoG in way) — after Gap 2
global GapNavVariation := 3
; Inventory + food + health (for Varrock / courses where you can fall)
global InventoryX1 := 0
global InventoryY1 := 0
global InventoryX2 := 0
global InventoryY2 := 0
global FoodColor := ""
global FoodColorVariation := 15
global HealthCheckX := 0
global HealthCheckY := 0
global HealthCheckColor := ""       ; pixel color when healthy; if different → eat food
global HealthCheckVariation := 10
; Run duration (0 = unlimited)
global RunDurationMinutes := 0
global RunStartTime := 0

; Main loop
global MainLoopInterval := 400
global ClickJitter := 1
global ClickDelayMs := 50
global RadiusStep := 100      ; larger steps = fewer PixelSearch rings (faster find)
global BoundsScanStep := 8    ; coarser bounds = fewer PixelGetColor calls (was 3)
global BoundsMaxDist := 32    ; limit expansion for faster scan (was 45)
global AgilityWaitingForCompletion := false
global AgilityCompletionCheckAfter := 0      ; don't check for XP until 2s after click (avoid previous XP)
global AgilityCompletionCheckDelayMs := 3000 ; wait 3s before looking for XP drop
global AgilityCompletionTimeoutAt := 0      ; safety: advance if XP not seen by this tick
global AgilityCompletionMaxWaitMs := 15000   ; if no XP in 15s, retry same step (click may have missed)
global AgilityWaitingForGap3 := false       ; Varrock: after clicking gap nav, wait for Gap 3 color (no XP)
global AgilityWaitingForStep1 := false     ; after clicking nav tile, wait for step 1 color (no XP)
global MinClickIntervalMs := 2000           ; minimum ms between any two clicks
global LastClickTime := 0                    ; A_TickCount when we last clicked
global MarkOfGraceRetryIntervalMs := 3000   ; re-click MoG secondary every 3s until primary gone
global MarkOfGraceMaxRetries := 10          ; give up after 10 retries (~30s) to avoid infinite stuck

CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

GetStepCount(course) {
    return (course = "Varrock") ? 9 : 7
}

GetStepNames(course) {
    return (course = "Varrock") ? VarrockSteps : DraynorSteps
}

; --- Load config ---
LoadConfig() {
    global ConfigPath, StepColors, StepColorsDraynor, StepColorsVarrock, SelectedCourse
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global CompletionAreaX1, CompletionAreaY1, CompletionAreaX2, CompletionAreaY2, CompletionColor
    global MarkOfGracePrimaryColor, MarkOfGraceSecondaryColor, NavTileColor, GapNavColor, RunDurationMinutes
    global InventoryX1, InventoryY1, InventoryX2, InventoryY2, FoodColor, FoodColorVariation
    global HealthCheckX, HealthCheckY, HealthCheckColor, HealthCheckVariation
    StepColorsDraynor := []
    StepColorsVarrock := []
    Loop 7
        StepColorsDraynor.Push("")
    Loop 9
        StepColorsVarrock.Push("")
    try {
        if FileExist(ConfigPath) {
            PlayAreaX1 := Integer(IniRead(ConfigPath, "PlayArea", "X1", "0"))
            PlayAreaY1 := Integer(IniRead(ConfigPath, "PlayArea", "Y1", "0"))
            PlayAreaX2 := Integer(IniRead(ConfigPath, "PlayArea", "X2", "0"))
            PlayAreaY2 := Integer(IniRead(ConfigPath, "PlayArea", "Y2", "0"))
            SelectedCourse := IniRead(ConfigPath, "Settings", "Course", "Draynor")
            if (SelectedCourse != "Varrock")
                SelectedCourse := "Draynor"
            RunDurationMinutes := Integer(IniRead(ConfigPath, "Settings", "RunDurationMinutes", "0"))
            if (RunDurationMinutes < 0)
                RunDurationMinutes := 0
            CompletionAreaX1 := Integer(IniRead(ConfigPath, "Completion", "X1", "0"))
            CompletionAreaY1 := Integer(IniRead(ConfigPath, "Completion", "Y1", "0"))
            CompletionAreaX2 := Integer(IniRead(ConfigPath, "Completion", "X2", "0"))
            CompletionAreaY2 := Integer(IniRead(ConfigPath, "Completion", "Y2", "0"))
            cc := IniRead(ConfigPath, "Completion", "Color", "")
            if (cc != "")
                CompletionColor := "0x" cc
            else
                CompletionColor := ""
            mogP := IniRead(ConfigPath, "MarkOfGrace", "PrimaryColor", "")
            if (mogP = "")
                mogP := IniRead(ConfigPath, "MarkOfGrace", "Color", "")
            if (mogP != "")
                MarkOfGracePrimaryColor := "0x" mogP
            else
                MarkOfGracePrimaryColor := ""
            mogS := IniRead(ConfigPath, "MarkOfGrace", "SecondaryColor", "")
            if (mogS != "")
                MarkOfGraceSecondaryColor := "0x" mogS
            else
                MarkOfGraceSecondaryColor := ""
            nav := IniRead(ConfigPath, "NavTile", "Color", "")
            if (nav != "")
                NavTileColor := "0x" nav
            else
                NavTileColor := ""
            gapNav := IniRead(ConfigPath, "Varrock", "GapNavColor", "")
            if (gapNav != "")
                GapNavColor := "0x" gapNav
            else
                GapNavColor := ""
            ; Inventory, food, health
            InventoryX1 := Integer(IniRead(ConfigPath, "Inventory", "X1", "0"))
            InventoryY1 := Integer(IniRead(ConfigPath, "Inventory", "Y1", "0"))
            InventoryX2 := Integer(IniRead(ConfigPath, "Inventory", "X2", "0"))
            InventoryY2 := Integer(IniRead(ConfigPath, "Inventory", "Y2", "0"))
            fc := IniRead(ConfigPath, "Food", "Color", "")
            FoodColor := (fc != "") ? "0x" fc : ""
            FoodColorVariation := Integer(IniRead(ConfigPath, "Food", "Variation", "15"))
            HealthCheckX := Integer(IniRead(ConfigPath, "Health", "X", "0"))
            HealthCheckY := Integer(IniRead(ConfigPath, "Health", "Y", "0"))
            hc := IniRead(ConfigPath, "Health", "Color", "")
            HealthCheckColor := (hc != "") ? "0x" hc : ""
            HealthCheckVariation := Integer(IniRead(ConfigPath, "Health", "Variation", "10"))
            ; Step colors per course
            loop 7 {
                i := A_Index
                c := IniRead(ConfigPath, "Draynor", "Step" i "Color", "")
                StepColorsDraynor[i] := (c != "") ? "0x" c : ""
            }
            loop 9 {
                i := A_Index
                c := IniRead(ConfigPath, "Varrock", "Step" i "Color", "")
                StepColorsVarrock[i] := (c != "") ? "0x" c : ""
            }
        }
    } catch
        {}
    StepColors := (SelectedCourse = "Varrock") ? StepColorsVarrock : StepColorsDraynor
}
LoadConfig()

; --- Status GUI ---
global StatusGui := ""
global LastCourseForStepDDL := ""   ; only rebuild step dropdown when course changes

SetGuiText(ctrl, str) {
    try
        ctrl.Text := str
    catch
        try
            ctrl.Value := str
        catch
            {}
}

BuildStatusGui() {
    global StatusGui, RunDurationMinutes, SelectedCourse
    StatusGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow")
    StatusGui.BackColor := "1e1e1e"
    StatusGui.SetFont("s9 cD0D0D0", "Segoe UI")
    StatusGui.MarginX := 12
    StatusGui.MarginY := 6
    StatusGui.Add("Text", "Section", "Agility Bot")
    StatusGui.Add("Text", "vStatusText xs", "Paused  |  Step 1/7")
    StatusGui.Add("Edit", "vActionText xs ReadOnly r1 w400 Background1e1e1e", "Action: —")
    StatusGui["ActionText"].SetFont("cA0D0A0")
    StatusGui.Add("Edit", "vDebugText xs ReadOnly r1 w400 Background1e1e1e", "Debug: —")
    StatusGui["DebugText"].SetFont("c808080")
    StatusGui.Add("Text", "vTimerText xs", "Time left: --")
    StatusGui.Add("Text", "xs Section", "Run (min):")
    StatusGui.Add("Edit", "vRunMinutes x+6 yp-2 w44", String(RunDurationMinutes))
    StatusGui["RunMinutes"].SetFont("cBlack")
    StatusGui.Add("Text", "x+6 yp+2", "0 = unlimited")
    StatusGui.Add("Text", "xs Section y+4", "Course:")
    StatusGui.Add("DDL", "vCourseChoose x+6 yp-2 w120 Choose1", ["Draynor Village", "Varrock"])
    StatusGui["CourseChoose"].SetFont("cBlack")
    StatusGui.Add("Text", "xs Section y+8", "Configuration:")
    StatusGui.Add("Text", "vPlayAreaRow xs y+2", "[—] Play area     Ctrl+Shift+B (TL)  Ctrl+Shift+N (BR)")
    StatusGui.Add("Text", "vCompletionRow xs", "[—] Completion (XP drop)  Ctrl+Shift+E (TL)  Ctrl+Shift+R (BR)  Ctrl+Shift+V (color)")
    StatusGui.Add("Text", "vMarkOfGraceRow xs", "[—] Mark of Grace  Primary: Ctrl+Shift+G  Secondary: Ctrl+Shift+J (clicks secondary)")
    StatusGui.Add("Text", "vNavTileRow xs", "[—] Nav tile (back to start)     Ctrl+Shift+H (color)")
    StatusGui.Add("Text", "vGapNavRow xs", "[—] Gap nav (Varrock, after Gap 2)     Ctrl+Shift+A (color)")
    StatusGui.Add("Text", "xs Section", "Set step color:")
    StatusGui.Add("DDL", "vConfigStepChoose x+6 yp-2 w120 Choose1", ["1. Rough wall", "2. Tightrope 1", "3. Tightrope 2", "4. Narrow wall", "5. Jump-up Wall", "6. Jump Gap", "7. Crate"])
    StatusGui["ConfigStepChoose"].SetFont("cBlack")
    StatusGui.Add("Text", "x+6 yp+2", "Ctrl+Shift+C")
    StatusGui.Add("Text", "vStep1Row xs", "[—] 1. Rough wall")
    StatusGui.Add("Text", "vStep2Row xs", "[—] 2. Tightrope 1")
    StatusGui.Add("Text", "vStep3Row xs", "[—] 3. Tightrope 2")
    StatusGui.Add("Text", "vStep4Row xs", "[—] 4. Narrow wall")
    StatusGui.Add("Text", "vStep5Row xs", "[—] 5. Jump-up Wall")
    StatusGui.Add("Text", "vStep6Row xs", "[—] 6. Jump Gap")
    StatusGui.Add("Text", "vStep7Row xs", "[—] 7. Crate")
    StatusGui.Add("Text", "vStep8Row xs", "[—] 8. —")
    StatusGui.Add("Text", "vStep9Row xs", "[—] 9. —")
    StatusGui.Add("Text", "xs Section y+4", "Inventory / Health (Varrock fall):")
    StatusGui.Add("Text", "vInventoryRow xs y+2", "[—] Inventory area  Ctrl+Shift+I (TL)  Ctrl+Shift+K (BR)")
    StatusGui.Add("Text", "vFoodRow xs", "[—] Food color  Ctrl+Shift+F")
    StatusGui.Add("Text", "vHealthRow xs", "[—] Health check pixel  Ctrl+Shift+P")
    StatusGui.Add("Text", "xs y+8", "Hotkeys:")
    StatusGui.Add("Text", "vHotkeysRow xs y+2", "Start Ctrl+Shift+Q  |  Pause Ctrl+Shift+W  |  Exit Ctrl+Shift+X")
    StatusGui.Show("x" (A_ScreenWidth - 460) " y10 NoActivate w440")
    ; Sync course dropdown to loaded config (so Varrock stays selected if that was saved)
    if (SelectedCourse = "Varrock")
        StatusGui["CourseChoose"].Choose(2)
    else
        StatusGui["CourseChoose"].Choose(1)
}

UpdateStatusGui() {
    global StatusGui, IsRunning, CurrentStep, ConfigStep, RunDurationMinutes, RunStartTime, ConfigPath
    global AgilityStatusAction, AgilityDebugLine, StepColors, StepColorsDraynor, StepColorsVarrock, SelectedCourse
    global LastCourseForStepDDL
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global CompletionAreaX1, CompletionAreaY1, CompletionAreaX2, CompletionAreaY2, CompletionColor, MarkOfGracePrimaryColor, MarkOfGraceSecondaryColor, NavTileColor, GapNavColor
    global InventoryX1, InventoryY1, InventoryX2, InventoryY2, FoodColor, HealthCheckX, HealthCheckY, HealthCheckColor
    if !StatusGui
        return
    ; Sync from dropdowns: read values first (never overwrite user selection by clearing then reading)
    try {
        courseVal := StatusGui["CourseChoose"].Value
        SelectedCourse := (courseVal = 2 || courseVal = "Varrock") ? "Varrock" : "Draynor"
        StepColors := (SelectedCourse = "Varrock") ? StepColorsVarrock : StepColorsDraynor
        stepCount := GetStepCount(SelectedCourse)
        names := GetStepNames(SelectedCourse)
        ; Read step selection BEFORE we might clear the list (so we don't lose user's choice)
        stepVal := StatusGui["ConfigStepChoose"].Value
        savedStepIndex := Integer(stepVal)
        if (savedStepIndex < 1 || savedStepIndex > stepCount)
            savedStepIndex := Min(ConfigStep, stepCount)
        if (savedStepIndex < 1)
            savedStepIndex := 1
        ; Only rebuild step dropdown when course actually changed (stops constant reset to item 1)
        if (SelectedCourse != LastCourseForStepDDL) {
            opts := []
            Loop stepCount
                opts.Push(A_Index ". " names[A_Index])
            Loop 9 {
                try
                    StatusGui["ConfigStepChoose"].Delete(1)
                catch
                    break
            }
            StatusGui["ConfigStepChoose"].Add(opts)
            StatusGui["ConfigStepChoose"].Choose(savedStepIndex)
            LastCourseForStepDDL := SelectedCourse
        }
        ConfigStep := Integer(StatusGui["ConfigStepChoose"].Value)
        if (ConfigStep < 1 || ConfigStep > stepCount)
            ConfigStep := 1
        if (CurrentStep > stepCount)
            CurrentStep := stepCount
        try
            IniWrite(SelectedCourse, ConfigPath, "Settings", "Course")
        catch
            {}
    } catch
        {}
    runMin := 0
    try
        runMin := Integer(StatusGui["RunMinutes"].Value)
    catch
        {}
    if (runMin < 0)
        runMin := 0
    if (IsRunning && runMin = 0 && RunDurationMinutes > 0)
        runMin := RunDurationMinutes
    if (IsRunning && runMin > 0 && RunStartTime > 0) {
        elapsed := A_TickCount - RunStartTime
        if (elapsed >= runMin * 60000) {
            PauseAgility()
            ToolTip("Run duration reached (" runMin " min).")
            SetTimer(() => ToolTip(), 3000)
            return
        }
        rem := (runMin * 60000) - elapsed
        sec := Max(0, Round(rem / 1000))
        SetGuiText(StatusGui["TimerText"], "Time left: " (sec // 60) ":" (Format("{:02}", Mod(sec, 60))))
    } else
        SetGuiText(StatusGui["TimerText"], "Time left: --")
    runTxt := IsRunning ? "Running" : "Paused"
    stepCount := GetStepCount(SelectedCourse)
    stepTxt := "Step " CurrentStep "/" stepCount
    SetGuiText(StatusGui["StatusText"], runTxt "  |  " stepTxt)
    StatusGui["ActionText"].Value := "Action: " (AgilityStatusAction != "" ? AgilityStatusAction : (IsRunning ? "Looking for obstacle" : "Idle"))
    StatusGui["DebugText"].Value := "Debug: " (AgilityDebugLine != "" ? AgilityDebugLine : "Step=" CurrentStep)
    pSet := (PlayAreaX2 > PlayAreaX1 && PlayAreaY2 > PlayAreaY1)
    SetGuiText(StatusGui["PlayAreaRow"], "[" (pSet ? "✓" : "—") "] Play area     Ctrl+Shift+B (TL)  Ctrl+Shift+N (BR)")
    compSet := (CompletionAreaX2 > CompletionAreaX1 && CompletionAreaY2 > CompletionAreaY1 && CompletionColor != "")
    SetGuiText(StatusGui["CompletionRow"], "[" (compSet ? "✓" : "—") "] Completion (XP drop)  Ctrl+Shift+E (TL)  Ctrl+Shift+R (BR)  Ctrl+Shift+V (color)")
    mogSet := (MarkOfGracePrimaryColor != "" && MarkOfGraceSecondaryColor != "")
    SetGuiText(StatusGui["MarkOfGraceRow"], "[" (mogSet ? "✓" : "—") "] Mark of Grace  Primary: Ctrl+Shift+G  Secondary: Ctrl+Shift+J (clicks secondary)")
    navSet := (NavTileColor != "")
    SetGuiText(StatusGui["NavTileRow"], "[" (navSet ? "✓" : "—") "] Nav tile (back to start)     Ctrl+Shift+H (color)")
    gapNavSet := (GapNavColor != "")
    SetGuiText(StatusGui["GapNavRow"], "[" (gapNavSet ? "✓" : "—") "] Gap nav (Varrock, after Gap 2)     Ctrl+Shift+A (color)")
    names := GetStepNames(SelectedCourse)
    stepCount := GetStepCount(SelectedCourse)
    loop 9 {
        i := A_Index
        if (i <= stepCount) {
            c := StepColors.Has(i) ? StepColors[i] : ""
            SetGuiText(StatusGui["Step" i "Row"], "[" (c != "" ? "✓" : "—") "] " i ". " names[i])
        } else
            SetGuiText(StatusGui["Step" i "Row"], "[—] " i ". —")
    }
    invSet := (InventoryX2 > InventoryX1 && InventoryY2 > InventoryY1)
    SetGuiText(StatusGui["InventoryRow"], "[" (invSet ? "✓" : "—") "] Inventory area  Ctrl+Shift+I (TL)  Ctrl+Shift+K (BR)")
    SetGuiText(StatusGui["FoodRow"], "[" (FoodColor != "" ? "✓" : "—") "] Food color  Ctrl+Shift+F")
    healthSet := (HealthCheckColor != "" && HealthCheckX != 0 && HealthCheckY != 0)
    SetGuiText(StatusGui["HealthRow"], "[" (healthSet ? "✓" : "—") "] Health check pixel  Ctrl+Shift+P")
}

; --- Overlays ---
BuildPlayAreaOverlay() {
    global PlayAreaOverlayGuis, PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2, CornerMarkSize
    for g in PlayAreaOverlayGuis {
        try
            g.Destroy()
        catch
            {}
    }
    PlayAreaOverlayGuis := []
    if (PlayAreaX2 <= PlayAreaX1 || PlayAreaY2 <= PlayAreaY1)
        return
    L := CornerMarkSize
    W := 4
    line(x, y, w, h) {
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
        g.BackColor := "FF0000"
        g.Show("x" x " y" y " w" w " h" h " NoActivate")
        return g
    }
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY1, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY1, L, W))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - W, PlayAreaY1, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - L, PlayAreaY1, L, W))
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY2 - L, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY2 - W, L, W))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - W, PlayAreaY2 - L, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - L, PlayAreaY2 - W, L, W))
}

; --- Hotkeys ---
^+q:: StartAgility()
^+w:: PauseAgility()
^+x:: ExitAgility()
^+b:: SetPlayAreaTL()
^+n:: SetPlayAreaBR()
^+e:: SetCompletionAreaTL()
^+r:: SetCompletionAreaBR()
^+v:: SetCompletionColor()
^+g:: SetMarkOfGracePrimaryColor()
^+j:: SetMarkOfGraceSecondaryColor()
^+h:: SetNavTileColor()
^+a:: SetGapNavColor()
^+c:: SetCurrentStepColor()
^+i:: SetInventoryTL()
^+k:: SetInventoryBR()
^+f:: SetFoodColor()
^+p:: SetHealthCheckPixel()

; --- Start / Pause / Exit ---
StartAgility() {
    global IsRunning, RunDurationMinutes, RunStartTime, StatusGui, ConfigPath
    global CurrentStep, StepColors, SelectedCourse
    global CompletionAreaX1, CompletionAreaY1, CompletionAreaX2, CompletionAreaY2, CompletionColor
    if (IsRunning)
        return
    stepCount := GetStepCount(SelectedCourse)
    missing := []
    Loop stepCount {
        if (!StepColors.Has(A_Index) || StepColors[A_Index] = "")
            missing.Push(A_Index)
    }
    if (missing.Length > 0) {
        missingStr := ""
        for i in missing
            missingStr .= (missingStr ? ", " : "") . i
        MsgBox("Set colors for steps: " missingStr ". Use dropdown and Ctrl+Shift+C for each obstacle.", "Agility Bot", "Icon!")
        return
    }
    ; Require XP drop completion area and color
    if (CompletionAreaX2 <= CompletionAreaX1 || CompletionAreaY2 <= CompletionAreaY1 || CompletionColor = "") {
        MsgBox("Set completion (XP drop) area and color: Ctrl+Shift+E, Ctrl+Shift+R, Ctrl+Shift+V", "Agility Bot", "Icon!")
        return
    }
    try {
        RunDurationMinutes := Integer(StatusGui["RunMinutes"].Value)
        if (RunDurationMinutes < 0)
            RunDurationMinutes := 0
        IniWrite(String(RunDurationMinutes), ConfigPath, "Settings", "RunDurationMinutes")
    } catch
        {}
    RunStartTime := A_TickCount
    IsRunning := true
    CurrentStep := 1
    AgilityWaitingForCompletion := false
    AgilityWaitingForGap3 := false
    AgilityWaitingForStep1 := false
    SetTimer(DoAgilityStep, MainLoopInterval)
    if (RunDurationMinutes > 0)
        UpdateStatusGui()
    ToolTip("Agility bot: Running")
    SetTimer(() => ToolTip(), 2000)
}

PauseAgility() {
    global IsRunning, RunStartTime
    IsRunning := false
    RunStartTime := 0
    SetTimer(DoAgilityStep, 0)
    ToolTip("Agility bot: Paused")
    SetTimer(() => ToolTip(), 2000)
}

ExitAgility() {
    global IsRunning
    IsRunning := false
    SetTimer(DoAgilityStep, 0)
    ToolTip()
    ExitApp()
}

; --- Config setters ---
SetPlayAreaTL() {
    global PlayAreaX1, PlayAreaY1, ConfigPath
    MouseGetPos(&mx, &my)
    PlayAreaX1 := mx
    PlayAreaY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "PlayArea", "X1")
        IniWrite(String(my), ConfigPath, "PlayArea", "Y1")
    } catch
        {}
    ToolTip("Play area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildPlayAreaOverlay()
}

SetPlayAreaBR() {
    global PlayAreaX2, PlayAreaY2, ConfigPath
    MouseGetPos(&mx, &my)
    PlayAreaX2 := mx
    PlayAreaY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "PlayArea", "X2")
        IniWrite(String(my), ConfigPath, "PlayArea", "Y2")
    } catch
        {}
    ToolTip("Play area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildPlayAreaOverlay()
}

SetCurrentStepColor() {
    global StepColors, ConfigStep, ConfigPath, StatusGui, SelectedCourse
    try
        stepNum := Integer(StatusGui["ConfigStepChoose"].Value)
    catch
        stepNum := 1
    stepCount := GetStepCount(SelectedCourse)
    if (stepNum < 1 || stepNum > stepCount)
        stepNum := 1
    MouseGetPos(&mx, &my)
    c := PixelGetColor(mx, my, "RGB")
    if (!StepColors.Has(1)) {
        Loop stepCount
            StepColors.Push("")
    }
    StepColors[stepNum] := c
    try
        IniWrite(SubStr(c, 3), ConfigPath, SelectedCourse, "Step" stepNum "Color")
    catch
        {}
    names := GetStepNames(SelectedCourse)
    ToolTip("Step " stepNum " (" names[stepNum] ") color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetCompletionAreaTL() {
    global CompletionAreaX1, CompletionAreaY1, ConfigPath
    MouseGetPos(&mx, &my)
    CompletionAreaX1 := mx
    CompletionAreaY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "Completion", "X1")
        IniWrite(String(my), ConfigPath, "Completion", "Y1")
    } catch
        {}
    ToolTip("Completion area TL (e.g. XP drop region) at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetCompletionAreaBR() {
    global CompletionAreaX2, CompletionAreaY2, ConfigPath
    MouseGetPos(&mx, &my)
    CompletionAreaX2 := mx
    CompletionAreaY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "Completion", "X2")
        IniWrite(String(my), ConfigPath, "Completion", "Y2")
    } catch
        {}
    ToolTip("Completion area BR at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetCompletionColor() {
    global CompletionColor, ConfigPath
    MouseGetPos(&mx, &my)
    CompletionColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(CompletionColor, 3), ConfigPath, "Completion", "Color")
    catch
        {}
    ToolTip("Completion color (e.g. XP drop) set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetMarkOfGracePrimaryColor() {
    global MarkOfGracePrimaryColor, ConfigPath
    MouseGetPos(&mx, &my)
    MarkOfGracePrimaryColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(MarkOfGracePrimaryColor, 3), ConfigPath, "MarkOfGrace", "PrimaryColor")
    catch
        {}
    ToolTip("Mark of Grace PRIMARY color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetMarkOfGraceSecondaryColor() {
    global MarkOfGraceSecondaryColor, ConfigPath
    MouseGetPos(&mx, &my)
    MarkOfGraceSecondaryColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(MarkOfGraceSecondaryColor, 3), ConfigPath, "MarkOfGrace", "SecondaryColor")
    catch
        {}
    ToolTip("Mark of Grace SECONDARY color (click target) set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetNavTileColor() {
    global NavTileColor, ConfigPath
    MouseGetPos(&mx, &my)
    NavTileColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(NavTileColor, 3), ConfigPath, "NavTile", "Color")
    catch
        {}
    ToolTip("Nav tile color (back to start) set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetGapNavColor() {
    global GapNavColor, ConfigPath
    MouseGetPos(&mx, &my)
    GapNavColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(GapNavColor, 3), ConfigPath, "Varrock", "GapNavColor")
    catch
        {}
    ToolTip("Gap nav (Varrock, after Gap 2) color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetInventoryTL() {
    global InventoryX1, InventoryY1, ConfigPath
    MouseGetPos(&mx, &my)
    InventoryX1 := mx
    InventoryY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "Inventory", "X1")
        IniWrite(String(my), ConfigPath, "Inventory", "Y1")
    } catch
        {}
    ToolTip("Inventory area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetInventoryBR() {
    global InventoryX2, InventoryY2, ConfigPath
    MouseGetPos(&mx, &my)
    InventoryX2 := mx
    InventoryY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "Inventory", "X2")
        IniWrite(String(my), ConfigPath, "Inventory", "Y2")
    } catch
        {}
    ToolTip("Inventory area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetFoodColor() {
    global FoodColor, FoodColorVariation, ConfigPath
    MouseGetPos(&mx, &my)
    FoodColor := PixelGetColor(mx, my, "RGB")
    try {
        IniWrite(SubStr(FoodColor, 3), ConfigPath, "Food", "Color")
        IniWrite(String(FoodColorVariation), ConfigPath, "Food", "Variation")
    } catch
        {}
    ToolTip("Food color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetHealthCheckPixel() {
    global HealthCheckX, HealthCheckY, HealthCheckColor, HealthCheckVariation, ConfigPath
    MouseGetPos(&mx, &my)
    HealthCheckX := mx
    HealthCheckY := my
    HealthCheckColor := PixelGetColor(mx, my, "RGB")
    try {
        IniWrite(String(mx), ConfigPath, "Health", "X")
        IniWrite(String(my), ConfigPath, "Health", "Y")
        IniWrite(SubStr(HealthCheckColor, 3), ConfigPath, "Health", "Color")
        IniWrite(String(HealthCheckVariation), ConfigPath, "Health", "Variation")
    } catch
        {}
    ToolTip("Health check pixel (healthy color) set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

; --- Helpers ---
ColorsMatch(c1, c2, variation) {
    c1 := Integer(c1)
    c2 := Integer(c2)
    return (Abs((c1>>16)&0xFF - (c2>>16)&0xFF) <= variation && Abs((c1>>8)&0xFF - (c2>>8)&0xFF) <= variation && Abs(c1&0xFF - c2&0xFF) <= variation)
}

GetPlayArea() {
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    if (PlayAreaX2 > PlayAreaX1 && PlayAreaY2 > PlayAreaY1)
        return {x1: PlayAreaX1, y1: PlayAreaY1, x2: PlayAreaX2, y2: PlayAreaY2}
    return {x1: 0, y1: 0, x2: A_ScreenWidth, y2: A_ScreenHeight}
}

ColorInArea(x1, y1, x2, y2, targetColor, variation) {
    try
        return PixelSearch(&ox, &oy, x1, y1, x2, y2, Integer(targetColor), variation)
    catch
        return false
}

IsHealthLow() {
    global HealthCheckX, HealthCheckY, HealthCheckColor, HealthCheckVariation
    if (HealthCheckColor = "" || HealthCheckX = 0 && HealthCheckY = 0)
        return false
    try
        pix := PixelGetColor(HealthCheckX, HealthCheckY, "RGB")
    catch
        return false
    return !ColorsMatch(pix, HealthCheckColor, HealthCheckVariation)
}

FindAndClickFoodInInventory() {
    global FoodColor, FoodColorVariation, InventoryX1, InventoryY1, InventoryX2, InventoryY2
    if (FoodColor = "" || InventoryX2 <= InventoryX1 || InventoryY2 <= InventoryY1)
        return false
    zone := {x1: InventoryX1, y1: InventoryY1, x2: InventoryX2, y2: InventoryY2}
    return FindAndClickColor(FoodColor, FoodColorVariation, zone)
}

FindAndClickColor(targetColor, colorVariation, searchZone := "") {
    global ClickJitter, ClickDelayMs, RadiusStep, BoundsScanStep, BoundsMaxDist
    useZone := searchZone && searchZone.x2 > searchZone.x1 && searchZone.y2 > searchZone.y1
    pa := useZone ? searchZone : GetPlayArea()
    if (targetColor = "")
        return false
    cx := (pa.x1 + pa.x2) // 2
    cy := (pa.y1 + pa.y2) // 2
    radius := 0
    maxR := Max(pa.x2 - pa.x1, pa.y2 - pa.y1) // 2 + RadiusStep
    foundX := 0
    foundY := 0
    while (radius <= maxR) {
        x1 := Max(pa.x1, cx - radius)
        y1 := Max(pa.y1, cy - radius)
        x2 := Min(pa.x2, cx + radius)
        y2 := Min(pa.y2, cy + radius)
        if PixelSearch(&foundX, &foundY, x1, y1, x2, y2, Integer(targetColor), colorVariation)
            break
        radius += RadiusStep
    }
    if (radius > maxR)
        return false
    ; Bounds expansion: find blob edges with coarse step (fewer PixelGetColor = faster)
    minX := maxX := foundX
    minY := maxY := foundY
    limitL := Max(pa.x1, foundX - BoundsMaxDist)
    limitR := Min(pa.x2, foundX + BoundsMaxDist)
    limitT := Max(pa.y1, foundY - BoundsMaxDist)
    limitB := Min(pa.y2, foundY + BoundsMaxDist)
    x := foundX - BoundsScanStep
    while (x >= limitL) {
        try {
            if ColorsMatch(PixelGetColor(x, foundY, "RGB"), targetColor, colorVariation)
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
            if ColorsMatch(PixelGetColor(x, foundY, "RGB"), targetColor, colorVariation)
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
            if ColorsMatch(PixelGetColor(foundX, y, "RGB"), targetColor, colorVariation)
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
            if ColorsMatch(PixelGetColor(foundX, y, "RGB"), targetColor, colorVariation)
                maxY := y
            else
                break
        } catch
            break
        y += BoundsScanStep
    }
    clickX := (minX + maxX) // 2
    clickY := (minY + maxY) // 2
    if (ClickJitter > 0) {
        clickX += Random(-ClickJitter, ClickJitter)
        clickY += Random(-ClickJitter, ClickJitter)
    }
    clickX := Max(pa.x1, Min(pa.x2, clickX))
    clickY := Max(pa.y1, Min(pa.y2, clickY))
    MouseMove(clickX, clickY)
    if (ClickDelayMs > 0)
        Sleep(ClickDelayMs)
    global LastClickTime := A_TickCount
    Click()
    return true
}

; Mark of Grace: primary must be present; secondary must be near primary; clicks secondary only.
; Waits until primary is no longer present; re-clicks secondary every 3s until primary is gone.
; Gives up after MarkOfGraceMaxRetries to avoid infinite stuck if primary color persists (e.g. wrong color).
FindMarkOfGraceAndClickSecondary() {
    global MarkOfGracePrimaryColor, MarkOfGraceSecondaryColor, MarkOfGraceVariation, MarkOfGraceNearPixels
    global MarkOfGraceRetryIntervalMs, MarkOfGraceMaxRetries
    if (MarkOfGracePrimaryColor = "" || MarkOfGraceSecondaryColor = "")
        return false
    pa := GetPlayArea()
    if !PixelSearch(&px, &py, pa.x1, pa.y1, pa.x2, pa.y2, Integer(MarkOfGracePrimaryColor), MarkOfGraceVariation)
        return false
    ; Secondary must be within MarkOfGraceNearPixels of where primary was found — we click secondary only
    zone := {x1: Max(pa.x1, px - MarkOfGraceNearPixels), y1: Max(pa.y1, py - MarkOfGraceNearPixels), x2: Min(pa.x2, px + MarkOfGraceNearPixels), y2: Min(pa.y2, py + MarkOfGraceNearPixels)}
    if (!FindAndClickColor(MarkOfGraceSecondaryColor, MarkOfGraceVariation, zone))
        return false
    ; Wait until primary is no longer present; re-click secondary every 3s until primary is gone (max retries to avoid stuck)
    retries := 0
    while (retries < MarkOfGraceMaxRetries) {
        Sleep(MarkOfGraceRetryIntervalMs)
        if !PixelSearch(&px, &py, pa.x1, pa.y1, pa.x2, pa.y2, Integer(MarkOfGracePrimaryColor), MarkOfGraceVariation)
            break
        zone := {x1: Max(pa.x1, px - MarkOfGraceNearPixels), y1: Max(pa.y1, py - MarkOfGraceNearPixels), x2: Min(pa.x2, px + MarkOfGraceNearPixels), y2: Min(pa.y2, py + MarkOfGraceNearPixels)}
        FindAndClickColor(MarkOfGraceSecondaryColor, MarkOfGraceVariation, zone)
        retries++
    }
    return true
}

; --- Main logic ---
DoAgilityStep() {
    global IsRunning, CurrentStep, StepColors, StepColorVariation, StepColorVariationLedge, SelectedCourse
    global AgilityStatusAction, AgilityDebugLine
    global AgilityWaitingForCompletion, AgilityCompletionCheckAfter, AgilityCompletionTimeoutAt, AgilityCompletionMaxWaitMs
    global AgilityCompletionCheckDelayMs, AgilityWaitingForGap3, AgilityWaitingForStep1, MinClickIntervalMs, LastClickTime
    global CompletionAreaX1, CompletionAreaY1, CompletionAreaX2, CompletionAreaY2
    global CompletionColor, CompletionVariation
    global MarkOfGracePrimaryColor, MarkOfGraceSecondaryColor, MarkOfGraceVariation
    global NavTileColor, NavTileVariation, GapNavColor, GapNavVariation

    if (!IsRunning)
        return

    stepCount := GetStepCount(SelectedCourse)
    names := GetStepNames(SelectedCourse)
    AgilityDebugLine := "Step=" CurrentStep

    ; Health check: eat until healthy; if no food left, PAUSE to avoid death
    if (HealthCheckColor != "" && (HealthCheckX != 0 || HealthCheckY != 0)) {
        while (IsHealthLow()) {
            if (FindAndClickFoodInInventory()) {
                AgilityStatusAction := "Eating food (low health)..."
                Sleep(1500)
            } else {
                PauseAgility()
                AgilityStatusAction := "No food — PAUSED to avoid death"
                ToolTip("No food left — bot PAUSED. Restock food and press Ctrl+Shift+Q to resume.")
                SetTimer(() => ToolTip(), 8000)
                return
            }
        }
    }

    ; Varrock: after clicking gap nav, wait for Gap 3 color to show (no XP expected)
    if (AgilityWaitingForGap3) {
        gap3Color := StepColors.Has(6) ? StepColors[6] : ""
        pa := GetPlayArea()
        dx := 0
        dy := 0
        if (gap3Color != "" && PixelSearch(&dx, &dy, pa.x1, pa.y1, pa.x2, pa.y2, Integer(gap3Color), StepColorVariation)) {
            AgilityWaitingForGap3 := false
            AgilityStatusAction := "Gap 3 visible — will click next"
        } else {
            AgilityStatusAction := "Waiting for Gap 3..."
        }
        return
    }

    ; After clicking nav tile, wait for step 1 color to show (no XP expected)
    if (AgilityWaitingForStep1) {
        step1Color := StepColors.Has(1) ? StepColors[1] : ""
        pa := GetPlayArea()
        dx := 0
        dy := 0
        if (step1Color != "" && PixelSearch(&dx, &dy, pa.x1, pa.y1, pa.x2, pa.y2, Integer(step1Color), StepColorVariation)) {
            AgilityWaitingForStep1 := false
            AgilityStatusAction := "Step 1 visible — will click next"
        } else {
            AgilityStatusAction := "Waiting for step 1..."
        }
        return
    }

    ; If we clicked and are waiting for completion (XP drop only)
    if (AgilityWaitingForCompletion) {
        ; Don't check for XP until 2s after click (so we don't mistake previous XP for new one)
        if (A_TickCount < AgilityCompletionCheckAfter) {
            AgilityStatusAction := "Waiting..."
            return
        }
        ; Check completion: once we see XP (after 2s delay), advance immediately
        if (CompletionColor != "" && CompletionAreaX2 > CompletionAreaX1 && CompletionAreaY2 > CompletionAreaY1) {
            xpVisible := ColorInArea(CompletionAreaX1, CompletionAreaY1, CompletionAreaX2, CompletionAreaY2, CompletionColor, CompletionVariation)
            if (xpVisible) {
                ; XP seen — advance now (no need to wait for it to disappear)
                AgilityWaitingForCompletion := false
                nextStep := Mod(CurrentStep, stepCount) + 1
                nextColor := StepColors.Has(nextStep) ? StepColors[nextStep] : ""
                pa := GetPlayArea()
                dx := 0
                dy := 0
                nextVar := (SelectedCourse = "Varrock" && nextStep = 8) ? StepColorVariationLedge : StepColorVariation
                nextStepFound := (nextColor != "" && PixelSearch(&dx, &dy, pa.x1, pa.y1, pa.x2, pa.y2, Integer(nextColor), nextVar))
                navTileFound := (NavTileColor != "" && PixelSearch(&dx, &dy, pa.x1, pa.y1, pa.x2, pa.y2, Integer(NavTileColor), NavTileVariation))
                if (SelectedCourse = "Varrock" && !nextStepFound && navTileFound) {
                    ; Fell: only click nav if step 1 not visible; if step 1 visible, click step 1 obstacle
                    step1Color := StepColors.Has(1) ? StepColors[1] : ""
                    step1Found := (step1Color != "" && PixelSearch(&dx, &dy, pa.x1, pa.y1, pa.x2, pa.y2, Integer(step1Color), StepColorVariation))
                    if (step1Found) {
                        FindAndClickColor(step1Color, StepColorVariation, "")
                        AgilityWaitingForCompletion := true
                        AgilityCompletionCheckAfter := A_TickCount + AgilityCompletionCheckDelayMs
                        AgilityCompletionTimeoutAt := A_TickCount + AgilityCompletionMaxWaitMs
                        CurrentStep := 1
                        AgilityStatusAction := "Fell — step 1 visible, clicking obstacle"
                    } else {
                        FindAndClickColor(NavTileColor, NavTileVariation, "")
                        CurrentStep := 1
                        AgilityStatusAction := "Fell — navigating back to start"
                    }
                    return
                }
                ; Normal advance
                if (MarkOfGracePrimaryColor != "" && MarkOfGraceSecondaryColor != "")
                    FindMarkOfGraceAndClickSecondary()
                CurrentStep := nextStep
                AgilityStatusAction := "Completed — next: " names[CurrentStep]
                return
            }
        }
        ; Timeout: no XP in 15s — only treat as "fell" if nav visible AND current step color NOT visible
        if (A_TickCount >= AgilityCompletionTimeoutAt) {
            AgilityWaitingForCompletion := false
            pa := GetPlayArea()
            dx := 0
            dy := 0
            navTileVisible := (NavTileColor != "" && PixelSearch(&dx, &dy, pa.x1, pa.y1, pa.x2, pa.y2, Integer(NavTileColor), NavTileVariation))
            currentStepColor := StepColors.Has(CurrentStep) ? StepColors[CurrentStep] : ""
            stepVarTimeout := (SelectedCourse = "Varrock" && CurrentStep = 8) ? StepColorVariationLedge : StepColorVariation
            currentStepVisible := (currentStepColor != "" && PixelSearch(&dx, &dy, pa.x1, pa.y1, pa.x2, pa.y2, Integer(currentStepColor), stepVarTimeout))
            step1Color := StepColors.Has(1) ? StepColors[1] : ""
            step1Visible := (step1Color != "" && PixelSearch(&dx, &dy, pa.x1, pa.y1, pa.x2, pa.y2, Integer(step1Color), StepColorVariation))
            ; Nav only if current step AND step 1 not visible; if step 1 visible, click step 1 not nav
            if (navTileVisible && !currentStepVisible && step1Visible) {
                FindAndClickColor(step1Color, StepColorVariation, "")
                AgilityWaitingForCompletion := true
                AgilityCompletionCheckAfter := A_TickCount + AgilityCompletionCheckDelayMs
                AgilityCompletionTimeoutAt := A_TickCount + AgilityCompletionMaxWaitMs
                CurrentStep := 1
                AgilityStatusAction := "Timeout — step 1 visible, clicking obstacle"
                return
            }
            if (navTileVisible && !currentStepVisible && !step1Visible) {
                FindAndClickColor(NavTileColor, NavTileVariation, "")
                CurrentStep := 1
                AgilityStatusAction := "Fell (timeout) — navigating back to start"
                return
            }
            AgilityStatusAction := "No XP in 15s — retrying step " CurrentStep " (" names[CurrentStep] ")"
            return
        }
        AgilityStatusAction := "Waiting for XP drop..."
        return
    }

    ; Enforce minimum time between clicks (2 seconds)
    if ((A_TickCount - LastClickTime) < MinClickIntervalMs) {
        AgilityStatusAction := "Waiting " (MinClickIntervalMs - (A_TickCount - LastClickTime)) " ms before next click..."
        return
    }

    ; Get color for current step
    c := StepColors.Has(CurrentStep) ? StepColors[CurrentStep] : ""
    if (c = "") {
        AgilityStatusAction := "Set step " CurrentStep " color (Ctrl+Shift+C)"
        return
    }
    ; Ledge (Varrock step 8): use stricter variation to avoid misclicks
    stepVar := (SelectedCourse = "Varrock" && CurrentStep = 8) ? StepColorVariationLedge : StepColorVariation

    ; Step 1: try obstacle first, then nav tile (walk to start) if obstacle not visible (nav has no XP — wait for step 1 color)
    ; Varrock step 6 (Gap 3): try obstacle first, then gap nav if MoG blocking view (gap nav has no XP — wait for Gap 3 color)
    clicked := false
    clickedGapNav := false
    clickedNavTile := false
    if (CurrentStep = 1 && NavTileColor != "") {
        clicked := FindAndClickColor(c, stepVar, "")
        if (!clicked) {
            clickedNavTile := FindAndClickColor(NavTileColor, NavTileVariation, "")
            clicked := clickedNavTile
        }
    } else if (SelectedCourse = "Varrock" && CurrentStep = 6 && GapNavColor != "") {
        clicked := FindAndClickColor(c, stepVar, "")
        if (!clicked) {
            clickedGapNav := FindAndClickColor(GapNavColor, GapNavVariation, "")
            clicked := clickedGapNav
        }
    } else
        clicked := FindAndClickColor(c, stepVar, "")

    if (clicked) {
        if (clickedNavTile) {
            AgilityWaitingForStep1 := true
            AgilityStatusAction := "Clicked nav — waiting for step 1"
        } else if (clickedGapNav) {
            AgilityWaitingForGap3 := true
            AgilityStatusAction := "Clicked gap nav — waiting for Gap 3"
        } else {
            AgilityWaitingForCompletion := true
            AgilityCompletionCheckAfter := A_TickCount + AgilityCompletionCheckDelayMs
            AgilityCompletionTimeoutAt := A_TickCount + AgilityCompletionMaxWaitMs
            AgilityStatusAction := "Clicked — waiting for XP drop"
        }
    } else {
        AgilityStatusAction := "Looking for step " CurrentStep
    }
}

; --- Build and run ---
BuildStatusGui()
BuildPlayAreaOverlay()
SetTimer(UpdateStatusGui, 500)
UpdateStatusGui()
