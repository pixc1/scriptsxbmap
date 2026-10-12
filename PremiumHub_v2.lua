--[[
	PREMIUM HUB v3.0
	- حدود متحركة + عنوان لامع + خلفية متدرجة
	- تأثير ريبل (Ripple) على الأزرار + تحريك عند الضغط
	- مؤشر تبويبات منزلق + انتقال ناعم بين الصفحات
	- إشعارات بشريط عدّاد + شاشة تحميل بدوّارة
	- تبويب جديد: 🏆 الكؤوس (انتقال لكل كأس + جولة تلقائية)
	اختصار: RightShift لإظهار/إخفاء النافذة
]]

-- ==========================================
-- ⚙️ إعدادات الكؤوس (عدّل هنا)
-- ==========================================
local CONFIG = {
	CupOffset = Vector3.new(0, 3, 0), -- يرفع اللاعب فوق الكأس شوي حتى ما يعلق بالأرض
	TourDelay = 1.5,                  -- الفاصل الافتراضي بين الكؤوس في الجولة (ثانية)
}

-- أضف كل كأس بسطر: { "اسم الكأس", Vector3.new(X, Y, Z) },
local Cups = {
	-- { "كأس 1", Vector3.new(0, 0, 0) },
	-- { "كأس 2", Vector3.new(0, 0, 0) },
}

-- ==========================================
-- الخدمات
-- ==========================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local localPlayer = Players.LocalPlayer

-- ==========================================
-- التثبيت الآمن
-- ==========================================
local function pickParent()
	if typeof(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and typeof(h) == "Instance" then return h end
	end
	local ok = pcall(function()
		local probe = Instance.new("Folder")
		probe.Parent = CoreGui
		probe:Destroy()
	end)
	if ok then return CoreGui end
	return localPlayer:WaitForChild("PlayerGui")
end

local targetParent = pickParent()

for _, p in ipairs({ targetParent, localPlayer:FindFirstChild("PlayerGui") }) do
	local old = p and p:FindFirstChild("PremiumHubV3")
	if old then old:Destroy() end
	local old2 = p and p:FindFirstChild("PremiumHubV2")
	if old2 then old2:Destroy() end
end

-- ==========================================
-- الثيم والحالة
-- ==========================================
local Theme = {
	bg = Color3.fromRGB(14, 14, 20),
	header = Color3.fromRGB(20, 20, 28),
	side = Color3.fromRGB(17, 17, 24),
	card = Color3.fromRGB(26, 26, 36),
	stroke = Color3.fromRGB(42, 42, 56),
	off = Color3.fromRGB(48, 48, 64),
	text = Color3.fromRGB(236, 236, 246),
	sub = Color3.fromRGB(140, 140, 162),
	green = Color3.fromRGB(46, 184, 114),
	red = Color3.fromRGB(224, 72, 84),
	orange = Color3.fromRGB(214, 128, 40),
	blue = Color3.fromRGB(48, 138, 230),
	accent = Color3.fromRGB(124, 92, 255),
}

local DEFAULT_SPEED, DEFAULT_JUMP = 16, 50
local WHITE = Color3.new(1, 1, 1)

local State = {
	running = true,
	saved = nil,
	speedOn = false, speed = 50,
	jumpOn = false, jump = 100,
	flying = false, flySpeed = 2.5,
	autoReturn = false, returnDist = 50,
	loader = true,
	notifs = true,
	teleporting = false,
	tourDelay = CONFIG.TourDelay,
	visited = {},
}

local Conns = {}
local function track(c) table.insert(Conns, c) return c end

local Loops = {}

-- ==========================================
-- دوال مساعدة
-- ==========================================
local function new(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else inst[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(inst, r)
	return new("UICorner", { CornerRadius = typeof(r) == "UDim" and r or UDim.new(0, r), Parent = inst })
end

local function stroke(inst, color, thick, trans)
	return new("UIStroke", {
		Color = color, Thickness = thick or 1, Transparency = trans or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst,
	})
end

local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- تأثير يتكرر للأبد (حدود، لمعة...)
local function loop(inst, time, props)
	local tw = TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), props)
	tw:Play()
	table.insert(Loops, tw)
	return tw
end

-- ربط العناصر بلون الواجهة (يتغير من الإعدادات)
local accentBinds = {}
local function bindAccent(fn)
	table.insert(accentBinds, fn)
	fn(Theme.accent)
end
local function setAccent(c)
	Theme.accent = c
	for _, f in ipairs(accentBinds) do f(c) end
end

local function getChar() return localPlayer.Character end
local function getRoot() local c = getChar() return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = getChar() return c and c:FindFirstChildOfClass("Humanoid") end

local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

-- تأثير الموجة عند الضغط
local function ripple(obj, x, y)
	local rx = math.clamp(x - obj.AbsolutePosition.X, 0, obj.AbsoluteSize.X)
	local ry = math.clamp(y - obj.AbsolutePosition.Y, 0, obj.AbsoluteSize.Y)
	local size = math.max(obj.AbsoluteSize.X, obj.AbsoluteSize.Y) * 2.4
	local c = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(rx, ry), Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.78, BorderSizePixel = 0,
		ZIndex = obj.ZIndex + 1, Parent = obj,
	})
	corner(c, UDim.new(1, 0))
	tween(c, 0.55, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 })
	task.delay(0.6, function() c:Destroy() end)
end

-- سحب يعمل باللمس والماوس
local function makeDraggable(handle, target)
	local info = { moved = false }
	local dragging, startMouse, startPos = false, nil, nil

	handle.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			info.moved = false
			startMouse = input.Position
			startPos = target.Position
			local conn
			conn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					conn:Disconnect()
				end
			end)
		end
	end)

	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startMouse
			if d.Magnitude > 6 then info.moved = true end
			if info.moved then
				target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end))

	return info
