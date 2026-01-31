#Requires AutoHotkey v2.0

; --- State ---
global IsRunning := false
global ConfigPath := A_ScriptDir "\Woodcut.ini"

; Play area – only search/click inside this rect (0,0,0,0 = full screen)
global PlayAreaX1 := 0
global PlayAreaY1 := 0
global PlayAreaX2 := 0
global PlayAreaY2 := 0
global PlayAreaOverlayGuis := []
global CornerMarkSize := 30

; Last inventory slot: area + color when full (logs in slot)
global InvSlotX1 := 0
global InvSlotY1 := 0
global InvSlotX2 := 0
global InvSlotY2 := 0
global InvSlotFullColor := ""      ; color when logs in last slot (inventory full)
global InvSlotVariation := 15
global IsInventoryFull := false
global InvSlotCheckInterval := 500
global InvSlotOverlayGuis := []
global InvSlotCornerSize := 8

; Nav1 tile (walk to bank / walk back to trees)
global Nav1Color := ""
global Nav1Variation := 5

; Deposit box (click to open)
global DepositBoxColor := ""
global DepositBoxVariation := 5

; Tree color (click to chop)
global TreeColor := ""
global TreeColorVariation := 10

; Woodcutting status: area + color (color in area = actively woodcutting)
global WcStatusX1 := 0
global WcStatusY1 := 0
global WcStatusX2 := 0
global WcStatusY2 := 0
global WcStatusColor := ""
global WcStatusVariation := 15
global WcStatusOverlayGuis := []
global WcStatusCornerSize := 8

; Deposit area + color (deposit box open: area where deposit button is; click color = deposit-all)
global DepositAreaX1 := 0
global DepositAreaY1 := 0
global DepositAreaX2 := 0
global DepositAreaY2 := 0
global DepositColor := ""          ; color of deposit-all button to click
global DepositColorVariation := 15

; Run duration (0 = unlimited)
global RunDurationMinutes := 0
global RunStartTime := 0

; Phase: "cutting" | "banking"
global WoodcutPhase := "cutting"
; Banking step: 0=idle, 1=find bank (nav1 or deposit), 2=wait deposit open, 3=click deposit, 4=wait deposit done
; BankSubStep for step 1: 0=normal, 1=waiting after nav1, 2=nav1 failed 5x, waiting before deposit try, 3=try deposit 5x
global BankStep := 0
global BankSubStep := 0
global BankWaitUntil := 0
global BankNav1FailCount := 0
global BankDepositBoxFailCount := 0
global MaxNav1Attempts := 5
global MaxDepositBoxAttempts := 5

; Main loop interval (faster = snappier when moving)
global MainLoopInterval := 350
global CuttingNav1WaitUntil := 0   ; when we clicked nav1 (no tree), wait before next action
global TreeClickWaitUntil := 0     ; cooldown after clicking a tree (3-5 seconds)
global CuttingNav1Clicked := false ; true after clicking nav1 (waiting for trees), reset when we click a tree
global TreeClickNoWcCount := 0    ; tree clicks without woodcutting status; pause if reaches 10
global ClickJitter := 1
global ClickDelayMs := 50
global RadiusStep := 80
global BoundsScanStep := 3        ; step when finding tree edges (smaller = more accurate, slower)
global BoundsMaxDist := 45       ; max px from first pixel when finding edges

global WcStatusAction := ""
global WcDebugLine := ""

CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

