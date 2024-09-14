--[[
	ROYALE HIGH ACCESSORY PRESERVER, WRITTEN IN 2024	|
	LAST UPDATED ON SEPTEMBER 13TH, 2024				|
	____________________________________________________/
	PURPOSE
	Royale High has a lot of beautiful, well-designed clothes, but with more recent sets (~2024), it has
	become harder to properly save their items. This isn't just due to how most clothes have multiple
	toggles or feminine/masculine variants, but rather because of the newest addition, variations. Any
	item could have three or more "categories" that the player can cycle through, creating potentially
	endless combinations!
	
	This almost killed "RH model stealing", but sometimes tough situations create interesting challenges
	that motivate you to work around them, and well, that's exactly why I created this script! With it,
	you can easily "capture" multiple variations of an item, and/or use it to place multiple items worth
	of variations and toggles, then save all of them at once with two taps!
	
	HOW TO USE THIS SCRIPT?
	Run this script (preferrably using a LoadString) and a pink box will appear in the top right corner of
	the screen. It has three buttons:
	1. CLOSE -	Self-explanatory; Click this cute heart-shaped button to stop this script any time.
	2. CHECK -	Tries to find a single equipped accessory, skirt, or shoes on your character. If anything
				is found, its name will be shown, enabling the SAVE button.
	3. SAVE -	Another self-explanatory button. When enabled, tapping this copies the clothes Model to
				a folder in Lighting,named after the base item for organization!
	
	This script wasn't programmed in a robust manner, so it's very strict about what it expects to find!
	Please unequip ALL accessories, shoes, and skirts, then equip or try on a single item within one of
	those categories. Select a toggle and your variations, then tap the CHECK button. If you haven't
	saved this specific toggle/variation combination during this session, you can SAVE the item!
	
	This script doesn't need an item that includes multiple toggles to work; Even if you try on an old
	item that just displays the "exit try on mode" button, you can use the CHECK button to detect and
	save it, as long as the item includes an "AccessoryName" or "HeelName" StringValue, which most do.
	
	Once you've saved/copied everything that you want, tap the "EXPORT" button and confirm the action to
	start saving everything to two JSON files, which should complete within a couple seconds. Once this is
	done, you can safely start saving other items; Everything that was saved to JSON before isn't in the
	internal Lighting/Clothing Captures folder anymore (and won't be re-saved)!
]]--

-- SERVICES
local Players								= game:GetService("Players")
local Lighting								= game:GetService("Lighting")

-- Look for the "base" folder that this script will save everything into. (Sub-folders will be created for each item.)
local SaveBase : Folder?					= Lighting:FindFirstChild("Clothing Captures")
if not SaveBase then
	SaveBase								= Instance.new("Folder")
	SaveBase.Name							= "Clothing Captures"
	SaveBase.Parent							= Lighting
end
local SaveFolder : Folder?					= nil

-- REFERENCES - PLAYER
local LocalPlayer							= Players.LocalPlayer
local PlayerGui								= LocalPlayer.PlayerGui

-- CONSTANTS
local Color_ButtonEnabled					= Color3.new(0.4,0.875,1)
local Color_ButtonDisabled					= Color3.new(0.2,0.4425,0.5)
local BarPos_Active							= UDim2.fromScale(0.975,0.025)
local BarPos_Inactive						= UDim2.fromScale(0.975,-0.333)

-- Though it looks like both use the same toggle/variation seleciton GUI, clothes and furniture actually use separate copies of the same
-- GUI design; Everything inside both of the frames has the same layout, so this script will change between them depending on what it's
-- targetting.
local GUIBase_Clothing						= PlayerGui.PreviewToggles.PreviewTogglesFrame
local GUIBase_Furniture						= PlayerGui.DecorateModeGui.TogglesFrameNEW

local EquippedStorage						= workspace:FindFirstChild("EquippedStorage")
if not EquippedStorage then
	error("RH Accessory Preserver - You aren't currently playing Royale High, or are in a realm without an EquippedStorage folder.")
end

-- This script uses Xane's Recreator API! The boilerplate code below will load it from one of its locations online, trying each in order.
local RecreatorAPIMirrors = {
	'https://pastebin.com/raw/DL77J2LY',
	'https://raw.githubusercontent.com/Xane123/Roblox-Scripts/main/API_Recreation.luau'
}
-- Prepare our environment; If this executor supports it, use its getgenv() function, falling back on the detectable _G if it isn't available.
local env				= getgenv and getgenv() or _G

if env then
	if not env.XRecreator then
		for i,mirror in RecreatorAPIMirrors do
			-- Attempt to load Xane's Recreator API from Pastebin,
			local success, errormsg = pcall(function() loadstring(game:HttpGet(mirror))() end)
			if success then
				print("Loaded Recreator API from source", i, "of", #RecreatorAPIMirrors)
				break
			else
				warn("Recreator API couldn't load from " .. mirror .. ". It's either removed, or isn't available in your region.")
			end
		end
		
		if env.XRecreator and env.XRecreator.Save then
			print("Recreator API has been imported and setup successfully!")
		else
			game:GetService("Debris"):AddItem(script, 5)
			local VisibleError = Instance.new("Hint", game:GetService("CoreGui"))
			VisibleError.Text = "Error: Xane's Recreator API couldn't load/initialize! Please load a local copy of that script " ..
				"then execute this one again, or try again."
			game:GetService("Debris"):AddItem(VisibleError,7)
			error("The Recreator API couldn't load or initialize. This script depends on it, so execution cannot continue.")
		end
	else print("The recreator API is already set up! Its functions will be used by this script.")
	end
else
	game:GetService("Debris"):AddItem(script, 1)
	error("Couldn't find a destination for the recreation APIs! (Your executor is really bad if you see this!)")
end

-- XANE'S RECREATOR API TYPES
-- The format used by the API's internal Instance list. This is used by both the API and this GUI script.
type InternalListEntry		= {
	Instance			: Instance,	-- Instance which this entry represents. Its class and name are used when generating the visible list.
	Level				: number	-- Represents the depth this instance was placed at in the hierarchy during the scan. 0 is the container itself.
}

-- List item definition for the currently shown subset of the full list, generated as needed.
type VisibleListEntry		= {
	CheckboxClickEvent	: RBXScriptConnection,	-- Connection which lets the user (de)select this item. (This also updates its icon.)
	CameraFocusEvent	: RBXScriptConnection,	-- Click event for a button which makes the user's camera focus on this instance.
	CamRevertEvent1		: RBXScriptConnection,	-- Right-click event, which brings the camera back to the player.
	CamRevertEvent2		: RBXScriptConnection,	-- Alternative camera reverting event, for mobile devices (long tap).
	Instance			: Instance,				-- Reference to this instance, used to access its properties if needed.
	RowBase				: Frame,				-- A reference to this row's container Frame.
	Checkbox			: TextButton,			-- The toggle-box found at the left side of this row/entry.
	SelectBox			: SelectionBox,			-- This Instance's SelectionBox, which is created and destroyed as needed upon its selection.
	IsSelectAllRow		: boolean				-- If TRUE, selecting this row will deselect all instances within the selected container.
}

type ClassDefinition		= {
	ListView						: {		-- Properties that customize how this instance is displayed in the list (only used in the script).
		Icon						: string,
		CreateTest					: boolean,
		CanView						: string,
	},
	Props							: {string}		-- List of properties that should be saved or loaded to/from JSON for this instance.
}

-- Dictionary returned after successfully importing/loading serialized JSON data using Recreator.Load(). Each key is named after
-- and points to the Model that the function placed your imported Instances into, and will be nil if nothing was imported to a
-- location. If the third argument is true, all models will be put inside of another Model in CoreGui (hidden from LocalScripts).
type XRecreatorImportResult	= {
	Workspace			: Model?,
	Players				: Model?,
	Lighting			: Model?,
	ReplicatedStorage	: Model?,
	StarterGui			: Model?,
	SoundService		: Model?,
	StarterPack			: Model?
}

-- The contents of getgenv().XRecreator after the Recreation API initializes. These functions send commands to the API, making
-- it very easy to automate actions like selecting Instances, saving them to JSON files, and loading stuff FROM those files.
type ModelRecreatorStruct	= {
	-- FUNCTIONS
	Select		: (_mode:"set"|"add"|"remove", _list:{Instance}) -> (),	-- Updates the API's selection.
	MakeList	: (_baseInst : Instance) -> (nil),						-- Generates a series of list entries, for GUI's that display one.
	Save		: (_name:string,_rescan:boolean) -> (boolean),			-- Saves selection to files. Will fail on invalid filenames.
	CustomizeProgressBox:(_message : string, _total : number) -> (),	-- Affects the text shown in "saving"/"indexing" GUI (may be unusable).
	ActivateAPI	: (_use : boolean) -> boolean,							-- Requests to use API functions. If in use, this returns FALSE.
	SetStatusGui: (_gui:TextLabel) -> (nil),							-- Changes GUI that save status is shown in. Set to nil to use default.
	OnSaveDone	: (_success : boolean) -> (),							-- External code ran upon finishing. Used for other scripts' cleanup.
	IsInstanceAllowed : (_instance : Instance) -> (boolean),			-- Checks if an Instance's type is safe to save. (Model Recreator v3)
	Load		: (_header:string,_pieces:{string},_dest:Instance?) -> (XRecreatorImportResult?),	-- Import previously saved JSON instances.
	LoadFile	: (_saveName:string,_dest:Instance?) -> (XRecreatorImportResult?),	-- Loads from a JSON capture set, passing to Load().

	-- VARIABLES
	Reserved	: boolean,												-- Set to TRUE after a script calls ActivateAPI().
	IgnoreAttrib: string,												-- Instances with this attribute won't be scanned.
	Selection	: {Instance},											-- List of instances marked to be saved.
	FullList	: {InternalListEntry},									-- List generated by MakeList(), which can be used by scripts' GUIs.
	StatusGui	: TextLabel,											-- Reference to current label that save/index statuses are shown in.
	PageLength	: number,												-- How many instances SHOULD be shown on list pages. (Not used by API.)
	AntiLagInterval : number,											-- How many instances to parse before waiting, to reduce lag.
	ClassData	: {ClassDefinition}									-- This script's "Roblox class API" (read-only).
}
local Recreator : ModelRecreatorStruct = env.XRecreator	-- Let's simplify references to the API by just defining a new "shortcut" variable.
if not Recreator.ActivateAPI(true) then	-- Attempt to claim the API; If it's in use, the script will stop here.
	warn("Another script is using Xane's recreator API! Please close that script or rejoin (if it doesn't have a 'close' button).")
	script:Destroy()		
	return false
end

--[[
	Figure out if we're in the Campus 3 dorms, based on the current place ID. When in the dorms, this script scans the workspace for
	this player's dorm, and if it exists, it will target/save the most recent furniture item added to their dorm instead of their
	own clothes.
]]--
local IsDorms							= if game.PlaceId == 1067660288 then true else false

-- CONNECTIONS & VARIABLES
--[[
	This script is designed in a mostly event-driven fashion, relying on Roblox's ChildAdded/ChildRemoved events to
	determine when the player (un)equips an item (which adds/removes a Model from their EquippedStorage sub-folder)
	and re-evaluate what its target is. When the close button is tapped, everything is cleaned up, which is easy
	because of these variables.
	
	For the record, there isn't a text field or button for choosing which category to save from. When this script
	initializes or the player (un)equips an accessory, a skirt, or shoes ("heels" internally), it checks all three
	folders in order:
	
	1.	If the player is wearing any accessories, that category is always chosen. In the event they're wearing more
		than one, saving will be disabled; Only equip the item you want to save forms of!
	2.	If no accessories are equipped, it checks for a skirt (which is placed in its own folder for some reason).
	3.	When neither of the previous conditions are met, it checks for a dummy Model in their Heels folder. When
		these are saved, the full character model is cloned, as shoes REPLACE leg parts for some reason.
]]--
local Conn_SaveBtn : RBXScriptConnection	= nil	-- Attempts to save the current accessory, skirt, or shoes (character model), in order.
local Conn_CheckBtn : RBXScriptConnection	= nil	-- Manually scans the player's sub-folders for a single accessory to target.
local Conn_ExportBtn : RBXScriptConnection	= nil	-- Shows the "export wizard" confirmation dialog, which converts clothes to JSON data.
local Conn_RHClose1 : RBXScriptConnection	= nil	-- Closes the confirmation dialog.
local Conn_RHClose2 : RBXScriptConnection	= nil	-- Same as Conn_RHClose1
local Conn_RHYesBtn : RBXScriptConnection	= nil	-- Saves everything in the CLothing Captures folder to JSON files.
local Conn_CloseBtn : RBXScriptConnection	= nil	-- Disconnects all event connections, destroys the GUI, and hopefully ends this script.
local Conn_SidebarVis : RBXScriptConnection	= nil	-- Toggle GUI visibility toggle detection event.
local Conn_CharAdded : RBXScriptConnection	= nil	-- This player's CharacterAdded event. This ends the script, as it breaks GUI references.
local Conn_CharRemove : RBXScriptConnection	= nil	-- This player's CharacterRemoving event, which also causes a self-destruct.

local Conn_DormCheck : RBXScriptConnection	= nil	-- Workspace.ChildAdded check, used to detect when the player's dorm appears.
local Conn_FurniAdd : RBXScriptConnection	= nil	-- ChildAdded event for DormFurniture model, which updates the "furniture" pointer.
local Conn_FurniRem : RBXScriptConnection	= nil	-- ChildRemoved event for that model. Clears the pointer/reference if it's set.

local Permissions							= {
	CanSave = false,								-- If TRUE, allows cloning the player's current targetted clothing when clicking 💾Save.
	CanCheck = true,								-- When set, the user can look for their targeted accessory.
	CanClose = true,								-- Disables the close button if this is false. Doesn't prevent emergency shutdowns.
	CanExport = false								-- When TRUE, the player can save everything to JSON files by tapping the EXPORT button.
}
local Target : Model?						= nil	-- When set, this is the Model that will be cloned and named based on the preview GUI.
local SaveName : string						= ""	-- Generated name for the current accessory's toggle and variations. (It's pretty long!)

type VariationEntry							= {
	CategoryName : string,
	VarName : string,
	VarNumber : number
}

-- Array of dictionary entries about each "category"'s name, and the current variation's name and number.
local VariationInfo : {VariationEntry}		= {}
local ToggleNum : number					= 0		-- Items' current toggle number, used if the toggle selection GUI is visible.
-- ItemName isn't a global variable since its value is redundant with SaveName in most situations.

local FullFolder1 : Folder?					= EquippedStorage:FindFirstChild("Accessories")
local FullFolder2 : Folder?					= EquippedStorage:FindFirstChild("Skirts")
local FullFolder3 : Folder?					= EquippedStorage:FindFirstChild("Heels")

if not FullFolder1 or not FullFolder2 or not FullFolder3 then
	error("RH Accessory Preserver - The standard Accessories, Skirts, and Heels folders can't be located, so execution can't continue.")
end

local AccessoryFolder : Folder?				= FullFolder1:FindFirstChild(LocalPlayer.Name)
local SkirtFolder : Folder?					= FullFolder2:FindFirstChild(LocalPlayer.Name)
local HeelFolder : Folder?					= FullFolder3:FindFirstChild(LocalPlayer.Name)

local DormPart : Part?						= nil	-- Reference to the outer Part that has a matching user ID.
local FurniContainer : Model?				= nil	-- DormFurniture model within the player's dorm.
local LatestFurniture : Model?				= nil	-- The most recent Model that appeared inside DormFurniture.

-- REFERENCES - RH's PREVIEW GUI
--[[
	This script grabs most of its info from the sidebar that's shown when the player equips an item with multiple
	"toggles" (forms) and/or variations (alternative designs or appearances for parts of this toggle). Whenever
	the player tries to save a specific version (toggle and variation combination), a name is dynamically made
	using the item's name, current toggle number, and all variations' numbers and titles.
	
	This name doubles as an idenfifier; If this exact version has already been saved to Lighting, nothing
	will happen.
]]--
local GUI_Base								= GUIBase_Clothing	-- This changes between the clothing/furniture customization Frames as needed.

-- SCRIPT GUI
-- Although this script is relatively simple, it uses a GUI to show its current status and make it easy to save and stop the script.
--[[
	Roblox2Lua
	----------
	
	This code was generated using
	Deluct's Roblox2Lua plugin.
]]--
local xcapture_gui = Instance.new("ScreenGui")
xcapture_gui.DisplayOrder = 100
xcapture_gui.IgnoreGuiInset = false
xcapture_gui.ResetOnSpawn = true
xcapture_gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
xcapture_gui.Name = "XCaptureGUI"
xcapture_gui.Parent = game:GetService("CoreGui")

local message = Instance.new("TextLabel")
message.Font = Enum.Font.RobotoCondensed
message.Text = "Hello, exploiter! This script is still initializing, so...just sit tight, alright?"
message.TextColor3 = Color3.new(1, 1, 1)
message.TextScaled = true
message.TextStrokeColor3 = Color3.new(0.921569, 0.345098, 0.823529)
message.TextStrokeTransparency = 0
message.TextTruncate = Enum.TextTruncate.AtEnd
message.TextWrapped = true
message.AnchorPoint = Vector2.new(1, 0)
message.BackgroundColor3 = Color3.new(0.972549, 0.843137, 1)
message.BorderSizePixel = 0
message.Position = UDim2.new(0.975, 0, 0.025, 0)
message.Size = UDim2.new(0.475, 0, 0.125, 0)
message.Visible = true
message.Name = "Message"
message.Parent = xcapture_gui

local trash = Instance.new("UICorner")
trash.CornerRadius = UDim.new(0.25, 0)
trash.Parent = message

local save_button = Instance.new("TextButton")
save_button.Font = Enum.Font.DenkOne
save_button.Text = "💾"
save_button.TextColor3 = Color3.new(0, 0, 0)
save_button.TextSize = 32
save_button.TextWrapped = true
save_button.AnchorPoint = Vector2.new(1, 0)
save_button.BackgroundColor3 = Color3.new(0.509804, 0.878431, 1)
save_button.BorderSizePixel = 0
save_button.Position = UDim2.new(1, 0, 1, 0)
save_button.Size = UDim2.new(1, 0, 1, 0)
save_button.SizeConstraint = Enum.SizeConstraint.RelativeYY
save_button.Visible = true
save_button.Name = "SaveButton"
save_button.Parent = message

trash = Instance.new("UICorner")
trash.CornerRadius = UDim.new(1, 0)
trash.Parent = save_button

local check_button = Instance.new("TextButton")
check_button.Font = Enum.Font.Highway
check_button.Text = "Check"
check_button.TextColor3 = Color3.new(1, 1, 1)
check_button.TextScaled = true
check_button.TextSize = 32
check_button.TextStrokeColor3 = Color3.new(0.215686, 0.54902, 0.784314)
check_button.TextStrokeTransparency = 0
check_button.TextWrapped = true
check_button.AnchorPoint = Vector2.new(1, 0.5)
check_button.BackgroundColor3 = Color3.new(0.509804, 0.878431, 1)
check_button.BorderSizePixel = 0
check_button.Position = UDim2.new(0, 0, 0.5, 0)
check_button.Size = UDim2.new(1, 0, 1, 0)
check_button.SizeConstraint = Enum.SizeConstraint.RelativeYY
check_button.Visible = true
check_button.Name = "CheckButton"
check_button.Parent = save_button

trash = Instance.new("UICorner")
trash.CornerRadius = UDim.new(1, 0)
trash.Parent = check_button

local export_button = Instance.new("TextButton")
export_button.Font = Enum.Font.Highway
export_button.Text = "Export"
export_button.TextColor3 = Color3.new(1, 1, 1)
export_button.TextScaled = true
export_button.TextSize = 32
export_button.TextStrokeColor3 = Color3.new(0.215686, 0.54902, 0.784314)
export_button.TextStrokeTransparency = 0
export_button.TextWrapped = true
export_button.AnchorPoint = Vector2.new(1, 0.5)
export_button.BackgroundColor3 = Color3.new(0.509804, 0.878431, 1)
export_button.BorderSizePixel = 0
export_button.Position = UDim2.new(0, 0, 0.5, 0)
export_button.Size = UDim2.new(1, 0, 1, 0)
export_button.SizeConstraint = Enum.SizeConstraint.RelativeYY
export_button.Visible = true
export_button.Name = "ExportButton"
export_button.Parent = check_button

trash = Instance.new("UICorner")
trash.CornerRadius = UDim.new(1, 0)
trash.Parent = export_button

local close_button = Instance.new("ImageButton")
close_button.Image = "rbxassetid://11739785350"
close_button.ScaleType = Enum.ScaleType.Fit
close_button.AnchorPoint = Vector2.new(0.75, 0.25)
close_button.BackgroundColor3 = Color3.new(1, 1, 1)
close_button.BackgroundTransparency = 1
close_button.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
close_button.Position = UDim2.new(0, 0, 0.75, 0)
close_button.Rotation = -90
close_button.Size = UDim2.new(0.675000012, 0, 0.675000012, 0)
close_button.SizeConstraint = Enum.SizeConstraint.RelativeYY
close_button.Visible = true
close_button.ZIndex = 100
close_button.Name = "CloseButton"
close_button.Parent = message

-- RH CAMPUS 3 CONFIRMATION DIALOG (BASED ON DRESS UP CHAT COMMAND WINDOW)

local RHGUI_DialogBox = Instance.new("Frame")
RHGUI_DialogBox.BackgroundColor3 = Color3.new(1, 1, 1)
RHGUI_DialogBox.BackgroundTransparency = 1
RHGUI_DialogBox.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
RHGUI_DialogBox.Size = UDim2.new(1, 0, 1, 0)
RHGUI_DialogBox.Visible = false	-- This dialog appears after the user taps the "export" button in the main GUI.
RHGUI_DialogBox.ZIndex = 6
RHGUI_DialogBox.Parent = xcapture_gui

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.SourceSans
trash.Text = ""
trash.TextColor3 = Color3.new(0, 0, 0)
trash.TextSize = 14
trash.BackgroundColor3 = Color3.new(1, 1, 1)
trash.BackgroundTransparency = 0.5
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Position = UDim2.new(0.33594662, 0, 0.164119288, 0)
trash.Size = UDim2.new(0.357214063, 0, 0.303101391, 0)
trash.Visible = true
trash.Name = "realbg"
trash.Parent = RHGUI_DialogBox

local RHGUI_UICorner = Instance.new("UICorner")
RHGUI_UICorner.CornerRadius = UDim.new(0, 30)
RHGUI_UICorner.Parent = trash

local RHGUI_UIStroke = Instance.new("UIStroke")
RHGUI_UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
RHGUI_UIStroke.Color = Color3.new(1, 1, 1)
RHGUI_UIStroke.Thickness = 6.726562023162842
RHGUI_UIStroke.Parent = trash

local RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.662745, 0.764706)), ColorSequenceKeypoint.new(0.08650519698858261, Color3.new(1, 0.768627, 0.858824)), ColorSequenceKeypoint.new(0.17820100486278534, Color3.new(1, 0.690196, 0.945098)), ColorSequenceKeypoint.new(0.269896000623703, Color3.new(1, 0.870588, 0.996078)), ColorSequenceKeypoint.new(0.37024199962615967, Color3.new(0.784314, 0.752941, 1)), ColorSequenceKeypoint.new(0.46539801359176636, Color3.new(0.862745, 0.792157, 1)), ColorSequenceKeypoint.new(0.5519030094146729, Color3.new(0.615686, 0.835294, 1)), ColorSequenceKeypoint.new(0.6349480152130127, Color3.new(0.772549, 0.890196, 1)), ColorSequenceKeypoint.new(0.7128030061721802, Color3.new(0.545098, 1, 0.92549)), ColorSequenceKeypoint.new(0.797577977180481, Color3.new(0.686275, 0.917647, 1)), ColorSequenceKeypoint.new(0.899653971195221, Color3.new(0.933333, 1, 0.705882)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.901961, 0.745098))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = RHGUI_UIStroke