end

-- ==========================================
-- ScreenGui
-- ==========================================
local gui = new("ScreenGui", {
	Name = "PremiumHubV3",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
	Parent = targetParent,
})

-- ==========================================
-- الإشعارات (Toasts)
-- ==========================================
local notifyHolder = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(270, 200),
	ZIndex = 200,
	Parent = gui,
})
new("UIListLayout", {
	Padding = UDim.new(0, 6),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = notifyHolder,
})

local function notify(text, kind)
	if not State.notifs and kind ~= "error" then return end

	-- حد أقصى 4 إشعارات ظاهرة
	local kids = {}
	for _, c in ipairs(notifyHolder:GetChildren()) do
		if c:IsA("CanvasGroup") then table.insert(kids, c) end
	end
	if #kids >= 4 then kids[1]:Destroy() end

	local col = (kind == "error" and Theme.red) or (kind == "success" and Theme.green) or Theme.accent
	local card = new("CanvasGroup", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Theme.card,
		GroupTransparency = 1,
		ZIndex = 200,
		Parent = notifyHolder,
	})
	corner(card, 9)
	stroke(card, col, 1.2)
	local sc = new("UIScale", { Scale = 0.85, Parent = card })
	new("Frame", {
		Size = UDim2.new(0, 3, 1, 0), Position = UDim2.new(1, -3, 0, 0),
		BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 201, Parent = card,
	})
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -2), Position = UDim2.new(0, 8, 0, 0),
		Font = Enum.Font.GothamMedium, Text = text, TextColor3 = Theme.text, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 201, Parent = card,
	})
	local timer = new("Frame", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 202, Parent = card,
	})
	tween(card, 0.2, { GroupTransparency = 0 })
	tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(timer, 2.2, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)

	task.delay(2.2, function()
		if card.Parent then
			tween(card, 0.25, { GroupTransparency = 1 })
			task.wait(0.27)
			card:Destroy()
		end
	end)
end

-- ==========================================
-- شاشة التحميل + الانتقال الآمن
-- ==========================================
local function showLoader(duration)
	local overlay = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50, Parent = gui,
	})
	local card = new("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 24),
		Size = UDim2.fromOffset(230, 110), BackgroundColor3 = Theme.card,
		GroupTransparency = 1, ZIndex = 51, Parent = overlay,
	})
	corner(card, 14)
	stroke(card, Theme.accent, 1.5)

	-- دوّارة
	local spinner = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1, ZIndex = 52, Parent = card,
	})
	corner(spinner, UDim.new(1, 0))
	local ss = new("UIStroke", {
		Color = WHITE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = spinner,
	})
	local sg = new("UIGradient", {
		Color = ColorSequence.new(Theme.accent),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = ss,
	})
	local spin = TweenService:Create(sg, TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 })
	spin:Play()

	new("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 24),
		Font = Enum.Font.GothamBlack, Text = "🚀 جاري الانتقال...", TextColor3 = Theme.text, TextSize = 15,
		ZIndex = 52, Parent = card,
	})
	local pct = new("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 64), Size = UDim2.new(1, 0, 0, 16),
		Font = Enum.Font.GothamMedium, Text = "0%", TextColor3 = Theme.sub, TextSize = 11,
		ZIndex = 52, Parent = card,
	})
	local barBg = new("Frame", {
		Position = UDim2.new(0.1, 0, 0, 90), Size = UDim2.new(0.8, 0, 0, 6),
		BackgroundColor3 = Theme.off, BorderSizePixel = 0, ZIndex = 52, Parent = card,
	})
	corner(barBg, 3)
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.accent,
		BorderSizePixel = 0, ZIndex = 53, Parent = barBg,
	})
	corner(fill, 3)

	tween(overlay, 0.25, { BackgroundTransparency = 0.45 })
	tween(card, 0.35, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0.5, 0) }, Enum.EasingStyle.Back)

	local t0 = os.clock()
	while true do
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		fill.Size = UDim2.fromScale(a, 1)
		pct.Text = math.floor(a * 100) .. "%"
		if a >= 1 or not State.running then break end
		RunService.RenderStepped:Wait()
	end

	tween(card, 0.25, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, -16) })
	tween(overlay, 0.3, { BackgroundTransparency = 1 })
	task.wait(0.32)
	spin:Cancel()
	overlay:Destroy()
end

local function teleport(cf, quick)
	if State.teleporting then return end
	local root = getRoot()
	if not root then notify("لا توجد شخصية حالياً", "error") return end

	State.teleporting = true
	task.spawn(function()
		local useLoader = State.loader and not quick
		local duration = useLoader and 1.2 or 0.25

		local platform = new("Part", {
			Size = Vector3.new(24, 1, 24),
			Position = cf.Position - Vector3.new(0, 3.5, 0),
			Anchored = true, CanCollide = true, Transparency = 1,
			Parent = workspace,
		})

		root.CFrame = cf
		root.Anchored = true

		if useLoader then
			showLoader(duration)
		else
			task.wait(duration)
		end

		local r = getRoot()
		if r then r.Anchored = false end
		platform:Destroy()
		State.teleporting = false
	end)
end

-- ==========================================
-- النافذة الرئيسية
-- Shell = إطار الحدود المتحركة، Main = CanvasGroup لتقطيع الزوايا
-- ==========================================
local function winSize()
	local vp = workspace.CurrentCamera.ViewportSize
	return math.clamp(vp.X * 0.92, 300, 470), math.clamp(vp.Y * 0.82, 230, 310)
