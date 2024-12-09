-- SERVICES
local ReplicatedStorage					= game:GetService("ReplicatedStorage")
local ContextActionService				= game:GetService("ContextActionService")
local RunService						= game:GetService("RunService")
local UserInputService					= game:GetService("UserInputService")
local CollectionService					= game:GetService("CollectionService")
local TweenService						= game:GetService("TweenService")

local Constants						= {}

-- Required functions from PMM
local function DoBulkRaycastFromOrigin(_origin : Vector3, _directionArray : {Vector3}, _raycastParams : RaycastParams, _debugSettings :
	{
		-- Affects what each ray in the bulk operation will be colored as. Colors near its endwill be used for raycasts farther in the array.
		ColorRange : string,
		Time : number	-- How long each line will render for before being cleared. 0 = 1 frame.
	}
) : RaycastResult
	local result : RaycastResult = nil	-- Like with the standard raycast function, return nil by default.
	
	if _origin and type(_origin) == "vector" and
		_directionArray and type(_directionArray) == "table" and _directionArray[1] and type(_directionArray[1]) == "vector" and
		_raycastParams and typeof(_raycastParams) == "RaycastParams"
	then
		for count, _direction : Vector3 in _directionArray do
			result = workspace:Raycast(	-- Cast a ray towards a given direction and see if it hits anything.
				_origin,
				_direction,
				_raycastParams
			)
		end
	
	else	-- If any of the parameters aren't specified or valid, find out which is the problematic one and warn the programmer about it.
		if not _origin or type(_origin) ~= "vector" then warn("No origin was provided, or it isn't a Vector3 value.")
		--[[elseif not _directionArray or type(_directionArray) ~= "table" or _directionArray[1] or type(_directionArray[1]) ~= "vector" then
			warn("The list of directions wasn't defined or valid. It must be an array of Vector3 values only.")]]--
		elseif not _raycastParams or typeof(_raycastParams) ~= "RaycastParams" then
			warn("No raycast parameters were given to the function, or it isn't a RaycastParameters object.")
		end
	end
	
	return result	-- If any of the rays detected something, this will naturally contain a RaycastResult object, otherwise being nil.
end

-- SafeLerp(takes Vector3/Vector2/UDim2, Vector3/Vector2/UDim2, and number, returns number)
-- Lerps the given _value using its :Lerp() method, but checks for low magnitudes before
-- doing so, which (should) avoid the infamous "NaN bug".
local function SafeLerp(_value : any, _goal : any, _alpha : number) : any
	-- The initial "result" value will always be the given _value; If the lerp's magnitude is too small, to avoid Roblox's stupid NaN bug,
	-- this value is returned instead of zero, or any other value. This removes the need to wrap a call to this function in an "if" check.
	local result = _value
	
	if _value and _goal and _alpha then
		-- If everything checks out, attempt to lerp the value towards _goal. If the magnitude is too low, just return the original value.
		if result then
			if (_value-_goal).Magnitude > 0.001 then
				result = _value:Lerp(_goal, _alpha)
				-- print("Was lerped", result)
				-- else print("Left value as 0; Magnitude was only", (_value-_goal).Magnitude)
			end
		else warn("SafeLerp: The value provided wasn't a Vector3, Vector2, or UDim2. Sorry, Roblox only allows for lerping of those types.")
		end
	else warn("SafeLerp: A required parameter wasn't given.")
	end
	
	return result
end

