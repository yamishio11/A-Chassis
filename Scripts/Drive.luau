--[[	
	   ___  _____
	  / _ |/ ___/	Avxnturador   	| Novena						    Eniiqzz	    |
	 / __ / /__		LuaInt         	| Novena						    midmm5	    |
    /_/ |_\___/	 	Detomiks		| Base Chassis                      autopilo7   |

	                Version 1.6.4
--]]

--[[START]]
script.Parent:WaitForChild("Car")
script.Parent:WaitForChild("IsOn")
script.Parent:WaitForChild("ControlsOpen")
script.Parent:WaitForChild("Values")

--[[Dependencies]]
local player = game.Players.LocalPlayer
local mouse = player:GetMouse()
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local car = script.Parent.Car.Value
local _Tune = require(car["A-Chassis Tune"])
local Units = require(car["A-Chassis Tune"].Units)
local values = script.Parent.Values
local print = function(...) return end

player.PlayerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

GuiService.TouchControlsEnabled = false
local _MobileMode = "Tap"
local _MobileModes = {"Tap", "Tilt"}

--[[Output Scaling Factor]]
local FBrakeForce =_Tune.BrakeForce * 9.80665 * Units.Force_N*_Tune.BrakeBias--luaint edit, conversion to SI unit Detomiks
local RBrakeForce =_Tune.BrakeForce * 9.80665 * Units.Force_N*(1-_Tune.BrakeBias)--luaint edit
local PBrakeForceF = _Tune.PBrakeForce * 9.80665 * Units.Force_N*_Tune.PBrakeBias
local PBrakeForceR = _Tune.PBrakeForce * 9.80665 * Units.Force_N*(1-_Tune.PBrakeBias)
local EBrakeForce = _Tune.EBrakeForce
local SteerOuter  = _Tune.SteerOuter--luaint edit
local SteerInner  = _Tune.SteerInner--luaint edit
local RSteerOuter = _Tune.RSteerOuter
local RSteerInner = _Tune.RSteerInner

--[[Status Vars]]
local boolToNum = {[true] = 1, [false] = 0}
local min = math.min
local max = math.max

local _IsOn = _Tune.AutoStart
if _Tune.AutoStart and (_Tune.Engine or _Tune.Electric) then script.Parent.IsOn.Value=true end

local _GSteerT=0
local _GSteerC=0
local _GThrot=0
local _InThrot=0
local _IThrot=0
local _GBrake=0
local _InBrake=0
local _IBrake=0

local _GClutch = 0
local _ClPressing = false
local _PlayerClutch = false
local _Clutch = 0
local _ClutchKick = 0
local _ClutchModulate = 0

local _RPM = _Tune.IgnitionRPM
local _OutTorque = 0
local _CGear = 0
local _PGear = _CGear
local _ShiftUp = false
local _ShiftDn = false
local _Shifting = false
local _spLimit = 0

local _Boost = 0
local _TBoost = 0
local _SBoost = 0

local _HP = 0
local _TQ = 0
local _NH = 0
local _NT = 0
local _EH = 0
local _ET = 0
local _TH = 0
local _TT = 0
local _SH = 0
local _ST = 0
local _BH = 0
local _BT = 0

local _CVTRatio = _Tune.CVTMaxRatio
local _CurrentRatio = _Tune.Ratios[_CGear+2]
local _FlywheelEnergy = 0

local _TMode = _Tune.TransModes[1]

local _MSteer = false
local _SteerL = false
local _SteerR = false
local _PBrake = false

local _TCSTracker = {}
local _TCS = _Tune.TCSEnabled
local _TCSActive = false
local _TCSAmt = 0

local _ABSTracker = {}
local _ABS = _Tune.ABSEnabled
local _ABSActive = false
local _ABSAmt = 0

local FlipWait=tick()
local FlipDB=false

local _InControls = false
local _LastInputWasGamepad = false

local revLimiting = false

local _WheelSpeedsTable = {}
local _WheelSpeeds = {}
local _OldVelocity = Vector3.new()

local _CarCenter = CFrame.new()
local autoshiftvers = _Tune.AutoShiftVers

local _DragFactor = 1

--[[Shutdown]]
car.DriveSeat.ChildRemoved:connect(function(child) 
	if child.Name=="SeatWeld" and child:IsA("Weld") then
		GuiService.TouchControlsEnabled = true
		script.Parent:Destroy()
	end
end)

--[[Controls]]
local _CTRL = _Tune.Controls
local Controls = Instance.new("Folder",script.Parent)
Controls.Name = "Controls"
for i,v in next, (_CTRL) do
	local a=Instance.new("StringValue",Controls)
	a.Name=i
	a.Value=v.Name
	a.Changed:connect(function()
		if i=="MouseThrottle" or i=="MouseBrake" then
			if a.Value == "MouseButton1" or a.Value == "MouseButton2" then
				_CTRL[i]=Enum.UserInputType[a.Value]
			else
				_CTRL[i]=Enum.KeyCode[a.Value]
			end
		else
			_CTRL[i]=Enum.KeyCode[a.Value]
		end
	end)
end

--Deadzone Adjust
local _PPH = _Tune.Peripherals
	for i,v in next, (_PPH) do
	local a = Instance.new("IntValue",Controls)
	a.Name = i
	a.Value = v
	a.Changed:connect(function() 
		a.Value=math.min(100,math.max(0,a.Value))
		_PPH[i] = a.Value
	end)
end

function GetCarCenter()
	local centerF = Vector3.new()
	local centerR = Vector3.new()
	local countF = 0
	local countR = 0
	for i,v in next, car.Wheels:GetChildren() do
		if v.Name=="FL" or v.Name=="FR" or v.Name=="F" then
			centerF = centerF+v.CFrame.p
			countF = countF+1
		else
			centerR = centerR+v.CFrame.p
			countR = countR+1
		end
	end
	centerF = centerF/countF
	centerR = centerR/countR
	local center = CFrame.lookAt(centerR:Lerp(centerF,.5),centerF)
	return center
end

values.AutoClutch.Value = true