end

local W, H = winSize()
local SIDE_W = 100

local Shell = new("Frame", {
	Name = "Shell",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(W * 0.9, H * 0.9),
	BackgroundTransparency = 1,
	Parent = gui,
})
corner(Shell, 14)

-- حدود متحركة بتدرج دوّار
local borderStroke = new("UIStroke", {
	Color = WHITE, Thickness = 2, Transparency = 1,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = Shell,
})
local borderGrad = new("UIGradient", { Parent = borderStroke })
bindAccent(function(c)
	borderGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c),
		ColorSequenceKeypoint.new(0.35, Theme.stroke),
		ColorSequenceKeypoint.new(0.65, Theme.stroke),
		ColorSequenceKeypoint.new(1, c),
	})
end)
loop(borderGrad, 5, { Rotation = 360 })

local Main = new("CanvasGroup", {
	Name = "Main",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Theme.bg,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Parent = Shell,
})
corner(Main, 14)

-- خلفية متدرجة هادئة تتحرك ببطء
local BgGlow = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 0, Parent = Main,
})
local bgGrad = new("UIGradient", { Rotation = 45, Parent = BgGlow })
bindAccent(function(c)
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.bg),
		ColorSequenceKeypoint.new(1, Theme.bg:Lerp(c, 0.2)),
	})
end)
loop(bgGrad, 14, { Rotation = 405 })

-- الهيدر
local Header = new("Frame", {
	Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Theme.header, BorderSizePixel = 0, Parent = Main,
})
local title = new("TextLabel", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.new(0.6, 0, 1, 0), Font = Enum.Font.GothamBlack, Text = "✨ PREMIUM HUB",
	TextColor3 = WHITE, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Parent = Header,
})
-- لمعة تمر على العنوان
local titleGrad = new("UIGradient", { Offset = Vector2.new(-1, 0), Parent = title })
bindAccent(function(c)
	titleGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.text),
		ColorSequenceKeypoint.new(0.5, c),
		ColorSequenceKeypoint.new(1, Theme.text),
	})
end)
loop(titleGrad, 2.6, { Offset = Vector2.new(1, 0) })

local accentLine = new("Frame", {
	Position = UDim2.new(0, 0, 0, 41), Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0,
	BackgroundColor3 = Theme.accent, Parent = Main,
})
bindAccent(function(c) accentLine.BackgroundColor3 = c end)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.2),
	}),
	Parent = accentLine,
})

makeDraggable(Header, Shell)

local function headerBtn(text, xOffset, color)
	local b = new("TextButton", {
		Position = UDim2.new(0, xOffset, 0.5, -13), Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = color, AutoButtonColor = false, Font = Enum.Font.GothamBold,
		Text = text, TextColor3 = WHITE, TextSize = 13, BorderSizePixel = 0, Parent = Header,
	})
	corner(b, 8)
	local sc = new("UIScale", { Parent = b })
	b.InputBegan:Connect(function(i) if isPress(i) then tween(sc, 0.08, { Scale = 0.88 }) end end)
	b.InputEnded:Connect(function(i) if isPress(i) then tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back) end end)
	return b
end
local CloseBtn = headerBtn("✕", 10, Theme.red)
local MinBtn = headerBtn("—", 42, Theme.off)

-- الجسم
local Body = new("Frame", {
	Position = UDim2.new(0, 0, 0, 43), Size = UDim2.new(1, 0, 1, -43), BackgroundTransparency = 1, Parent = Main,
})

-- القائمة الجانبية (يمين = RTL)
local Side = new("Frame", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, SIDE_W, 1, 0), BackgroundColor3 = Theme.side, BorderSizePixel = 0, Parent = Body,
})

-- مؤشر التبويب المنزلق
local Highlight = new("Frame", {
	BackgroundColor3 = Theme.accent, BackgroundTransparency = 0.86, BorderSizePixel = 0,
	Size = UDim2.fromOffset(SIDE_W - 14, 32), Position = UDim2.fromOffset(7, 8), ZIndex = 1, Parent = Side,
})
corner(Highlight, 9)
local HBar = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -1, 0.5, 0), Size = UDim2.fromOffset(3, 16),
	BackgroundColor3 = Theme.accent, BorderSizePixel = 0, Parent = Highlight,
})
corner(HBar, 2)
bindAccent(function(c) Highlight.BackgroundColor3 = c HBar.BackgroundColor3 = c end)

local TabList = new("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
	Position = UDim2.new(0, 0, 0, 8), Size = UDim2.new(1, 0, 1, -50), ZIndex = 2, Parent = Side,
})
new("UIListLayout", {
	Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = TabList,
})
new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, 30),
	BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = Theme.sub,
	Text = "@" .. localPlayer.Name .. "\nv3.0", TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 2, Parent = Side,
})

local Pages = new("Frame", {
	Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, -SIDE_W, 1, 0), BackgroundTransparency = 1, Parent = Body,
})

-- ==========================================
-- نظام التبويبات
-- ==========================================
local tabs = {}
local currentTab

local function placeHighlight(animate)
	if not currentTab then return end
	local b = currentTab.btn
	local pos = b.AbsolutePosition - Side.AbsolutePosition
	local target = UDim2.fromOffset(pos.X, pos.Y)
	Highlight.Size = UDim2.fromOffset(b.AbsoluteSize.X, b.AbsoluteSize.Y)
	if animate then
		tween(Highlight, 0.3, { Position = target }, Enum.EasingStyle.Quint)
	else
		Highlight.Position = target
	end
end