local function UpdateCollisionProperties(_character, _density)
	if _character and typeof(_character) == "Instance" and _character.ClassName == "Model" and
		_density and type(_density) == "number"
	then
		
		-- Figure out what the properties of this character's HumanoidRootPart will be. (All other parts, excluding the ball, are massless.)
		local CharacterPhysicalProperties = {
			HRP = nil,
			Others = PhysicalProperties.new(0.01, 0, 0, 0, 0)
		}
		if _density >= 0.0 then CharacterPhysicalProperties.HRP = PhysicalProperties.new(_density, 0.3, 1, 1, 2)
		else CharacterPhysicalProperties.HRP = CharacterPhysicalProperties.Others
		end
		
		for _, _descendant : BasePart in ipairs(_character:GetDescendants()) do
			if _descendant:IsA("BasePart") then
				
				-- If density is 0 or above, set it to that, plus the other standard character values for PMM.
				-- Density being less than zero means this is a request to make the character massless, so others can carry them (toddlers).	
				if _descendant.Name == "HumanoidRootPart" then
					-- print("HumanoidRootPart is massless?", _density < 0.001)
					_descendant.Massless = _density < 0.001	-- The HRP is the only part of the Character that has any weight to it.
					_descendant.CustomPhysicalProperties = CharacterPhysicalProperties.HRP
				elseif _descendant.Name ~= "RollingCollision" then	-- If it's not the HRP and ball, it doesn't matter and is massless.
					-- print(_descendant.Name, "should be massless.")
					_descendant.Massless = true
					_descendant.CustomPhysicalProperties = CharacterPhysicalProperties.Others
				end
			end
		end
		
		-- If this player states they're in VR, Nexus VR doesn't support PhysicsCharacterController, so they're using the "legacy" one.
		-- However, when not in VR, the player's jump height is 0.001, so they can't jump by pressing A! Set their jump height to the
		-- "legacy" version's jump height. In the future, the legacy controller won't be used outside of VR, cluttering the code.
		-- The player's jump height can't be set to a specific value upon spawning, even if it wasn't set to 0.001 due to scripts not
		-- being updated for PhysicsCharacterController because of the different ages, anyways.
		--[[
			if game:GetService("Players"):GetPlayerFromCharacter(_character) and Players:GetPlayerFromCharacter(_character):GetAttribute("VirtualReality") then
				_character:FindFirstChildOfClass("Humanoid").JumpHeight = 0.001
					-- Constants.AgeProps[CharEntry.Attributes.CharData:GetAttribute("AgeClaimed")].JumpHeight
			end
		]]--
	else warn("UpdateCollisionProperties: An argument wasn't valid!")
	end
end

local LocalPlayer = game:GetService("Players").LocalPlayer

-- Scaling values for all four ages/sizes in Project Magical Mary, meant for HumanoidDescriptions.
-- Use the age bitfield values under Animations.Ages to index into this array.
Constants.AgeProps							= {
	[1] =
		{
			-- Base character sizing
			BodyTypeScale				= 0,
			DepthScale					= 0.475,
			HeadScale					= 0.75,
			HeightScale					= 0.393,
			ProportionScale				= 0,
			WidthScale					= 0.4,
			
			AgeValue					= 1,		-- A probably useless value, redundant with this index's "key" (which is 1 here).
			AgeName						= "Toddler",
			NameTagOffset				= 6.125,
			
			-- Standard speed/height property modifications (and density, which affects weight and momentum).
			WalkSpeed					= 6.25,
			RunSpeed					= 20,
			JumpHeight					= 7.5,	-- Character jump height in RP areas. (In platformer levels, custom characters are always adults.)
			Density						= 0.875,
			-- Density					= 0.875,
			
			-- Child and younger properties
			FallChance					= 248,	-- How likely (0-255) that this size will topple over when they ricochet off of a surface while moving.
			FallDuration				= 7.125,	-- Time that a fallen player will stay helplessly stuck on the floor, unable to get up.
			FallThreshold				= -0.0125,	-- How different the previous and current move directions must be to fall over.
			ParentsCanHold				= true,	-- Deprecated property; For new code, please use CarryAges below.
			CarryAges					= {		-- Ages that can carry this younger age.
				8
			}
		},
	[2] =
		{
			-- Base character sizing
			BodyTypeScale				= 1,
			DepthScale					= 0.733,
			HeadScale					= 0.815,
			HeightScale					= 0.48,
			ProportionScale				= 1,
			WidthScale					= 0.628,
			
			AgeValue					= 2,
			AgeName						= "Child",
			NameTagOffset				= 5.25,
			
			-- Standard speed/height property modifications (and density, which affects weight and momentum).
			WalkSpeed					= 9.75,
			RunSpeed					= 47.5,
			JumpHeight					= 14.75,
			Density						= 0.425,
			-- Density					= 0.425,
			
			-- Child and younger properties
			FallChance					= 96,
			FallDuration				= 3.25,
			FallThreshold				= -0.025,	-- How different the previous and current move directions must be to fall over.
			ParentsCanHold				= true,
			CarryAges					= {		-- Ages that can carry this younger age.
				8
			}
		},
	[4] =	-- All values here should be the exact middle betweeen kid and adult scaling values.
		{
			-- Base character sizing
			BodyTypeScale				= 0.75,
			DepthScale					= 0.842,
			HeadScale					= 0.88,
			HeightScale					= 0.74,
			ProportionScale				= 1,
			WidthScale					= 0.714,
			
			AgeValue					= 4,
			AgeName						= "Teenager",
			NameTagOffset				= 4.25,
			
			-- Standard speed/height property modifications (and density, which affects weight and momentum).
			WalkSpeed					= 10.75,
			RunSpeed					= 43.5,
			JumpHeight					= 20,
			Density						= 0.275,
			-- Density					= 0.275,
			
			-- Child and younger properties
			FallChance					= 20,
			FallDuration				= 1.5,
			FallThreshold				= -0.00625,	-- How different the previous and current move directions must be to fall over.
			ParentsCanHold				= false
		},
	[8] =	-- The default size used by players.
		{
			-- Base character sizing
			BodyTypeScale				= 0.5,
			DepthScale					= 0.95,
			HeadScale					= 0.945,
			HeightScale					= 1,
			ProportionScale				= 1,
			WidthScale					= 0.8,
			
			AgeValue					= 8,
			AgeName						= "Adult",
			NameTagOffset				= 3.25,
			
			-- Standard speed/height property modifications (and density, which affects weight and momentum).
			WalkSpeed					= 11.125,
			RunSpeed					= 62.25,
			JumpHeight					= 30,
			Density						= 0.25,
			-- Density						= 0.15,
			
			-- Child and younger properties
			ParentsCanHold				= false
		}
}

