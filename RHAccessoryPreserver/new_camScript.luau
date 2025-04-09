-- SERVICES
local UserInputService							= game:GetService("UserInputService")

-- REFERENCES
-- The final script should be hidden in CoreGui like the main one.
local hiddenUI = get_hidden_gui or gethui
if not hiddenUI then error("Your executor doesn't support hiding GUI's, so it's too unsafe to use this script. Sorry!") end

-- Ensure the main script generates its GUI before loading and executing this one!
local GUI_Base : ScreenGui						= hiddenUI():WaitForChild("NewRHAccessoryPreserver")
task.wait(0.333)

local GUI_Viewport : ViewportFrame				= GUI_Base:WaitForChild("WindowBack"):WaitForChild("Contents"):WaitForChild("PreviewModel")
local GUI_Scene : MeshPart						= GUI_Viewport:WaitForChild("WorldModel"):WaitForChild("PreviewScene")

-- Preview camera setup
local Camera									= Instance.new("Camera")
Camera.CameraType								= Enum.CameraType.Scriptable
Camera.FieldOfView								= 62.5
Camera.CFrame									= CFrame.identity
Camera.Name										= "PreCam"
Camera.Parent									= GUI_Viewport
GUI_Viewport.CurrentCamera						= Camera	-- Bind this new camera to the ViewportFrame.

-- Event connections
local Conn_InputBegan:RBXScriptConnection?		= nil
local Conn_InputEnded:RBXScriptConnection?		= nil
local Conn_InputChangedGUI:RBXScriptConnection?	= nil	-- Detects mouse wheel movement inside the viewport (for zooming on computers).
local Conn_InputChangedOut:RBXScriptConnection?	= nil	-- Detects mouse movements inside and outside of the viewport for rotation.
local Conn_TouchZoom:RBXScriptConnection?		= nil
local Conn_ChildAdded:RBXScriptConnection?		= nil	-- Detects when a new Model is added to the viewport, adjusting the "floor height".

-- STATIC DATA (CONSTANTS)
													-- Input methods that can start a click-drag to rotate or move (vertically) the camera.
local DRAG_START_INPUTS							= {Enum.UserInputType.MouseButton1,Enum.UserInputType.MouseButton2,Enum.UserInputType.Touch}
local DISTANCE_LIMITS							= NumberRange.new(1.5, 15)	-- How far the camera can move towards/away from the model.

-- VARIABLES
local CamOffset									= {
	Distance									= 7,	-- How far the camera has moved away from the origin in studs.
	StartHeight									= 0,	-- Vertical positioning/angle in degrees (-90 to 90)
	DragHeight									= 0,	-- Additional pitch adjustment added by the current drag.
	StartAngle									= 0,	-- Camera's rotation around the origin (0-359)
	DragAngle									= 0		-- Additional rotation added by the current mouse drag.
}
local DragStartPos : Vector3?					= nil	-- Keeps track of how far the player's finger/cursor's moved, for accurate rotation.
local Touch_StartDistance : number?				= nil	-- The camera's distance at the beginning of a touch pinch gesture.

--[[
	<custom><nb><md>
		A common function which updates the camera's CFrame based on the *CamOffset* dictionary entry's values.
		The camera always points towards the origin, which usually hovers above the middle of the center tile.
		Remember to pivot the "PreviewScene" mesh when placing a new model in the previewer (3D scene)!
		**Conn_ChildAdded** should handle that by itself, however.
]]--
local function UpdateCameraPosition()
	if not Camera then
		error("The 3D viewport camera was destroyed!")
	else
		if not GUI_Viewport.CurrentCamera then GUI_Viewport.CurrentCamera = Camera end
		
		-- Make a pre-rotated CFrame, which will be "moved backwards" to zoom out from the origin.
		-- local temp_RotatedCFrame = CFrame.Angles(math.rad(CamOffset.Pitch), math.rad(CamOffset.Angle), 0)
		local temp_RotatedCFrame =
			CFrame.new(0, CamOffset.StartHeight + CamOffset.DragHeight, 0) *
			CFrame.Angles(0, math.rad((CamOffset.StartAngle+CamOffset.DragAngle)%360), 0)
		Camera.CFrame = temp_RotatedCFrame * CFrame.new(temp_RotatedCFrame.LookVector * CamOffset.Distance, Vector3.zero)
	end
end

Conn_InputBegan		= GUI_Viewport.InputBegan:Connect(function(_input)
	--[[
		When the player clicks within the viewport, try to keep track of their movement relative to these starting coordinates.
		Don't do this if they're zooming in/out, which could cause glitches.
	]]
	if table.find(DRAG_START_INPUTS, _input.UserInputType) and not Touch_StartDistance then
		-- print("Drag started at", _input.Position.X, _input.Position.Y)
		DragStartPos = _input.Position
	end
end)