--Input Handler
function DealWithInput(input,IsRobloxFunction)
	if (UserInputService:GetFocusedTextBox()==nil) and not _InControls then --Ignore when UI Focus
		--Shift Down [Manual Transmission]
		if (input.KeyCode ==_CTRL["ContlrShiftDown"] or (_MSteer and input.KeyCode==_CTRL["MouseShiftDown"]) or ((not _MSteer) and input.KeyCode==_CTRL["ShiftDown"])) and ((_IsOn and ((_TMode=="Auto" and _CGear<=1) and _Tune.AutoShiftVers == "New") or _TMode=="Semi") or _TMode=="Manual") and input.UserInputState == Enum.UserInputState.Begin then
			if not _ShiftDn then _ShiftDn = true end
			
		--Shift Up [Manual Transmission]
		elseif (input.KeyCode ==_CTRL["ContlrShiftUp"] or (_MSteer and input.KeyCode==_CTRL["MouseShiftUp"]) or ((not _MSteer) and input.KeyCode==_CTRL["ShiftUp"])) and ((_IsOn and ((_TMode=="Auto" and _CGear<1) and _Tune.AutoShiftVers == "New") or _TMode=="Semi") or _TMode=="Manual") and input.UserInputState == Enum.UserInputState.Begin then
			if not _ShiftUp then _ShiftUp = true end
			
		--Toggle Clutch
		elseif (input.KeyCode ==_CTRL["ContlrClutch"] or (_MSteer and input.KeyCode==_CTRL["MouseClutch"]) or ((not _MSteer) and input.KeyCode==_CTRL["Clutch"])) and _TMode=="Manual" then
			if input.UserInputState == Enum.UserInputState.Begin then
				_ClPressing = true
				_PlayerClutch = true
			elseif input.UserInputState == Enum.UserInputState.End then
				_ClPressing = false
				_PlayerClutch = false
			end
			
		--Toggle PBrake
		elseif input.KeyCode ==_CTRL["ContlrPBrake"] or (_MSteer and input.KeyCode==_CTRL["MousePBrake"]) or ((not _MSteer) and input.KeyCode==_CTRL["PBrake"]) or ((not _MSteer) and input.KeyCode==_CTRL["PBrake2"]) then
			if input.UserInputState == Enum.UserInputState.Begin then
				_PBrake = not _PBrake
			elseif input.UserInputState == Enum.UserInputState.End then
				if car.DriveSeat.AssemblyLinearVelocity.Magnitude>5 then _PBrake = false end
			end
			
		--Toggle Transmission Mode
		elseif (input.KeyCode == _CTRL["ContlrToggleTMode"] or input.KeyCode==_CTRL["ToggleTransMode"]) and input.UserInputState == Enum.UserInputState.Begin then
			local n=1
			for i,v in next, (_Tune.TransModes) do
				if v==_TMode then n=i break end
			end
			n=n+1
			if n>#_Tune.TransModes then n=1 end
			_TMode = _Tune.TransModes[n]
			
		--Throttle
		elseif ((not _MSteer) and (input.KeyCode==_CTRL["Throttle"] or input.KeyCode == _CTRL["Throttle2"])) or ((((_CTRL["MouseThrottle"]==Enum.UserInputType.MouseButton1 or _CTRL["MouseThrottle"]==Enum.UserInputType.MouseButton2) and input.UserInputType == _CTRL["MouseThrottle"]) or input.KeyCode == _CTRL["MouseThrottle"])and _MSteer) then
			if input.UserInputState == Enum.UserInputState.Begin then
				_IThrot = 1
			else
				_IThrot = 0
			end
			
		--Brake
		elseif ((not _MSteer) and (input.KeyCode==_CTRL["Brake"] or input.KeyCode == _CTRL["Brake2"])) or ((((_CTRL["MouseBrake"]==Enum.UserInputType.MouseButton1 or _CTRL["MouseBrake"]==Enum.UserInputType.MouseButton2) and input.UserInputType == _CTRL["MouseBrake"]) or input.KeyCode == _CTRL["MouseBrake"])and _MSteer) then
			if input.UserInputState == Enum.UserInputState.Begin then
				_IBrake = 1
			else
				_IBrake = 0
			end
			
		--Steer Left
		elseif (not _MSteer) and (input.KeyCode==_CTRL["SteerLeft"] or input.KeyCode == _CTRL["SteerLeft2"]) then
			if input.UserInputState == Enum.UserInputState.Begin then
				_GSteerT = -1
				_SteerL = true
			else
				if _SteerR then
					_GSteerT = 1
				else
					_GSteerT = 0
				end
				_SteerL = false
			end
			
		--Steer Right
		elseif (not _MSteer) and (input.KeyCode==_CTRL["SteerRight"] or input.KeyCode == _CTRL["SteerRight2"]) then
			if input.UserInputState == Enum.UserInputState.Begin then
				_GSteerT = 1
				_SteerR = true
			else
				if _SteerL then
					_GSteerT = -1
				else
					_GSteerT = 0
				end
				_SteerR = false
			end
			
		--Toggle Mouse Controls
		elseif input.KeyCode ==_CTRL["ToggleMouseDrive"] then
			if input.UserInputState == Enum.UserInputState.End then
				_MSteer = not _MSteer
				_IThrot = 0
				_IBrake = 0
				_GSteerT = 0
			end
			
		--Toggle TCS
		elseif _Tune.TCSEnabled and _IsOn and input.KeyCode == _CTRL["ToggleTCS"] or input.KeyCode == _CTRL["ContlrToggleTCS"] then
			if input.UserInputState == Enum.UserInputState.End then _TCS = not _TCS end
		
		--Toggle ABS
		elseif _Tune.ABSEnabled and _IsOn and input.KeyCode == _CTRL["ToggleABS"] or input.KeyCode == _CTRL["ContlrToggleABS"] then
			if input.UserInputState == Enum.UserInputState.End then _ABS = not _ABS end
			
		end
		
		--Variable Controls
		if input.UserInputType.Name:find("Gamepad") then
			--Gamepad Steering
			if input.KeyCode == _CTRL["ContlrSteer"] then
				if input.Position.X>= 0 then
					local cDZone = math.min(.99,_Tune.Peripherals.ControlRDZone/100)
					if math.abs(input.Position.X)>cDZone then
						_GSteerT = (input.Position.X-cDZone)/(1-cDZone)
					else
						_GSteerT = 0
					end
				else
					local cDZone = math.min(.99,_Tune.Peripherals.ControlLDZone/100)
					if math.abs(input.Position.X)>cDZone then
						_GSteerT = (input.Position.X+cDZone)/(1-cDZone)
					else
						_GSteerT = 0
					end
				end
				
			--Gamepad Throttle
			elseif input.KeyCode == _CTRL["ContlrThrottle"] then
				_IThrot = math.max(0,input.Position.Z)
				
			--Gamepad Brake
			elseif input.KeyCode == _CTRL["ContlrBrake"] then
				_IBrake = input.Position.Z
			end
		end
	else
		_IThrot = 0
		_GSteerT = 0
		_IBrake = 0
	end
end
UserInputService.InputBegan:connect(DealWithInput)
UserInputService.InputChanged:connect(DealWithInput)
UserInputService.InputEnded:connect(DealWithInput)