local CharEntry = {}
CharEntry.Character = game:GetService("Players").LocalPlayer.Character
CharEntry.Humanoid = CharEntry.Character:WaitForChild("Humanoid")

-- Prepare a couple animations (RH-specific, sadly)
local RollPoseAnim = Instance.new("Animation")
RollPoseAnim.AnimationId = "rbxassetid://15984661700"
local RollingPose = CharEntry.Humanoid.Animator:LoadAnimation(RollPoseAnim)
RollingPose.Priority = Enum.AnimationPriority.Action4
local AirDashAnim = Instance.new("Animation")
AirDashAnim.AnimationId = "rbxassetid://6253592602"
local AirDashReaction = CharEntry.Humanoid.Animator:LoadAnimation(AirDashAnim)
AirDashReaction.Priority = Enum.AnimationPriority.Action4

-- Create an invisible ball within the player; They can use it to roll around by holding Q, L1, or a touch button. (Currently disabled.)
	local RollingSphere						= Instance.new("Part")
	RollingSphere.Name						= "RollingCollision"
	RollingSphere.Shape						= Enum.PartType.Ball
	RollingSphere.Transparency				= 1
	RollingSphere.Size						= Vector3.one * 5.25
	RollingSphere.CustomPhysicalProperties	= PhysicalProperties.new(10, 2, 0, 1, 0)
	RollingSphere.CanCollide				= false	-- By default, the sphere doesn't collide with anything. Only enable when rolling.
	RollingSphere.CanQuery					= false
	RollingSphere.CanTouch					= false
	RollingSphere.CollisionGroup			= "Player"
	RollingSphere.Massless					= true
	RollingSphere.Parent					= CharEntry.Character
	
	-- Wled the sphere to the player's HumanoidRootPart so it's always following them invisibly.
	local RollWeld							= Instance.new("Weld")
	RollWeld.Part0							= RollingSphere
	RollWeld.Part1							= CharEntry.Humanoid.RootPart
	RollWeld.Parent							= RollingSphere

UpdateCollisionProperties(CharEntry.Character, Constants.AgeProps[8].Density)
UpdateCollisionProperties(CharEntry.Character, Constants.AgeProps[8].Density)

-- REFERENCES
local LocalSphereColl : BasePart		= CharEntry.Character:WaitForChild("RollingCollision")
local DefaultCameraSubject				= workspace.CurrentCamera.CameraSubject