Conn_InputChangedGUI	= GUI_Viewport.InputChanged:Connect(function(_input)
	-- On computers, the mouse wheel zooms in/out. (This is ignored if they're pinch-zooming or moving the camera any other way, though.)
	if not DragStartPos and not Touch_StartDistance and _input.UserInputType == Enum.UserInputType.MouseWheel then
		CamOffset.Distance = math.clamp(CamOffset.Distance-(_input.Position.Z/2),DISTANCE_LIMITS.Min,DISTANCE_LIMITS.Max)
		UpdateCameraPosition()
	end
end)
Conn_InputChangedOut	= UserInputService.InputChanged:Connect(function(_input, _processed)
	if DragStartPos and not Touch_StartDistance and	-- Don't count a drag if the player's zooming in/out using touch.
		(_input.UserInputType == Enum.UserInputType.MouseMovement or _input.UserInputType == Enum.UserInputType.Touch)
	then
		CamOffset.DragAngle = _input.Position.X - DragStartPos.X
		CamOffset.DragHeight = _input.Position.Y - DragStartPos.Y
		
		-- If using a mouse, "slow down" camera movements to make drags feel consistent with Roblox's default camera movements and stuff.
		if _input.UserInputType ~= Enum.UserInputType.Touch then
			CamOffset.DragAngle /= 3.5
			CamOffset.DragHeight /= 48
		end
		-- print("Dragged", CamOffset.DragAngle, CamOffset.DragHeight)
		UpdateCameraPosition()
	end
end)

Conn_InputEnded		= UserInputService.InputEnded:Connect(function(_input)
	-- Stop tracking mouse movement if the player stops clicking (even outside of the viewport).
	if DragStartPos and table.find(DRAG_START_INPUTS, _input.UserInputType) then
		-- print("Drag ended!")
		DragStartPos = nil
		
		if CamOffset.DragAngle ~= 0 or CamOffset.DragHeight ~= 0 then
			CamOffset.StartAngle += CamOffset.DragAngle
			CamOffset.DragAngle = 0
			CamOffset.StartHeight += CamOffset.DragHeight
			CamOffset.DragHeight = 0
		end
	end
end)

--[[
	TODO: Implement zooming for touch devices/phones! Grab the current cam. distance, then continuously set the current distance to it
	multiplied by scale. Obviously, clamp it so the camera can't get closer or further away from the model than a PC exploiter could.
	Come to think of it, a smaller scale might represent a PINCH, so the range may need to be re-mapped so pinching INCREASES the final
	distance, and vice versa.
]]--
Conn_TouchZoom		= GUI_Viewport.TouchPinch:Connect(function(_, _scale, _, _state)
	if _state == Enum.UserInputState.End then
		Touch_StartDistance = nil
		return nil	-- After nil'ing the distance, end the function here.
	elseif _state == Enum.UserInputState.Begin then	-- When a pinch begins, note the current distance. Pinches will multiply it (somehow).
		Touch_StartDistance = CamOffset.Distance
		DragStartPos = nil	-- Just to be safe, end a touch drag gesture if it was triggered before Roblox detected this pinch.
	end
	
	--[[
		Re-map and invert the scale range so pinching zooms out to the camera's max distance, and vice versa.
	]]
	CamOffset.Distance = math.clamp(math.map(_scale,0, 3,DISTANCE_LIMITS.Max,DISTANCE_LIMITS.Min),DISTANCE_LIMITS.Min,DISTANCE_LIMITS.Max)
	print("New scale is", _scale)
end)

Conn_ChildAdded = GUI_Scene.Parent.ChildAdded:Connect(function(_newChild)
	if _newChild:IsA("Model") then
		-- Remove any other Models in the preview when a new one appears in it, to keep it tidy.
		for _,_otherChild in GUI_Scene.Parent:GetChildren() do
			if _otherChild.Name ~= "PreviewScene" and _otherChild ~= _newChild then _otherChild:Destroy() end
		end
		
		-- Always pivot the new Model to the origin first.
		_newChild:PivotTo(CFrame.identity)
		
		-- Let's find out what the new model is, so we can position the floor correctly.
		local temp_floorHeight : number	= 0 
		local temp_leftFoot				= _newChild:FindFirstChild("LeftFoot")
		local temp_rightFoot			= _newChild:FindFirstChild("RightFoot")
		if _newChild:FindFirstChildOfClass("Humanoid") and temp_leftFoot and temp_rightFoot then
			local temp_midpoint : Vector3 = temp_leftFoot.CFrame:Lerp(temp_rightFoot.CFrame, 0.5).Position
			GUI_Scene:PivotTo(Vector3.yAxis * temp_midpoint.Y)
		else	-- Otherwise, if this is a Model, move the floor to half its height, which should align it with its base most of the time.
			local _, temp_size = _newChild:GetBoundingBox()
			if temp_size then temp_floorHeight = -(temp_size.Y)/2 end
		end
		
		-- Invalidate the current drag, then reset the camera's height.
		DragStartPos			= nil
		CamOffset.DragHeight	= 0
		CamOffset.StartHeight	= 0
		UpdateCameraPosition()
	end
end)