local realbg_2 = Instance.new("TextLabel")
realbg_2.Font = Enum.Font.SourceSans
realbg_2.Text = ""
realbg_2.TextColor3 = Color3.new(0, 0, 0)
realbg_2.TextSize = 14
realbg_2.BackgroundColor3 = Color3.new(1, 1, 1)
realbg_2.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
realbg_2.Position = UDim2.new(0.332748592, 0, 0.161711112, 0)
realbg_2.Size = UDim2.new(0.363373876, 0, 0.308700293, 0)
realbg_2.Visible = true
realbg_2.ZIndex = 0
realbg_2.Name = "realbg"
realbg_2.Parent = RHGUI_DialogBox

RHGUI_UICorner = Instance.new("UICorner")
RHGUI_UICorner.CornerRadius = UDim.new(0, 30)
RHGUI_UICorner.Parent = realbg_2

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.662745, 0.764706)), ColorSequenceKeypoint.new(0.08650519698858261, Color3.new(1, 0.768627, 0.858824)), ColorSequenceKeypoint.new(0.17820100486278534, Color3.new(1, 0.690196, 0.945098)), ColorSequenceKeypoint.new(0.269896000623703, Color3.new(1, 0.870588, 0.996078)), ColorSequenceKeypoint.new(0.37024199962615967, Color3.new(0.784314, 0.752941, 1)), ColorSequenceKeypoint.new(0.46539801359176636, Color3.new(0.862745, 0.792157, 1)), ColorSequenceKeypoint.new(0.5519030094146729, Color3.new(0.615686, 0.835294, 1)), ColorSequenceKeypoint.new(0.6349480152130127, Color3.new(0.772549, 0.890196, 1)), ColorSequenceKeypoint.new(0.7128030061721802, Color3.new(0.545098, 1, 0.92549)), ColorSequenceKeypoint.new(0.797577977180481, Color3.new(0.686275, 0.917647, 1)), ColorSequenceKeypoint.new(0.899653971195221, Color3.new(0.933333, 1, 0.705882)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.901961, 0.745098))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = realbg_2