-- DATA
local RaycastParams_JumpCheck = RaycastParams.new()
RaycastParams_JumpCheck.IgnoreWater = true
RaycastParams_JumpCheck.RespectCanCollide = true
RaycastParams_JumpCheck.FilterType = Enum.RaycastFilterType.Exclude
RaycastParams_JumpCheck.FilterDescendantsInstances = {CharEntry.Character, workspace["EquippedStorage"]}

-- VARIABLES
local FloorDetected						= {	-- The result of both raycasting downward from the player and Roblox's built-in floor detection.
	Previous = false,
	Current = false,
	LastRayResult = nil
}
local FloorDetectionDisableTime			= 0.0	-- Time left until the floor check raycasts resume.
local AirMovementSpeed					= {
	Previous = Vector2.zero,	-- The unaltered X and Z velocities used on the previous frame, copied from "Lerped".
	Lerped = Vector2.zero,		-- The edited velocities, the ones passed to the AssemblyLinearVelocity Vector3 value.
	Current = Vector2.zero,		-- The player's current speed, which is lerped towards over time.
}

local JustStartedRoll					= false	-- Set to TRUE when the player initially curls up when rolling.
local Timer_JumpDebounce				= 0.0	-- Prevents the JumpRequested function from running code, preventing "high jumps" (maybe).
local Timer_HelplessFallTime			= 0.0	-- How much time that a player can't stand up, even when uncurling from rolling.

local PreviousPositions = { Vector3.zero, Vector3.zero }	-- The player's last two positions, used to calculate their speed.
local Differences =
	{
		AllAxis			= { Vector3.zero, Vector3.zero },
		HorizontalOnly	= { Vector3.zero, Vector3.zero }
	}
local OverallMoveAmount = Vector3.zero
-- SetupJumpVariables (takes nothing, returns nothing)
-- Forcibly updates specific variables relating to the looping RenderStepped function below.
-- This includes setting the player's previous movement variable to fake "inertia", and
-- making the function blindly assume that the player's jumping so it avoids raycasting.
local function SetupJumpVariables()
	AirMovementSpeed.Previous = Vector2.new(
		CharEntry.Humanoid.RootPart.AssemblyLinearVelocity.X,
		CharEntry.Humanoid.RootPart.AssemblyLinearVelocity.Z
	)
	AirMovementSpeed.Current = AirMovementSpeed.Previous
	AirMovementSpeed.Lerped = AirMovementSpeed.Previous
	FloorDetectionDisableTime = 0.75
	FloorDetected.Current = false	-- Force the loop to assume the player's in the air.
	return true
end