track(TabList:GetPropertyChangedSignal("CanvasPosition"):Connect(function() placeHighlight(false) end))

local function selectTab(t, instant)
	currentTab = t
	for _, o in ipairs(tabs) do
		local on = (o == t)
		if on and not o.page.Visible then
			o.page.Position = UDim2.fromOffset(instant and 0 or 18, 0)
			o.page.Visible = true
			if not instant then
				tween(o.page, 0.28, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
			end
		elseif not on then
			o.page.Visible = false
		end
		tween(o.label, 0.18, { TextColor3 = on and Theme.text or Theme.sub })
	end
	placeHighlight(not instant)
end

local function addTab(name, icon)
	local btn = new("TextButton", {
		Size = UDim2.new(1, -14, 0, 32), BackgroundTransparency = 1,
		AutoButtonColor = false, Text = "", BorderSizePixel = 0, ClipsDescendants = true,
		LayoutOrder = #tabs + 1, Parent = TabList,
	})
	corner(btn, 9)
	local label = new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 0, 0, 0),
		Font = Enum.Font.GothamBold, Text = icon .. " " .. name, TextColor3 = Theme.sub, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right, Parent = btn,
	})

	local page = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Left, Visible = false, Parent = Pages,
	})
	bindAccent(function(c) page.ScrollBarImageColor3 = c end)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10), Parent = page,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page,
	})

	local t = { btn = btn, label = label, page = page }
	table.insert(tabs, t)
	btn.InputBegan:Connect(function(i) if isPress(i) then ripple(btn, i.Position.X, i.Position.Y) end end)
	btn.Activated:Connect(function() selectTab(t) end)
	return page
end

-- ==========================================
-- مكونات الواجهة
-- ==========================================
local function Card(page, height)
	local f = new("Frame", {
		Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = Theme.card, BorderSizePixel = 0,
		ClipsDescendants = true, Parent = page,
	})
	corner(f, 10)
	local s = stroke(f, Theme.stroke, 1)
	return f, s
end

local function Section(page, text)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		Text = text, TextColor3 = Theme.sub, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Parent = page,
	})
end

local function Info(page, text)
	local card = Card(page, 40)
	local lbl = new("TextLabel", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -20, 1, -6), Font = Enum.Font.GothamMedium, Text = text, TextColor3 = Theme.sub,
		TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right, Parent = card,
	})
	return function(t, col) lbl.Text = t lbl.TextColor3 = col or Theme.sub end
end

local function Toggle(page, text, default, callback)
	local card = Card(page, 42)
	new("TextLabel", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(1, -76, 1, -6), Font = Enum.Font.GothamMedium, Text = text, TextColor3 = Theme.text,
		TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right, Parent = card,
	})
	local trackBar = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(40, 22),
		BackgroundColor3 = Theme.off, BorderSizePixel = 0, Parent = card,
	})
	corner(trackBar, 11)
	local glow = stroke(trackBar, Theme.accent, 2, 1)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = trackBar,
	})
	corner(knob, 8)

	local state = default and true or false
	local function render(animate)
		local t = animate and 0.2 or 0
		tween(trackBar, t, { BackgroundColor3 = state and Theme.accent or Theme.off })
		tween(glow, t, { Transparency = state and 0.55 or 1, Color = Theme.accent })
		tween(knob, t, {
			Position = state and UDim2.new(0, 21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
		}, Enum.EasingStyle.Back)
	end
	bindAccent(function() render(false) end)

	local function apply(v, canVeto)
		if callback then
			local r = callback(v)
			if canVeto and r == false then return end
		end
		state = v
		render(true)
	end

	local hit = new("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = card,
	})
	hit.InputBegan:Connect(function(i)
		if isPress(i) then
			ripple(card, i.Position.X, i.Position.Y)
			if not state then tween(knob, 0.12, { Size = UDim2.fromOffset(18, 16) }) end
		end
	end)
	hit.Activated:Connect(function() apply(not state, true) end)

	return { Set = function(v) apply(v and true or false, false) end }
end

local function Slider(page, text, min, max, default, step, callback)
	local card = Card(page, 58)
	new("TextLabel", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.new(0.65, 0, 0, 18), Font = Enum.Font.GothamMedium, Text = text, TextColor3 = Theme.text,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Parent = card,
	})
	local valueLabel = new("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(0.28, 0, 0, 18),
		Font = Enum.Font.GothamBold, Text = "", TextColor3 = Theme.accent, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
	})
	bindAccent(function(c) valueLabel.TextColor3 = c end)

	local hit = new("TextButton", {
		Text = "", BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 30), Size = UDim2.new(1, -24, 0, 24),
		Parent = card,
	})
	local trackBar = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.off, BorderSizePixel = 0, Parent = hit,
	})
	corner(trackBar, 3)
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.accent, BorderSizePixel = 0, Parent = trackBar,
	})
	corner(fill, 3)
	bindAccent(function(c) fill.BackgroundColor3 = c end)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = trackBar,
	})
	corner(knob, 8)
	local knobStroke = stroke(knob, Theme.accent, 2, 1)
	bindAccent(function(c) knobStroke.Color = c end)

	local value = default
	local function fmt(v)
		if step < 1 then return string.format("%.1f", v) end
		return tostring(math.floor(v + 0.5))
	end
	local function visual()
		local a = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.new(a, 0, 0.5, 0)
		valueLabel.Text = fmt(value)
	end
	visual()

	local function fromX(x)
		local a = math.clamp((x - trackBar.AbsolutePosition.X) / math.max(trackBar.AbsoluteSize.X, 1), 0, 1)
		local v = min + a * (max - min)
		v = math.clamp(math.floor(v / step + 0.5) * step, min, max)
		if v ~= value then
			value = v
			visual()
			if callback then callback(v) end
		end
	end

	local dragging = false
	hit.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging = true
			page.ScrollingEnabled = false -- يمنع تمرير الصفحة أثناء سحب السلايدر
			tween(knob, 0.12, { Size = UDim2.fromOffset(21, 21) }, Enum.EasingStyle.Back)
			tween(knobStroke, 0.12, { Transparency = 0.4 })
			fromX(i.Position.X)
		end
	end)
	track(UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			fromX(i.Position.X)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(i)
		if dragging and isPress(i) then
			dragging = false
			page.ScrollingEnabled = true
			tween(knob, 0.15, { Size = UDim2.fromOffset(16, 16) })
			tween(knobStroke, 0.15, { Transparency = 1 })
		end
	end))

	return {
		Set = function(v)
			value = math.clamp(v, min, max)
			visual()
			if callback then callback(value) end
		end,
	}