local RHGUI_CloseButton = Instance.new("ImageButton")
RHGUI_CloseButton.Image = "http://www.roblox.com/asset/?id=11739785350"
RHGUI_CloseButton.ScaleType = Enum.ScaleType.Fit
RHGUI_CloseButton.BackgroundColor3 = Color3.new(1, 1, 1)
RHGUI_CloseButton.BackgroundTransparency = 1
RHGUI_CloseButton.Position = UDim2.new(0.653472364, 0, 0.0741094872, 0)
RHGUI_CloseButton.Size = UDim2.new(0.0752811283, 0, 0.150844231, 0)
RHGUI_CloseButton.Visible = true
RHGUI_CloseButton.ZIndex = 2
RHGUI_CloseButton.Name = "Close"
RHGUI_CloseButton.Parent = RHGUI_DialogBox

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.DenkOne
trash.Text = "Do you want to save all of the clothes you've copied to JSON files?"
trash.TextColor3 = Color3.new(1, 1, 1)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(1, 1, 1)
trash.BackgroundTransparency = 1
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Position = UDim2.new(0.338040471, 0, 0.251509786, 0)
trash.Size = UDim2.new(0.35302639, 0, 0.139977559, 0)
trash.Visible = true
trash.Name = "Question"
trash.Parent = RHGUI_DialogBox