-- Fake jump momentum, timers, and floor status updates.
RunService.Stepped:Connect(function(_, _delta)
	-- If any timers need to be decremented, do that before anything else.
	if Timer_JumpDebounce > 0.0 then Timer_JumpDebounce -= _delta end
	if Timer_HelplessFallTime > 0.0 then
		Timer_HelplessFallTime -= _delta
		if Timer_HelplessFallTime <= 0.0 then	-- Once the timer expires, the player can stand up again.
			CharEntry.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)	-- Keep the player upright now.
			CharEntry.Humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		end
	end
	
	FloorDetected.Previous = FloorDetected.Current	-- Shift back the current floor status to the "previous" slot.
	
	if FloorDetectionDisableTime > 0.0 then FloorDetectionDisableTime -= _delta end	-- Any remaining time? Subtract delta from it first.
	
	if FloorDetectionDisableTime <= 0.0 then	-- Only raycast if it's currently allowed.
		FloorDetected.LastRayResult = DoBulkRaycastFromOrigin(
			CharEntry.Humanoid.RootPart.Position,
			{	-- Fire up to nine rays from the bottom of the player's HumanoidRootPart.
				Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1),

				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.1125)) + CharEntry.Humanoid.RootPart.CFrame.RightVector * -0.333,
				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.1125)) + CharEntry.Humanoid.RootPart.CFrame.RightVector * 0.333,
				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.1125)) + CharEntry.Humanoid.RootPart.CFrame.LookVector * -0.333,
				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.1125)) + CharEntry.Humanoid.RootPart.CFrame.LookVector * 0.333,

				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.125)) + CharEntry.Humanoid.RootPart.CFrame.RightVector * -0.75,
				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.125)) + CharEntry.Humanoid.RootPart.CFrame.RightVector * 0.75,
				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.125)) + CharEntry.Humanoid.RootPart.CFrame.LookVector * -0.75,
				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.125)) + CharEntry.Humanoid.RootPart.CFrame.LookVector * 0.75,

				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.25)) + CharEntry.Humanoid.RootPart.CFrame.RightVector * -1.5,
				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.25)) + CharEntry.Humanoid.RootPart.CFrame.RightVector * 1.5,
				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.25)) + CharEntry.Humanoid.RootPart.CFrame.LookVector * -1.5,
				(Vector3.yAxis * -(CharEntry.Humanoid.HipHeight + 1.25)) + CharEntry.Humanoid.RootPart.CFrame.LookVector * 1.5
			},
			RaycastParams_JumpCheck
		)
		
		--[[
			Is this floor's angle (normal) too steep?  It's probably not a slope or floor (and might be a wall), so don't use it.
			This is only done if the player isn't rolling, as that causes false positives and makes jumping while rolling frustrating!
			
			TODO: This code isn't what's cutting upward slope jumps off prematurely! Figure out what's going wrong when the player
			presses the JUMP button while walking into/towards a slope. Also, fix the inconsistent raycast timing while rolling, which
			makes jumping frustratingly unreliable, but only when rolling.
		]]--
		if FloorDetected.LastRayResult and FloorDetected.LastRayResult.Normal.Unit:Dot(Vector3.yAxis) < 0.0625
		then
			if not LocalPlayer:GetAttribute("IsRolling") then FloorDetected.LastRayResult = nil end
		end
		
		-- Update the current "floor status" variable here. If no ground's detected (with rays), this will be nil, so this is true/false.
		-- This also uses Roblox's built-in detection as a fallback, though obviously no "floor normal vector" will be provided to jumps.
		FloorDetected.Current = FloorDetected.LastRayResult ~= nil or CharEntry.Humanoid.FloorMaterial ~= Enum.Material.Air
		
		-- Did the player land? Clear their spring lock, if it was set by a spring before now.
		if FloorDetected.Current and FloorDetectionDisableTime <= 0 and not FloorDetected.Previous then
			LocalPlayer:SetAttribute("HasAirDashed", false)
			LocalPlayer:SetAttribute("SpringLocked", false)
		end
	end
	
	-- If the player just left the ground, keep this function from raycasting so it doesn't ruin it.
		if not FloorDetected.Current and FloorDetected.Previous and FloorDetectionDisableTime <= 0.0 then
			SetupJumpVariables()
		end
	
	if not FloorDetected.Current and not LocalPlayer:GetAttribute("IsRolling") then
		-- Calculate how fast that the player should move through the air, based on their current and previous/lerped speeds.
		-- To do that, first update what values we have. Inherit Previous's value from Lerped, then update Current.
		AirMovementSpeed.Previous = AirMovementSpeed.Lerped
		
		AirMovementSpeed.Current = Vector2.new(
			CharEntry.Humanoid.RootPart.AssemblyLinearVelocity.X,
			CharEntry.Humanoid.RootPart.AssemblyLinearVelocity.Z
			-- CharEntry.Humanoid.MoveDirection.X * CharEntry.Humanoid.WalkSpeed,
			-- CharEntry.Humanoid.MoveDirection.Z * CharEntry.Humanoid.WalkSpeed
		)
		
		--[[
			When jumping, the player has subtle control over their movement. Pressing nothing will cause them to slow down, and
			holding a direction will influence them to go that way. If the player was recently launched by a spring, this is
			disabled so spring chains always function. If abilities like Air Dashes and gliding using parasols are added, they
			should unset this player attribute "flag" so the player regains control.
		]]--
		if not LocalPlayer:GetAttribute("SpringLocked") then
			AirMovementSpeed.Lerped = SafeLerp(
				AirMovementSpeed.Previous,
				AirMovementSpeed.Current,
				0.125
			)
		end
		
		-- Constantly give the player fake velocity while in the air.
		CharEntry.Humanoid.RootPart.AssemblyLinearVelocity = Vector3.new(
			AirMovementSpeed.Lerped.X,	-- CharEntry.Humanoid.MoveDirection.X*CharEntry.Humanoid.WalkSpeed,
			CharEntry.Humanoid.RootPart.AssemblyLinearVelocity.Y,
			AirMovementSpeed.Lerped.Y)	-- CharEntry.Humanoid.MoveDirection.Z*CharEntry.Humanoid.WalkSpeed)
	end