end

local function Button(page, text, color, callback)
	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = color or Theme.accent, AutoButtonColor = false,
		Font = Enum.Font.GothamBold, Text = text, TextColor3 = WHITE, TextSize = 12,
		BorderSizePixel = 0, ClipsDescendants = true, Parent = page,
	})
	corner(btn, 10)
	if not color then bindAccent(function(c) btn.BackgroundColor3 = c end) end
	local sc = new("UIScale", { Parent = btn })
	btn.InputBegan:Connect(function(i)
		if isPress(i) then
			tween(sc, 0.08, { Scale = 0.96 })
			ripple(btn, i.Position.X, i.Position.Y)
		end
	end)
	btn.InputEnded:Connect(function(i)
		if isPress(i) then tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back) end
	end)
	btn.Activated:Connect(function() if callback then callback(btn) end end)
	return btn
end

local function Input(page, placeholder)
	local box = new("TextBox", {
		Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Theme.card, Font = Enum.Font.GothamMedium,
		PlaceholderText = placeholder, PlaceholderColor3 = Theme.sub, Text = "", TextColor3 = Theme.text,
		TextSize = 12, ClearTextOnFocus = false, ClipsDescendants = true, BorderSizePixel = 0, Parent = page,
	})
	corner(box, 10)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = box })
	local s = stroke(box, Theme.stroke, 1)
	box.Focused:Connect(function() tween(s, 0.15, { Color = Theme.accent }) end)
	box.FocusLost:Connect(function() tween(s, 0.15, { Color = Theme.stroke }) end)
	return box
end

local customBox -- حقل الإحداثيات المخصصة (يُنشأ في تبويب الانتقال)

local function copyText(str)
	local clip = setclipboard or toclipboard
	if clip then
		pcall(clip, str)
		return true
	end
	return false
end

-- ==========================================
-- الطيران
-- ==========================================
local flyToggle
local flyBV

local function setFly(on)
	State.flying = on
	if flyBV then flyBV:Destroy() flyBV = nil end
	local root = getRoot()
	if root then
		local old = root:FindFirstChild("PremiumFlyHold")
		if old then old:Destroy() end
	end
	if not on or not root then return end

	flyBV = new("BodyVelocity", {
		Name = "PremiumFlyHold", MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.zero, Parent = root,
	})

	task.spawn(function()
		local cam = workspace.CurrentCamera
		while State.flying and State.running do
			local dt = RunService.RenderStepped:Wait()
			local r, hum = getRoot(), getHum()
			if not r or not hum then break end

			local move = hum.MoveDirection
			local dir = Vector3.zero
			if move.Magnitude > 0 then
				local look = cam.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				local y = 0
				if flat.Magnitude > 0.001 then
					y = look.Y * flat.Unit:Dot(move) * 1.5
				end
				dir = Vector3.new(move.X, y, move.Z)
			end
			if hum.Jump then dir += Vector3.new(0, 1, 0) end
			if dir.Magnitude > 0 then
				r.CFrame += dir.Unit * (State.flySpeed * 60 * dt)
			end
		end
	end)
end

-- ==========================================
-- 🏠 تبويب الرئيسية
-- ==========================================
local pageMain = addTab("الرئيسية", "🏠")

Section(pageMain, "الحركة")
local speedToggle = Toggle(pageMain, "🏃 تفعيل السرعة", false, function(v)
	State.speedOn = v
	if not v then
		local hum = getHum()
		if hum then hum.WalkSpeed = DEFAULT_SPEED end
	end
end)
Slider(pageMain, "السرعة", 16, 300, State.speed, 1, function(v) State.speed = v end)

local jumpToggle = Toggle(pageMain, "🦘 تفعيل القفز العالي", false, function(v)
	State.jumpOn = v
	if not v then
		local hum = getHum()
		if hum then hum.JumpPower = DEFAULT_JUMP end
	end
end)
Slider(pageMain, "قوة القفز", 50, 350, State.jump, 1, function(v) State.jump = v end)

Section(pageMain, "الطيران")
flyToggle = Toggle(pageMain, "🛸 تفعيل الطيران", false, function(v)
	if v and not getRoot() then
		notify("لا توجد شخصية حالياً", "error")
		return false
	end
	setFly(v)
	notify(v and "تم تفعيل الطيران 🛸" or "تم إيقاف الطيران", v and "success" or nil)
end)
Slider(pageMain, "سرعة الطيران", 0.5, 10, State.flySpeed, 0.5, function(v) State.flySpeed = v end)

-- ==========================================
-- 🏆 تبويب الكؤوس
-- ==========================================
local pageCups = addTab("الكؤوس", "🏆")