function DealWithMobileInput()
	local mobile = script.Parent.Mobile
	
	mobile.Jump.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		player.Character:FindFirstChildWhichIsA("Humanoid").Jump = true
	end)
	
	mobile.ModeSwitch.MouseButton1Click:Connect(function()
		_MobileMode = _MobileModes[(table.find(_MobileModes, _MobileMode) or 0) + 1]
		if not _MobileMode then
			_MobileMode = _MobileModes[1]
		end
	end)
	
	-- Tap
	for _, button in next, mobile.Tap:GetChildren() do
		if not button:IsA("ImageButton") then continue end
		button.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			button.ImageColor3 = Color3.fromRGB(178,178,178)
			button.ImageLabel.ImageColor3 = Color3.new(0,0,0)
			button.ImageLabel.ImageTransparency = .5
			if button.Name == "Throttle" then
				_IThrot = 1
			elseif button.Name == "Brake" then
				_IBrake = 1
			elseif button.Name == "Left" then
				_GSteerT = -1
				_SteerL = true
			elseif button.Name == "Right" then
				_GSteerT = 1
				_SteerR = true
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			button.ImageColor3 = Color3.new(0, 0, 0)
			button.ImageLabel.ImageColor3 = Color3.new(1,1,1)
			button.ImageLabel.ImageTransparency = .8
			if button.Name == "Throttle" then
				_IThrot = 0
			elseif button.Name == "Brake" then
				_IBrake = 0
			elseif button.Name == "Left" then
				if _SteerR then
					_GSteerT = 1
				else
					_GSteerT = 0
				end
				_SteerL = false
			elseif button.Name == "Right" then
				if _SteerL then
					_GSteerT = -1
				else
					_GSteerT = 0
				end
				_SteerR = false
			end
		end)
	end
	
	-- Tilt
	for _, button in next, mobile.Tilt:GetChildren() do
		if not button:IsA("TextButton") then continue end
		button.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			if button.Name == "Throttle" then
				_IThrot = 1
			elseif button.Name == "Brake" then
				_IBrake = 1
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			if button.Name == "Throttle" then
				_IThrot = 0
			elseif button.Name == "Brake" then
				_IBrake = 0
			end
		end)
	end
	if UserInputService.GyroscopeEnabled then
		UserInputService.DeviceRotationChanged:Connect(function(rotation, cframe)
			if _MobileMode == "Tilt" then
				_GSteerT = -math.clamp(rotation.Position.Z*2, -1, 1)
			end
		end)
	end
end
DealWithMobileInput()

--[[Drivetrain Initialize]]
local Drive={}

--Power Front Wheels
	if _Tune.Config == "FWD" or _Tune.Config == "AWD" then for i,v in next, (car.Wheels:GetChildren()) do if v.Name=="FL" or v.Name=="FR" or v.Name=="F" then table.insert(Drive,v) end end end

--Power Rear Wheels
	if _Tune.Config == "RWD" or _Tune.Config == "AWD" then for i,v in next, (car.Wheels:GetChildren()) do if v.Name=="RL" or v.Name=="RR" or v.Name=="R" then table.insert(Drive,v) end end end

--Determine Wheel Size
local wDia = 0 for i,v in next, (Drive) do if v.Size.Y>wDia then wDia = v.Size.Y end end

--[[Throttle and Brake Input Smoothing]]
function Inputs(dt)
	local deltaTime = (60/(1/dt))
	if _InThrot <= _IThrot then
		_InThrot = math.min(_IThrot,_InThrot+(_Tune.ThrotAccel*deltaTime))
	else
		_InThrot = math.max(_IThrot,_InThrot-(_Tune.ThrotDecel*deltaTime))
	end
	if _InBrake <= _IBrake then
		_InBrake = math.min(_IBrake,_InBrake+(_Tune.BrakeAccel*deltaTime))
	else
		_InBrake = math.max(_IBrake,_InBrake-(_Tune.BrakeDecel*deltaTime))
	end
end

--[[Steering]]
SteerOuter = (_Tune.LockToLock*180)/_Tune.SteerRatio
SteerInner = math.min(SteerOuter-(SteerOuter*(1-_Tune.Ackerman)),SteerOuter*1.2)