; --- Load config ---
LoadConfig() {
    global ConfigPath
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotFullColor
    global Nav1Color, DepositBoxColor, TreeColor
    global WcStatusX1, WcStatusY1, WcStatusX2, WcStatusY2, WcStatusColor
    global DepositAreaX1, DepositAreaY1, DepositAreaX2, DepositAreaY2, DepositColor
    global RunDurationMinutes
    try {
        if FileExist(ConfigPath) {
            PlayAreaX1 := Integer(IniRead(ConfigPath, "PlayArea", "X1", "0"))
            PlayAreaY1 := Integer(IniRead(ConfigPath, "PlayArea", "Y1", "0"))
            PlayAreaX2 := Integer(IniRead(ConfigPath, "PlayArea", "X2", "0"))
            PlayAreaY2 := Integer(IniRead(ConfigPath, "PlayArea", "Y2", "0"))
            InvSlotX1 := Integer(IniRead(ConfigPath, "InvSlot", "X1", "0"))
            InvSlotY1 := Integer(IniRead(ConfigPath, "InvSlot", "Y1", "0"))
            InvSlotX2 := Integer(IniRead(ConfigPath, "InvSlot", "X2", "0"))
            InvSlotY2 := Integer(IniRead(ConfigPath, "InvSlot", "Y2", "0"))
            fc := IniRead(ConfigPath, "InvSlot", "FullColor", "")
            if (fc != "")
                InvSlotFullColor := "0x" fc
            n1 := IniRead(ConfigPath, "Banking", "Nav1Color", "")
            if (n1 != "")
                Nav1Color := "0x" n1
            db := IniRead(ConfigPath, "Banking", "DepositBoxColor", "")
            if (db != "")
                DepositBoxColor := "0x" db
            tc := IniRead(ConfigPath, "Tree", "Color", "")
            if (tc != "")
                TreeColor := "0x" tc
            WcStatusX1 := Integer(IniRead(ConfigPath, "WcStatus", "X1", "0"))
            WcStatusY1 := Integer(IniRead(ConfigPath, "WcStatus", "Y1", "0"))
            WcStatusX2 := Integer(IniRead(ConfigPath, "WcStatus", "X2", "0"))
            WcStatusY2 := Integer(IniRead(ConfigPath, "WcStatus", "Y2", "0"))
            wsc := IniRead(ConfigPath, "WcStatus", "Color", "")
            if (wsc != "")
                WcStatusColor := "0x" wsc
            DepositAreaX1 := Integer(IniRead(ConfigPath, "DepositArea", "X1", "0"))
            DepositAreaY1 := Integer(IniRead(ConfigPath, "DepositArea", "Y1", "0"))
            DepositAreaX2 := Integer(IniRead(ConfigPath, "DepositArea", "X2", "0"))
            DepositAreaY2 := Integer(IniRead(ConfigPath, "DepositArea", "Y2", "0"))
            dc := IniRead(ConfigPath, "DepositArea", "Color", "")
            if (dc != "")
                DepositColor := "0x" dc
            RunDurationMinutes := Integer(IniRead(ConfigPath, "Settings", "RunDurationMinutes", "0"))
            if (RunDurationMinutes < 0)
                RunDurationMinutes := 0
        }
    } catch
        {}
}
LoadConfig()

; --- Status GUI ---
global StatusGui := ""

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
    global StatusGui, RunDurationMinutes
    StatusGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow")
    StatusGui.BackColor := "1e1e1e"
    StatusGui.SetFont("s9 cD0D0D0", "Segoe UI")
    StatusGui.MarginX := 12
    StatusGui.MarginY := 6
    StatusGui.Add("Text", "Section", "Woodcutting Bot")
    StatusGui.Add("Text", "vStatusText xs", "Paused  |  Cutting  |  Inv: --")
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
    StatusGui.Add("Text", "vPlayAreaRow xs y+2", "[—] Play area        Ctrl+Shift+B (TL)  Ctrl+Shift+N (BR)")
    StatusGui.Add("Text", "vInvSlotRow xs", "[—] Last inv slot     Ctrl+Shift+I (TL)  Ctrl+Shift+O (BR)  Ctrl+Shift+A (full color)")
    StatusGui.Add("Text", "vNav1Row xs", "[—] Nav1 tile         Ctrl+Shift+1")
    StatusGui.Add("Text", "vDepositBoxRow xs", "[—] Deposit box       Ctrl+Shift+D")
    StatusGui.Add("Text", "vTreeRow xs", "[—] Tree color        Ctrl+Shift+T")
    StatusGui.Add("Text", "vWcStatusRow xs", "[—] Woodcut status   Ctrl+Shift+Y (TL)  Ctrl+Shift+U (BR)  Ctrl+Shift+V (color)")
    StatusGui.Add("Text", "vDepositRow xs", "[—] Deposit area     Ctrl+Shift+E (TL)  Ctrl+Shift+R (BR)  Ctrl+Shift+F (color)")
    StatusGui.Add("Text", "xs y+8", "Hotkeys:")
    StatusGui.Add("Text", "vHotkeysRow xs y+2", "Start Ctrl+Shift+Q  |  Pause Ctrl+Shift+W  |  Exit Ctrl+Shift+X")
    StatusGui.Show("x" (A_ScreenWidth - 520) " y10 NoActivate w500")
}