local setCupsInfo = Info(pageCups, "")
local cupCards = {}

local function refreshCupsInfo()
	local total = #Cups
	if total == 0 then
		setCupsInfo("🏆 لم تُضف إحداثيات الكؤوس بعد", Theme.orange)
		return
	end
	local done = 0
	for i = 1, total do
		if State.visited[i] then done += 1 end
	end
	setCupsInfo(string.format("🏆 الكؤوس: %d   •   تمت زيارة: %d", total, done), done == total and Theme.green or Theme.sub)
end

local function cupPosition(entry)
	local p = entry[2]
	if typeof(p) == "CFrame" then p = p.Position end
	return p
end

local function markVisited(i)
	State.visited[i] = true
	local c = cupCards[i]
	if c then
		c.badge.Text = "✓"
		tween(c.badge, 0.25, { BackgroundColor3 = Theme.green })
		c.stroke.Color = Theme.green
		tween(c.stroke, 1.4, { Color = Theme.stroke })
	end
	refreshCupsInfo()
end

local function teleportCup(i, quick)
	local entry = Cups[i]
	if not entry then return false end
	if State.teleporting then return false end
	if not getRoot() then notify("لا توجد شخصية حالياً", "error") return false end
	teleport(CFrame.new(cupPosition(entry) + CONFIG.CupOffset), quick)
	markVisited(i)
	notify("🏆 " .. tostring(entry[1]), "success")
	return true
end

-- الجولة التلقائية
local tourRunning = false
local tourBtn

local function setTourUI(on)
	tourBtn.Text = on and "⏹ إيقاف الجولة" or "▶ جولة على كل الكؤوس"
	tween(tourBtn, 0.2, { BackgroundColor3 = on and Theme.red or Theme.green })
end

local function startTour()
	if tourRunning then return end
	if #Cups == 0 then notify("لا توجد كؤوس مضافة بعد", "error") return end
	tourRunning = true
	setTourUI(true)
	task.spawn(function()
		for i = 1, #Cups do
			if not tourRunning or not State.running then break end
			repeat task.wait(0.05) until not State.teleporting or not State.running
			if not teleportCup(i, true) then break end
			local t0 = os.clock()
			while tourRunning and State.running and os.clock() - t0 < State.tourDelay do
				task.wait(0.05)
			end
		end
		if tourRunning then notify("انتهت الجولة على الكؤوس ✅", "success") end
		tourRunning = false
		if tourBtn.Parent then setTourUI(false) end
	end)
end

tourBtn = Button(pageCups, "▶ جولة على كل الكؤوس", Theme.green, function()
	if tourRunning then
		tourRunning = false
		setTourUI(false)
	else
		startTour()
	end
end)
Slider(pageCups, "الفاصل بين الكؤوس (ثانية)", 0.5, 5, State.tourDelay, 0.5, function(v) State.tourDelay = v end)

Section(pageCups, "قائمة الكؤوس")

if #Cups == 0 then
	Info(pageCups, "أضف الكؤوس في جدول Cups أعلى السكربت")
end

for i, entry in ipairs(Cups) do
	local card, cardStroke = Card(pageCups, 46)
	local p = cupPosition(entry)

	local badge = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Theme.accent, Font = Enum.Font.GothamBlack, Text = tostring(i), TextColor3 = WHITE,
		TextSize = 13, BorderSizePixel = 0, Parent = card,
	})
	corner(badge, UDim.new(1, 0))
	bindAccent(function(c) if not State.visited[i] then badge.BackgroundColor3 = c end end)

	new("TextLabel", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -46, 0.5, 0),
		Size = UDim2.new(1, -96, 1, -6), Font = Enum.Font.GothamBold, RichText = true,
		Text = string.format('🏆 %s\n<font size="10" color="rgb(140,140,162)">X %.0f  Y %.0f  Z %.0f</font>', tostring(entry[1]), p.X, p.Y, p.Z),
		TextColor3 = Theme.text, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})

	local go = new("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(36, 28),
		BackgroundColor3 = Theme.green, AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = "🚀",
		TextColor3 = WHITE, TextSize = 14, BorderSizePixel = 0, ClipsDescendants = true, Parent = card,
	})
	corner(go, 8)
	local sc = new("UIScale", { Parent = go })
	go.InputBegan:Connect(function(inp)
		if isPress(inp) then
			tween(sc, 0.08, { Scale = 0.9 })
			ripple(go, inp.Position.X, inp.Position.Y)
		end
	end)
	go.InputEnded:Connect(function(inp)
		if isPress(inp) then tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back) end
	end)
	go.Activated:Connect(function() teleportCup(i) end)

	cupCards[i] = { badge = badge, stroke = cardStroke }
end

Section(pageCups, "أدوات")