function Steering(dt)
	local deltaTime = (60/(1/dt))
	local controller = _LastInputWasGamepad or (_Tune.MSteerUsesContlr and _MSteer or false)
	local SteerSpeed = controller and (_Tune.ContlrSteerSpeed>0 and _Tune.ContlrSteerSpeed or _Tune.Steerspeed) or _Tune.SteerSpeed * (1-math.min(car.DriveSeat.AssemblyLinearVelocity.Magnitude/(Units.Velocity_mdivs/3.6)/_Tune.SteerSpeedDecay,1-(_Tune.MinSteerSpeed/100)))
	local ReturnSpeed = controller and (_Tune.ContlrReturnSpeed>0 and _Tune.ContlrReturnSpeed or _Tune.ReturnSpeed) or _Tune.ReturnSpeed * (1-math.min(car.DriveSeat.AssemblyLinearVelocity.Magnitude/(Units.Velocity_mdivs/3.6)/_Tune.SteerSpeedDecay,1-(_Tune.MinSteerSpeed/100)))
	
	if _MSteer then
		local msWidth = math.max(1,mouse.ViewSizeX*_Tune.Peripherals.MSteerWidth/200)
		local mdZone = _Tune.Peripherals.MSteerDZone/100
		local mST = ((mouse.X-mouse.ViewSizeX/2)/msWidth)
		if math.abs(mST)<=mdZone then
			_GSteerT = 0
		else
			_GSteerT = (math.max(math.min((math.abs(mST)-mdZone),(1-mdZone)),0)/(1-mdZone))^_Tune.MSteerExp * (mST / math.abs(mST))
		end
	end
	
	--Interpolate Steering
	if _GSteerC < _GSteerT then
		if _GSteerC<0 then
			_GSteerC = math.min(_GSteerT,_GSteerC+(ReturnSpeed*deltaTime))
		else
			_GSteerC = math.min(_GSteerT,_GSteerC+(SteerSpeed*deltaTime))
		end
	else
		if _GSteerC>0 then
			_GSteerC = math.max(_GSteerT,_GSteerC-(ReturnSpeed*deltaTime))
		else
			_GSteerC = math.max(_GSteerT,_GSteerC-(SteerSpeed*deltaTime))
		end
	end
	
	--Steer Decay Multiplier
	local sDecay = (1-math.min(car.DriveSeat.AssemblyLinearVelocity.Magnitude/(Units.Velocity_mdivs/3.6)/(_Tune.SteerDecay/(Units.Velocity_mdivs/3.6)),1-(_Tune.MinSteer/100)))
	local rsDecay = (1-math.min(car.DriveSeat.AssemblyLinearVelocity.Magnitude/(Units.Velocity_mdivs/3.6)/(_Tune.RSteerDecay/(Units.Velocity_mdivs/3.6)),1-(_Tune.MinSteer/100)))
	
	--Apply Steering
	for i,v in next, car.Wheels:GetChildren() do
		if v.Name=="F" then
			v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*SteerInner*sDecay),0)
		elseif v.Name=="FL" then
			if _GSteerC>= 0 then
				v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*SteerOuter*sDecay),0)--luaint edit
			else
				v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*SteerInner*sDecay),0)--luaint edit
			end	
		elseif v.Name=="FR" then
			if _GSteerC>= 0 then
				v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*SteerInner*sDecay),0)--luaint edit
			else
				v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*SteerOuter*sDecay),0)--luaint edit
			end
		elseif v.Name=='R' then
			if _Tune.FWSteer=='None' then
			elseif _Tune.FWSteer=='Static' then
				v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerInner*rsDecay*math.max(0,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
			elseif _Tune.FWSteer=='Speed' then
				v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*RSteerInner*rsDecay*math.min(1,(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
			elseif _Tune.FWSteer=='Both' then
				v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerInner*rsDecay*math.max(-1,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
			end
		elseif v.Name=='RL' then
			if _Tune.FWSteer=='None' then
			elseif _Tune.FWSteer=='Static' then
				if _GSteerC>= 0 then
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerOuter*rsDecay*math.max(0,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				else
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerInner*rsDecay*math.max(0,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				end
			elseif _Tune.FWSteer=='Speed' then
				if _GSteerC>= 0 then
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*RSteerOuter*rsDecay*math.min(1,(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				else
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*RSteerInner*rsDecay*math.min(1,(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				end
			elseif _Tune.FWSteer=='Both' then
				if _GSteerC>= 0 then
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerOuter*rsDecay*math.max(-1,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				else
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerInner*rsDecay*math.max(-1,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				end
			end
		elseif v.Name=='RR' then
			if _Tune.FWSteer=='None' then
			elseif _Tune.FWSteer=='Static' then
				if _GSteerC>= 0 then
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerInner*rsDecay*math.max(0,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				else
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerOuter*rsDecay*math.max(0,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				end
			elseif _Tune.FWSteer=='Speed' then
				if _GSteerC>= 0 then
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*RSteerInner*rsDecay*math.min(1,(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				else
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,-math.rad(_GSteerC*RSteerOuter*rsDecay*math.min(1,(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				end
			elseif _Tune.FWSteer=='Both' then
				if _GSteerC>= 0 then
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerInner*rsDecay*math.max(-1,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				else
					v.Arm.Steer.CFrame=v.Base.CFrame*CFrame.Angles(0,math.rad(_GSteerC*RSteerOuter*rsDecay*math.max(-1,1-(car.DriveSeat.Velocity.Magnitude/_Tune.RSteerSpeed))),0)--luaint edit
				end
			end
		end
		if v:GetAttribute("SteerDisabled") then v.Arm.Steer.CFrame = v.Base.CFrame end
	end
end

--[[Engine]]
local fFD = _Tune.FinalDrive*_Tune.FDMult
local fFDr = fFD*30/math.pi --this is for converting rad/s to RPM and whatnot
local cGrav = (_Tune.GravComp > 0 and _Tune.GravComp or workspace.Gravity)*_Tune.InclineComp/35
local wDRatio = wDia*math.pi/60
local cfWRot = CFrame.Angles(math.pi/2,-math.pi/2,0)
local cfYRot = CFrame.Angles(0,math.pi,0)

--Electric Only Setup
if not _Tune.Engine and _Tune.Electric then 
	_Tune.Redline = _Tune.E_Redline 
	_Tune.ShiftRPM = _Tune.E_Redline
	_Tune.Turbochargers = 0
	_Tune.Superchargers = 0
	_Tune.Clutch = false 
	_Tune.IdleRPM = 0 
	_Tune.IdleThrottle = 0
	_Tune.ClutchType = "Clutch" 
	_Tune.AutoShiftType = "DCT" 
	_Tune.ShiftUpTime = 0.1 
	_Tune.ShiftDnTime = 0.1 
end

--Powertrain
task.wait()

--Automatic Transmission
function Auto()
	local maxSpin=0
	for i,v in next, Drive do if _WheelSpeeds[v.Name]>maxSpin then maxSpin = _WheelSpeeds[v.Name] end end
	if _IsOn then
		if _Tune.AutoShiftVers == "Old" and _CGear == 0 then _CGear = 1 _ClPressing = false end
		if _CGear >= 1 then
			if (_CGear==1 and _InBrake > 0 and car.DriveSeat.AssemblyLinearVelocity.Magnitude < 5) and _Tune.AutoShiftVers == "Old" then
				_CGear = -1 _ClPressing = false
			elseif car.DriveSeat.AssemblyLinearVelocity.Magnitude > 5 and _Tune.ClutchType ~= "CVT" then
				if _Tune.AutoShiftMode == "RPM" then
					if _RPM>(_Tune.ShiftRPM+_Tune.AutoUpThresh) then
						if not _ShiftUp and not _Shifting then _ShiftUp = true end
					elseif math.max(math.min(maxSpin*_Tune.Ratios[_CGear+1]*fFDr,_Tune.Redline+100),0)<(_Tune.ShiftRPM-_Tune.AutoDownThresh) and _CGear>1 then
						if not _ShiftDn and not _Shifting then _ShiftDn = true end 
					end
				else
					if car.DriveSeat.AssemblyLinearVelocity.Magnitude > math.ceil(wDRatio*(_Tune.ShiftRPM+_Tune.AutoUpThresh)/_CurrentRatio/fFD) then
						if not _ShiftUp and not _Shifting then _ShiftUp = true end
					elseif car.DriveSeat.AssemblyLinearVelocity.Magnitude < math.ceil(wDRatio*(_Tune.ShiftRPM-_Tune.AutoDownThresh)/_Tune.Ratios[_CGear+1]/fFD) and _CGear>1 then
						if not _ShiftDn and not _Shifting then _ShiftDn = true end
					end
				end
			end
		else
			if (_InThrot > 0 and car.DriveSeat.AssemblyLinearVelocity.Magnitude < 5) and _Tune.AutoShiftVers == "Old" then
				_CGear = 1 _ClPressing = false
			end
		end
	end 
end

function Gear()
	local maxSpin=0
	for i,v in next, (Drive) do if _WheelSpeeds[v.Name]>maxSpin then maxSpin = _WheelSpeeds[v.Name] end end
	if _ShiftUp and not _Shifting then
		if (_TMode == "Manual" and not _ClPressing) or (_TMode == "Manual" and _Tune.ClutchRel and (_InThrot>0)) or _CGear == #_Tune.Ratios-2 or (_TMode ~= "Manual" and not _IsOn) then _ShiftUp = false return end
		local NextGear = math.min(_CGear+3,#_Tune.Ratios)
		if _TMode~="Manual" and _Tune.ClutchType ~= "CVT" then
			_Shifting = true
			if _CGear>0 then 
				if _Tune.AutoShiftType=="DCT" then 
					task.wait(_Tune.ShiftUpTime)
				elseif _Tune.AutoShiftType=="Rev" then
					repeat task.wait() until _RPM<=math.max(math.min(maxSpin*_Tune.Ratios[NextGear]*fFDr,_Tune.Redline-_Tune.RevBounce),_Tune.IdleRPM+_Tune.ClutchIdle) or not _IsOn or _ShiftDn 
				end
			end
		end
		_ShiftUp = false
		_Shifting = false
		if _TMode ~= "Manual" and not _IsOn then return end
		if NextGear >= 4 and _Tune.ClutchType == "CVT" then return end  -- make sure it cannot go past 1st gear
		_CGear = math.min(_CGear+1,#_Tune.Ratios-2)
		if _TMode ~= "Manual" or (_TMode == "Manual" and _CGear == 1) and _IsOn then _ClPressing = false end
	end
	if _ShiftDn and not _Shifting then
		if (_TMode == "Manual" and not _ClPressing) or _CGear == -1 or (_TMode ~= "Manual" and not _IsOn) then _ShiftDn = false return end
		local PrevGear = math.min(_CGear+1,#_Tune.Ratios)
		if _TMode~="Manual" then
			_Shifting = true
			if _CGear>1 then 
				if _Tune.AutoShiftType=="DCT" then 
					task.wait(_Tune.ShiftDnTime)
				elseif _Tune.AutoShiftType=="Rev" then
					repeat task.wait() until _RPM>=math.max(math.min(maxSpin*_Tune.Ratios[PrevGear]*fFDr,_Tune.Redline-_Tune.RevBounce),_Tune.IdleRPM+_Tune.ClutchIdle) or not _IsOn or _ShiftUp
				end
			end
		end
		_ShiftDn = false
		_Shifting = false
		if _TMode ~= "Manual" and not _IsOn then return end
		_CGear = math.max(_CGear-1,-1)
		if _TMode ~= "Manual" or (_TMode == "Manual" and _CGear == -1) and _IsOn then _ClPressing = false end
	end
end

local _GoalRPM=0
local tqTCS = 1
local _StallOK = false
local ticc = tick()

--Power calculation prerequesites
local function f(m, n, p, q, M, b, x)
	return math.clamp(M - ( (q-n)/(b^p-b^m) * (b^x-b^m) + n ), 0, M)
end

--Apply Power
function Engine(dt)
	local deltaTime = (60/(1/dt))
	
	--Average Rotational Speed Calculation
	local fwspeed=0
	local fwcount=0
	local rwspeed=0
	local rwcount=0

	for i,v in next, (car.Wheels:GetChildren()) do
		if v.Name=="FL" or v.Name=="FR" or v.Name == "F" then
			fwspeed=fwspeed+_WheelSpeeds[v.Name]
			fwcount=fwcount+1
		elseif v.Name=="RL" or v.Name=="RR" or v.Name == "R" then
			rwspeed=rwspeed+_WheelSpeeds[v.Name]
			rwcount=rwcount+1
		end
	end
	fwspeed=fwspeed/fwcount
	rwspeed=rwspeed/rwcount	
	local cwspeed=(fwspeed+rwspeed)/2

	local maxSpin=0
	local maxCount=0
	local revThrot=_GThrot
	for i,v in next, (Drive) do maxSpin = maxSpin + _WheelSpeeds[v.Name] maxCount = maxCount + 1 end
	maxSpin=maxSpin/maxCount
	local _WheelRPM = maxSpin*_CurrentRatio*fFDr
	
	--CVT
	if _Tune.ClutchType == "CVT" then
		_CVTRatio = math.clamp((_Tune.CVTRPM*_GThrot)/(maxSpin*fFDr), _Tune.CVTMinRatio, _Tune.CVTMaxRatio)
	end

	--Update ratio
	_CurrentRatio = _Tune.ClutchType == "CVT" and _CVTRatio or _Tune.Ratios[_CGear+2]
	_spLimit = (_Tune.Redline+100)/(fFDr*_CurrentRatio)
	
	--Neutral Gear
	if ((_CGear == 0 or _Shifting) and _IsOn) then 
		_ClPressing = true
		_Clutch = 1
		_StallOK = false
	end
	
	_FlywheelEnergy = math.max(_FlywheelEnergy-_Tune.Flywheel, 0)
	if _Clutch == 1 then
		_FlywheelEnergy = math.max((_RPM-_WheelRPM)/1000 * _GThrot * _Tune.FlywheelEnergy,0)
	end
	
	local revMin = 1
	local goalMin = 1
	local goalMax = _Tune.Redline+100
	if _Tune.Stall and _Tune.Clutch then revMin = 0 end
	
	if _Shifting and _ShiftUp then 
		_GThrot = _Tune.IdleThrottle/100
	elseif _Shifting and _ShiftDn then
		_GThrot = (_Tune.ShiftThrot/100)
	else
		if (_Tune.AutoShiftVers == "Old" and _CGear==-1 and _TMode=="Auto") then
			_GThrot = _InBrake
		else
			_GThrot = math.max(_InThrot, _Tune.IdleThrottle/100)
		end
	end
	
	if (_Tune.AutoShiftVers == "Old" and _CGear==-1 and _TMode=="Auto") then
		_GBrake = _InThrot
	else
		_GBrake = _InBrake
	end
	
	if not _IsOn then 
		ticc = tick()
		_Clutch = 1 
		if not script.Parent.Starting.Value then
			_GThrot = 0
		end
	end
	
	if ((_ClPressing and _CGear == 0) or (_PlayerClutch and _CGear ~= 0)) and _Tune.NeutralLimit then
		if (_CGear == 0 and not _Tune.LimitClutch) or _Tune.LimitClutch then
			goalMax = _Tune.NeutralRevRPM
		end
	end
	
	--Determine RPM
	-- Rev limiter/speed limiter
	if _RPM >= _Tune.Redline then
		revLimiting = true
	elseif _RPM < _Tune.Redline-_Tune.RevBounce then
		revLimiting = false
	end
	if revLimiting then
		_GThrot = _Tune.IdleThrottle/100
	end
	
	local limit = (_CGear<0 and _Tune.ReverseSpeed or _Tune.SpeedLimit)
	if limit > 0 then
		if car.DriveSeat.AssemblyLinearVelocity.Magnitude >= limit-_Tune.SLimitGradient then
			_GThrot = math.max(math.min(_GThrot, math.max((limit-car.DriveSeat.AssemblyLinearVelocity.Magnitude/(Units.Velocity_mdivs/3.6))/_Tune.SLimitGradient,0)), _Tune.IdleThrottle/100)
		end
	end

	-- Idle
	if _RPM<_Tune.IdleRPM and _IsOn then
		_GThrot = math.max(_GThrot, math.clamp((_Tune.IdleRPM-_RPM)/400, 0, 1))
	end
	
	if (_Tune.Engine or _Tune.Electric) and (not script.Parent.Starting.Value) then
		_GoalRPM = math.clamp(_RPM - (_Tune.RevDecay*deltaTime) + (_Tune.RevAccel*revThrot*values.Torque.Value*deltaTime) - (math.clamp(math.max(_RPM-_Tune.IdleRPM,0)/math.max(_Tune.Redline-_Tune.IdleRPM,1),0,1)*_Tune.RevDecayRPM*deltaTime),goalMin,goalMax)
	end

	--Starting
	if script.Parent.Starting.Value then
		if _RPM > _Tune.IgnitionRPM then
			script.Parent.IsOn.Value = true
			script.Parent.Starting.Value = false
			_GThrot = 0
		else
			_GoalRPM += _Tune.IgnitionAccel
			_GThrot = 1
		end
	end
	
	if _Tune.Clutch then
		if values.AutoClutch and _IsOn then
			if _Tune.ClutchType == "Clutch" or _Tune.ClutchType == "CVT" then
				if _ClPressing then _ClutchKick = 1 end
				_ClutchKick = _ClutchKick*(_Tune.ClutchEngage/100)		
				local ClRPMInfluence = math.max((_RPM)*_Tune.ClutchRPMMult/(_Tune.Redline),0)
				if _Tune.ClutchMode == "New" then ClRPMInfluence = 0 end
				_ClutchModulate = math.min(((((script.Parent.Values.Velocity.Value.Magnitude/(Units.Velocity_mdivs/3.6)/_Tune.SpeedEngage)/math.abs(_CGear)) + ClRPMInfluence) - _ClutchKick), 1)
			elseif _Tune.ClutchType == "TorqueConverter" and _Tune.TQLock then
				if (_GThrot<=_Tune.IdleThrottle/100 and script.Parent.Values.Velocity.Value.Magnitude/(Units.Velocity_mdivs/3.6)<_Tune.SpeedEngage) or (_GThrot>_Tune.IdleThrottle/100 and (_RPM < _Tune.RPMEngage and _WheelRPM < _Tune.RPMEngage)) then
					_ClutchModulate = math.min(_ClutchModulate*(_Tune.ClutchEngage/100), 1)
				else
					_ClutchModulate = math.min(_ClutchModulate*(_Tune.ClutchEngage/100)+(1-(_Tune.ClutchEngage/100)), 1)
				end
			elseif _Tune.ClutchType == "TorqueConverter" and not _Tune.TQLock then
				_ClutchModulate = math.min((_RPM/_Tune.Redline)*0.7, 1)
			end
			if not _ClPressing then _Clutch = math.min(1-_ClutchModulate,1) else _Clutch = 1 end
			_StallOK = (_Clutch<=0.01) or _StallOK
		else
			_StallOK = _Tune.Stall
			_Clutch = script.Parent.Values.Clutch.Value
		end
	else
		_StallOK = false
		if not _ClPressing and not _Shifting then _Clutch = 0 else _Clutch = 1 end
	end
	
	if revLimiting or script.Parent.Starting.Value then
		_Clutch = 1
	end
	if _RPM <= _Tune.IdleRPM+_Tune.ClutchIdle and _IsOn then
		_Clutch = math.max(_Clutch, math.clamp((_Tune.IdleRPM+_Tune.ClutchIdle-_RPM)/100, 0, 1))
	end
	
	local aRPM = math.max(math.min((_GoalRPM*_Clutch) + (_WheelRPM*(1-_Clutch)),_Tune.Redline+100),revMin)
	local clutchP = math.min(math.abs(aRPM-_RPM)/(_Tune.Flywheel*deltaTime),.9)
	if _ClPressing then clutchP = 0 end
    print("-----S")
    print(_RPM)
    print(clutchP)
    if _RPM ~= _RPM then
        _RPM = goalMin
    end
	_RPM = _RPM*clutchP + aRPM*(1-clutchP)
	if _RPM > goalMax then
		_RPM = goalMax
	elseif _RPM < goalMin then
		_RPM = goalMin
	end
    if _RPM ~= _RPM then
        _RPM = goalMin
    end
    print("-----M")
    print(_RPM)
    print(clutchP)
	
	if _RPM<=(_Tune.IdleRPM/4) and _StallOK and (tick()-ticc>=0.2) then script.Parent.IsOn.Value = not _Tune.Stall end

	-- Torque calculations (Detomiks)
	-- What you see here is mostly just ported over from Desmos.
	local x = _RPM/1000
	local NTorque = 0
	local ETorque = 0
	local TTorque = 0
	local STorque = 0
	if _Tune.Engine then
		local NIdleTorque = f(_Tune.IdleRPM/1000, _Tune.IdleTorque, _Tune.PeakTorqueRPM/1000, _Tune.PeakTorque, _Tune.PeakTorque, _Tune.IdleTorqueCurve, x)
		local NRedlineTorque = f(_Tune.PeakTorqueRPM/1000, _Tune.PeakTorque, _Tune.Redline/1000, _Tune.RedlineTorque, _Tune.PeakTorque, 1/_Tune.RedlineTorqueCurve, x)
        print("++++++++")
        print(_Tune.VVLTorque)
        print(_Tune.VVLRPM)
        print(_Tune.VVLTime)
        print(_Tune.VVLCurve)
        print(x)
        local VVL = 0
        if _Tune.VVLTorque ~= 0 then
            VVL = _Tune.VVLTorque - f(_Tune.VVLRPM/1000, 0, (_Tune.VVLRPM + _Tune.VVLTime)/1000, _Tune.VVLTorque, _Tune.VVLTorque, _Tune.VVLCurve, x)
        end
        if VVL ~= VVL then
            VVL = 0
        end
        print(VVL)
        print("ZZZZ")
        print(boolToNum[_Tune.Engine])
        print(_Tune.PeakTorque)
        print(NIdleTorque)
        print(NRedlineTorque)
        print(VVL)
        print("XMXMMX")
		NTorque = boolToNum[_Tune.Engine] * (_Tune.PeakTorque - NIdleTorque - NRedlineTorque + VVL)
		_NH, _NT = (NTorque*x)/5.252, NTorque
		
		if _Tune.Turbochargers > 0 then
			local _TBoostGoal = _Tune.Turbochargers * _GThrot^3 * (_Tune.T_Boost - f(_Tune.IdleRPM/1000, _Tune.T_IdleBoost, _Tune.T_PeakRPM/1000, _Tune.T_Boost, _Tune.T_Boost, 1/_Tune.T_Curve, x))
			if _TBoostGoal > _TBoost then
				_TBoost = math.min(_TBoost + _Tune.T_SpoolIncrease * _GThrot * deltaTime, _TBoostGoal)
			elseif _TBoost > _TBoostGoal then
				_TBoost = math.max(_TBoost * _Tune.T_SpoolDecrease, _TBoostGoal)
			end
			TTorque = _TBoost * _Tune.T_Efficiency
			_TH, _TT = (TTorque*x)/5.252, TTorque
		end
		if _Tune.Superchargers > 0 then
			local SIdleBoost = f(_Tune.IdleRPM/1000, _Tune.S_IdleBoost, _Tune.S_PeakRPM/1000, _Tune.S_PeakBoost, _Tune.S_PeakBoost, _Tune.S_IdleCurve, x)
			local SRedlineBoost = f(_Tune.S_PeakRPM/1000, _Tune.S_PeakBoost, _Tune.Redline/1000, _Tune.S_RedlineBoost, _Tune.S_PeakBoost, 1/_Tune.S_RedlineCurve, x)
			local _SBoostGoal = _Tune.Superchargers * _GThrot * (_Tune.S_PeakBoost - SIdleBoost - SRedlineBoost)
			if _SBoostGoal > _SBoost then
				_SBoost = math.min(_SBoost + _Tune.S_PeakBoost*_Tune.S_Response*deltaTime, _SBoostGoal)
			elseif _SBoost > _SBoostGoal then
				_SBoost = math.max(_SBoost - _Tune.S_PeakBoost*_Tune.S_Response*deltaTime, _SBoostGoal)
			end
			STorque = _SBoost * _Tune.S_Efficiency
			_SH, _ST = (STorque*x)/5.252, STorque
		end
		if _Tune.Turbochargers > 0 or _Tune.Superchargers > 0 then
			_BH, _BT = ((TTorque+STorque)*x)/5.252, TTorque+STorque
		end
	end
	if _Tune.Electric then
		ETorque = boolToNum[_Tune.Electric] * (_Tune.E_Torque - f(_Tune.E_TransitionRPM/1000, _Tune.E_Torque, _Tune.E_Redline/1000, _Tune.E_RedlineTorque, _Tune.E_Torque, _Tune.E_Curve, x))
		_EH, _ET = (ETorque*x)/5.252, ETorque
	end


    print({
        ["NTorque"] = NTorque, --NaN
        ["ETorque"] = ETorque,
        ["TTorque"] = TTorque,
        ["STorque"] = STorque,
        ["_RPM"] = _RPM, --NaN
        ["HPLimit"] = _Tune.HPLimit
    })
	local TotalTorque = math.clamp(NTorque + ETorque + TTorque + STorque, 0, (_Tune.HPLimit > 0 and _Tune.HPLimit or math.huge)*(5.252/x))
	_HP, _TQ = (TotalTorque*x)/5.252, TotalTorque
	
	-- Exit engine
	_OutTorque = _TQ * _CurrentRatio * fFD
	local iComp = (_CarCenter.LookVector.Y)*cGrav
	if _CGear==-1 then iComp=-iComp end
	_OutTorque = _OutTorque*math.max(1,(1+iComp))
	
	--Update Wheels
	for i,v in next, (car.Wheels:GetChildren()) do
		--Reference Wheel Orientation
		local Ref=(CFrame.new(v.Position-((v.Arm.CFrame*cfWRot).lookVector),v.Position)*cfYRot).lookVector
		local aRef=1
		local RRdiffMult=1
		local RLdiffMult=1
		local FRdiffMult=1
		local FLdiffMult=1
		if v.Name=="FL" or v.Name=="RL" then aRef=-1 end
		
		--Differential/Torque-Vectoring
		if v.Name=="FR" then
			local avg=((_WheelSpeeds[v.Name]/_WheelSpeeds["FL"])-1)*(_Tune.FDiffPreload/10)
			FRdiffMult=math.ceil(math.max(0,math.min(2,1-( ((_Tune.FDiffPower/100)*avg*_GThrot) + ((_Tune.FDiffCoast/100)*avg*(1-_GThrot)))))*100)/100
			FLdiffMult=2-FRdiffMult
		elseif v.Name=="FL" then
			local avg=((_WheelSpeeds[v.Name]/_WheelSpeeds["FR"])-1)*(_Tune.FDiffPreload/10)
			FLdiffMult=math.ceil(math.max(0,math.min(2,1-( ((_Tune.FDiffPower/100)*avg*_GThrot) + ((_Tune.FDiffCoast/100)*avg*(1-_GThrot)))))*100)/100
			FRdiffMult=2-FLdiffMult
		elseif v.Name=="RR" then
			local avg=((_WheelSpeeds[v.Name]/_WheelSpeeds["RL"])-1)*(_Tune.RDiffPreload/10)
			RRdiffMult=math.ceil(math.max(0,math.min(2,1-( ((_Tune.RDiffPower/100)*avg*_GThrot) + ((_Tune.RDiffCoast/100)*avg*(1-_GThrot)))))*100)/100
			RLdiffMult=2-RRdiffMult
		elseif v.Name=="RL" then
			local avg=((_WheelSpeeds[v.Name]/_WheelSpeeds["RR"])-1)*(_Tune.RDiffPreload/10)
			RLdiffMult=math.ceil(math.max(0,math.min(2,1-( ((_Tune.RDiffPower/100)*avg*_GThrot) + ((_Tune.RDiffCoast/100)*avg*(1-_GThrot)))))*100)/100
			RRdiffMult=2-RLdiffMult
		end
		--Limit values to prevent physics death
		if RRdiffMult > 2 then RRdiffMult = 2 elseif RRdiffMult < 0 then RRdiffMult = 0 end
		if RLdiffMult > 2 then RLdiffMult = 2 elseif RLdiffMult < 0 then RLdiffMult = 0 end
		if FRdiffMult > 2 then FRdiffMult = 2 elseif FRdiffMult < 0 then FRdiffMult = 0 end
		if FLdiffMult > 2 then FLdiffMult = 2 elseif FLdiffMult < 0 then FLdiffMult = 0 end
		
		--Output
	
		--Apply Power
		local on=1
		if not script.Parent.IsOn.Value then on=0 end
		local throt = _GThrot
		local brake = _GBrake
		local clutch=1
		if _ClPressing then clutch=0 end
		if _RPM < _Tune.IdleRPM then clutch = 0 end
		local tq = (_OutTorque+_FlywheelEnergy)/#Drive
				
		--Apply ABS
		local tqABS = 1
		if _ABS and brake>0 and math.abs(v.RotVelocity.Magnitude*(v.Size.Y/2)/(Units.Velocity_mdivs/3.6) - v.Velocity.Magnitude/(Units.Velocity_mdivs/3.6))-_Tune.ABSThreshold>0 then
			tqABS = math.max(0, _Tune.ABSLimit / 100)
		end
		if tqABS<1 then
			_ABSActive = true
		end
		_ABSAmt += tqABS
		_ABSTracker[v.Name] = 1 - tqABS
	
		local PBrakeV=0
		if _PBrake==true then PBrakeV=1 else PBrakeV=0 end
		
		local driven = false
		for _,a in next, (Drive) do if a==v then driven = true end end
		local engineTorque = 0
		local brakeTorque = 0
		if driven then
			--Apply AWD Vectoring
			if _Tune.Config == "AWD" then
				local bias = (_Tune.TorqueVector+1)
				if string.find(v.Name,"F") then
					tq = tq*(2-bias)
				elseif string.find(v.Name,"R") then
					tq = tq*bias
				end
			end
			
			--Apply TCS
			tqTCS = 1
			if _TCS and throt>0 then
				tqTCS = 1-(math.min(math.max(0,math.abs(v.RotVelocity.Magnitude*(v.Size.Y/2)/(Units.Velocity_mdivs/3.6) - v.Velocity.Magnitude/(Units.Velocity_mdivs/3.6))-_Tune.TCSThreshold)/_Tune.TCSGradient,1)*(1-(_Tune.TCSLimit/100)))
			end
			if tqTCS < 1 then
				_TCSActive = true
			end
			_TCSTracker[v.Name] = 1 - tqTCS
			
			--Update Forces
			local tqOUT = tq*1.356*Units.Torque_nm*(60/workspace:GetRealPhysicsFPS())*throt*tqTCS*on*clutch
			if tqOUT < 0 then tqOUT = 0 elseif tqOUT > 1000000 then tqOUT = 0 end
			-- convert lb-ft to nm to roblox stuff
			-- if it reaches an absurdly high number, set it to 0 to prevent physics death
			
			if v.Name=='RR' then
				v["#AV"].MotorMaxTorque=tqOUT*RRdiffMult
			elseif v.Name=='RL' then
				v["#AV"].MotorMaxTorque=tqOUT*RLdiffMult
			elseif v.Name=='FR' then
				v["#AV"].MotorMaxTorque=tqOUT*FRdiffMult
			elseif v.Name=='FL' then
				v["#AV"].MotorMaxTorque=tqOUT*FLdiffMult
			else
				v["#AV"].MotorMaxTorque=tqOUT
			end
			v["#AV"].AngularVelocity=_spLimit*math.sign(_CGear)

			if string.find(v.Name,"F") then
				local force = (FBrakeForce*(60/workspace:GetRealPhysicsFPS())*brake*tqABS)+(EBrakeForce*((1-throt)*(_RPM/_Tune.Redline)))+(PBrakeForceF*PBrakeV)
				if force > 1000000 then force = 0 elseif force < 0 then force = 0 end
				v["#BV"].MotorMaxTorque = force
			else
				local force = (RBrakeForce*(60/workspace:GetRealPhysicsFPS())*brake*tqABS)+(EBrakeForce*((1-throt)*(_RPM/_Tune.Redline)))+(PBrakeForceR*PBrakeV)
				if force > 1000000 then force = 0 elseif force < 0 then force = 0 end
				v["#BV"].MotorMaxTorque = force
			end
		else--luaint edit
			v["#AV"].MotorMaxTorque=0
			v["#AV"].AngularVelocity=0
			if string.find(v.Name,"F") then
				v["#BV"].MotorMaxTorque=(FBrakeForce*(60/workspace:GetRealPhysicsFPS())*brake*tqABS)+(PBrakeForceF*PBrakeV)
			else
				v["#BV"].MotorMaxTorque=(RBrakeForce*(60/workspace:GetRealPhysicsFPS())*brake*tqABS)+(PBrakeForceR*PBrakeV)
			end
		end
	end
end

--[[Flip]]
function Flip()
	--Detect Orientation
	if (car.DriveSeat.CFrame*CFrame.Angles(math.pi/2,0,0)).lookVector.y > .1 or FlipDB then
		FlipWait=tick()
		
	--Apply Flip
	else
		if tick()-FlipWait>=3 then
			FlipDB=true
			local gyro = car.DriveSeat.Flip
			gyro.maxTorque = Vector3.new(10000,0,10000)
			gyro.P=3000
			gyro.D=500
			task.wait(1)
			gyro.maxTorque = Vector3.new(0,0,0)
			gyro.P=0
			gyro.D=0
			FlipDB=false
		end
	end
end

--[[Run]]

--Print Version
local ver=require(car["A-Chassis Tune"].README)
print("A-Chassis, Version "..ver)

--Runtime Loops
game:GetService("RunService").Heartbeat:Connect(function(dt)
	--Update Internal Values
	_IsOn = script.Parent.IsOn.Value
	_InControls = script.Parent.ControlsOpen.Value
	_LastInputWasGamepad = string.find(UserInputService:GetLastInputType().Name, "Gamepad") and true or false
	_CarCenter = GetCarCenter()
	
	--Update External Values
	-- Transmission
	if values.AutoClutch.Value then values.Clutch.Value = _Clutch end
	values.Gear.Value = _CGear
	values.TransmissionMode.Value = _TMode
	values.CurrentRatio.Value = _CurrentRatio
	values.RPM.Value = _RPM
    print({
        ["_RPM"] = _RPM,
        ["_CurrentRatio"] = _CurrentRatio
    })
	-- Boost
	values.Boost.Value = _TBoost + _SBoost
	values.BoostTurbo.Value = _TBoost
	values.BoostSuper.Value = _SBoost
	-- Horsepower
	values.HpNatural.Value = _NH
	values.HpElectric.Value = _EH
	values.HpTurbo.Value = _TH
	values.HpSuper.Value = _SH
	values.HpBoosted.Value = _BH
	values.Horsepower.Value = _HP
	-- Torque
	values.TqNatural.Value = _NT
	values.TqElectric.Value = _ET
	values.TqTurbo.Value = _TT
	values.TqSuper.Value = _ST
	values.TqBoosted.Value = _BT
	values.Torque.Value = _TQ
	-- Inputs
	values.Throttle.Value = _GThrot
	values.IThrottle.Value = _IThrot
	values.Brake.Value = _GBrake
	values.IBrake.Value = _IBrake
	values.SteerC.Value = _GSteerC
	values.SteerT.Value = _GSteerT
	values.MouseSteerOn.Value = _MSteer
	values.PBrake.Value = _PBrake
	-- Velocity
	values.Velocity.Value = car.DriveSeat.AssemblyLinearVelocity
	values.CarCenter.Value = _CarCenter
	
	-- TCS
	_TCSAmt = 0
	local count = 0
	for i, v in next, _TCSTracker do
		if not values.TCSTracker:FindFirstChild(i) then
			Instance.new("NumberValue", values.TCSTracker).Name = i
		end
		values.TCSTracker[i].Value = v
		_TCSAmt += v
		count += 1
	end
	values.TCS.Value = _TCS
	values.TCSActive.Value = _TCSActive
	_TCSAmt /= count
	values.TCSAmt.Value = _TCSAmt
	_TCSActive = false
	-- ABS
	_ABSAmt = 0
	local count = 0
	for i, v in next, _ABSTracker do
		if not values.ABSTracker:FindFirstChild(i) then
			Instance.new("NumberValue", values.ABSTracker).Name = i
		end
		values.ABSTracker[i].Value = v
		_ABSAmt += v
		count += 1
	end
	values.ABS.Value = _ABS
	values.ABSActive.Value = _ABSActive
	_ABSAmt /= count
	values.ABSAmt.Value = _ABSAmt
	_ABSActive = false
	-- Wheel speeds
	for _, wheel in next, car.Wheels:GetChildren() do
		if not _WheelSpeedsTable[wheel.Name] then
			_WheelSpeedsTable[wheel.Name] = {}
		end
		table.insert(_WheelSpeedsTable[wheel.Name], wheel.RotVelocity.Magnitude)
		if #_WheelSpeedsTable[wheel.Name] > 6 then
			table.remove(_WheelSpeedsTable[wheel.Name], 1)
		end
		local avg = 0
		for _, a in next, _WheelSpeedsTable[wheel.Name] do
			avg += a
		end
		avg /= #_WheelSpeedsTable[wheel.Name]
		_WheelSpeeds[wheel.Name] = avg
	end
	local rot = 0
	for i, v in next, _WheelSpeeds do
		if not values.WheelSpeeds:FindFirstChild(i) then
			Instance.new("NumberValue", values.WheelSpeeds).Name = i
		end
		values.WheelSpeeds[i].Value = v
		rot += v*(car.Wheels[i].Size.Y/2)
	end
	
	values.AverageRotSpeed.Value = rot/#car.Wheels:GetChildren()
	values.Acceleration.Value = (car.DriveSeat.AssemblyLinearVelocity-_OldVelocity)*(1/dt)
	_OldVelocity = car.DriveSeat.AssemblyLinearVelocity
	values.DragFactor.Value = _DragFactor
	
	--Inputs
	
	Inputs(dt)

	--Steering

	Steering(dt)

	--Gear

	Gear()

	--Power

	Engine(dt)
	
	--Automatic Transmission
	if _TMode == "Auto" then Auto() end

	--Flip
	if _Tune.AutoFlip then Flip() end
	
	--Mobile UI
	local mobile = UserInputService:GetLastInputType() == Enum.UserInputType.Touch
	script.Parent.Mobile.Visible = mobile
	script.Parent.Mobile.ModeSwitch.Visible = car.DriveSeat.AssemblyLinearVelocity.Magnitude < 5
	script.Parent.Mobile.ModeSwitch.Text = _MobileMode
	script.Parent.Mobile.Jump.Visible = script.Parent.Mobile.ModeSwitch.Visible
	if mobile then
		_Tune.AutoShiftVers = "Old"
		_TMode = "Auto"
	else
		_Tune.AutoShiftVers = autoshiftvers
	end
	for _, v in next, script.Parent.Mobile:GetChildren() do
		if v.ClassName ~= "Frame" then continue end
		v.Visible = _MobileMode == v.Name
	end
end)

--[[END]]