UpdateStatusGui() {
    global StatusGui, IsRunning, WoodcutPhase, BankStep, RunDurationMinutes, RunStartTime, ConfigPath
    global IsInventoryFull, WcStatusAction, WcDebugLine
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotFullColor
    global Nav1Color, DepositBoxColor, TreeColor
    global WcStatusX1, WcStatusY1, WcStatusX2, WcStatusY2, WcStatusColor
    global DepositAreaX1, DepositAreaY1, DepositAreaX2, DepositAreaY2, DepositColor
    if !StatusGui
        return
    try {
        runMin := Integer(StatusGui["RunMinutes"].Value)
        if (runMin < 0) runMin := 0
        if (IsRunning && runMin > 0 && RunStartTime > 0) {
            elapsed := A_TickCount - RunStartTime
            if (elapsed >= runMin * 60000) {
                PauseWoodcut()
                ToolTip("Run duration reached (" runMin " min).")
                SetTimer(() => ToolTip(), 3000)
                return
            }
            rem := (runMin * 60000) - elapsed
            sec := Max(0, Round(rem / 1000))
            SetGuiText(StatusGui["TimerText"], "Time left: " (sec // 60) ":" (Format("{:02}", Mod(sec, 60))))
        } else
            SetGuiText(StatusGui["TimerText"], "Time left: --")
    } catch
        SetGuiText(StatusGui["TimerText"], "Time left: --")
    runTxt := IsRunning ? "Running" : "Paused"
    phaseTxt := WoodcutPhase = "banking" ? "Banking" : "Cutting"
    invTxt := (InvSlotX2 > InvSlotX1 && InvSlotY2 > InvSlotY1) ? (IsInventoryFull ? "Inv: Full" : "Inv: OK") : "Inv: --"
    SetGuiText(StatusGui["StatusText"], runTxt "  |  " phaseTxt "  |  " invTxt)
    actionTxt := WcStatusAction != "" ? WcStatusAction : (IsRunning ? (WoodcutPhase = "banking" ? "Banking..." : "Cutting trees") : "Idle")
    debugTxt := WcDebugLine != "" ? WcDebugLine : ("Phase=" WoodcutPhase " BankStep=" BankStep)
    StatusGui["ActionText"].Value := "Action: " actionTxt
    StatusGui["DebugText"].Value := "Debug: " debugTxt
    ; Config checkmarks
    pSet := (PlayAreaX2 > PlayAreaX1 && PlayAreaY2 > PlayAreaY1)
    iSet := (InvSlotX2 > InvSlotX1 && InvSlotY2 > InvSlotY1 && InvSlotFullColor != "")
    n1Set := (Nav1Color != "")
    dbSet := (DepositBoxColor != "")
    tSet := (TreeColor != "")
    wsSet := (WcStatusX2 > WcStatusX1 && WcStatusY2 > WcStatusY1 && WcStatusColor != "")
    dSet := (DepositAreaX2 > DepositAreaX1 && DepositAreaY2 > DepositAreaY1 && DepositColor != "")
    SetGuiText(StatusGui["PlayAreaRow"], "[" (pSet ? "✓" : "—") "] Play area        Ctrl+Shift+B (TL)  Ctrl+Shift+N (BR)")
    SetGuiText(StatusGui["InvSlotRow"], "[" (iSet ? "✓" : "—") "] Last inv slot     Ctrl+Shift+I (TL)  Ctrl+Shift+O (BR)  Ctrl+Shift+A (full color)")
    SetGuiText(StatusGui["Nav1Row"], "[" (n1Set ? "✓" : "—") "] Nav1 tile         Ctrl+Shift+1")
    SetGuiText(StatusGui["DepositBoxRow"], "[" (dbSet ? "✓" : "—") "] Deposit box       Ctrl+Shift+D")
    SetGuiText(StatusGui["TreeRow"], "[" (tSet ? "✓" : "—") "] Tree color        Ctrl+Shift+T")
    SetGuiText(StatusGui["WcStatusRow"], "[" (wsSet ? "✓" : "—") "] Woodcut status   Ctrl+Shift+Y (TL)  Ctrl+Shift+U (BR)  Ctrl+Shift+V (color)")
    SetGuiText(StatusGui["DepositRow"], "[" (dSet ? "✓" : "—") "] Deposit area     Ctrl+Shift+E (TL)  Ctrl+Shift+R (BR)  Ctrl+Shift+F (color)")
}

; --- Overlays ---
BuildPlayAreaOverlay() {
    global PlayAreaOverlayGuis, PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2, CornerMarkSize
    for g in PlayAreaOverlayGuis {
        try
            g.Destroy()
        catch
            continue
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

BuildInvSlotOverlay() {
    global InvSlotOverlayGuis, InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotCornerSize
    for g in InvSlotOverlayGuis {
        try
            g.Destroy()
        catch
            continue
    }
    InvSlotOverlayGuis := []
    if (InvSlotX2 <= InvSlotX1 || InvSlotY2 <= InvSlotY1)
        return
    L := InvSlotCornerSize
    W := 2
    line(x, y, w, h) {
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
        g.BackColor := "00FFFF"
        g.Show("x" x " y" y " w" w " h" h " NoActivate")
        return g
    }
    InvSlotOverlayGuis.Push(line(InvSlotX1, InvSlotY1, W, L))
    InvSlotOverlayGuis.Push(line(InvSlotX1, InvSlotY1, L, W))
    InvSlotOverlayGuis.Push(line(InvSlotX2 - W, InvSlotY1, W, L))
    InvSlotOverlayGuis.Push(line(InvSlotX2 - L, InvSlotY1, L, W))
    InvSlotOverlayGuis.Push(line(InvSlotX1, InvSlotY2 - L, W, L))
    InvSlotOverlayGuis.Push(line(InvSlotX1, InvSlotY2 - W, L, W))
    InvSlotOverlayGuis.Push(line(InvSlotX2 - W, InvSlotY2 - L, W, L))
    InvSlotOverlayGuis.Push(line(InvSlotX2 - L, InvSlotY2 - W, L, W))
}

BuildWcStatusOverlay() {
    global WcStatusOverlayGuis, WcStatusX1, WcStatusY1, WcStatusX2, WcStatusY2, WcStatusCornerSize
    for g in WcStatusOverlayGuis {
        try
            g.Destroy()
        catch
            continue
    }
    WcStatusOverlayGuis := []
    if (WcStatusX2 <= WcStatusX1 || WcStatusY2 <= WcStatusY1)
        return
    L := WcStatusCornerSize
    W := 2
    line(x, y, w, h) {
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
        g.BackColor := "FFFF00"
        g.Show("x" x " y" y " w" w " h" h " NoActivate")
        return g
    }
    WcStatusOverlayGuis.Push(line(WcStatusX1, WcStatusY1, W, L))
    WcStatusOverlayGuis.Push(line(WcStatusX1, WcStatusY1, L, W))
    WcStatusOverlayGuis.Push(line(WcStatusX2 - W, WcStatusY1, W, L))
    WcStatusOverlayGuis.Push(line(WcStatusX2 - L, WcStatusY1, L, W))
    WcStatusOverlayGuis.Push(line(WcStatusX1, WcStatusY2 - L, W, L))
    WcStatusOverlayGuis.Push(line(WcStatusX1, WcStatusY2 - W, L, W))
    WcStatusOverlayGuis.Push(line(WcStatusX2 - W, WcStatusY2 - L, W, L))
    WcStatusOverlayGuis.Push(line(WcStatusX2 - L, WcStatusY2 - W, L, W))
}

; --- Hotkeys ---
^+q:: StartWoodcut()
^+w:: PauseWoodcut()
^+x:: ExitWoodcut()
^+b:: SetPlayAreaTL()
^+n:: SetPlayAreaBR()
^+i:: SetInvSlotTL()
^+o:: SetInvSlotBR()
^+a:: SetInvSlotFullColor()
^+1:: SetNav1Color()
^+d:: SetDepositBoxColor()
^+t:: SetTreeColor()
^+y:: SetWcStatusTL()
^+u:: SetWcStatusBR()
^+v:: SetWcStatusColor()
^+e:: SetDepositAreaTL()
^+r:: SetDepositAreaBR()
^+f:: SetDepositColor()

; --- Start / Pause / Exit ---
StartWoodcut() {
    global IsRunning, RunDurationMinutes, RunStartTime, StatusGui, ConfigPath
    global WoodcutPhase, BankStep, BankNav1FailCount, BankDepositBoxFailCount
    if (IsRunning)
        return
    try {
        RunDurationMinutes := Integer(StatusGui["RunMinutes"].Value)
        if (RunDurationMinutes < 0) RunDurationMinutes := 0
        IniWrite(String(RunDurationMinutes), ConfigPath, "Settings", "RunDurationMinutes")
    } catch
        {}
    RunStartTime := A_TickCount
    IsRunning := true
    WoodcutPhase := "cutting"
    BankStep := 0
    BankSubStep := 0
    BankNav1FailCount := 0
    BankDepositBoxFailCount := 0
    TreeClickNoWcCount := 0
    SetTimer(DoWoodcutStep, MainLoopInterval)
    SetTimer(UpdateInvSlotState, InvSlotCheckInterval)
    ToolTip("Woodcutting bot: Running")
    SetTimer(() => ToolTip(), 2000)
}

PauseWoodcut() {
    global IsRunning, RunStartTime
    IsRunning := false
    RunStartTime := 0
    SetTimer(DoWoodcutStep, 0)
    SetTimer(UpdateInvSlotState, 0)
    ToolTip("Woodcutting bot: Paused")
    SetTimer(() => ToolTip(), 2000)
}

ExitWoodcut() {
    global IsRunning
    IsRunning := false
    SetTimer(DoWoodcutStep, 0)
    SetTimer(UpdateInvSlotState, 0)
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

SetInvSlotTL() {
    global InvSlotX1, InvSlotY1, ConfigPath
    MouseGetPos(&mx, &my)
    InvSlotX1 := mx
    InvSlotY1 := my
       try {
        IniWrite(String(mx), ConfigPath, "InvSlot", "X1")
        IniWrite(String(my), ConfigPath, "InvSlot", "Y1")
    } catch
        {}
    ToolTip("Last inv slot TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildInvSlotOverlay()
}

SetInvSlotBR() {
    global InvSlotX2, InvSlotY2, ConfigPath
    MouseGetPos(&mx, &my)
    InvSlotX2 := mx
    InvSlotY2 := my
       try {
        IniWrite(String(mx), ConfigPath, "InvSlot", "X2")
        IniWrite(String(my), ConfigPath, "InvSlot", "Y2")
    } catch
        {}
    ToolTip("Last inv slot BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildInvSlotOverlay()
}

SetInvSlotFullColor() {
    global InvSlotFullColor, ConfigPath
    MouseGetPos(&mx, &my)
    InvSlotFullColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(InvSlotFullColor, 3), ConfigPath, "InvSlot", "FullColor")
    catch
        {}
    ToolTip("Last inv slot full color (logs) set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetNav1Color() {
    global Nav1Color, ConfigPath
    MouseGetPos(&mx, &my)
    Nav1Color := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(Nav1Color, 3), ConfigPath, "Banking", "Nav1Color")
    catch
        {}
    ToolTip("Nav1 tile color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetDepositBoxColor() {
    global DepositBoxColor, ConfigPath
    MouseGetPos(&mx, &my)
    DepositBoxColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(DepositBoxColor, 3), ConfigPath, "Banking", "DepositBoxColor")
    catch
        {}
    ToolTip("Deposit box color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetTreeColor() {
    global TreeColor, ConfigPath
    MouseGetPos(&mx, &my)
    TreeColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(TreeColor, 3), ConfigPath, "Tree", "Color")
    catch
        {}
    ToolTip("Tree color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetWcStatusTL() {
    global WcStatusX1, WcStatusY1, ConfigPath
    MouseGetPos(&mx, &my)
    WcStatusX1 := mx
    WcStatusY1 := my
       try {
        IniWrite(String(mx), ConfigPath, "WcStatus", "X1")
        IniWrite(String(my), ConfigPath, "WcStatus", "Y1")
    } catch
        {}
    ToolTip("Woodcut status area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildWcStatusOverlay()
}

SetWcStatusBR() {
    global WcStatusX2, WcStatusY2, ConfigPath
    MouseGetPos(&mx, &my)
    WcStatusX2 := mx
    WcStatusY2 := my
       try {
        IniWrite(String(mx), ConfigPath, "WcStatus", "X2")
        IniWrite(String(my), ConfigPath, "WcStatus", "Y2")
    } catch
        {}
    ToolTip("Woodcut status area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildWcStatusOverlay()
}

SetWcStatusColor() {
    global WcStatusColor, ConfigPath
    MouseGetPos(&mx, &my)
    WcStatusColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(WcStatusColor, 3), ConfigPath, "WcStatus", "Color")
    catch
        {}
    ToolTip("Woodcut status color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetDepositAreaTL() {
    global DepositAreaX1, DepositAreaY1, ConfigPath
    MouseGetPos(&mx, &my)
    DepositAreaX1 := mx
    DepositAreaY1 := my
       try {
        IniWrite(String(mx), ConfigPath, "DepositArea", "X1")
        IniWrite(String(my), ConfigPath, "DepositArea", "Y1")
    } catch
        {}
    ToolTip("Deposit area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetDepositAreaBR() {
    global DepositAreaX2, DepositAreaY2, ConfigPath
    MouseGetPos(&mx, &my)
    DepositAreaX2 := mx
    DepositAreaY2 := my
       try {
        IniWrite(String(mx), ConfigPath, "DepositArea", "X2")
        IniWrite(String(my), ConfigPath, "DepositArea", "Y2")
    } catch
        {}
    ToolTip("Deposit area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetDepositColor() {
    global DepositColor, ConfigPath
    MouseGetPos(&mx, &my)
    DepositColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(DepositColor, 3), ConfigPath, "DepositArea", "Color")
    catch
        {}
    ToolTip("Deposit button color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

; --- Helpers ---
ColorsMatch(c1, c2, variation) {
    c1 := Integer(c1)
    c2 := Integer(c2)
    return (Abs((c1>>16)&0xFF - (c2>>16)&0xFF) <= variation && Abs((c1>>8)&0xFF - (c2>>8)&0xFF) <= variation && Abs(c1&0xFF - c2&0xFF) <= variation)
}

ColorInArea(x1, y1, x2, y2, targetColor, variation) {
    try
        return PixelSearch(&ox, &oy, x1, y1, x2, y2, Integer(targetColor), variation)
    catch
        return false
}

GetPlayArea() {
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    if (PlayAreaX2 > PlayAreaX1 && PlayAreaY2 > PlayAreaY1)
        return {x1: PlayAreaX1, y1: PlayAreaY1, x2: PlayAreaX2, y2: PlayAreaY2}
    return {x1: 0, y1: 0, x2: A_ScreenWidth, y2: A_ScreenHeight}
}

; Find color in play area and click. useBbox=true: find edges of colored region, click center (reliable).
FindAndClickColor(targetColor, colorVariation, useBbox := true) {
    global ClickJitter, ClickDelayMs, RadiusStep, BoundsScanStep, BoundsMaxDist
    pa := GetPlayArea()
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
    if (useBbox) {
        ; Bounding box: find edges of colored region, click center (avoids clicking through)
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
    } else {
        clickX := foundX
        clickY := foundY
    }
    if (ClickJitter > 0) {
        clickX += Random(-ClickJitter, ClickJitter)
        clickY += Random(-ClickJitter, ClickJitter)
    }
    clickX := Max(pa.x1, Min(pa.x2, clickX))
    clickY := Max(pa.y1, Min(pa.y2, clickY))
    MouseMove(clickX, clickY)
    ; Give game time to register hover before click (fixes clicking through objects)
    if (ClickDelayMs > 0)
        Sleep(ClickDelayMs + Random(0, 40))
    Click()
    return true
}

; Update inv slot: full when last-slot full color exists in area
UpdateInvSlotState() {
    global IsInventoryFull, InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotFullColor, InvSlotVariation
    if (InvSlotX2 <= InvSlotX1 || InvSlotY2 <= InvSlotY1 || InvSlotFullColor = "")
        return
    IsInventoryFull := ColorInArea(InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotFullColor, InvSlotVariation)
}

; True if woodcutting status color exists in status area
IsWoodcutting() {
    global WcStatusX1, WcStatusY1, WcStatusX2, WcStatusY2, WcStatusColor, WcStatusVariation
    if (WcStatusX2 <= WcStatusX1 || WcStatusY2 <= WcStatusY1 || WcStatusColor = "")
        return false
    return ColorInArea(WcStatusX1, WcStatusY1, WcStatusX2, WcStatusY2, WcStatusColor, WcStatusVariation)
}

; True if deposit color exists in deposit area (box open, deposit button visible)
IsDepositVisible() {
    global DepositAreaX1, DepositAreaY1, DepositAreaX2, DepositAreaY2, DepositColor, DepositColorVariation
    if (DepositAreaX2 <= DepositAreaX1 || DepositAreaY2 <= DepositAreaY1 || DepositColor = "")
        return false
    return ColorInArea(DepositAreaX1, DepositAreaY1, DepositAreaX2, DepositAreaY2, DepositColor, DepositColorVariation)
}

; Click deposit color within deposit area
ClickDepositInArea() {
    global DepositAreaX1, DepositAreaY1, DepositAreaX2, DepositAreaY2, DepositColor, DepositColorVariation
    global ClickJitter, ClickDelayMs
    if (DepositAreaX2 <= DepositAreaX1 || DepositAreaY2 <= DepositAreaY1 || DepositColor = "")
        return false
    try {
        if PixelSearch(&ox, &oy, DepositAreaX1, DepositAreaY1, DepositAreaX2, DepositAreaY2, Integer(DepositColor), DepositColorVariation) {
            clickX := ox + (ClickJitter ? Random(-ClickJitter, ClickJitter) : 0)
            clickY := oy + (ClickJitter ? Random(-ClickJitter, ClickJitter) : 0)
            MouseMove(clickX, clickY)
            if (ClickDelayMs > 0) Sleep(ClickDelayMs)
            Click()
            return true
        }
    } catch
        {}
    return false
}

; --- Main logic ---
DoWoodcutStep() {
    global IsRunning, WoodcutPhase, BankStep, BankWaitUntil
    global BankNav1FailCount, BankDepositBoxFailCount, BankSubStep
    global IsInventoryFull, CuttingNav1WaitUntil, TreeClickWaitUntil, CuttingNav1Clicked, TreeClickNoWcCount
    global TreeColor, TreeColorVariation, Nav1Color, Nav1Variation
    global DepositBoxColor, DepositBoxVariation
    global WcStatusAction, WcDebugLine

    if (!IsRunning)
        return

    ; Transition to banking when inventory full
    if (IsInventoryFull && WoodcutPhase = "cutting") {
        WoodcutPhase := "banking"
        BankStep := 1
        BankSubStep := 0
        BankNav1FailCount := 0
        BankDepositBoxFailCount := 0
        TreeClickNoWcCount := 0
    }

    if (WoodcutPhase = "banking") {
        DoBankingStep()
        return
    }

    ; --- Cutting phase ---
    WcDebugLine := "Phase=cutting"

    ; Start of cutting: need tree. If tree visible, click. If not, click nav1 and wait.
    ; During cutting: if we see tree AND status color NOT in area -> click tree. Trees can be gone (ok).
    if (TreeColor = "") {
        WcStatusAction := "Set tree color (Ctrl+Shift+T)"
        return
    }

    pa := GetPlayArea()
    treeVisible := ColorInArea(pa.x1, pa.y1, pa.x2, pa.y2, TreeColor, TreeColorVariation)
    isWcing := IsWoodcutting()

    ; Reset failsafe counter when woodcutting status appears
    if (isWcing)
        TreeClickNoWcCount := 0

    ; If tree visible and NOT woodcutting -> click tree (respect cooldown)
    if (treeVisible && !isWcing) {
        if (A_TickCount < TreeClickWaitUntil) {
            WcStatusAction := "Waiting after tree click..."
            return
        }
        ; Failsafe: 10 tree clicks with no woodcutting status = pause
        if (TreeClickNoWcCount >= 10) {
            PauseWoodcut()
            ToolTip("Tree clicks failed 10 times (woodcutting never started). Paused.")
            SetTimer(() => ToolTip(), 5000)
            WcStatusAction := "PAUSED: Tree clicks not registering"
            return
        }
        if (FindAndClickColor(TreeColor, TreeColorVariation, true)) {
            TreeClickNoWcCount++
            WcStatusAction := "Clicked tree (" TreeClickNoWcCount "/10)"
            TreeClickWaitUntil := A_TickCount + Random(3000, 5000)
            CuttingNav1Clicked := false  ; reset so we can click nav1 again if trees disappear
        } else {
            WcStatusAction := "Tree visible but click failed"
        }
        return
    }

    ; If no tree visible: click nav1 ONCE and then just wait for trees
    if (!treeVisible && Nav1Color != "") {
        ; Already clicked nav1, just wait for trees
        if (CuttingNav1Clicked) {
            WcStatusAction := "Waiting for trees..."
            return
        }
        ; Click nav1 once
        if (FindAndClickColor(Nav1Color, Nav1Variation, true)) {
            WcStatusAction := "No tree — clicked nav1, waiting for trees"
            CuttingNav1Clicked := true
        } else {
            WcStatusAction := "No tree — nav1 not found"
        }
        return
    }

    ; Tree visible and woodcutting, or no tree (trees gone for a while - ok)
    if (treeVisible && isWcing)
        WcStatusAction := "Woodcutting..."
    else if (!treeVisible && Nav1Color = "")
        WcStatusAction := "No tree, set Nav1 (Ctrl+Shift+1)"
    else
        WcStatusAction := "Waiting for tree"
}

DoBankingStep() {
    global IsRunning, WoodcutPhase, BankStep, BankSubStep, BankWaitUntil
    global BankNav1FailCount, BankDepositBoxFailCount, MaxNav1Attempts, MaxDepositBoxAttempts
    global Nav1Color, Nav1Variation, DepositBoxColor, DepositBoxVariation
    global WcStatusAction, WcDebugLine

    if (!IsRunning)
        return

    WcDebugLine := "Phase=banking Step=" BankStep " sub=" BankSubStep " n1Fail=" BankNav1FailCount " dbFail=" BankDepositBoxFailCount

    ; Step 1: Find bank. SubStep: 0=normal, 1=waiting after nav1, 2=waiting before deposit try, 3=try deposit 5x
    if (BankStep = 1) {
        pa := GetPlayArea()
        depositBoxVisible := (DepositBoxColor != "" && ColorInArea(pa.x1, pa.y1, pa.x2, pa.y2, DepositBoxColor, DepositBoxVariation))

        ; SubStep 1: waiting after nav1 click - check if wait elapsed
        if (BankSubStep = 1) {
            if (A_TickCount >= BankWaitUntil) {
                BankSubStep := 0
                ; Fall through to check deposit box again
            } else {
                WcStatusAction := "Waiting after nav1..."
                return
            }
        }

        ; SubStep 2: nav1 failed 5x, waiting 5-7s before deposit box try
        if (BankSubStep = 2) {
            if (A_TickCount >= BankWaitUntil) {
                BankSubStep := 3
                ; Fall through to try deposit box
            } else {
                WcStatusAction := "Nav1 failed — wait 5-7s..."
                return
            }
        }

        ; Check deposit box first (or after nav1 wait)
        if (depositBoxVisible) {
            if (FindAndClickColor(DepositBoxColor, DepositBoxVariation, false)) {
                BankStep := 2
                BankSubStep := 0
                BankWaitUntil := A_TickCount + Random(5000, 7000)
                WcStatusAction := "Clicked deposit box — wait for open"
            }
            return
        }

        ; SubStep 3: try deposit box 5 times (last resort after nav1 failed 5x)
        if (BankSubStep = 3) {
            if (DepositBoxColor = "") {
                PauseWoodcut()
                ToolTip("Unable to find bank. Deposit box color not set. Paused.")
                SetTimer(() => ToolTip(), 5000)
                WcStatusAction := "PAUSED: No deposit box color"
                return
            }
            if (FindAndClickColor(DepositBoxColor, DepositBoxVariation, false)) {
                BankStep := 2
                BankSubStep := 0
                BankWaitUntil := A_TickCount + Random(5000, 7000)
                WcStatusAction := "Clicked deposit box — wait for open"
            } else {
                BankDepositBoxFailCount++
                if (BankDepositBoxFailCount >= MaxDepositBoxAttempts) {
                    PauseWoodcut()
                    ToolTip("Unable to find bank. Nav1 and deposit box failed 5 times. Paused.")
                    SetTimer(() => ToolTip(), 5000)
                    WcStatusAction := "PAUSED: Unable to find bank"
                } else {
                    WcStatusAction := "Deposit box not found (" BankDepositBoxFailCount "/" MaxDepositBoxAttempts ")"
                }
            }
            return
        }

        ; Normal: deposit box not visible. Try nav1.
        if (Nav1Color != "" && BankNav1FailCount < MaxNav1Attempts) {
            if (FindAndClickColor(Nav1Color, Nav1Variation, true)) {
                BankSubStep := 1
                BankWaitUntil := A_TickCount + Random(5000, 7000)
                WcStatusAction := "Clicked nav1 — waiting"
            } else {
                BankNav1FailCount++
                WcStatusAction := "Nav1 not found (" BankNav1FailCount "/" MaxNav1Attempts ")"
                if (BankNav1FailCount >= MaxNav1Attempts) {
                    BankSubStep := 2
                    BankWaitUntil := A_TickCount + Random(5000, 7000)
                }
            }
            return
        }

        ; Nav1 failed 5 times or not set - enter last resort
        if (BankNav1FailCount >= MaxNav1Attempts) {
            BankSubStep := 2
            BankWaitUntil := A_TickCount + Random(5000, 7000)
            WcStatusAction := "Nav1 failed — wait 5-7s then try deposit box"
            return
        }

        if (Nav1Color = "") {
            PauseWoodcut()
            ToolTip("Unable to find bank. Set Nav1 (Ctrl+Shift+1) and Deposit box (Ctrl+Shift+D). Paused.")
            SetTimer(() => ToolTip(), 5000)
            WcStatusAction := "PAUSED: Nav1 not set"
        }
        return
    }

    ; Step 2: Wait for deposit area with color to show up (box open)
    if (BankStep = 2) {
        if (IsDepositVisible()) {
            BankStep := 3
            WcStatusAction := "Deposit box open — click deposit"
        } else if (A_TickCount >= BankWaitUntil) {
            BankStep := 1
            BankSubStep := 0
            WcStatusAction := "Deposit box open timeout — retry"
        } else {
            WcStatusAction := "Wait for deposit box to open..."
        }
        return
    }

    ; Step 3: Click deposit color in deposit area
    if (BankStep = 3) {
        if (ClickDepositInArea()) {
            BankStep := 4
            WcStatusAction := "Clicked deposit — wait for done"
        } else {
            WcStatusAction := "Deposit button not found"
        }
        return
    }

    ; Step 4: Wait until deposit color no longer in area (box closed, done)
    if (BankStep = 4) {
        if (!IsDepositVisible()) {
            WoodcutPhase := "cutting"
            BankStep := 0
            BankSubStep := 0
            BankNav1FailCount := 0
            BankDepositBoxFailCount := 0
            WcStatusAction := "Banking done — back to cutting"
        } else {
            WcStatusAction := "Depositing..."
        }
    }
}

; --- Build and run ---
BuildStatusGui()
BuildPlayAreaOverlay()
BuildInvSlotOverlay()
BuildWcStatusOverlay()
SetTimer(UpdateStatusGui, 500)
UpdateStatusGui()