local trash2 = Instance.new("UIStroke")
trash2.Color = Color3.new(0.968628, 0.764706, 0.92549)
trash2.Thickness = 0.8968749642372131
trash2.Parent = trash

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.698039, 0.858824)), ColorSequenceKeypoint.new(0.4757789969444275, Color3.new(0.737255, 0.8, 1)), ColorSequenceKeypoint.new(1, Color3.new(0.776471, 0.87451, 1))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = trash2

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.DenkOne
trash.Text = "Royale High Export Wizard"
trash.TextColor3 = Color3.new(1, 1, 1)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(1, 1, 1)
trash.BackgroundTransparency = 1
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Position = UDim2.new(0.364769131, 0, 0.166903496, 0)
trash.Size = UDim2.new(0.297829062, 0, 0.0748210698, 0)
trash.Visible = true
trash.ZIndex = 4
trash.Parent = RHGUI_DialogBox

RHGUI_UIStroke = Instance.new("UIStroke")
RHGUI_UIStroke.Color = Color3.new(0.827451, 0.713726, 0.827451)
RHGUI_UIStroke.Thickness = 2.242187261581421
RHGUI_UIStroke.Parent = trash

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.698039, 0.858824)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(0.776471, 0.87451, 1))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = RHGUI_UIStroke

trash2 = Instance.new("UIAspectRatioConstraint")
trash2.AspectRatio = 7.5869879722595215
trash2.Parent = trash

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.DenkOne
trash.Text = "Royale High Export Wizard"
trash.TextColor3 = Color3.new(1, 1, 1)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(1, 1, 1)
trash.BackgroundTransparency = 1
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Position = UDim2.new(0.365729809, 0, 0.163955122, 0)
trash.Size = UDim2.new(0.297527522, 0, 0.0747453496, 0)
trash.Visible = true
trash.ZIndex = 5
trash.Parent = RHGUI_DialogBox

RHGUI_UIStroke = Instance.new("UIStroke")
RHGUI_UIStroke.Color = Color3.new(0.968628, 0.835294, 0.964706)
RHGUI_UIStroke.Thickness = 2.242187261581421
RHGUI_UIStroke.Parent = trash

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.698039, 0.858824)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(0.776471, 0.87451, 1))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = RHGUI_UIStroke

trash2 = Instance.new("UIAspectRatioConstraint")
trash2.AspectRatio = 7.5869879722595215
trash2.Parent = trash

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.AmaticSC
trash.Text = ""
trash.TextColor3 = Color3.new(1, 1, 1)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(0.572549, 0.733333, 0.905882)
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Position = UDim2.new(0.461651295, 0, 0.437609375, 0)
trash.Size = UDim2.new(0.109941334, 0, 0.0904901996, 0)
trash.Visible = false
trash.Name = "loaddropshadow"
trash.Parent = RHGUI_DialogBox

RHGUI_UICorner = Instance.new("UICorner")
RHGUI_UICorner.CornerRadius = UDim.new(0, 30)
RHGUI_UICorner.Parent = trash

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.AmaticSC
trash.Text = ""
trash.TextColor3 = Color3.new(1, 1, 1)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(0.607843, 0.854902, 0.639216)
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Position = UDim2.new(0.346433431, 0, 0.436794281, 0)
trash.Size = UDim2.new(0.156052262, 0, 0.0904901996, 0)
trash.Visible = true
trash.Name = "loaddropshadow"
trash.Parent = RHGUI_DialogBox

RHGUI_UICorner = Instance.new("UICorner")
RHGUI_UICorner.CornerRadius = UDim.new(0, 30)
RHGUI_UICorner.Parent = trash

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.AmaticSC
trash.Text = ""
trash.TextColor3 = Color3.new(1, 1, 1)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(0.968627, 0.643137, 0.772549)
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Position = UDim2.new(0.524774492, 0, 0.436336517, 0)
trash.Size = UDim2.new(0.155064568, 0, 0.0904901996, 0)
trash.Visible = true
trash.Name = "loaddropshadow"
trash.Parent = RHGUI_DialogBox