Button(pageCups, "📋 نسخ موقعي كسطر كأس جاهز", Theme.orange, function()
	local root = getRoot()
	if not root then notify("لا توجد شخصية حالياً", "error") return end
	local p = root.Position
	local line = string.format('{ "كأس %d", Vector3.new(%.1f, %.1f, %.1f) },', #Cups + 1, p.X, p.Y, p.Z)
	if copyText(line) then
		notify("تم نسخ سطر الكأس", "success")
	else
		if customBox then customBox.Text = line end
		notify("النسخ غير مدعوم، وُضع السطر في حقل الانتقال")
	end
end)

Button(pageCups, "↺ تصفير علامات الزيارة", Theme.off, function()
	State.visited = {}
	for i, c in pairs(cupCards) do
		c.badge.Text = tostring(i)
		tween(c.badge, 0.2, { BackgroundColor3 = Theme.accent })
	end
	refreshCupsInfo()
	notify("تم تصفير العلامات")
end)

refreshCupsInfo()

-- ==========================================
-- 📍 تبويب الانتقال
-- ==========================================
local pageTP = addTab("الانتقال", "📍")

local setSavedInfo = Info(pageTP, "📍 لا يوجد موقع محفوظ بعد")

Button(pageTP, "📌 حفظ موقعي الحالي", Theme.blue, function()
	local root = getRoot()
	if not root then notify("لا توجد شخصية حالياً", "error") return end
	State.saved = root.CFrame
	local p = root.Position
	setSavedInfo(string.format("✅ محفوظ: X %.0f  Y %.0f  Z %.0f", p.X, p.Y, p.Z), Theme.green)
	notify("تم حفظ الموقع بنجاح", "success")
end)

Button(pageTP, "🚀 انتقال للموقع المحفوظ", Theme.green, function()
	if State.saved then teleport(State.saved) else notify("احفظ موقعاً أولاً", "error") end
end)

Button(pageTP, "📄 نسخ إحداثيات الموقع المحفوظ", Theme.orange, function()
	if not State.saved then notify("احفظ موقعاً أولاً", "error") return end
	local str = tostring(State.saved)
	if copyText(str) then
		notify("تم نسخ الإحداثيات", "success")
	else
		customBox.Text = str
		notify("النسخ غير مدعوم، وُضعت الإحداثيات في الحقل")
	end
end)

Section(pageTP, "إحداثيات مخصصة")
customBox = Input(pageTP, "✂️ الصق الإحداثيات هنا...")

local function parseCFrame(str)
	local nums = {}
	for token in string.gmatch(str, "[^,%s%(%)]+") do
		local n = tonumber(token)
		if n then table.insert(nums, n) end
	end
	if #nums >= 12 then return CFrame.new(table.unpack(nums, 1, 12))
	elseif #nums >= 3 then return CFrame.new(nums[1], nums[2], nums[3]) end
	return nil
end

Button(pageTP, "🎯 انتقال للإحداثيات الملصقة", Color3.fromRGB(200, 50, 120), function()
	local cf = parseCFrame(customBox.Text)
	if cf then teleport(cf) else notify("إحداثيات غير صحيحة", "error") end
end)

-- ==========================================
-- 🛡️ تبويب الحماية
-- ==========================================
local pageSafe = addTab("الحماية", "🛡️")

local autoToggle = Toggle(pageSafe, "🛡️ رجوع تلقائي للموقع المحفوظ", false, function(v)
	if v and not State.saved then
		notify("احفظ موقعاً أولاً", "error")
		return false
	end
	State.autoReturn = v
	notify(v and "تم تفعيل الرجوع التلقائي" or "تم إيقاف الرجوع التلقائي", v and "success" or nil)
end)
Slider(pageSafe, "أقصى مسافة للابتعاد", 10, 500, State.returnDist, 5, function(v)
	State.returnDist = v
end)

Section(pageSafe, "التأثيرات")
Toggle(pageSafe, "🎬 شاشة التحميل عند الانتقال", true, function(v) State.loader = v end)

-- ==========================================
-- ⚙️ تبويب الإعدادات
-- ==========================================
local pageSet = addTab("الإعدادات", "⚙️")

-- الزر العائم للانتقال السريع
local function FloatButton(icon, size)
	local b = new("TextButton", {
		Size = UDim2.fromOffset(size, size), BackgroundColor3 = Theme.header, AutoButtonColor = false,
		Font = Enum.Font.GothamBold, Text = icon, TextSize = math.floor(size * 0.45), TextColor3 = Theme.accent,
		Visible = false, ZIndex = 60, BorderSizePixel = 0, Parent = gui,
	})
	corner(b, UDim.new(1, 0))
	local st = stroke(b, Theme.accent, 2.5)
	bindAccent(function(c) st.Color = c b.TextColor3 = c end)
	local sc = new("UIScale", { Parent = b })
	b.InputBegan:Connect(function(i) if isPress(i) then tween(sc, 0.08, { Scale = 0.88 }) end end)
	b.InputEnded:Connect(function(i) if isPress(i) then tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back) end end)
	return b, makeDraggable(b, b)
end

local quick, quickDrag = FloatButton("⚡", 50)
quick.Position = UDim2.new(1, -70, 0.6, 0)
quick.Visible = true

local ring = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1, ZIndex = 59, Parent = quick,
})
corner(ring, UDim.new(1, 0))
local ringStroke = stroke(ring, Theme.accent, 2, 1)
bindAccent(function(c) ringStroke.Color = c end)

task.spawn(function()
	while State.running do
		if State.saved and quick.Visible then
			ring.Size = UDim2.fromScale(1, 1)
			ringStroke.Transparency = 0.2
			local tw = TweenService:Create(ring, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1.7, 1.7) })
			TweenService:Create(ringStroke, TweenInfo.new(1.1), { Transparency = 1 }):Play()
			tw:Play()
			tw.Completed:Wait()
		else
			task.wait(0.4)
		end
	end
end)

quick.Activated:Connect(function()
	if quickDrag.moved then return end
	if State.saved then teleport(State.saved) else notify("احفظ موقعاً أولاً", "error") end
end)

Section(pageSet, "العرض")
Toggle(pageSet, "⚡ زر الانتقال السريع العائم", true, function(v) quick.Visible = v end)
Toggle(pageSet, "🌈 الحدود المتحركة", true, function(v) borderStroke.Enabled = v end)
Toggle(pageSet, "🔔 الإشعارات", true, function(v) State.notifs = v end)