end)

local function ChangeWalkSpeed(_actionName : string, _inputState : Enum.UserInputState, _inputObject : InputObject)
	if _inputState == Enum.UserInputState.End and _actionName == "ToggleSprint" then
		if CharEntry.Humanoid.WalkSpeed <= Constants.AgeProps[8].WalkSpeed+1.0 then
			CharEntry.Humanoid.WalkSpeed = Constants.AgeProps[8].RunSpeed
			ContextActionService:SetTitle(_actionName, "Walk")
		else
			CharEntry.Humanoid.WalkSpeed = Constants.AgeProps[8].WalkSpeed
			ContextActionService:SetTitle(_actionName, "Run")
		end
	end
end

-- GetRollToggleConditions (takes UserInputState enumerator, returns boolean)
-- Based on this player's last input type, checks for specific conditions, which essentially changes
-- the type of input necessary to start/stop rolling. The first argument determines whether this
-- is fhe first or second nested if statement in ToggleRoll() (needed for toggles to only run the
-- inner code when the input ends), and the second argument is ToggleRoll()'s input state value.

-- On mobile, this checks for if this is specifically an "end" input (1) and if the player's IsRolling
-- attribute is false (2). On keyboard/mouse, this instead always returns true (1) and checks if this input is
-- beginning, soecifically (2).
local function GetRollToggleConditions(_checkNumber : number, _inputState : Enum.UserInputState)
	local pass = false	-- By default, return "false" and invalidate the if stateement.
	if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then	-- Touchscreens (mobile)
		if _checkNumber <= 1 then
			if _inputState == Enum.UserInputState.End then
				if (not LocalPlayer:GetAttribute("IsRolling") and OverallMoveAmount.Magnitude > 1) or
					LocalPlayer:GetAttribute("IsRolling")	-- Rolling can only begin while moving, but you can always stop rolling.
				then
					pass = true	-- You can't roll unless you're moving!
				end
			end
		else
			if not LocalPlayer:GetAttribute("IsRolling") then pass = true end
		end
	else	-- Keyboard, mouse, and gamepad
		if _checkNumber <= 1 then
			if (not LocalPlayer:GetAttribute("IsRolling") and OverallMoveAmount.Magnitude > 1) or
				LocalPlayer:GetAttribute("IsRolling")	-- Rolling can only begin while moving, but you can always stop rolling.
			then
				pass = true	-- You can't roll unless you're moving!
			end
		else
			if _inputState == Enum.UserInputState.Begin then pass = true end
		end
	end
	
	return pass
end

local function ToggleRoll(_actionName : string, _inputState : Enum.UserInputState, _inputObject : InputObject)
	if _actionName == "Roll" and GetRollToggleConditions(1, _inputState) and not CharEntry.Character:GetAttribute("IsBeingCarried") then
		if GetRollToggleConditions(2, _inputState) then
			JustStartedRoll = true
			LocalPlayer:SetAttribute("IsRolling", true)	-- Set this attribute so other scripts can detect when the player's rolling.
			CharEntry.Humanoid.PlatformStand = true
			CharEntry.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			LocalSphereColl.CanCollide = true
			LocalSphereColl.Massless = false	-- Allow the invisible sphere to take over the player's movement.
			workspace.CurrentCamera.CameraSubject = LocalSphereColl
			
			RollingPose:Play()
			ContextActionService:SetTitle(_actionName, "Uncurl")
			
			-- Don't unset this flag until a quarter-second later, so the player can't do a "high jump" by jumping as they start rolling.
			task.delay(0.25, function()
				if JustStartedRoll then JustStartedRoll = false end
			end)
			
			-- "Transfer" the player's momentum into roll speed!
			LocalSphereColl.AssemblyAngularVelocity = Vector3.new(
				OverallMoveAmount.Z * 6,
				0,
				-OverallMoveAmount.X * 6
			)
		else	-- If they're rolling, end the roll.
			LocalPlayer:SetAttribute("IsRolling", false)
			LocalSphereColl.Orientation = Vector3.yAxis * LocalSphereColl.Orientation.Y
			CharEntry.Humanoid.PlatformStand = false
			RollingPose:Stop()
			
			-- If the player is allowed to return to standing, let them. Otherwise, transition to FallingDown.
			if CharEntry.Humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp) then
				CharEntry.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
				CharEntry.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			else
				CharEntry.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)	-- Let the player fall over...for now.
				CharEntry.Humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
			end
			workspace.CurrentCamera.CameraSubject = DefaultCameraSubject
			-- task.wait()
			LocalSphereColl.Massless = true	-- Let the player move with "momentum" again.
			LocalSphereColl.CanCollide = false
			ContextActionService:SetTitle(_actionName, "Roll")
		end
	end