RHGUI_UICorner = Instance.new("UICorner")
RHGUI_UICorner.CornerRadius = UDim.new(0, 30)
RHGUI_UICorner.Parent = trash

local RHGUI_NoButton = Instance.new("TextButton")
RHGUI_NoButton.Font = Enum.Font.PatrickHand
RHGUI_NoButton.Text = ""
RHGUI_NoButton.TextColor3 = Color3.new(1, 1, 1)
RHGUI_NoButton.TextScaled = true
RHGUI_NoButton.TextSize = 14
RHGUI_NoButton.TextWrapped = true
RHGUI_NoButton.BackgroundColor3 = Color3.new(1, 0.921569, 0.960784)
RHGUI_NoButton.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
RHGUI_NoButton.Position = UDim2.new(0.526900828, 0, 0.400722116, 0)
RHGUI_NoButton.Size = UDim2.new(0.149213374, 0, 0.111390956, 0)
RHGUI_NoButton.Visible = true
RHGUI_NoButton.ZIndex = 2
RHGUI_NoButton.Name = "No"
RHGUI_NoButton.Parent = RHGUI_DialogBox

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.AmaticSC
trash.Text = "No"
trash.TextColor3 = Color3.new(1, 1, 1)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(1, 1, 1)
trash.BackgroundTransparency = 1
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Size = UDim2.new(1, 0, 1, 0)
trash.Visible = true
trash.ZIndex = 3
trash.Parent = RHGUI_NoButton

RHGUI_UIStroke = Instance.new("UIStroke")
RHGUI_UIStroke.Color = Color3.new(0.968627, 0.835294, 0.964706)
RHGUI_UIStroke.Thickness = 2.242187261581421
RHGUI_UIStroke.Parent = trash

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.921569, 0.960784)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.921569, 0.960784))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = RHGUI_UIStroke

RHGUI_UIStroke = Instance.new("UIStroke")
RHGUI_UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
RHGUI_UIStroke.Color = Color3.new(0.968628, 0.843137, 0.956863)
RHGUI_UIStroke.Thickness = 2.242187261581421
RHGUI_UIStroke.Parent = RHGUI_NoButton

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.921569, 0.960784)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.921569, 0.960784))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = RHGUI_UIStroke

RHGUI_UICorner = Instance.new("UICorner")
RHGUI_UICorner.CornerRadius = UDim.new(0, 30)
RHGUI_UICorner.Parent = RHGUI_NoButton

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.AmaticSC
trash.Text = "No"
trash.TextColor3 = Color3.new(0.968627, 0.643137, 0.772549)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(1, 1, 1)
trash.BackgroundTransparency = 1
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Position = UDim2.new(0.00999999978, 0, 0.0500000007, 0)
trash.Size = UDim2.new(1, 0, 1, 0)
trash.Visible = true
trash.ZIndex = 2
trash.Parent = RHGUI_NoButton

RHGUI_UIStroke = Instance.new("UIStroke")
RHGUI_UIStroke.Color = Color3.new(0.968627, 0.643137, 0.772549)
RHGUI_UIStroke.Thickness = 2.242187261581421
RHGUI_UIStroke.Parent = trash

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.843137, 0.964706, 1)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(0.843137, 0.964706, 1))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = RHGUI_UIStroke

local RHGUI_YesButton = Instance.new("TextButton")
RHGUI_YesButton.Font = Enum.Font.PatrickHand
RHGUI_YesButton.Text = ""
RHGUI_YesButton.TextColor3 = Color3.new(1, 1, 1)
RHGUI_YesButton.TextScaled = true
RHGUI_YesButton.TextSize = 14
RHGUI_YesButton.TextWrapped = true
RHGUI_YesButton.BackgroundColor3 = Color3.new(0.796078, 1, 0.843137)
RHGUI_YesButton.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
RHGUI_YesButton.Position = UDim2.new(0.350170195, 0, 0.400259346, 0)
RHGUI_YesButton.Size = UDim2.new(0.149213344, 0, 0.111390948, 0)
RHGUI_YesButton.Visible = true
RHGUI_YesButton.ZIndex = 2
RHGUI_YesButton.Name = "Yes"
RHGUI_YesButton.Parent = RHGUI_DialogBox

RHGUI_UICorner = Instance.new("UICorner")
RHGUI_UICorner.CornerRadius = UDim.new(0, 30)
RHGUI_UICorner.Parent = RHGUI_YesButton

RHGUI_UIStroke = Instance.new("UIStroke")
RHGUI_UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
RHGUI_UIStroke.Color = Color3.new(0.811765, 0.968628, 0.788235)
RHGUI_UIStroke.Thickness = 2.242187261581421
RHGUI_UIStroke.Parent = RHGUI_YesButton

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.796079, 1, 0.843137)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(0.796079, 1, 0.843137))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = RHGUI_UIStroke

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.AmaticSC
trash.Text = "Yes"
trash.TextColor3 = Color3.new(1, 1, 1)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(1, 1, 1)
trash.BackgroundTransparency = 1
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Size = UDim2.new(1, 0, 1, 0)
trash.Visible = true
trash.ZIndex = 3
trash.Parent = RHGUI_YesButton

RHGUI_UIStroke = Instance.new("UIStroke")
RHGUI_UIStroke.Color = Color3.new(0.662745, 0.933333, 0.701961)
RHGUI_UIStroke.Thickness = 2.242187261581421
RHGUI_UIStroke.Parent = trash

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.796079, 1, 0.843137)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(0.796079, 1, 0.843137))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = RHGUI_UIStroke

trash = Instance.new("TextLabel")
trash.Font = Enum.Font.AmaticSC
trash.Text = "Yes"
trash.TextColor3 = Color3.new(0.607843, 0.854902, 0.639216)
trash.TextScaled = true
trash.TextSize = 14
trash.TextWrapped = true
trash.BackgroundColor3 = Color3.new(1, 1, 1)
trash.BackgroundTransparency = 1
trash.BorderColor3 = Color3.new(0.105882, 0.164706, 0.207843)
trash.Position = UDim2.new(0.00999999978, 0, 0.0500000007, 0)
trash.Size = UDim2.new(1, 0, 1, 0)
trash.Visible = true
trash.ZIndex = 2
trash.Parent = RHGUI_YesButton

RHGUI_UIStroke = Instance.new("UIStroke")
RHGUI_UIStroke.Color = Color3.new(0.607843, 0.854902, 0.639216)
RHGUI_UIStroke.Thickness = 2.242187261581421
RHGUI_UIStroke.Parent = trash

RHGUI_UIGradient = Instance.new("UIGradient")
RHGUI_UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.796079, 1, 0.843137)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(0.796079, 1, 0.843137))})
RHGUI_UIGradient.Rotation = 90
RHGUI_UIGradient.Parent = RHGUI_UIStroke

-- Invalidate someof the temporary GUI variables, which won't be referencesd any more in this script.
trash = nil
trash2 = nil
RHGUI_UICorner = nil
RHGUI_UIStroke = nil
RHGUI_UIGradient = nil

-- FUNCTIONS
local function DisconnectEvent(_event : RBXScriptConnection)
	if _event then
		_event:Disconnect()
		_event = nil
	end
	
	return nil
end