-- ألوان الواجهة
local swatchCard = Card(pageSet, 74)
new("TextLabel", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8),
	Size = UDim2.new(1, -24, 0, 18), Font = Enum.Font.GothamMedium, Text = "🎨 لون الواجهة", TextColor3 = Theme.text,
	TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Parent = swatchCard,
})
local swatchRow = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34),
	Size = UDim2.new(1, -24, 0, 28), Parent = swatchCard,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), Parent = swatchRow,
})
for _, col in ipairs({
	Color3.fromRGB(124, 92, 255), Color3.fromRGB(46, 184, 114), Color3.fromRGB(56, 152, 255),
	Color3.fromRGB(255, 95, 140), Color3.fromRGB(255, 170, 60),
}) do
	local sw = new("TextButton", {
		Size = UDim2.fromOffset(26, 26), BackgroundColor3 = col, Text = "", AutoButtonColor = false,
		BorderSizePixel = 0, Parent = swatchRow,
	})
	corner(sw, UDim.new(1, 0))
	stroke(sw, WHITE, 1.5, 0.6)
	local sc = new("UIScale", { Parent = sw })
	sw.InputBegan:Connect(function(i) if isPress(i) then tween(sc, 0.08, { Scale = 0.85 }) end end)
	sw.InputEnded:Connect(function(i) if isPress(i) then tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back) end end)
	sw.Activated:Connect(function() setAccent(col) end)
end

Section(pageSet, "أدوات")
Button(pageSet, "🔄 إعادة ضبط كل الميزات", Theme.off, function()
	speedToggle.Set(false)
	jumpToggle.Set(false)
	flyToggle.Set(false)
	autoToggle.Set(false)
	tourRunning = false
	setTourUI(false)
	notify("تمت إعادة الضبط", "success")
end)

-- ==========================================
-- التصغير والإغلاق
-- ==========================================
local mini, miniDrag = FloatButton("✨", 44)

local function setMinimized(v)
	if v then
		local p, s = Shell.AbsolutePosition, Shell.AbsoluteSize
		mini.Position = UDim2.fromOffset(p.X + s.X - 44, p.Y)
		tween(Main, 0.18, { GroupTransparency = 1 })
		tween(borderStroke, 0.18, { Transparency = 1 })
		task.wait(0.18)
		Shell.Visible = false
		mini.Visible = true
	else
		mini.Visible = false
		Shell.Visible = true
		local w, h = winSize()
		Shell.Size = UDim2.fromOffset(w * 0.9, h * 0.9)
		Main.GroupTransparency = 1
		tween(Shell, 0.35, { Size = UDim2.fromOffset(w, h) }, Enum.EasingStyle.Back)
		tween(Main, 0.3, { GroupTransparency = 0 })
		tween(borderStroke, 0.3, { Transparency = 0 })
	end
end

MinBtn.Activated:Connect(function() task.spawn(setMinimized, true) end)
mini.Activated:Connect(function()
	if miniDrag.moved then return end
	setMinimized(false)
end)

-- اختصار الكيبورد (للكمبيوتر)
track(UserInputService.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.RightShift then
		task.spawn(setMinimized, Shell.Visible)
	end
end))

local function destroyAll()
	State.running = false
	State.flying = false
	tourRunning = false
	pcall(function()
		local root, hum = getRoot(), getHum()
		if root then
			root.Anchored = false
			local bv = root:FindFirstChild("PremiumFlyHold")
			if bv then bv:Destroy() end
		end
		if hum then
			if State.speedOn then hum.WalkSpeed = DEFAULT_SPEED end
			if State.jumpOn then hum.JumpPower = DEFAULT_JUMP end
		end
	end)
	for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
	for _, t in ipairs(Loops) do pcall(function() t:Cancel() end) end
	gui:Destroy()
end

local closeArmed = false
CloseBtn.Activated:Connect(function()
	if not closeArmed then
		closeArmed = true
		CloseBtn.Text = "؟"
		notify("اضغط ✕ مرة ثانية للإغلاق", "error")
		task.delay(2, function()
			closeArmed = false
			if CloseBtn.Parent then CloseBtn.Text = "✕" end
		end)
		return
	end
	destroyAll()
end)

-- ==========================================
-- الحلقات الأساسية
-- ==========================================
task.spawn(function()
	while State.running do
		pcall(function()
			local hum, root = getHum(), getRoot()
			if hum then
				if State.speedOn and not State.flying then hum.WalkSpeed = State.speed end
				if State.jumpOn then
					hum.UseJumpPower = true
					hum.JumpPower = State.jump
				end
			end
			if State.autoReturn and State.saved and root and not State.teleporting then
				if (root.Position - State.saved.Position).Magnitude > State.returnDist then
					teleport(State.saved)
				end
			end
		end)
		task.wait(0.15)
	end
end)

track(localPlayer.CharacterAdded:Connect(function()
	State.teleporting = false
	if State.flying then flyToggle.Set(false) end
end))

track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	if Shell.Visible then
		local w, h = winSize()
		Shell.Size = UDim2.fromOffset(w, h)
	end
end))

-- ==========================================
-- التشغيل (أنيميشن الدخول)
-- ==========================================
RunService.Heartbeat:Wait() -- ننتظر فريم حتى يحسب الـ Layout المواقع
selectTab(tabs[1], true)
tween(Shell, 0.45, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Back)
tween(Main, 0.35, { GroupTransparency = 0 })
tween(borderStroke, 0.4, { Transparency = 0 })
task.delay(0.55, function() notify("تم تحميل Premium Hub ✨", "success") end)