end

ContextActionService:BindAction("ToggleSprint", ChangeWalkSpeed, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("ToggleSprint", "Run")
ContextActionService:BindAction("Roll", ToggleRoll, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("Roll", "Roll")
local temp_jumpImpulseValue = 0.0	-- This variable is updated on each jump. Its value varies based on the Player's outdated "obby" attribute.

UserInputService.JumpRequest:Connect(function()
	-- The player can only jump if they haven't recently already done so, and if they're not sitting/being held.
	-- and CharEntry.Humanoid.JumpHeight > 0
	if not CharEntry.Humanoid.SeatPart and Timer_JumpDebounce <= 0.0 then
		-- Only allow jumps if the player CAN jump.
		if CharEntry.Humanoid.JumpPower > 0.001 then CharEntry.Humanoid.JumpPower = 0 end -- 0.001 end
		
		if FloorDetected.Current then	-- If grounded, try to jump!
			if LocalPlayer:GetAttribute("IsRolling") and not JustStartedRoll then
				-- Do a raycast below the player's rolling collision. If it hits something, they might be on the ground.
				local temp_groundCheckResult = workspace:Spherecast(
					LocalSphereColl.Position + (Vector3.yAxis/2),
					LocalSphereColl.Size.X,
					Vector3.yAxis * -7.5,
					RaycastParams_JumpCheck
				)
				--[[local temp_groundCheckResult = DoBulkRaycastFromOrigin(
					LocalSphereColl.Position,
					{	-- Fire up to five rays from the bottom of the player's rolling collision.
						Vector3.yAxis * -(LocalSphereColl.Size.Y + 1),
						(Vector3.yAxis * -(LocalSphereColl.Size.Y + 1)) + Vector3.xAxis * -1.5,
						(Vector3.yAxis * -(LocalSphereColl.Size.Y + 1)) + Vector3.xAxis * 1.5,
						(Vector3.yAxis * -(LocalSphereColl.Size.Y + 1)) + Vector3.zAxis * -1.5,
						(Vector3.yAxis * -(LocalSphereColl.Size.Y + 1)) + Vector3.zAxis * 1.5
					},
					RaycastParams_JumpCheck
				)]]--
				
				if FloorDetected.Current then
					-- print("Jumping while rolling!")
					--[[
						TODO: If PhysicsCharacterController will be used in the future, check if the PhysCharController "active" attribute is
						set for this player (in its char. entry) then reference the PhysCharController dictionary entry's JumpPower instead of
						StandardVR's JumpHeight constant value.
					]]--
					temp_jumpImpulseValue = Constants.AgeProps[8].JumpHeight
					
					LocalSphereColl.Massless = true
					if FloorDetected.LastRayResult then
						LocalSphereColl:ApplyImpulse(
							FloorDetected.LastRayResult.Normal * temp_jumpImpulseValue
						)
					else
						LocalSphereColl:ApplyImpulse(
							Vector3.yAxis * temp_jumpImpulseValue
						)
					end
					
					task.wait()
					LocalSphereColl.Massless = false
				end
			else	-- If jumping normally, update the player's last move direction variable then start the looping function until they land.
				-- SetupJumpVariables() (Why was this commented out?)
				
				if FloorDetected.Current then
					-- print("Jumping while...not rolling!")
					
					--[[
						TODO: If PhysicsCharacterController will be used in the future, check if the PhysCharController "active" attribute is
						set for this player (in its char. entry) then reference the PhysCharController dictionary entry's JumpPower instead of
						StandardVR's JumpHeight constant value.
					]]--
					temp_jumpImpulseValue = Constants.AgeProps[8].JumpHeight
					
					if FloorDetected.LastRayResult then
						CharEntry.Humanoid.RootPart:ApplyImpulse(FloorDetected.LastRayResult.Normal * temp_jumpImpulseValue)
					else
						CharEntry.Humanoid.RootPart:ApplyImpulse(Vector3.yAxis * temp_jumpImpulseValue)
					end
				end
				
				
			end
		-- If the player's in the air and tries to jump, perform an Air Dash!
		elseif not LocalPlayer:GetAttribute("HasAirDashed") and not LocalPlayer:GetAttribute("IsRolling") then
			LocalPlayer:SetAttribute("HasAirDashed", true)
			
			AirMovementSpeed.Current = Vector2.new(
				CharEntry.Humanoid.RootPart.CFrame.LookVector.X,
				CharEntry.Humanoid.RootPart.CFrame.LookVector.Z
			)
			AirMovementSpeed.Previous = AirMovementSpeed.Current
			AirMovementSpeed.Lerped = AirMovementSpeed.Current
			AirDashReaction:Play(0.3)
			task.delay(0.6, function() AirDashReaction:Stop(0.5) end)
			
			CharEntry.Humanoid.RootPart.AssemblyLinearVelocity = Vector3.new(
				CharEntry.Humanoid.RootPart.CFrame.LookVector.X * 768,
				28,
				CharEntry.Humanoid.RootPart.CFrame.LookVector.Z * 768
			)
			-- print(CharEntry.Humanoid.RootPart.CFrame.LookVector.X,CharEntry.Humanoid.RootPart.CFrame.LookVector.Z)
			CharEntry.Humanoid.RootPart.AssemblyAngularVelocity = Vector3.zero
		end
	end
	
	print("Jump request received!")
	Timer_JumpDebounce = 0.325
end)

RunService.Stepped:Connect(function(_time, _delta)
	-- Get the difference between the player's position on this frame compared to the previous, and shift back the Vector3 stored before it.
	Differences.AllAxis[2] = Differences.AllAxis[1]	-- The current frame and previous one's player position differences are stored here.
	Differences.AllAxis[1] = (LocalSphereColl.Position - PreviousPositions[1])
	Differences.HorizontalOnly[2] = Differences.HorizontalOnly[1]	-- The current frame and previous one's player position differences are stored here.
	Differences.HorizontalOnly[1] = Vector3.new(	-- Also store the differences in position each frame, but only for horizontal movement.
		LocalSphereColl.Position.X - PreviousPositions[1].X,
		0,
		LocalSphereColl.Position.Z - PreviousPositions[1].Z
	)	-- (VectorLocalSphereColl.Position - PreviousPositions[1])
	
	OverallMoveAmount += Differences.AllAxis[1]
	
	OverallMoveAmount = SafeLerp(OverallMoveAmount, Vector3.zero, _delta*8)
	
	-- Shift the last previous position back an index, then overwrite it with this frame's position, which will BE the previous next frame.
	PreviousPositions[2] = PreviousPositions[1]
	PreviousPositions[1] = LocalSphereColl.Position
end)

CharEntry.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
CharEntry.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
CharEntry.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
CharEntry.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

-- In Royale High, disable flight, which prevents performing Air Dashes.
local RHFlyFlag = LocalPlayer:FindFirstChild("FlyAllowed")
if RHFlyFlag then
	RHFlyFlag.Value = false
else	-- Some RH realms don't have this BoolValue object, but they'll always include the common flight script. If it's found, destroy it, which'll also disable flight.
	local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
	if PlayerScripts then
		local FlyScript = PlayerScripts:FindFirstChild("FlyScriptNew")
		if FlyScript then FlyScript:Destroy() end
	end
end

workspace.Gravity = 75