-- Updates the specified "permission" and changes the color of its associated button.
local ButtonInfo = {
	["save"]		= {
		OnColor		= Color_ButtonEnabled,
		OffColor	= Color_ButtonDisabled,
		Instance	= save_button,
		Variable	= "CanSave"
	},
	["check"]		= {
		OnColor		= Color_ButtonEnabled,
		OffColor	= Color_ButtonDisabled,
		Instance	= check_button,
		Variable	= "CanCheck"
	},
	["close"]		= {
		Instance	= close_button,
		Variable	= "CanClose"
	},
	["export"]		= {
		OnColor		= Color_ButtonEnabled,
		OffColor	= Color_ButtonDisabled,
		Instance	= export_button,
		Variable	= "CanExport"
	}
}
local function UpdateButton(_buttonName : "save"|"check"|"close"|"export", _enabled : boolean)
	if _buttonName == "save" or _buttonName == "check" or _buttonName == "close" then
		Permissions[ButtonInfo[_buttonName].Variable] = _enabled
		
		-- If this is a basic text-based button, its background changes colors based on if it's enabled or not.
		if ButtonInfo[_buttonName].OnColor then
			if _enabled then ButtonInfo[_buttonName].Instance.BackgroundColor3 = ButtonInfo[_buttonName].OnColor
			else ButtonInfo[_buttonName].Instance.BackgroundColor3 = ButtonInfo[_buttonName].OffColor
			end
		else ButtonInfo[_buttonName].Instance.Visible = _enabled
		end
	end
	
	return nil
end

-- Disconnects all event connections, slides the main GUI off-screen, then destroys this script and the ScreenGui.
local function Shutdown(_playAnim : boolean)
	DisconnectEvent(Conn_CharAdded)
	DisconnectEvent(Conn_CharRemove)
	DisconnectEvent(Conn_SaveBtn)
	DisconnectEvent(Conn_CheckBtn)
	DisconnectEvent(Conn_ExportBtn)
	DisconnectEvent(Conn_RHClose1)
	DisconnectEvent(Conn_RHClose2)
	DisconnectEvent(Conn_RHYesBtn)
	DisconnectEvent(Conn_CloseBtn)
	DisconnectEvent(Conn_SidebarVis)
	
	DisconnectEvent(Conn_DormCheck)
	DisconnectEvent(Conn_FurniAdd)
	DisconnectEvent(Conn_FurniRem)
	
	if _playAnim then
		message:TweenPosition(
			BarPos_Inactive,
			Enum.EasingDirection.InOut,
			Enum.EasingStyle.Back,
			0.75,
			true
		)
		task.wait(0.75)
	end
	xcapture_gui:Destroy()
	
	warn("RH Accessory Preserver has shut down. Please execute the script again if you would like to continue saving things!")
	print('Any clothes you\'ve copied but haven\'t exported are still in game.Lighting["Clothing Captures"]!')
	Recreator.ActivateAPI(false)	-- Unclaim the API, so other scripts can safely use it.
	script:Destroy()
end

-- If the player's character respawns, all GUI references break, which would glitch this script out. Let's avoid that by immediately closing.
Conn_CharAdded	= LocalPlayer.CharacterAdded:Connect(function() Shutdown(false) end)
Conn_CharRemove	= LocalPlayer.CharacterRemoving:Connect(function() Shutdown(false) end)

-- Clicking the close button destroys the GUI, but plays the animation. This only works when it isn't cloning a Model, though.
Conn_CloseBtn	= close_button.MouseButton1Click:Connect(function() if Permissions.CanClose then Shutdown(true); end; end)

-- GetTargetInFolder (takes Folder reference, returns a specifically-formatted dictionary)
-- Sees if the provided Folder contains a single item, returning it as a "target". If there are no or 2+ items
-- inside of it, only the total will be returned.
local function GetTargetInFolder(_directory : Folder)
	local details : {
		Target : Model?,
		Count : number
	} = {
		Target = nil,
		Count = 0
	}
	
	if _directory then
		details.Count = #_directory:GetChildren()
		if details.Count == 1 then	-- If there's just one Model in the Folder, return it as a possible target!
			details.Target = _directory:GetChildren()[1]
		end
	end
	
	return details
end

-- For some reason, the preview GUI uses the Starlight Skirt's name as placeholder text. Annoyingly, this script believes it's
-- legitimately the item the player's wearing and creates a folder for it using the function below. Since this skirt is a real
-- item, I can't just ignore this specific name, in case the player wants to save it.

-- It may be hackish, but this script won't create a folder for this specific sentence, which helpfully tells the player what
-- they have to do to continue. This will only be noticeable if the player's trying on or wearing this specific skirt, though.
local SaveDisabledName = "Please close then re-open this GUI."
if GUI_Base.ItemName.Text == "Starlight Skirt" then
	GUI_Base.ItemName.Text = SaveDisabledName
end
-- SetSaveFolder (takes optional string, returns nil)
-- A short function that checks for a folder with a specified name, creating it if it doesn't exist.
-- Regardless, the global SaveFolder variable is updated to point to it.
local function SetSaveFolder(_itemName : string?)
	if _itemName and _itemName ~= SaveDisabledName then
		SaveFolder = SaveBase:FindFirstChild(_itemName)
		if not SaveFolder then	-- If the sub-folder doesn't exist, create a new one.
			SaveFolder								= Instance.new("Folder")
			SaveFolder.Name							= _itemName
			SaveFolder.Parent						= SaveBase
		end
	else	-- If a nil value is provided, just invalidate the variable.
		SaveFolder									= nil
	end
	
return nil
end

--[[
	Request1ModelValidation (takes nothing, returns nothing)
	An update function, which scans this player's Accessories, Skirts, and Heels sub-folders (in that order)
	for a single item to later "save" (clone to its sub-folder in Lighting). When scanning a folder, this
	function only advances if it's empty, so it's recommended to not wear any accessories or skirts in general
	to ensure that it picks the correct category when the player's in Try On mode, which equips the clothes
	like normal internally.
	
	If a folder just contains one instance, it's picked as the target, and the preview GUI is scanned for info
	like the item's name, current toggle, and any variations' names and numbers. This forms the final name
	that the cloned Model will use, and will prevent the player from accidentally saving something they already
	have in its folder.
]]--
local UpdateQueued = false
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local LeftUpperLeg = LocalPlayer.Character:FindFirstChild("LeftUpperLeg")
local function Request1ModelValidation()
	UpdateButton("save", false)	-- Disable the save button, but don't disable the checking button, as you can't scan while already doing it.
	Target = nil		-- Invalidate the current target.
	SaveFolder = nil	-- Similarly, disassociate with the previous save destination.
	Character = LocalPlayer.Character
	LeftUpperLeg = LocalPlayer.Character:FindFirstChild("LeftUpperLeg")	-- Also update the leg part reference, for detecting "modern" RH heels.
	
	if not UpdateQueued then
		ToggleNum = 0	-- Clear the toggle and variation info, which'll be updated later in this function if it's applicable.
		table.clear(VariationInfo)
		
		message.Text = "Checking for a compatible target..."
		UpdateQueued = true
		
		if not LatestFurniture then
			local temp_folderList = {AccessoryFolder,SkirtFolder,HeelFolder}
			for num,category in temp_folderList do
				local temp_result = GetTargetInFolder(category)
				if temp_result.Count > 0 then	-- Even if the folder contains multiple items, this function won't bother checking other folders
					if temp_result.Count == 1 and temp_result.Target then
						Target = temp_result.Target
						message.Text = "Found " .. Target.Name .. "! Trying to get a more specific name for it..."
						
						-- Although a "shoes" Model is placed in the Heels sub-folder, it only contains a value with its name! The actual
						-- 3D model is within the player's character model, so it has to be saved.
						
						-- Well, the info above applies to most "modern" shoes, but some older items like the "Glittering Jelly Platforms"
						-- function more like accessories. While this hasn't been confirmed yet, their meshes are likely found within the
						-- "Heels" model in that folder.
						
						-- There's an easy way to tell if shoes replace the player's leg parts; When this happens, their legs become basic,
						-- hidden block Parts. If the player's UpperLeftLeg is a Part, these are "modern", so the player's Character model
						-- itself will be saved instead of the "Heels" model.
						if Target.Name == "Heels" then
							if LeftUpperLeg and LeftUpperLeg:IsA("Part") then	-- If it's a Part, it was replaced. Save the whole character!
								Target = Character
							end
						end
						break
					end
					if num < #temp_folderList then
						message.Text = "You're wearing 2+ " .. category.Name .. "! Unequip everything to check " ..
							temp_folderList[num+1].Name .. " or just wear the single item you want to save, then tap CHECK again."
					else message.Text = "You aren't wearing any accessories, a skirt, or shoes. Please equip or use Try On (Shop) to continue."
					end
					break
				end
			end
			GUI_Base = GUIBase_Clothing		-- If any of the code above ran, we're targeting clothing, so let's reference "PreviewToggles".
		else	-- When in a dorm, this script locks onto the last thing that spawned, completely ignoring the player's character.
			Target = LatestFurniture	-- This won't work for furniture that doesn't show the "PreviewToggles" GUI, but oh well...
			GUI_Base = GUIBase_Furniture	-- Check the dorm furniture editing GUI for this item's name and other info.
		end
		
		-- If a valid target was found, assume it's the selected item that the player's customizing.
		if Target then
			if GUI_Base.Visible then	-- Is the preview GUI visible? We'll grab detailed info from it!
				local ItemName : TextLabel					= GUI_Base:FindFirstChild("ItemName")
				
				if ItemName == SaveDisabledName then
					message.Text = "Oh... Do you want to save the Starlight Skirt? Please close then re-open the toggle preview GUI." ..
						"That item's name is also the default name shown in the GUI, so this is required, sorry..."
					UpdateButton("check", true)
					UpdateButton("save", false)
					
					task.wait(0.75)
					UpdateQueued = false
					return
				end
				
				-- Now that we know the item's actual name from RH's GUI, let's prepare our "save" folder, using it as its name.
				SetSaveFolder(ItemName.Text)
				
				-- Figure out the player's current toggle number by checking each sub-frame's UIStroke visibility. Selected toggles are outlined.
				for _,toggle in GUI_Base.Inner:GetChildren() do
					if toggle:IsA("Frame") then
						if toggle:FindFirstChild("UIStrokeSelected") and toggle:FindFirstChild("UIStrokeSelected").Enabled then
							ToggleNum = tonumber(toggle.ToggleNumber.Text)	-- Get the small number in its upper left corner and use that.
							break
						end
					end
				end
				
				-- Next, iterate through this item's variation "categories" and get their information by using some "string magic".
				for _,category in GUI_Base.DynamicToggleVariants.ToggleCycleFrame:GetChildren() do
					if category:IsA("Frame") then
						local temp_newEntry	= {
							CategoryName	= category.Name:sub(7),	-- Remove the first 6 letters (which are usually "Cycle ").
							VarName			= "Unknown",
							VarNumber		= -1
						}
						
						-- Unfortunately, Royale High crams both the current variation and its name into the same string, so the cryptic-looking
						-- "code" below figures out where the left-most number and name are, and slices the original string up, storing the info.
						local VariationStr:string	= category.CurrentCycleItem.Text	-- This includes both the number and name ("(1/5) Angel").
						local slashPos				= VariationStr:find("/",1,true)		-- The slash separates the current and total variations.
						local _,rightParenLoc		= VariationStr:find(") ",1,true)	-- The right parentheses and space are the name's left bound.
						
						temp_newEntry.VarNumber		= tonumber(VariationStr:sub(2,slashPos-1))
						temp_newEntry.VarName		= VariationStr:sub(rightParenLoc+1)
						
						table.insert(VariationInfo, category.LayoutOrder, temp_newEntry)	-- Insert this entry at its position in RH's list.
					end
				end
				
				-- Finally, assemble this Model's final name, starting with its given name and toggle number.
				SaveName = ItemName.Text .. " T" .. ToggleNum
				if #VariationInfo > 0 then
					SaveName ..= " V"	-- Add a separator character before appending the variation information to the Model's name.
					for num,category in VariationInfo do	-- Append each variation's category name, number, and variant name to the name. This is messy.
						SaveName ..= tostring(category.VarNumber)
						
						-- BUG: For some reason (most of the time), items with two variation categories incorrectly don't include a "slash" in
						-- their Model name, but mysteriously do after tapping the CHECK button 1-2 more times. It's unknown why, but this bug
						-- almost consistently happens with items that have 2 categories; 3 category items are never affected!
						-- If a saved item's named something like "[Item Name] T1 V11" then it was affected by this strange bug.
						if num < #VariationInfo then SaveName ..= "/" end	-- If this isn't the last variation, add a separator before continuing.
					end
					
					-- table.clear(VariationInfo)	-- Clear this table to slightly lower memory usage, if it matters here.
				end
			else	-- Otherwise, there's still hope! See if the target contains a StringValue with its name!
				local temp_name:StringValue =
					Target:FindFirstChild("HeelName") or
					Target:FindFirstChild("AccessoryName") or
					Target:FindFirstChild("SkirtName") or
					Target:FindFirstChild("NameTag")	-- Dorm furniture
				if temp_name then
					SetSaveFolder(temp_name.Value)	-- Save this item's Model to a folder named after the item itself.
					if GUI_Base == GUIBase_Furniture then	-- Dorm furniture can include a NumberValue with its toggle number inside.
						local ToggleNum : NumberValue? = Target:FindFirstChild("ToggleIndex")
						if ToggleNum then	-- If the toggle number Instance exists, use the furniture's name and toggle number as its title.
							SaveName = temp_name.Value .. " T" .. ToggleNum.Value
						else SaveName = "Item"	-- Otherwise, fall back on "Item" like clothing.
						end
					else
						SaveName = "Item"
					end
				else SetSaveFolder(nil)	-- If a name can't be found, this item just can't be saved.
				end
			end
			
			-- Regardless of how the name's generated, make sure an item with this specific name hasn't been saved yet...
			if SaveFolder then
				if not SaveFolder:FindFirstChild(SaveName) then
					message.Text	= "All ready! Want to save\u{000D}\u{000A}"
					
					-- When saving an item without toggles, its SaveName is "Item", which isn't descriptive, so its real name (the save
					-- folder's) is used instead so the user knows the script has selected their desired item.
					if SaveName:len()<=5 then
						message.Text ..= SaveFolder.Name .. "?"
					else
						message.Text ..= SaveName .. "?"
					end
					UpdateButton("save", true)
					UpdateButton("check", true)
				else
					message.Text	= "You've already saved this specific toggle and variant combination." ..
						"Please try another one then CHECK again."
				end
			else
				UpdateButton("save", false)
				message.Text		= "Something was found, but its name can't be determined. Sorry, but this item can't be saved..."
			end
		else message.Text			= "No valid target was found. Please equip 1 item then tap CHECK again."
		end
		
		-- To stop checks from happening too frequently, intentionally stall for 3/4 of a second after every scan.
		task.wait(0.75)
		UpdateQueued = false
	end
end

Conn_CheckBtn		= check_button.MouseButton1Click:Connect(function()
	if Permissions.CanCheck then
		--[[
			message.Text = "CanCheck was " .. tostring(Permissions.CanCheck) .. "."
			wait(0.125)
		]]--
		
		FindDorm()	-- Try to set up dorm-related variables so furniture and halo variations/toggles can be saved easily.
		Request1ModelValidation()
	end
end)

Conn_SidebarVis		= GUI_Base.PreviewTogglesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	UpdateButton("check", true)
	
	if GUI_Base.Visible then
		Request1ModelValidation()
		if Target then
			message.Text =
				"Choose the toggle and variation combo you want to save, then tap CHECK to get its details. If everything's fine, tap SAVE."
		end
	else
		Request1ModelValidation()
		message.Text = "The sidebar was hidden. Equip another SINGLE accessory, skirt, or shoes and you'll be able to save it."
	end
end)

save_button.MouseButton1Click:Connect(function()
	if Target and Permissions.CanSave then
		UpdateButton("save", false)
		UpdateButton("check", false)
		UpdateButton("close", false)
		message.Text = "Saving model... (If this doesn't change, please check the F9 console!)\u{000D}\u{000A}" .. SaveName
		if not Target.Archivable then Target.Archivable = true end	-- Character models aren't saved, so we're fixing that before cloning it.
		
		local NewClone = Target:Clone()
		NewClone.Name = SaveName
		if NewClone:FindFirstChildOfClass("Humanoid") then	-- 2D clothes and the player's face texture(s) aren't saved when saving shoes.
			local shirt = NewClone:FindFirstChildOfClass("Shirt")
			local pants = NewClone:FindFirstChildOfClass("Pants")
			local shirtGFX = NewClone:FindFirstChildOfClass("ShirtGraphic")
			if shirt then shirt:Destroy() end
			if pants then pants:Destroy() end
			if shirtGFX then shirtGFX:Destroy() end
			
			local head = NewClone:FindFirstChild("Head")
			if head then
				for _,inst in head:GetChildren() do
					if inst:IsA("Decal") then inst:Destroy() end
				end
			end
		end
		
		-- Before moving the clone to its destination, copy its toggle and variation information to attributes. Previously,
		-- all info was written to each instance's name, but that has a length limit, so these specific details are just
		-- placed in variables to keep things tidier.
		if ToggleNum > 0 then NewClone:SetAttribute("Toggle", ToggleNum) end
		if VariationInfo and VariationInfo[1] then
			for num,category in VariationInfo do
				NewClone:SetAttribute("Var" .. num .. "Category", category.CategoryName)
				NewClone:SetAttribute("Var" .. num .. "Choice", category.VarName .. " (" .. tostring(category.VarNumber) .. ")")
			end
		end
		
		NewClone.Parent = SaveFolder
		message.Text = "Save completed! Feel free to change toggles/variations now.\u{000D}\u{000A}" .. SaveName
		UpdateButton("export", true)	-- Now that something was saved, the export button is usable!
		UpdateButton("close", true)
		UpdateButton("check", true)
	end
end)

-- Slide the bar onto the screen, now that everything's (hopefully) ready...
message:TweenPosition(
	BarPos_Active,
	Enum.EasingDirection.Out,
	Enum.EasingStyle.Quad,
	0.5,
	false
)

UpdateButton("check", true)
UpdateButton("close", true)
UpdateButton("export", false)

message.Text = "Welcome to the RH Accessory Preserver!"
if GUI_Base.Visible then
	if GetTargetInFolder(AccessoryFolder).Count == 1 then
		message.Text ..= " Tap the CHECK button to 'save' your current toggle/variation combination to a folder in Lighting!"
	else
		message.Text ..= " Unequip all but one accessory, open the editing sidebar, then tap CHECK to select it for saving."
	end
else
	message.Text ..= " The editing sidebar isn't open currently. Please equip a single accessory, then tap CHECK when you're ready!"
end

-- If anything is already inside the Clothing Captures folder, enable the export button.
if SaveBase and #SaveBase:GetChildren() > 0 then
	UpdateButton("export", true)
end

-- CONFIRMATION DIALOG BOX

-- Hides the confirmation dialog, bringing back the main bar.
local function DenyExport()
	RHGUI_DialogBox.Visible = false
	message.Visible = true
	save_button.Visible = true
	check_button.Visible = true
	close_button.Visible = true
	export_button.Visible = true
end
Conn_RHClose1		= RHGUI_CloseButton.MouseButton1Click:Connect(DenyExport)
Conn_RHClose2		= RHGUI_NoButton.MouseButton1Click:Connect(DenyExport)

-- Does the opposite of the previous function, showing the confirmation dialog instead of the main GUI.
Conn_ExportBtn		= export_button.MouseButton1Click:Connect(function()
	if Permissions.CanExport then
		message.Visible = false
		
		-- Hide all buttons attached to the message box; When saving begins, the message box is used by the API to show its status.
		save_button.Visible = false
		check_button.Visible = false
		close_button.Visible = false
		export_button.Visible = false
		
		RHGUI_DialogBox.Visible = true
	end
end)

local SavePrefix	= "RH Clothing Save #"
-- Unlike Xane's Model Recreator, RH Accessory Preserver keeps things simple by naming saved files itself. All captures
-- are saved as "RH Clothing Save #[number]", which increases each time the player tries to save something. It
-- intelligently makes sure an "index" is empty before it starts writing to it.
Conn_RHYesBtn		= RHGUI_YesButton.MouseButton1Click:Connect(function()
	if not UpdateQueued then
		UpdateQueued = true	-- Repurpose this debounce from the item info-getting function as a general "debounce" flag.
		
		-- Disable every button.
		UpdateButton("save", false)
		UpdateButton("check", false)
		UpdateButton("close", false)
		UpdateButton("export", false)
		
		RHGUI_DialogBox.Visible = false	-- Hide the dialog box, leaving the player without any GUI.
		message.Visible = true	-- Show the message box for status updates (by the Recreation API).
		
		local FoundSlot	= false
		local SaveSlot	= 1
		while not FoundSlot do
			local FileStatus = nil	-- Check each possible file in order, starting with #1. If something doesn't exist, FileStatus will be nil.
			pcall(function()
				FileStatus = readfile(SavePrefix .. SaveSlot .. "_header.json")
			end)
			if not FileStatus then FoundSlot = true	-- We found an open slot? Save here!
			else
				SaveSlot += 1
				task.wait()	-- This will slow down saves if there are a lot of clothing captures on the device, but that beats the app freezing!
			end
		end
		
		Recreator.Select("set", {SaveBase})	-- Sadly, the full captures folder is incldued with each capture, but it's emptied after each export.
		Recreator.Save(SavePrefix .. SaveSlot)
		Recreator.Select("set", {})
		
		if SaveBase and #SaveBase:GetChildren() > 0 then SaveBase:ClearAllChildren() end	-- Remove all copied items from the folder.
		
		-- TODO: Consider moving items to a secondary folder in ServerStorage or something; When checking an item's full name to see if
		-- it has already been saved, that function could check that folder and the Lighting save directory. Since the items aren't in
		-- THE save folder, they wouldn't be incldued in future exports, either.
		
		UpdateButton("save", false)
		UpdateButton("check", true)
		UpdateButton("close", true)
		UpdateButton("export", false)
		message.Visible = true
	end
end)

--[[
	DORM FURNITURE SUPPORT (HACKISH, INCOMPLETE, AND MOST LIKELY BROKEN)
	The code below manages the special "dorm reference variables", which lock onto the player's dorm Part, their DormFurniture model,
	and the most recently-added piece of furniture in the room. The regular code used above for clothing will check these variables
	and try to save it instead of an accessory if everything is defined.
]]--
if IsDorms then
	message.Text ..= " Claim a dorm then tap CHECK to lock onto it!"
end

-- Looks for a part named after this player's user ID; When a player owns a dorm, its outer Part is renamed (I think).
function FindDorm()
	if IsDorms then
		DormPart = workspace:FindFirstChild(LocalPlayer.UserId)
		if DormPart and DormPart:IsA("Part") then
			if not FurniContainer then	-- Only set up furniture-related stuff if the reference hasn't been set up yet.
				FurniContainer = DormPart:FindFirstChild("DormFurniture")
				Conn_FurniAdd = FurniContainer.ChildAdded:Connect(function(_newItem)
					if _newItem:IsA("Model") then
						task.wait()	-- Intentionally wait in case a race condition is caused by a Model appearing and disappearing at once.
						LatestFurniture = _newItem	-- Try to capture this piece of furniture the next time CHECK is tapped.
						message.Text	= "A new item appeared in your dorm, and may be save-able!"
					end
				end)
				Conn_FurniRem = FurniContainer.ChildRemoved:Connect(function(_item)
					if LatestFurniture then
						LatestFurniture = nil	-- When anything is removed from the dorm, this script will detach from it.
						message.Text	= "Something was removed or unloaded from your dorm, and has been untargeted."
					end
				end)
			end
			
		else	-- If there's somehow another Instance with the player's user ID in the dorm realm, it cannot be used.
			DormPart = nil
			if FurniContainer then
				FurniContainer = nil
				DisconnectEvent(Conn_FurniAdd)
				DisconnectEvent(Conn_FurniRem)
			end
			
		end
	end
	
	return
end

Recreator.SetStatusGui(message)