-- SERVICES
local Lighting					= game:GetService("Lighting")
local ReplicatedStorage			= game:GetService("ReplicatedStorage")
local StarterGui				= game:GetService("StarterGui")
local HttpService				= game:GetService("HttpService")
local InsertService				= game:GetService("InsertService")
local MaterialService			= game:GetService("MaterialService")
local ChangeHistoryService		= game:GetService("ChangeHistoryService")
local Selection					= game:GetService("Selection")

-- INITIALIZATION (REFERENCES)
print("Xane's Model Recreator (Plugin) - Initializing...")

-- Go ahead and generate a floating window for this plugin, which will always appear when Studio starts.
local panel_info = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, -- Widget will be initialized in floating panel
	true, -- Widget will be initially enabled
	false, -- Don't override the previous enabled state
	225, -- Default width of the floating window
	600, -- Default height of the floating window
	200, -- Minimum width of the floating window (optional)
	550 -- Minimum height of the floating window (optional)
)

-- Create new widget GUI, then move the plugin Frame into the new "widget".
local Panel						= plugin:CreateDockWidgetPluginGui("Xane's Asset Importer", panel_info)
Panel.Title						= "Xane's Asset Importer"
local GUIBase					= script.Parent.XaneContainer
GUIBase.Parent					= Panel

-- Add a button to the plugins tab that shows the GUI, in case it's hidden. (It can also be shown by right-clicking and selecting it from the list.)
if not _G.XaneInternal then _G.XaneInternal = {} end
if not _G.XaneInternal.Toolbar then _G.XaneInternal.Toolbar = plugin:CreateToolbar("Xane's Plugins") end
local Action : PluginToolbarButton =
	_G.XaneInternal.Toolbar:CreateButton(
		"Xane_ImportPlugin",
		"Toggles visibility of Xane's asset importing GUI.",
		"rbxassetid://11914973890",
		"Import Assets..."
	)
Action.ClickableWhenViewportHidden = false
Action.Click:Connect(function()	-- When this button is clicked, toggle the widget's visibility.
	Panel.Enabled			= not Panel.Enabled
	Action:SetActive(Panel.Enabled)
end)

local Contents					= GUIBase.Contents
local PageController			= Contents.UIPageLayout	-- Instance which can move between the plugin's pages when needed.

-- Page 1 (Header Data)
local Page1						= Contents.Page1
local Page1_TextBox				= Page1.HeaderBox
local Page1_Error				= Page1.Error

-- Page 2 (Piece Info Imports)
local Page2						= Contents.Page2
local Page2_Message				= Page2.MessagePart1
local Page2_TextBox				= Page2.PieceBox	-- Input box where each piece's JSON data is pasted.
local Page2_TextBoxLabel		= Page2_TextBox.Label	-- The text box's label, which updates to reflect which piece it wants next.
local Page2_Status				= Page2.Status		-- A line of circle emoji, showing how close the user is to completing this import.
local Page2_Error				= Page2.Error		-- A normally-hidden label, which becomes visible if any exceptions are caught then displayed.
local Page2_BackButton			= Page2.BackButton

-- Page 3 (Settings)
local Page3						= Contents.Page3
local Page3_BackButton			= Page3.Buttons.Back
local Page3_StartButton			= Page3.Buttons.Import
local Page3_CheckLighting		= Page3.Option1		-- When set, the lighting properties stored in the header are applied in Studio after importing.
local Page3_CheckMaterials		= Page3.Option2
local Page3_CheckAllWorkspace	= Page3.Option3		-- If selected, the "container imposter" models are all placed in workspace instead of separated.
local Page3_CheckAutoSelect		= Page3.Option4		-- When enabled, the imported assets (dummy models) are selected when everything's done.

Page3_CheckAllWorkspace.Visible	= false	-- TODO: Remove this to show the check after fixing this option's bugs (inner Models don't appear).

-- Page 4 (Progress)
local Page4						= Contents.Page4
local Page4_Message				= Page4.Message

-- VARIABLES
local Header						: {		-- The decoded header data for this exported model, which contains data for the pieces and moe.
	Metadata						: {
		Name						: string,		-- Name of this "file", used to name the destination "folders".
		PlaceId						: number,		-- Place which the contents of this export came from.
		GameId						: number		-- The ID of the experience that these Instances were saved from.
	},
	LightingProperties				: {		-- Properties of the Lighting container, based on heir values upon beignning`
		Ambient						: {number},	-- Color3
		Brightness					: number,
		ColorShift_Top				: {number},	-- Color3
		ColorShift_Bottom			: {number},	-- Color3
		EnvironmentDiffuseScale		: number,
		EnvironmentSpecularScale	: number,
		GlobalShadows				: boolean,
		OutdoorAmbient				: {number},	-- Color3
		ShadowSoftness				: number,
		ClockTime					: number,
		GeographicLatitude			: number,
		FogColor					: {number},	-- Color3
		FogEnd						: number,
		FogStart					: number
	},
	MaterialVariants				: {	-- An array of dictionary entries, similar to pieces' instance entries. Only MaterialVariants are in here.
		{
			Name					: string,	-- Debug IDs aren't needed for these, as they're all parented to a single folder while importing.
			BaseMaterial			: {string},
			CustomPhysicalProperties: {number},
			MaterialPattern			: {string},
			ColorMap				: string,
			NormalMap				: string,
			MetalnessMap			: string,
			RoughnessMap			: string,
			StudsPerTile			: number
		}
	},
	ImposterIds						: {string},	-- Debug IDs of the four containers' "dummy models", destinations for Instances in this export.
	PieceInfo						: {
		{	-- Determines which destination Model this piece's contents will be parented to. PlayerGui puts instances in StarterGui.
			InsertLocation			: "workspace"|"players"|"playergui"|"lighting"|"repstore",
			BaseInstName			: string	-- The selected base Instance (1st index in the piece's JSON data)'s name.
		}
	}
}
	= {}
local PieceData					: {		-- An array of decoded JSON arrays, one for each "piece".
	{	-- This array's first level holds each piece's data in its own subarray.
		{
			Name					: string,
			DebugId					: string,
			Parent					: string,
			ClassName				: string,
			Instance				: Instance,	-- Reference to the newly-created Instance, the replica.
			Attributes				: {any},	-- A string-indexed array of any attributes' values that this Instance had upon capture.
			Tags					: {string}	-- A basic array of this Instance's tags, which are imported along with Instances themselves.
		}
	}
}
	= {}
local TempDataStorage			= {}	-- A variable which will temporarily contain decoded JSON data while it's validated.


-- Import settings (adjusted on page 3)
local Setting					= {
	UseLighting					= false,
	UseMaterials				= true,
	AllWorkspace				= false,
	AutoSelect					= true,
	TerrainColors				= true,
	TerrainAddAir				= true
}

local IsBusy					= false	-- Flag which blocks most input, mainly used when doing delayed actions like changing pages.

--[[
	An array of string-based indices which links "debug IDs" to Instances. The exported JSON data can't contain actual Instance
	pointers, so it represents them using the strings gathered using Instance:GetDebugId(). After importing starts, all Instances
	are immediately created then associated to the original debug IDs by storing them in this array. Just before importing is
	complete, all Instances are linked to one another by checking each "Instance" debug ID against this array;
	
	If there's a match, it's set to its cooresponding reference, and if not, it's either left as nil (properties) or parented to
	the most relevant "imposter Model" (for the parent property). This allows Instances from different pieces to link to one
	another; For example, if a player's character model and their EquippedStorage subfolders are selected individually (in
	Royale High), their replacement body parts will be welded to their actual body parts, exactly like they are during gameplay.
]]--
local DebugIDList : {Instance}	= {}

-- STATIC DATA & FUNCTIONS
-- Arrays of properties shared by multiple classes, used to simplify the main class data array/list below.
-- If any list contains a property starting with "UseCmnList_", the script should iterate through the array named after its value here.
local CommonPropList					= {
	Instance							= {
		Name							= "string",
		Parent							= "Instance"
	},
	Attachment							= {
		Axis							= "Vector3",
		SecondaryAxis					= "Vector3",
		CFrame							= "CFrame",	-- Set the CFrame last, in case the previous properties are redundant.
		Visible							= "boolean"
	},
	Decal								= {
		Color3							= "Color3",
		Face							= "EnumItem",	-- Inherited from FaceInstance class
		LocalTransparencyModifier		= "number",
		Texture							= "string",
		Transparency					= "number",
		ZIndex							= "number"
	},
	Model								= {
		LevelOfDetail					= "EnumItem",
		ModelStreamingMode				= "EnumItem",
		PrimaryPart						= "Instance"
	},
	BasePart							= {
		Anchored						= "boolean",
		BackSurface						= "EnumItem",
		BottomSurface					= "EnumItem",
		CFrame							= "CFrame",
		CanCollide						= "boolean",
		CanQuery						= "boolean",
		CanTouch						= "boolean",
		CastShadow						= "boolean",
		CollisionGroup					= "string",
		Color							= "Color3",
		EnableFluidForces				= "boolean",
		FrontSurface					= "EnumItem",
		LeftSurface						= "EnumItem",
		LocalTransparencyModifier		= "number",
		Locked							= "boolean",
		Massless						= "boolean",
		Material						= "EnumItem",
		MaterialVariant					= "string",
		PivotOffset						= "CFrame",
		Reflectance						= "number",
		RightSurface					= "EnumItem",
		RootPriority					= "number",
		Size							= "Vector3",
		TopSurface						= "EnumItem",
		Transparency					= "number"
	},
	Constraint							= {
		Attachment0						= "Instance",
		Attachment1						= "Instance",
		Color							= "BrickColor",
		Enabled							= "boolean",
		Visible							= "boolean"
	},
	JointInstance						= {
		C0								= "CFrame",
		C1								= "CFrame",
		Enabled							= "boolean",
		Part0							= "Instance",
		Part1							= "Instance"
	},
	Light								= {
		Brightness						= "number",
		Color							= "Color3",
		Enabled							= "boolean",
		Shadows							= "boolean"
	},
	Motor								= {
		CurrentAngle					= "number",
		DesiredAngle					= "number",
		MaxVelocity						= "number"
	},
	SoundEffect							= {
		Enabled							= "boolean",
		Priority						= "number"
	},
	WetDrySound							= {
		DryLevel						= "number",
		WetLevel						= "number"
	},
	SpotAndSurfaceLight					= {
		Angle							= "number",
		Face							= "EnumItem",
		Range							= "number"
	},
	SurfaceGuiBase						= {
		Active							= "boolean",
		Adornee							= "Instance",
		Face							= "EnumItem",
	},
	BaseWrap							= {
		CageMeshId						= "string",
		CageOrigin						= "CFrame",
		ImportOrigin					= "CFrame"
	},
	PBRMapSet							= {
		ColorMap						= "string",
		MetalnessMap					= "string",
		NormalMap						= "string",
		RoughnessMap					= "string"
	},
	LayerCollector						= {	-- Used by ScreenGui's and possibly moe classes.
		Enabled							= "boolean",
		ResetOnSpawn					= "boolean",
		ZIndexBehavior					= "EnumItem"
	},
	GuiButton							= {
		AutoButtonColor					= "boolean",
		Modal							= "boolean",
		Selected						= "boolean",
		Style							= "EnumItem"
	},
	GuiObject							= {
		Active							= "boolean",
		AnchorPoint						= "Vector2",
		AutomaticSize					= "EnumItem",
		BackgroundColor3				= "Color3",
		BackgroundTransparency			= "number",
		BorderColor3					= "Color3",
		BorderMode						= "EnumItem",
		BorderSizePixel					= "number",
		ClipsDescendants				= "boolean",
		-- Draggable					= "boolean",
		Interactable					= "boolean",
		LayoutOrder						= "number",
		Position						= "UDim2",
		Rotation						= "number",
		Selectable						= "boolean",
		SelectionOrder					= "number",
		Size							= "UDim2",
		SizeConstraint					= "EnumItem",
		Visible							= "boolean",
		ZIndex							= "number"
	},
	GuiBase2d							= {
		AutoLocalize					= "boolean"
	},
	GuiTextElement						= {	-- TextButtons and TextLabels have the exact same properties!
		FontFace						= "Font",
		LineHeight						= "number",
		MaxVisibleGraphemes				= "number",
		RichText						= "boolean",
		Text							= "string",
		TextColor3						= "Color3",
		TextDirection					= "EnumItem",
		TextScaled						= "boolean",
		TextSize						= "number",
		TextStrokeColor3				= "Color3",
		TextStrokeTransparency			= "number",
		TextTransparency				= "number",
		TextTruncate					= "EnumItem",
		TextWrapped						= "boolean",
		TextXAlignment					= "EnumItem",
		TextYAlignment					= "EnumItem"
	},
	GuiImageElement						= {	-- Properties reused between ImageLabels and ImageButtons.
		Image							= "string",
		ImageColor3						= "Color3",
		ImageRectOffset					= "Vector2",
		ImageRectSize					= "Vector2",
		ImageTransparency				= "number",
		ResampleMode					= "EnumItem",
		ScaleType						= "EnumItem",
		SliceCenter						= "Rect",
		SliceScale						= "number",
		TileSize						= "UDim2"
	},
	UIGridStyleLayout					= {
		FillDirection					= "EnumItem",
		HorizontalAlignment				= "EnumItem",
		SortOrder						= "EnumItem",
		VerticalAlignment				= "EnumItem"
	}
}

-- A very long, complex array of dictionary entries that specifies what properties should be saved for specific instance classes, and what
-- their types are. This may look almost identical to its plugin counterpart, but there are some differences. For example, MeshParts' MeshId
-- property is included in the script version so it saves its value, but it's commented out in the plugin, since modifying that property
-- directly will cause errors and break its functions.

-- When iterating through one of these property lists, make sure it's always done from top to bottom; Sometimes, the properties have to be set
-- out of alphabetical order! Also, Don't use a "UseCmnList_" definition to inherit from the "Instance" list above! The final script will
-- automatically do that to simplify things.

-- When ay reference to an Instance is found by the Studio plugin, just silently add each of the properties to an array index named after the
-- instance's "intended debug ID", then go back through that list afte all instances have been "imported" and use the complete "debug ID" array
-- to link each of the properties to their intended "reconstructed" instances.
local ClassData							= {
	["AdGui"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "📊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "LayerCollector",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiBase2d",
			UseCmnList_3				= "SurfaceGuiBase",
			AdShape						= "EnumItem",
			EnableVideoAds				= "boolean",
			FallbackImage				= "string",
		}
	},
	["Attachment"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔌",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Attachment"	-- Common properties that this class shares with others.
		}
	},
	["Accessory"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "👚",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "child"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			AccessoryType				= "EnumItem",
			AttachmentPoint				= "CFrame"	-- Inherited from Accoutrement (What even is that word?)
		}
	},
	["Animation"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🤺",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			AnimationId					= "string"
		}
	},
	["AnimationController"]				= {	-- AnimationController instances don't have any properties other than standard Instance ones.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🤺",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
		}
	},
	--[[["Animator"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🤺",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			PreferLodEnabled			= "boolean"
		}
	},]]--
	["Atmosphere"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⛅",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Color						= "Color3",
			Decay						= "Color3",
			Density						= "number",
			Glare						= "number",
			Haze						= "number",
			Offset						= "number"
		}
	},
	["Backpack"]						= {	-- Backpacks don't have any properties other than standard Instance ones.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🎒",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
		}
	},
	["Beam"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⚡",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Attachment0					= "Instance",
			Attachment1					= "Instance",
			LightInfluence				= "number",	-- Brightness is only used if LightInfluence is set to a low value.
			Brightness					= "number",
			Color						= "ColorSequence",
			CurveSize0					= "number",
			CurveSize1					= "number",
			Enabled						= "boolean",
			FaceCamera					= "boolean",
			LightEmission				= "number",
			Segments					= "number",
			Texture						= "string",
			TextureLength				= "number",
			TextureMode					= "EnumItem",
			TextureSpeed				= "number",
			Transparency				= "NumberSequence",
			Width0						= "number",
			Width1						= "number",
			ZOffset						= "number"
		}
	},
	["BillboardGui"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🛑",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "LayerCollector",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiBase2d",
			Active						= "boolean",
			Adornee						= "Instance",
			AlwaysOnTop					= "boolean",
			Brightness					= "number",
			ClipsDescendants			= "boolean",
			DistanceLowerLimit			= "number",
			DistanceStep				= "number",
			DistanceUpperLimit			= "number",
			ExtentsOffset				= "Vector3",
			ExtentsOffsetWorldSpace		= "Vector3",
			LightInfluence				= "number",
			MaxDistance					= "number",
			Size						= "UDim2",
			SizeOffset					= "Vector2",
			StudsOffset					= "Vector3",
			StudsOffsetWorldSpace		= "Vector3"
		}
	},
	["BloomEffect"]						= {	-- Decals' properties are reused for Textures.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌄",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Enabled						= "boolean",	-- Inherited from PostEffect class
			Intensity					= "number",
			Size						= "number",
			Threshold					= "number"
		}
	},
	["BlurEffect"]						= {	-- Decals' properties are reused for Textures.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌄",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Enabled						= "boolean",	-- Inherited from PostEffect class
			Size						= "number",
		}
	},
	["Bone"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🦴",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Attachment",	-- Common properties that this class shares with others.
			Transform					= "CFrame"
		}
	},
	["BoolValue"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Value						= "boolean"
		}
	},
	["BrickColorValue"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Value						= "BrickColor"
		}
	},
	["Camera"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🎥",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Cameras aren't used much outside of ViewportFrames so I don't want to script viewing them.
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			CameraType					= "EnumItem",
			CameraSubject				= "Instance",
			FieldOfViewMode				= "EnumItem",
			DiagonalFieldOfView			= "number",
			MaxAxisFieldOfView			= "number",
			FieldOfView					= "number",
			Focus						= "CFrame",
			HeadLocked					= "boolean",
			HeadScale					= "number",
			VRTiltAndRollEnabled		= "boolean",
			CFrame						= "CFrame"
		}
	},
	["CanvasGroup"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🏢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "GuiObject",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiBase2d",
			GroupColor3					= "Color3",
			GroupTransparency			= "number"
		}
	},
	["CFrameValue"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Value						= "CFrame"
		}
	},
	["ChorusSoundEffect"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SoundEffect",	-- Common properties that this class shares with others.
			-- UseCmnList_2				= "WetDrySound",
			Depth						= "number",		-- These are the same properties as FlangeSoundEffect! Consider creating a "common list" of these.
			Mix							= "number",
			Rate						= "number"
		}
	},
	["Color3Value"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Value						= "Color3"
		}
	},
	["ColorCorrectionEffect"]			= {	-- Decals' properties are reused for Textures.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌄",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Enabled						= "boolean",	-- Inherited from PostEffect class
			Brightness					= "number",
			Contrast					= "number",
			Saturation					= "number",
			TintColor					= "Color3"
		}
	},
	["CompressorSoundEffect"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SoundEffect",	-- Common properties that this class shares with others.
			-- UseCmnList_2				= "WetDrySound",
			Attack						= "number",
			GainMakeup					= "number",
			Ratio						= "number",
			Release						= "number",
			SideChain					= "Instance",
			Threshold					= "number"
		}
	},
	["Configuration"]					= {	-- Configuration folders don't have any properties other than standard Instance ones.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⚙",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
		}
	},
	["CornerWedgePart"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧱",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "yes"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BasePart"	-- Use all of the properties shared by all BasePart instances.
		}
	},
	["Decal"]							= {	-- Decals' properties are reused for Textures.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "📄",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Decal",	-- Common properties that this class shares with others.
		}
	},
	["DepthOfFieldEffect"]						= {	-- Decals' properties are reused for Textures.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌄",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Enabled						= "boolean",	-- Inherited from PostEffect class
			FarIntensity				= "number",
			FocusDistance				= "number",
			InFocusRadius				= "number",
			NearIntensity				= "number"
		}
	},
	["DistortionSoundEffect"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SoundEffect",	-- Common properties that this class shares with others.
			-- UseCmnList_2				= "WetDrySound",
			Level						= "number"
		}
	},
	["DoubleConstrainedValue"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			MaxValue					= "number",
			MinValue					= "number"
		}
	},
	["EchoSoundEffect"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SoundEffect",	-- Common properties that this class shares with others.
			UseCmnList_2				= "WetDrySound",
			Delay						= "number",
			Feedback					= "number"
		}
	},
	["EqualizerSoundEffect"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SoundEffect",	-- Common properties that this class shares with others.
			-- UseCmnList_2				= "WetDrySound",
			HighGain					= "number",
			LowGain						= "number",
			MidGain						= "number"
		}
	},
	["Fire"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔥",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Color						= "Color3",
			Enabled						= "boolean",
			Heat						= "number",
			SecondaryColor				= "Color3",
			Size						= "number",
			TimeScale					= "number"
		}
	},
	["FlangeSoundEffect"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SoundEffect",	-- Common properties that this class shares with others.
			-- UseCmnList_2				= "WetDrySound",
			Depth						= "number",		-- These are the same properties as ChorusSoundEffect! Consider creating a "common list" of these.
			Mix							= "number",
			Rate						= "number"
		}
	},
	["Folder"]							= {	-- Folders don't have any properties other than standard Instance ones.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "📁",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
		}
	},
	["Frame"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🖼",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "GuiObject",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiBase2d",
			Style						= "EnumItem"
		}
	},
	["Highlight"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔳",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Adornee						= "Instance",
			DepthMode					= "EnumItem",
			Enabled						= "boolean",
			FillColor					= "Color3",
			FillTransparency			= "number",
			OutlineColor				= "Color3",
			OutlineTransparency			= "number"
		}
	},
	["HingeConstraint"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧷",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Constraint",	-- Common properties that this class shares with others.
			ActuatorType				= "EnumItem",
			AngularResponsiveness		= "number",
			AngularVelocity				= "number",
			LimitsEnabled				= "boolean",
			LowerAngle					= "number",
			MotorMaxAcceleration		= "number",
			MotorMaxTorque				= "number",
			Radius						= "number",
			Restitution					= "number",
			ServoMaxTorque				= "number",
			TargetAngle					= "number",
			UpperAngle					= "number"
		}
	},
	["Humanoid"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🙍🏼‍",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			AutoJumpEnabled				= "boolean",
			AutoRotate					= "boolean",
			AutomaticScalingEnabled		= "boolean",
			BreakJointsOnDeath			= "boolean",
			CameraOffset				= "Vector3",
			DisplayDistanceType			= "EnumItem",
			DisplayName					= "string",
			-- EvaluateStateMachine		= "boolean",
			Health						= "number",
			HealthDisplayDistance		= "number",
			HealthDisplayType			= "EnumItem",
			HipHeight					= "number",
			JumpHeight					= "number",
			JumpPower					= "number",
			MaxHealth					= "number",
			MaxSlopeAngle				= "number",
			NameDisplayDistance			= "number",
			NameOcclusion				= "EnumItem",
			PlatformStand				= "boolean",
			RequiresNeck				= "boolean",
			RigType						= "EnumItem",	-- Should this property be captured?
			UseJumpPower				= "boolean",
			WalkSpeed					= "number"
		}
	},
	["HumanoidDescription"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "👤",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			BackAccessory				= "string",
			BodyTypeScale				= "number",
			ClimbAnimation				= "number",
			DepthScale					= "number",
			Face						= "number",
			FaceAccessory				= "string",
			FallAnimation				= "number",
			FrontAccessory				= "string",
			GraphicTShirt				= "number",
			HairAccessory				= "string",
			HatAccessory				= "string",
			Head						= "number",
			HeadColor					= "Color3",
			HeadScale					= "number",
			HeightScale					= "number",
			IdleAnimation				= "number",
			JumpAnimation				= "number",
			LeftArm						= "number",
			LeftArmColor				= "Color3",
			LeftLeg						= "number",
			LeftLegColor				= "Color3",
			MoodAnimation				= "number",
			NeckAccessory				= "string",
			Pants						= "number",
			ProportionScale				= "number",
			RightArm					= "number",
			RightArmColor				= "Color3",
			RightLeg					= "number",
			RightLegColor				= "Color3",
			RunAnimation				= "number",
			Shirt						= "number",
			ShouldersAccessory			= "string",
			SwimAnimation				= "number",
			Torso						= "number",
			TorsoColor					= "Color3",
			WaistAccessory				= "string",
			WalkAnimation				= "number",
			WidthScale					= "number"
		}
	},
	["ImageButton"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🏞",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "GuiImageElement",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiButton",
			UseCmnList_3				= "GuiObject",
			UseCmnList_4				= "GuiBase2d",
			HoverImage					= "string",
			PressedImage				= "string"
		}
	},
	["ImageLabel"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🏞",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "GuiImageElement",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiObject",
			UseCmnList_3				= "GuiBase2d"
		}
	},
	["IntValue"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Value						= "number"
		}
	},
	["IntConstrainedValue"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			MaxValue					= "number",
			MinValue					= "number"
		}
	},
	["LineForce"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "↗",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Constraint",	-- Common properties that this class shares with others.
			ApplyAtCenterOfMass			= "boolean",
			InverseSquareLaw			= "boolean",
			Magnitude					= "number",
			MaxForce					= "number",
			ReactionForceEnabled		= "boolean"
		}
	},
	["MaterialVariant"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🏁",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "PBRMapSet",	-- Common properties that this class shares with others.
			BaseMaterial				= "EnumItem",
			CustomPhysicalProperties	= "PhysicalProperties",
			MaterialPattern				= "EnumItem",
			StudsPerTile				= "number",
		}
	},
	["MeshPart"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧭",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "yes"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BasePart",	-- Use all of the properties shared by all BasePart instances.
			DoubleSided					= "boolean",
			TextureID					= "string",
			-- MeshId					= "string",	-- Comment this line out in the plugin! MeshIds can't be set directly, only used on creation.
			RenderFidelity				= "EnumItem",	-- Comment this out too...
			CollisionFidelity			= "EnumItem"	-- ...and this one! (This inherits from the "TriangleMeshPart" class, also used by unions.)
		}
	},
	["Model"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔳",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "yes"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Model"	-- Other classes inherit from this one.
		}
	},
	["Motor"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🛵",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Motor",
			UseCmnList_2				= "JointInstance"
		}
	},
	["Motor6D"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "💪🏼",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Motor",
			UseCmnList_2				= "JointInstance",
			Transform					= "CFrame"
		}
	},
	["NumberValue"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Value						= "number"
		}
	},
	["ObjectValue"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Value						= "Instance"
		}
	},
	["Pants"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "👕",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			PantsTemplate				= "string",
			Color3						= "Color3"	-- Inherited from Clothing class
		}
	},
	["Part"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧱",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "yes"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BasePart",	-- Use all of the properties shared by all BasePart instances.
			Shape						= "EnumItem"
		}
	},
	["ParticleEmitter"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "✨",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Acceleration				= "Vector3",
			LightInfluence				= "number",	-- Brightness is only used if LightInfluence is set to a low value.
			Brightness					= "number",
			Color						= "ColorSequence",
			Drag						= "number",
			EmissionDirection			= "EnumItem",
			Enabled						= "boolean",
			FlipbookFramerate			= "NumberRange",
			FlipbookIncompatible		= "string",
			FlipbookLayout				= "EnumItem",
			FlipbookMode				= "EnumItem",
			FlipbookStartRandom			= "boolean",
			Lifetime					= "NumberRange",
			LightEmission				= "number",
			LockedToPart				= "boolean",
			Orientation					= "EnumItem",
			Rate						= "number",
			RotSpeed					= "NumberRange",
			Rotation					= "NumberRange",
			Shape						= "EnumItem",
			ShapeInOut					= "EnumItem",
			ShapePartial				= "number",
			ShapeStyle					= "EnumItem",
			Size						= "NumberSequence",
			Speed						= "NumberRange",
			SpreadAngle					= "Vector2",
			Squash						= "NumberSequence",
			Texture						= "string",
			TimeScale					= "number",
			Transparency				= "NumberSequence",
			VelocityInheritance			= "number",
			WindAffectsDrag				= "boolean",
			ZOffset						= "number"
		}
	},
	["PitchShiftSoundEffect"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SoundEffect",	-- Common properties that this class shares with others.
			-- UseCmnList_2				= "WetDrySound",
			Octave						= "number"
		}
	},
	["PlaneConstraint"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧷",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Constraint"	-- Common properties that this class shares with others.
		}
	},
	["Player"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "👤",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			AutoJumpEnabled				= "boolean",
			CameraMaxZoomDistance		= "number",
			CameraMinZoomDistance		= "number",
			CameraMode					= "EnumItem",
			CanLoadCharacterAppearance	= "boolean",
			Character					= "Instance",
			CharacterAppearanceId		= "number",
			DevCameraOcclusionMode		= "EnumItem",
			DevComputerCameraMode		= "EnumItem",
			DevComputerMovementMode		= "EnumItem",
			DevEnableMouseLock			= "boolean",
			DevTouchCameraMode			= "EnumItem",
			DevTouchMovementMode		= "EnumItem",
			DisplayName					= "string",
			HealthDisplayDistance		= "number",
			NameDisplayDistance			= "number",
			Neutral						= "boolean",
			-- ReplicationFocus			= "Instance",
			-- RespawnLocation			= "Instance",
			-- Team						= "Instance",
			TeamColor					= "BrickColor",
			UserId						= "number"
		}
	},
	["PlayerGui"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "📱",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			ScreenOrientation			= "EnumItem",
		}
	},
	["PointLight"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "💡",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Light",	-- Common properties that this class shares with others.
			Range						= "number"
		}
	},
	["PrismaticConstraint"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧷",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SlidingBallConstraint",	-- Common properties that this class shares with others.
			UseCmnList_2				= "Constraint"
		}
	},
	["ReverbSoundEffect"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SoundEffect",	-- Common properties that this class shares with others.
			UseCmnList_2				= "WetDrySound",
			DecayTime					= "number",
			Density						= "number",
			Diffusion					= "number"
		}
	},
	["RodConstraint"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧷",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Constraint",	-- Common properties that this class shares with others.
			Length						= "boolean",
			LimitAngle0					= "number",
			LimitAngle1					= "number",
			LimitsEnabled				= "boolean",
			Thickness					= "number"
		}
	},
	["RopeConstraint"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧷",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Constraint",	-- Common properties that this class shares with others.
			Length						= "number",
			Restitution					= "number",
			Thickness					= "number",
			WinchEnabled				= "boolean",
			WinchForce					= "number",
			WinchResponsiveness			= "number",
			WinchSpeed					= "number",
			WinchTarget					= "number"
		}
	},
	["ScreenGui"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "📱",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "LayerCollector",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiBase2d",
			ClipToDeviceSafeArea		= "boolean",
			DisplayOrder				= "number",
			IgnoreGuiInset				= "boolean",
			SafeAreaCompatibility		= "EnumItem",
			ScreenInsets				= "EnumItem"
		}
	},
	["ScrollingFrame"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🖼",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "GuiObject",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiBase2d",
			AutomaticCanvasSize			= "EnumItem",
			BottomImage					= "string",
			CanvasPosition				= "Vector2",
			CanvasSize					= "UDim2",
			ElasticBehavior				= "EnumItem",
			HorizontalScrollBarInset	= "EnumItem",
			MidImage					= "string",
			ScrollBarImageColor3		= "Color3",
			ScrollBarImageTransparency	= "number",
			ScrollBarThickness			= "number",
			ScrollingDirection			= "EnumItem",
			ScrollingEnabled			= "boolean",
			TopImage					= "string",
			VerticalScrollBarInset		= "EnumItem",
			VerticalScrollBarPosition	= "EnumItem"
		}
	},
	["Seat"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🪑",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "yes"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BasePart",	-- Use all of the properties shared by all BasePart instances.
			Shape						= "EnumItem",	-- Inherited from Part class
			Disabled					= "boolean"
		}
	},
	["Shirt"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "👕",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			ShirtTemplate				= "string",
			Color3						= "Color3"	-- Inherited from Clothing class
		}
	},
	["ShirtGraphic"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🎽",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Graphic						= "string",
			Color3						= "Color3"
		}
	},
	["Sky"]								= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌄",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			CelestialBodiesShown		= "boolean",
			MoonAngularSize				= "number",
			MoonTextureId				= "string",
			SkyboxBk					= "string",
			SkyboxDn					= "string",
			SkyboxFt					= "string",
			SkyboxLf					= "string",
			SkyboxRt					= "string",
			SkyboxUp					= "string",
			StarCount					= "number",
			SunAngularSize				= "number",
			SunTextureId				= "string"
		}
	},
	["Smoke"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "☁",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Color						= "Color3",
			Enabled						= "boolean",
			Opacity						= "number",
			RiseVelocity				= "number",
			Size						= "number",
			TimeScale					= "number"
		}
	},
	["Sparkles"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "✨",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Color						= "Color3",
			Enabled						= "boolean",
			SparkleColor				= "Color3",
			TimeScale					= "number"
		}
	},
	["SpawnLocation"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌌",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "yes"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BasePart",	-- Use all of the properties shared by all BasePart instances.
			Shape						= "EnumItem",	-- Inherited from Part class
			AllowTeamChangeOnTouch		= "boolean",
			Duration					= "number",
			Enabled						= "boolean",
			Neutral						= "boolean",
			TeamColor					= "BrickColor"
		}
	},
	["SpecialMesh"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🥘",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			MeshType					= "EnumItem",
			MeshId						= "string",		-- Inherited from FileMesh
			TextureId					= "string",		-- Inherited from FileMesh
			Offset						= "Vector3",	-- Inherited from DataModelMesh
			Scale						= "Vector3",	-- Inherited from DataModelMesh
			VertexColor					= "Vector3"		-- Inherited from DataModelMesh
		}
	},
	["SpotLight"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "💡",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Light",	-- Common properties that this class shares with others.
			UseCmnList_2				= "SpotAndSurfaceLight"
		}
	},
	["SpringConstraint"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧷",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Constraint",	-- Common properties that this class shares with others.
			Coils						= "number",
			Damping						= "number",
			FreeLength					= "number",
			LimitsEnabled				= "boolean",
			MaxForce					= "number",
			MaxLength					= "number",
			MinLength					= "number",
			Radius						= "number",
			Stiffness					= "number",
			Thickness					= "number"
		}
	},
	["StringValue"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Value						= "string"
		}
	},
	["SunRaysEffect"]					= {	-- Decals' properties are reused for Textures.
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌞",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Enabled						= "boolean",	-- Inherited from PostEffect class
			Intensity					= "number",
			Spread						= "number"
		}
	},
	["SurfaceAppearance"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🏐",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "PBRMapSet",	-- Common properties that this class shares with others.
			Color						= "Color3",
			AlphaMode					= "EnumItem",
		}
	},
	["SurfaceGui"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌘",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "LayerCollector",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiBase2d",
			UseCmnList_3				= "SurfaceGuiBase",
			AlwaysOnTop					= "boolean",
			Brightness					= "number",
			CanvasSize					= "Vector2",
			ClipsDescendants			= "boolean",
			LightInfluence				= "number",
			MaxDistance					= "number",
			PixelsPerStud				= "number",
			SizingMode					= "EnumItem",
			ToolPunchThroughDistance	= "number",
			ZOffset						= "number"
		}
	},
	["SurfaceLight"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "💡",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Light",	-- Common properties that this class shares with others.
			UseCmnList_2				= "SpotAndSurfaceLight"
		}
	},
	["TextBox"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🖊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "GuiTextElement",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiObject",
			UseCmnList_3				= "GuiBase2d",
			ClearTextOnFocus			= "boolean",
			-- CursorPosition				= "number",
			MultiLine					= "boolean",
			PlaceholderColor3			= "Color3",
			PlaceholderText				= "string",
			-- SelectionStart				= "number",
			ShowNativeInput				= "boolean",
			TextEditable				= "boolean"
		}
	},
	["TextButton"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔠",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "GuiTextElement",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiButton",
			UseCmnList_3				= "GuiObject",
			UseCmnList_4				= "GuiBase2d"
		}
	},
	["TextLabel"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔠",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "GuiTextElement",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiObject",
			UseCmnList_3				= "GuiBase2d"
		}
	},
	["Texture"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "📄",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Decal",	-- Common properties that this class shares with others.
			OffsetStudsU				= "number",
			OffsetStudsV				= "number",
			StudsPerTileU				= "number",
			StudsPerTileV				= "number"
		}
	},
	["Tool"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🛠",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "child"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Model",	-- Common properties that this class shares with others.
			CanBeDropped				= "boolean",
			Enabled						= "boolean",
			Grip						= "CFrame",
			ManualActivationOnly		= "boolean",
			RequiresHandle				= "boolean",
			ToolTip						= "string",
			TextureId					= "string"	-- Inherited from BackpackItem
		}
	},
	["Trail"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🎗",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "parent"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Attachment0					= "Instance",
			Attachment1					= "Instance",
			LightInfluence				= "number",	-- Brightness is only used if LightInfluence is set to a low value.
			Brightness					= "number",
			Color						= "ColorSequence",
			Enabled						= "boolean",
			FaceCamera					= "boolean",
			Lifetime					= "number",
			LightEmission				= "number",
			MaxLength					= "number",
			MinLength					= "number",
			Texture						= "string",
			TextureLength				= "number",
			TextureMode					= "EnumItem",
			Transparency				= "number",
			WidthScale					= "NumberSequence"
		}
	},
	["TremoloSoundEffect"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "SoundEffect",	-- Common properties that this class shares with others.
			-- UseCmnList_2				= "WetDrySound",
			Depth						= "number",
			Duty						= "number",
			Frequency					= "number"
		}
	},
	["TrussPart"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "💈",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "yes"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BasePart",	-- Use all of the properties shared by all BasePart instances.
			Style						= "EnumItem"
		}
	},
	["UIAspectRatioConstraint"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⏹",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			AspectRatio					= "number",
			AspectType					= "EnumItem",
			DominantAxis				= "EnumItem"
		}
	},
	["UICorner"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⏹",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			CornerRadius				= "UDim"
		}
	},
	["UIFlexItem"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔛",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			FlexMode					= "EnumItem",
			GrowRatio					= "number",
			ItemLineAlignment			= "EnumItem",
			ShrinkRatio					= "number"
		}
	},
	["UIGradient"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🎨",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Color						= "ColorSequence",
			Enabled						= "boolean",
			Offset						= "Vector2",
			Rotation					= "number",
			Transparency				= "NumberSequence"
		}
	},
	["UIGridLayout"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⏹",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no",	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "UIGridStyleLayout",
			CellPadding					= "UDim2",
			CellSize					= "UDim2",
			FillDirectionMaxCells		= "number",
			StartCorner					= "EnumItem"
		}
	},
	["UIListLayout"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⏹",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "UIGridStyleLayout",
			HorizontalFlex				= "EnumItem",
			ItemLineAlignment			= "EnumItem",
			Padding						= "UDim",
			VerticalFlex				= "EnumItem",
			Wraps						= "boolean"
		}
	},
	["UIPadding"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "◻",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			PaddingBottom				= "UDim",
			PaddingLeft					= "UDim",
			PaddingRight				= "UDim",
			PaddingTop					= "UDim"
		}
	},
	["UIPageLayout"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⏹",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no",	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "UIGridStyleLayout",
			Animated					= "boolean",
			Circular					= "boolean",
			EasingDirection				= "EnumItem",
			EasingStyle					= "EnumItem",
			GamepadInputEnabled			= "boolean",
			Padding						= "UDim",
			ScrollWheelInputEnabled		= "boolean",
			TouchInputEnabled			= "boolean",
			TweenTime					= "number"
		}
	},
	["UIScale"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "↗",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Scale						= "number"
		}
	},
	["UISizeConstraint"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⏹",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			MaxSize						= "Vector2",
			MinSize						= "Vector2"
		}
	},
	["UIStroke"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🖇",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			ApplyStrokeMode				= "EnumItem",
			Color						= "Color3",
			Enabled						= "boolean",
			LineJoinMode				= "EnumItem",
			Thickness					= "number",
			Transparency				= "number"
		}
	},
	["UITableLayout"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⏹",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no",	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "UIGridStyleLayout",
			FillEmptySpaceColumns		= "boolean",
			FillEmptySpaceRows			= "boolean",
			MajorAxis					= "EnumItem",
			Padding						= "UDim2"
		}
	},
	["UITextSizeConstraint"]			= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "⏹",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			MaxTextSize						= "number",
			MinTextSize						= "number"
		}
	},
	["UniversalConstraint"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧷",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Constraint",	-- Common properties that this class shares with others.
			LimitsEnabled				= "boolean",
			MaxAngle					= "number",
			Radius						= "number",
			Restitution					= "number"
		}
	},
	["Vector3Value"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔢",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Value						= "Vector3"
		}
	},
	["VectorForce"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "↗",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Constraint",	-- Common properties that this class shares with others.
			ApplyAtCenterOfMass			= "boolean",
			Force						= "Vector3",
			RelativeTo					= "EnumItem"
		}
	},
	["VehicleSeat"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🚗",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "yes"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BasePart",	-- Use all of the properties shared by all BasePart instances.
			Disabled					= "boolean",
			HeadsUpDisplay				= "boolean",
			MaxSpeed					= "number",
			Torque						= "number",
			TurnSpeed					= "number"
		}
	},
	["ViewportFrame"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "📊",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "GuiObject",	-- Common properties that this class shares with others.
			UseCmnList_2				= "GuiBase2d",
			Ambient						= "Color3",
			CurrentCamera				= "Instance",
			ImageColor3					= "Color3",
			ImageTransparency			= "number",
			LightColor					= "Color3",
			LightDirection				= "Vector3"
		}
	},
	["WedgePart"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🧱",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "yes"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BasePart"	-- Use all of the properties shared by all BasePart instances.
		}
	},
	["Weld"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔗",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "JointInstance"
		}
	},
	["WeldConstraint"]					= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🔗",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= true,	-- Create an Instance of this type when testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			Enabled						= "boolean",
			Part0						= "Instance",
			Part1						= "Instance"
		}
	},
	["WorldModel"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌎",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "Model"	-- Common properties that this class shares with others.
		}
	},
	["WrapLayer"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "↔",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BaseWrap",	-- Common properties that this class shares with others.
			AutoSkin					= "EnumItem",
			BindOffset					= "CFrame",
			Enabled						= "boolean",
			Order						= "number",
			Puffiness					= "number",
			ReferenceMeshId				= "string",
			ReferenceOrigin				= "CFrame",
			ShrinkFactor				= "number"
		}
	},
	["WrapTarget"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "↔",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		},
		Props							= {		-- List of properties that should be saved or loaded to/from JSON for this instance.
			UseCmnList_1				= "BaseWrap",	-- Common properties that this class shares with others.
			Stiffness					= "number"
		}
	},
	
	-- The four Instance classes below are only ever displayed in the list, never exported or imported, so they're intentionally folder-like.
	["Workspace"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌎",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		}
	},
	["Players"]							= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "👥",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		}
	},
	["Lighting"]						= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "🌤",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		}
	},
	["ReplicatedStorage"]				= {
		ListView						= {		-- Properties that customize how this instance is displayed in the list (only used in the script).
			Icon						= "📦",	-- Emoji used to represent this instance when it's unselected.
			CreateTest					= false,	-- Don't attempt to make an Instance of this type if testing the script in Roblox Studio.
			CanView						= "no"	-- Can the camera focus on this instance?
		}
	},
}

-- A filtered list of terrain-specific materials that use terrain colors, used to index materials as numerical indices in saves.
local TerrainMaterialList	=  {
	"WoodPlanks",
	"Slate",
	"Concrete",
	"Brick",
	"Cobblestone",
	"Rock",
	"Sandstone",
	"Basalt",
	"CrackedLava",
	"Limestone",
	"Pavement",
	"Grass",
	"LeafyGrass",
	"Sand",
	"Snow",
	"Mud",
	"Ground",
	"Asphalt",
	"Salt",
	"Ice",
	"Glacier"
}

-- COLORSEQUENCE & NUMBERSEQUENCE FUNCTIONS (COPIED FROM MY PARSING UTILITY)
-- Iterates through the provided array of strings and makes sure all items can be converted into numbers.
local function ContainsOnlyNumbers(_list : {string})
	local success = false	-- Assume failure by default.

	-- Make sure the list exists, is an array, contains at least one item, and the first item is a string.
	if _list and type(_list) == "table" and #_list > 0 and type(_list[1]) == "string" then
		for _, item in _list do
			if tonumber(item) then success = true	-- if any number is found, it is treated as a "success", but if a non-number is found, this becomes false.
			else	-- Did you find something that isn't a number in the list? Stop iterating and say that this is a failure.
				print(item, "isn't a number.")
				success = false
				break
			end
		end
	end

	return success
end

-- GetSequenceType (takes array of strings and a string, returns string)
-- Does various checks on the given list of numbers (in string form) to decide if it could be a NumberSequence or ColorSequence.
local function GetSequenceType(_seq : {string}, _fallback : string) : string?
	-- A string noting what type of sequence that the passed sequence of strings is. It becomes "number" or "color" in most cases.
	-- In the event neither type is detected, the "fallback" type passed to this function is used instead.
	local GuessedType = _fallback
	local FilteredLists = {		-- Filtered versions of the "sequence" which only contain every 5th and 3rd entry, respectively, used for the last verify step.
		ColorSeq = {},
		NumberSeq = {}
	}

	-- Detection flags, used when the filtered lists are iterated through. If all numbers in a given list are zeroes, the cooresponding flag here will be TRUE.
	local IsNumberSequence = true
	local IsColorSequence = true

	-- Catch if the "list" isn't actually an array, or if the values within it somehow aren't strings. If it meets either of those criteria, reject it.
	-- Unlike in this function's origins, this returns nil instead of "none" here, which is simpler to check for (if not [variable]).
	if not ContainsOnlyNumbers(_seq) then return nil end
	if type(_seq) ~= "table" then return nil
	elseif type(_seq[1]) ~= "string" then return nil
	end

	-- Add every 3rd and 5th number to the "filtered" lists. These can be used to identify a list's type, but can't really be trusted
	-- because NumberSequences' 3rd numbers aren't always 0; Those are actually used for its "envelope" values!
	for i, value in _seq do
		if i % 3 == 0 then table.insert(FilteredLists.NumberSeq, value)	-- NumberSequences use multiples of 3 numbers.
		elseif i % 5 == 0 then table.insert(FilteredLists.ColorSeq, value)	-- ColorSequences use multiples of 5 numbers.
		end
	end

	-- Though it's really unoptimal, and shouldn't be done this way if this was, say, code for Project Magical Mary,
	-- let's check both filtered lists and see if they're filled with zeroes. If any non-zero number is found, immediately break the loop.
	-- Also, if the list doesn't contain a multiple of 3 or 5 numbers, it can't be a number or color sequence, respectively.
	if #_seq % 5 == 0 then
		for _, value in FilteredLists.ColorSeq do
			if value ~= "0" then
				IsColorSequence = false	-- This can't be a ColorSequence. Skip the rest of the list!
				break
			end
		end
	else IsColorSequence = false	-- ColorSequences always have a multiple of five numbers.
	end

	if #_seq % 3 == 0 then
		for _, value in FilteredLists.NumberSeq do
			if not tonumber(value) then	-- If this value can't be converted into a number, this can't be any kind of sequence!
				IsColorSequence = false
				IsNumberSequence = false	-- This can't be a NumberSequence. Skip the rest of the list!
				break
			elseif tonumber(value) < 0 or tonumber(value) > 1 then	-- Envelopes are within a 0-1 range inclusively.
				IsNumberSequence = false
				break
			end
		end
	else IsNumberSequence = false	-- NumberSequences always have a multiple of three numbers.
	end

	if IsNumberSequence then GuessedType = "number"
	elseif IsColorSequence then GuessedType = "color"
	end

	return GuessedType	-- Return whatever type that the sequenced was guessed to be. If it wasn't confirmed, this will use whatever the default was.
end

-- The main sequence-parsing function, ported and modified from my parsing utility! It tries to make sense of a series of numbers
-- separated by single spaces, converting it back into a ColorSequence or NumberSequence. If a sequence contains 5 colors or 3
-- numeric values, it's ambiguous, and it's vital that any valid sequence is imported as the exact type Roblox expects for a given
-- property. If the script can't tell for sure, it'll blindly assume it's the type given as the second parameter.

-- As long as nothing unexpected makes this function throw an error while executing, it will return two values (like a pcall), a
-- boolean, which is TRUE if a seqeunce was created successfully) and either a string (for errors) or the sequence, if it passes!
local function ParseSequence(_sequence : string, _type : string) : (boolean, string|ColorSequence|NumberSequence)
	-- First, see if anything actually was inputted, and if there aren't any trailing spaces.
	local SeemsValid = false	-- This is set to TRUE if the text passes these checks.
	
	if _sequence:len() > 0 then
		if _sequence:sub(1,1) ~= " " then
			if _sequence:sub(-1,-1) ~= " " then
				if _sequence:find(" ") then
					SeemsValid = true	-- Hmm, this seems like a legitimate sequence. Let's continue!
				else return false, "This isn't a number sequence. No spaces were found!"
				end
			else return false, "There was a space after the sequence of numbers (normally impossible)."
			end
		else return false, "There was a space before the sequence began (normally impossible)."
		end
	else return false, "Somehow, the sequence didn't contain any text."
	end
	
	if SeemsValid then
		-- Split the sequence into items on each space.
		local NumList = _sequence:split(" ")
		
		-- An array of keypoints, used to make the complete ColorSequence/NumberSequence at the end of this function.
		local KeypointCollection : {ColorSequenceKeypoint}|{NumberSequenceKeypoint} = {}
		-- print("Array contents:", NumList)
		if type(NumList) == "table" and #NumList > 1 then
			local DetectedType = GetSequenceType(NumList, _type)
			-- print(temp_sequenceType)
			
			-- Cool, it's a valid sequence, so parsing can begin. The detected sequence type is only checked to stop invalid sequences from passing.
			if DetectedType then
				-- Write the header section of the parser's output.
				local temp_output = ""
				local item_multiple = 3	-- During the for loop, only one every "X" items are processed.
				if _type == "color" then
					-- temp_output = "This is a ColorSequence with " .. #NumList / 5 .. " points.\u{000D}\u{000A}\u{000D}\u{000A}"
					item_multiple = 5
				-- else temp_output = "This is a NumberSequence with " .. #NumList / 3 .. " points.\u{000D}\u{000A}\u{000D}\u{000A}"
				end
				
				-- If the sequence contains 21 or more points, fail immediately with a warning. Otheerwise, proceed to parsing the string.
				if #NumList / item_multiple <= 20 then
					-- Next, advance through each item in the array, assuming that each number represents what it's meant to.
					-- For both kinds of sequences, the first value is always the "position" or "alpha" or the point on the graph in Studio.
					-- In ColorSequences, the next 3 values are the RGB components of a Color3, while there's only 1 value for NumberSequences, its numerical value.
					-- For some reason, the next number is always zero, and I don't know why Roblox added this padding between each point.
					local ZeroMissing = false	-- If a useless zero used for padding isn't found, parsing fails on the spot.
					for i = 1,	#NumList do
						if i == 1 or i % item_multiple == 1 then
							-- print("Now parsing point #", (i/item_multiple)+1, ", array index", i)
							-- temp_output = temp_output .. "POINT " .. math.floor(i / item_multiple)+1 .. "/" .. #NumList / item_multiple .. "\u{000D}\u{000A}"
							-- temp_output = temp_output .. "Position: " .. NumList[i] .. "\u{000D}\u{000A}"
							if _type == "color" then
								-- print("Color should start at index", i+1, "and its RGB values should be", NumList[i+1], NumList[i+2], "and", NumList[i+3])
								local temp_newKeypoint = ColorSequenceKeypoint.new(
									math.clamp(tonumber(NumList[i]), 0.0, 1.0),	-- Limit the "point's position"/alpha to its intended range of zero to one.
									Color3.new(tonumber(NumList[i+1]), tonumber(NumList[i+2]), tonumber(NumList[i+3]))
								)
								table.insert(KeypointCollection, temp_newKeypoint)	-- Add this keypoint to the list.
								-- temp_output = temp_output .. "Color: " .. NumList[i+1] .. ", " .. NumList[i+2] .. ", " .. NumList[i+3] ..
								-- 	"\u{000D}\u{000A}\u{000D}\u{000A}"
							else
								-- NumberSequence values are interpreted as greyscale colors, from black to white. This way, the player doesn't see empty space
								-- instead of a gradient. Values above 1 will show up as pure white.
								local temp_newKeypoint = NumberSequenceKeypoint.new(	-- Use all three values for this new keypoint.
									tonumber(NumList[i]), tonumber(NumList[i+1]), tonumber(NumList[i+2])
								)
								table.insert(KeypointCollection, temp_newKeypoint)	-- Add this keypoint to the list.
								-- If this array index is in bounds, display its contents directly, otherwise writing an error message in output.
								local temp_valueForOutput = if NumList[i+1] then NumList[i+1] else "index out of bounds (may be a malformed NumberSequence string)"
								local temp_envelopeForOutput = if NumList[i+2] then NumList[i+2] else "index out of bounds (may be a malformed NumberSequence string)"
								temp_output = temp_output .. "Value: " .. temp_valueForOutput .. "\u{000D}\u{000A}" ..
									"Envelope: " .. temp_envelopeForOutput .. "\u{000D}\u{000A}\u{000D}\u{000A}"
							end
						end
					end
					-- temp_output = temp_output .. "Parsing done by JoyfulFlowerMary's ColorSequence & NumberSequence String Parser."
					
					-- Make sure the sequence is in the correct, ascending order (in terms of time), then construct the finished sequence!
					local FinalSequence : ColorSequence|NumberSequence = nil
					if KeypointCollection and #KeypointCollection > 0 then
						table.sort(KeypointCollection, function(itemA, itemB)
							return itemA.Time < itemB.Time
						end)
						if _type == "color" then
							FinalSequence = ColorSequence.new(KeypointCollection)
						else
							FinalSequence = NumberSequence.new(KeypointCollection)
						end
					end
					
					return true, FinalSequence	-- The ColorSequence or NumberSequence was successfully converted! Let's return it.
				else	-- If the sequence contains 21 or more points, fail immediately with a warning.
					return false, "Sequence contains too many points (21+)"
				end
			elseif not ContainsOnlyNumbers(NumList) then
				return false, "A sequence included a non-numerical value."
			else
				return false, "Somehow, the sequence value saved for a property wasn't a valid sequence."
			end
		else warn("Somehow, this wasn't actually a valid sequence… What did you do?")
		end
	end
	return false, "Reached end of the parsing function without returning. (Report this to Xane, and remember to give him your capture's JSON files!)"
end

-- GetValue (takes any and string, returns varied content)
-- Interprets a given value as a specific, previously deserialized variable type, restoring it to its original, intended form.
local function GetValue(_value : any, _type : string)
	-- While the "type" argument is respected in most of this function, if the value provided is nil, it takes priority over everything else.
	if typeof(_value) == "nil"  then
		return nil	-- JSON supports nil values! It writes "null" instead of "nil".
	end
	
	-- Basic variables can be used as-is, safely.
	if _type == "boolean" or _type == "number" or _type == "string" then
		return _value
	elseif _type == "Color3" then
		return Color3.new(_value[1], _value[2], _value[3])
	elseif _type == "BrickColor" then
		return BrickColor.new(_value)
		-- TODO: Oh dear... ColorSequences and NumberSequences can't "just" be imported; Try to modify code from the ColorSequence Parsing Utility
		-- (one of my personal Roblox places/experiences) and use that here to reconstruct the ColorSequence/NumberSequence.
		-- Until this is done, the space-separated number series will always be ignored, returning a default gradient instead!
	elseif _type == "ColorSequence" then
		local success, sequence = ParseSequence(_value, "color")
		-- For some reason, every single sequence that has been included in captures using Feb 2024 builds of the script has included an unnecessary
		-- space after the sequence of numbers, which causes the parsing function to fail early. If this call fails due to an extra space, retry
		-- but with the last character excluded. If it fails at this point, there's no point trying to salvage this gradient...
		-- TODO: Check if the last character in the sequence is a space, and if it is, use string:sub(1,-2) to avoid including it in future strings.
		if not success and sequence:find("space after") then
			success, sequence = ParseSequence(_value:sub(1,-2), "color")
		end
		
		-- Did either of the previous function calls succeed? If so, use the sequence! If not, just generate an ugly placeholder and use that instead.
		if success then return sequence
		else
			warn("Xane's Model Recreator (Plugin) - Couldn't convert a ColorSequence properly!", sequence)
			return ColorSequence.new(Color3.new(1,1,1), Color3.new(0,0,0))
		end
	elseif _type == "NumberSequence" then
		-- Old captures of ParticleEmitters incorrectly save their transparency as a number, so they may fail to import if actual "sequence"
		-- handling code is added to replace these greyscale gradient placeholder "functions".
		-- Does what the comment above says happen? Note any errors that occur when importing ParticleEmitters!
		
		local success, sequence = ParseSequence(_value, "number")
		-- For some reason, every single sequence that has been included in captures using Feb 2024 builds of the script has included an unnecessary
		-- space after the sequence of numbers, which causes the parsing function to fail early. If this call fails due to an extra space, retry
		-- but with the last character excluded. If it fails at this point, there's no point trying to salvage this gradient...
		-- TODO: Check if the last character in the sequence is a space, and if it is, use string:sub(1,-2) to avoid including it in future strings.
		if not success and sequence:find("space after") then
			success, sequence = ParseSequence(_value:sub(1,-2), "number")
		end
		
		-- Did either of the previous function calls succeed? If so, use the sequence! If not, just generate an ugly placeholder and use that instead.
		if success then return sequence
		else
			warn("Xane's Model Recreator (Plugin) - Couldn't convert a NumberSequence properly!", sequence)
			return NumberSequence.new(1, 0)
		end
	elseif _type == "NumberRange" then
		return NumberRange.new(_value[1], _value[2])
	elseif _type == "UDim" then
		return UDim.new(_value[1], _value[2])
	elseif _type == "UDim2" then
		return UDim2.new(_value[1], _value[2], _value[3], _value[4])
	elseif _type == "Rect" then	-- Rects are stored as the minimum Vector2 XY values followed by their "max" counterparts. Use Rect.new([1],[2],[3],[4])!
		return Rect.new(_value[1], _value[2], _value[3], _value[4])
	elseif _type == "Font" then
		if true then	-- not _value[2] or not _value[3] then
			return Font.new(_value[1])
		else	-- If only the font family is defined, just use that. Otherwise, try to fill in the weight and style as needed.
			return Font.new(
				_value[1] or "rbxasset://fonts/families/Arimo.json",
				_value[2] or Enum.FontWeight.Regular,
				_value[3] or Enum.FontStyle.Normal
			)
		end
	elseif _type == "Vector2" then
		return Vector2.new(_value[1], _value[2])
	elseif _type == "Vector3" then
		return Vector3.new(_value[1], _value[2], _value[3])
	elseif _type == "EnumItem" then
		return Enum[_value[1]][_value[2]]
	elseif _type == "CFrame" then
		return CFrame.new(
			_value[1], _value[2], _value[3],
			_value[4], _value[5], _value[6],
			_value[7], _value[8], _value[9],
			_value[10], _value[11], _value[12]
		)
	elseif _type == "Instance" then	-- This tries to match a debug ID to its cooresponding Instance. If one isn't found, it'll return nil.
		local DebugIDMatch : Instance? = nil	-- By default, this function will return nil, but this will become an Instance if a match is found
		for i : string, v : Instance in DebugIDList do	-- Iterate through the debug ID list and try to find this instance's ID within it
			if i == _value then
				DebugIDMatch = v	-- If a match is found, return the Instance associated with the debug ID.
				break
			end
		end
		
		return DebugIDMatch	-- If this instance's debug ID wasn't found, this will store "nil" instead, which should be fine.
	elseif _type == "PhysicalProperties" then
		return PhysicalProperties.new(_value[1], _value[2], _value[3], _value[4], _value[5])
	elseif _type == "Faces" then
		return Faces.new(_value)	-- _value supposedly is a list of NormalId Enum values, which willl hopefully work here.
	end
end

-- Updates the specified setting followed by its button on the third page.
local SettingLinkInfo	= {	-- A series of dictionary entries which determine which button that a given setting affects, and its text label.
	["UseLighting"]		= {
		Button			= Page3_CheckLighting,
		Text			= "Apply saved lighting"
	},
	["UseMaterials"]	= {
		Button			= Page3_CheckMaterials,
		Text			= "Import material vars."
	},
	["AllWorkspace"]	= {
		Button			= Page3_CheckAllWorkspace,
		Text			= "Put all in workspace"
	},
	["AutoSelect"]		= {
		Button			= Page3_CheckAutoSelect,
		Text			= "Select after import"
	},
	["TerrainColors"]	= {
		Button			= Page3_CheckAutoSelect,	-- TODO: Assign the terrain setting buttons to their intended buttons once added.
		Text			= "Set colors/water properties"
	},
	["TerrainAddAir"]	= {
		Button			= Page3_CheckAutoSelect,
		Text			= "Import all (incl. air)"
	},
}
local function ChangeSetting(
	_which : "UseLighting"|"UseMaterials"|"AllWorkspace"|"AutoSelect"|"TerrainColors"|"TerrainAddAir",
	_value : boolean
)
	if IsBusy then return end	-- Don't allow this function to run during a transition.
	
	if SettingLinkInfo[_which] then
		Setting[_which] = _value

		-- Change the symbol on this setting's linked button then append its description to it.
		SettingLinkInfo[_which].Button.Text = _value and "✅ " or "❌ "
		SettingLinkInfo[_which].Button.Text ..= SettingLinkInfo[_which].Text
	else warn("Xane's Model Recreator (Plugin) - Tried to change unknown setting", _which)
	end
end

local function ResetGui()
	if IsBusy then return end	-- Don't allow this function to run during a transition.
	
	table.clear(DebugIDList)
	Header = {}	-- This really looks like it could use some optimization, but let's empty all three of the decoded JSON dictionaries.
	Header = nil
	PieceData = {}	-- PieceData isn't completely destroyed because UpdateStatus() checks its index count, which would break if it was nil'd.
	TempDataStorage = {}
	TempDataStorage = nil
	
	-- Force all settings back to their default values.
	ChangeSetting("UseLighting", false)
	ChangeSetting("UseMaterials", true)
	ChangeSetting("AllWorkspace", false)
	ChangeSetting("AutoSelect", true)
	
	-- Empty both of the input textboxes and reset the "importing" message back to its initial placeholder sentence.
	Page1_TextBox.Text = ""
	Page1_Error.Visible = false
	
	Page2_TextBox.Text = ""
	Page2_Error.Visible = false
	
	Page4_Message.Text = "Importing..."
	
	PageController:JumpTo(Page1)	-- Finally, jump back to the first page.
end
ResetGui()	-- Immediately go to the first page and wait for the user's exported header JSON structure.

-- Generates a series of colored circle emoji on the second page based on the current header and piece info entries' contents.
-- If the argument is TRUE, the first circle will always be colored yellow.
local function UpdateStatus(_highlightFirst : boolean)
	local EmojiChain = ""
	
	if Header and Header.PieceInfo and #Header.PieceInfo > 0 then
		for i = 1, #Header.PieceInfo do
			if _highlightFirst and i == 1 then
				EmojiChain ..= "🟡 "	-- Always highlight the first circle when the second page is first shown.
			elseif PieceData[i] then	-- Is this piece in the array? Color its circle green.
				EmojiChain ..= "🟢 "
			elseif not PieceData[i] and PieceData[i-1] then	-- If this is the first missing piece, use yellow to emphasize it as the current one.
				EmojiChain ..= "🟡 "
			else					-- Otherwise, if a piece is completely missing and isn't the current one, color the circle red.
				EmojiChain ..= "🔴 "
			end
		end
	else EmojiChain = "❌ ❌ ❌"
	end
	Page2_Status.Text = EmojiChain
end

-- PAGE 1 CODE (HEADER DATA)

-- The header!
Page1_TextBox.FocusLost:Connect(function(_pressedEnter)
	Page1_Error.Visible = false	-- Hide any visible error messages, just in case everything is parsed without errors.
	
	if Page1_TextBox.Text:len() > 0 then
		local success, errormsg = pcall(function()
			TempDataStorage = HttpService:JSONDecode(Page1_TextBox.Text)
		end)
		
		if success then
			print("Imported header file contents:", TempDataStorage)
			if TempDataStorage.Metadata and TempDataStorage.Metadata.Name and
				TempDataStorage.LightingProperties and TempDataStorage.LightingProperties.ClockTime and
				TempDataStorage.PieceInfo and TempDataStorage.PieceInfo[1] and TempDataStorage.PieceInfo[1].InsertLocation
			then
				Page1_TextBox.Text = "ACCEPTED! ✅"
				task.wait(PageController.TweenTime)
				Header = TempDataStorage	-- This is valid header data, so it's safe to move to the final "header" entry.
				TempDataStorage = {}	-- Wipe the temporary storage container clean, as it'll be used again on the next page.
				TempDataStorage = nil
				
				Page2_Message.Text		= "Okay! You're about to import <b> " .. Header.Metadata.Name .. ", which has <b>" ..
					#Header.PieceInfo .. "</b> pieces! Please paste each requested piece below."
				Page2_TextBoxLabel.Text	= "Piece 1/" .. #Header.PieceInfo
				UpdateStatus(true)
				PageController:JumpTo(Page2)
			elseif TempDataStorage.Data and TempDataStorage.Properties and TempDataStorage.Position then
				Page1_TextBox.Text = "ACCEPTED! ✅"
				task.wait(PageController.TweenTime)
				-- TODO: Slide to a brand new "terrain import settings" screen here, and import after the user clicks "start".
				ImportTerrain()
			else
				Page1_Error.Text = "This isn't a valid export header! Did you copy and paste text from the _header.json file?"
				Page1_Error.Visible = true
			end
			TempDataStorage = nil
		else
			Page1.Error.Text = "Couldn't parse JSON. Make sure this is a legitimate capture from the script."
			Page1_Error.Visible = true
		end
	end
end)

-- PAGE 2 CODE (PIECE INFO IMPORTING)
Page2_BackButton.MouseButton1Click:Connect(function()
	ResetGui()
end)

Page2_TextBox.FocusLost:Connect(function(_pressedEnter)
	Page2_Error.Visible = false	-- Hide any visible error messages, just in case everything is parsed without errors.

	if Page2_TextBox.Text:len() > 0 then
		local success, errormsg = pcall(function()
			TempDataStorage = HttpService:JSONDecode(Page2_TextBox.Text)
		end)
		
		if success then
			if TempDataStorage[1] and TempDataStorage[1].Name and TempDataStorage[1].ClassName then
				-- If this is a modern export that has GUID validation, make sure this piece's GUID matches with the header's before proceeding.
				if true -- not Header.PieceInfo[#PieceData].GUID or
					-- (Header.PieceInfo[#PieceData].GUID and TempDataStorage[1].GUID == Header.PieceInfo[#PieceData].GUID)
				then
					-- This is a valid piece! Append it to PieceData.
					table.insert(PieceData, TempDataStorage)
					TempDataStorage = {}	-- Wipe the temporary storage container clean, as it'll be used again on the next page.
					TempDataStorage = nil
					UpdateStatus(false)	-- Redraw the status circles displayed under the input field.
					Page2_TextBox.Text = "ACCEPTED! ✅"
					task.wait(PageController.TweenTime)
					
					-- Was that the final piece? If so, jump to the settings page. Otherwise, update the text field and await the next chunk.
					if #PieceData < #Header.PieceInfo then
						Page2_TextBoxLabel.Text = "Piece " .. #PieceData+1 .. "/" .. #Header.PieceInfo
						Page2_TextBox.Text = ""
					else
						PageController:JumpTo(Page3)
					end
				else	-- If the GUIDs don't match exactly, this piece won't be accepted, even if would be valid without this check in place.
					Page2_Error.Text = "That piece isn't the right one! Make sure you're pasting JSON data from " ..
						Header.Metadata.Name .. "_piece" .. #PieceData .. ".json and try again."
					Page2_Error.Visible = true
					Page2_TextBox.Text = "DENIED! ⛔"
					task.wait(PageController.TweenTime)
					Page2_TextBox.Text = ""
				end
			else
				Page2_Error.Text = "This isn't a valid export header! Did you copy and paste text from the _header.json file?"
				Page2_Error.Visible = true
			end
			TempDataStorage = nil
		else
			Page2.Error.Text = "Couldn't parse JSON. Make sure this is a legitimate capture from the script."
			Page2_Error.Visible = true
		end
	end
end)

-- PAGE 3 (SETTINGS)
Page3_BackButton.MouseButton1Click:Connect(function()
	ResetGui()
end)

--[[
	The top-right button advances to page 4, where the import starts! Unlike the first three pages, the meat of this plugin happens as a
	chain reaction, caused by clicking this very button! To keep the code down here neater, this redirects execution to another one above.
]]--
Page3_StartButton.MouseButton1Click:Connect(function()
	PageController:JumpTo(Page4)
	ImportAsset()
end)

Page3_CheckLighting.MouseButton1Click:Connect(		function() ChangeSetting("UseLighting", not Setting["UseLighting"]) end)
Page3_CheckMaterials.MouseButton1Click:Connect(		function() ChangeSetting("UseMaterials", not Setting["UseMaterials"]) end)
Page3_CheckAllWorkspace.MouseButton1Click:Connect(	function() ChangeSetting("AllWorkspace", not Setting["AllWorkspace"]) end)
Page3_CheckAutoSelect.MouseButton1Click:Connect(	function() ChangeSetting("AutoSelect", not Setting["AutoSelect"]) end)

-- One of the most important functions here; This creates all of the instances within an import and "recreates" them here in Studio!
local ImposterDestInfo					= {
	[4]									= {	-- The first level/index is picked depending on the number of imposter IDs.
		-- The four containers are for workspace, Players, Lighting, and ReplicatedStorage in that order.
		{
			Instance					= workspace,
			AbbrevDestName				= "workspace"
		},
		{
			Instance					= StarterGui,
			AbbrevDestName				= "players"
		},
		{
			Instance					= Lighting,
			AbbrevDestName				= "lighting"
		},
		{
			Instance					= ReplicatedStorage,
			AbbrevDestName				= "repstore"
		}
	},
	[7]									= {
		-- Later exports may add 3 more supported containers, copying Instances from PlayerGui into StarterGui instead of Players.
		-- The four containers are for workspace, Players, Lighting, and ReplicatedStorage in that order.
		{
			Instance					= workspace,
			AbbrevDestName				= "workspace"
		},
		{
			Instance					= game:GetService("Players"),
			AbbrevDestName				= "players"
		},
		{
			Instance					= Lighting,
			AbbrevDestName				= "lighting"
		},
		{
			Instance					= ReplicatedStorage,
			AbbrevDestName				= "repstore"
		},
		{
			Instance					= StarterGui,
			AbbrevDestName				= "playergui"
		},
		{
			Instance					= game:GetService("SoundService"),
			AbbrevDestName				= "sndservice"
		},
		{
			Instance					= game:GetService("StarterPack"),
			AbbrevDestName				= "startpack"
		}
	}
}

-- A small array which uses string indexes to associate the "keywords" in the dictiomnary entries above to the final "imposter" containers.
local ImposterDB						= {}

-- A list of Instance classes that should be silently replaced with Models due to Roblox's arbitrary limits on which classes scripts can create.
local InvalidClasses					= {
	"Player",
	"PlayerGui"
}
function ImportAsset()
	-- table.clear(DebugIDList)
	table.clear(ImposterDB)
	
	local currentAction	=
		ChangeHistoryService:TryBeginRecording("XMR_importAsset", "Import asset(s) from " .. (Header.Metadata.Name or "Unknown"))
	--[[
		First, create the four container imposters. Imported assets will be inserted into these, which keeps the workspace organized!
		One Model is created and any relevant metadata is used to help the user identify an import, in case they're doing a bulk operation.
		This Model is cloned to all supported containers. If only four imposter debug IDs are listed in the header, all Players-related instances
		will be put in StarterGui (which is always done at the moment).
	]]--
	Page4_Message.Text						= "Preparing to import... (Generating containers.)"
	local OuterContainer : Model?			= nil	-- In all-workspace mode, all containers are placed within ANOTHER Model in workspace.
	local initial_container_to_clone		= Instance.new("Model")
	initial_container_to_clone.Name			= Header.Metadata.Name .. "_" .. HttpService:GenerateGUID(false):sub(1,8)	-- Append 8 random digits.
	initial_container_to_clone:SetAttribute("OriginGameId", Header.Metadata.GameId)		-- Store the game's ID and place ID as attributes.
	initial_container_to_clone:SetAttribute("OriginPlaceId", Header.Metadata.PlaceId)
	initial_container_to_clone:SetAttribute("TotalPieces", #Header.PieceInfo)
	initial_container_to_clone:SetAttribute("Credit", "Imported using Xane's Asset Importer!")
	
	if Setting.AllWorkspace then
		OuterContainer						= initial_container_to_clone:Clone()
	end
	
	-- Create each "imposter" container, assigning it to the debug ID that it used in the game it came from.
	-- The variable assignment last in this loop assigns Model to its container "keyword", used if an orphan needs to be parented to container.
	for i : number,debugId : string in Header.ImposterIds do	
		local NewImposter					= initial_container_to_clone:Clone()
		if Setting.AllWorkspace then	-- In "all-workspace" mode, Models are stored within another named after export, so use container names.
			NewImposter.Name				= ImposterDestInfo[#Header.ImposterIds][i].Instance.Name
		end
		NewImposter.Parent					= OuterContainer or ImposterDestInfo[#Header.ImposterIds][i].Instance
		DebugIDList[Header.ImposterIds[i]] = NewImposter	-- Link this Instance to its intended debug ID.
		ImposterDB[ImposterDestInfo[#Header.ImposterIds][i].AbbrevDestName] = NewImposter
		
		-- If this is a legacy 4-container import, assign "playergui" to the same container as the "players" keyword.
		-- Yes, the script may use EITHER of those keywords for destinations, but only accounts for four containers. What a mistake.
		if #Header.ImposterIds == 4 and ImposterDestInfo[#Header.ImposterIds][i].AbbrevDestName == "players" then
			ImposterDB["playergui"] = NewImposter
		end
	end
	initial_container_to_clone:Destroy()	-- Destroy the template, as it's no longer needed.
	
	--[[
		Make a new MeshPart, which will temporarily hold on to all of the imported assets. This is needed for things like Attachments and
		SurfaceAppearance instances, which require this class to spawn, annoyingly. In the future, more of these temporary storage
		containers may be necessary, picked based on the instance type. (Animators and other picky instances could then be saved!)
	]]--
	
	local TempDirectory						= Instance.new("MeshPart")
	TempDirectory.Size						= Vector3.one
	TempDirectory.Anchored					= true
	TempDirectory.Name						= "Importing... Please wait."
	TempDirectory.Parent					= ReplicatedStorage
	
	-- If it's been requested for this import, go ahead and recreate any MaterialVariants that the originating game was using.
	-- Without these, meshes may look off, so that's why UseMateirals is set by default.
	if Header.MaterialVariants and #Header.MaterialVariants > 0 and Setting.UseMaterials then
		-- Create a new folder for this import's materials, to keep existing projects 
		local MatFolder						= Instance.new("Folder")
		MatFolder.Name						= Header.Metadata.Name .. "_" .. HttpService:GenerateGUID(false):sub(1,8)	-- Append 8 random digits.
		MatFolder.Parent					= MaterialService
		
		-- Add each MaterialVariant to the new folder that we just made.
		for _,material in Header.MaterialVariants do
			local temp_newMatVar			= Instance.new("MaterialVariant")
			temp_newMatVar.BaseMaterial		= GetValue(material.BaseMaterial, "EnumItem")
			temp_newMatVar.MaterialPattern	= GetValue(material.MaterialPattern, "EnumItem")
			temp_newMatVar.ColorMap			= material.ColorMap
			temp_newMatVar.NormalMap		= material.NormalMap
			temp_newMatVar.MetalnessMap		= material.MetalnessMap
			temp_newMatVar.RoughnessMap		= material.RoughnessMap
			temp_newMatVar.StudsPerTile		= material.StudsPerTile
			temp_newMatVar.Name				= material.Name
			temp_newMatVar.Parent			= MatFolder
		end
	end
	
	-- Import all Instances from every piece, dumping them all into the "messy pile" MeshPart.
	for i,piece in PieceData do
		Page4_Message.Text						= "About to begin importing piece " .. i .. "."
		for entry,inst in piece do
			Page4_Message.Text					= "Creating instance " .. entry .. "/" .. #PieceData[i] .. " from piece " .. i .. "..."
			local NewInstance					= nil
			local temp_classname				= inst.ClassName
			local temp_isforbidden : number?	= nil	-- If this instance is a Player or PlayerGui, it isn't allowed and will become a Model.
			if table.find(InvalidClasses, temp_classname) then temp_classname = "Model" end
			
			-- MeshParts must be created using InsertService:CreateMeshPartAsync().
			if temp_classname == "MeshPart" and inst.MeshId and inst.MeshId:len() > 0 then
				-- print("Piece", i, "entry", entry, "is about to create a mesh using ID", inst.MeshId)
				local success, errormsg = pcall(function()
					NewInstance					= InsertService:CreateMeshPartAsync(
						inst.MeshId,
						GetValue(inst.CollisionFidelity, "EnumItem"),
						GetValue(inst.RenderFidelity, "EnumItem")
					)
				end)
				if not success then
					warn("Xane's Model Recreator (Plugin) - Piece "..i.." entry "..entry.." tried to use an invalid mesh, "..tostring(inst.MeshId))
					NewInstance					= Instance.new(temp_classname)	-- Just create a blank MeshPart if it can't be created normally.
					NewInstance:SetAttribute("ImportFail_MeshId", inst.MeshId)	-- Write the original mesh ID in an attribute in case it helps.
				end
			else	-- For anything else, just use Instance.new() to create the necessary instances, including meshless MeshParts.
				NewInstance					= Instance.new(temp_classname)
			end

			-- Name this instance, toss it in the pile, then assign its former debug ID to it. We aren't going to setup its properties until
			-- all of the Instances exist; Some properties link Instances together, so we need a complete list of debug IDs before then.
			NewInstance.Name				= inst.Name
			NewInstance.Parent				= TempDirectory	-- TODO: Try commenting this out once Instances are parented to their intended parents.
			DebugIDList[inst.DebugId]		= NewInstance	-- Add this Instance to the debug ID array.
			PieceData[i][entry].Instance	= NewInstance	-- Also store a reference to the final Instance inside of its PieceData entry.
			
			-- If this instance had attributes set on it, restore those by applying them to this instance.
			-- This is currently disabled because the script doesn't save attributes properly; This plugin expects an attribute's entry
			-- to include an array with two items, its serialized form ([1]) then its type as a string ([2]), but for whatever reason,
			-- it's just storing the value by itself! This confusing bug caused this section to be disabled for now.
			--[[
				if PieceData[i][entry].Attributes then
					for name,data in PieceData[i][entry].Attributes do
						print("Attribute detected for" .. PieceData[i][entry].Name .. ", item " .. i)
						print("Name:", name)
						print("Value array:", data[1])
						print("Type:", data[2])
						NewInstance:SetAttribute(name, GetValue(data[1], data[2]))
					end
				end
			]]--
			
			-- Also, if it had any tags, make sure this instance is tagged in the same way.
			if PieceData[i][entry].Tags then
				for _,tag in PieceData[i][entry].Tags do
					NewInstance:AddTag(tag)
				end
			end
		end
	end
	
	-- Now that all of the Instances are here, let's give them all of their intended property values!
	local temp_value
	for i,piece in PieceData do
		-- Both of these functions are wrapped in pcalls so no errors can stop the import before it finishes (hopefully).
		local success1, errormsg1 = pcall(function()
			for entry,inst in piece do
				local success2, errormsg2 = pcall(function()
					local temp_classname				= inst.ClassName
					local temp_isforbidden : number?	= nil	-- If this instance is a Player or PlayerGui, it isn't allowed and will become a Model.
					if table.find(InvalidClasses, temp_classname) then temp_classname = "Model" end
					
					if ClassData[temp_classname] then
						Page4_Message.Text					= "Setting properties of " .. entry .. "/" .. #PieceData[i] .. " from piece " .. i .. "..."
						-- print("About to edit class", temp_classname)
						-- Any class-specific properties are set using its property list in ClassData. If a property's name starts
						-- with "UseCmnList_", a secondary list of properties is checked and added to this list.
						-- This code was copied from the script, just like that array.
						for property1 : string,type1 : string in ClassData[temp_classname].Props do
							if property1:find("UseCmnList_") then
								if CommonPropList[type1] then
									-- print("Entering a common list,", type1)
									for property2 : string, type2 : string in CommonPropList[type1] do
										-- print("Applying", property2, "type", type2)
										-- Intentionally avoid updating any properties with nil values; When in doubt, stick to the defaults.
										temp_value = GetValue(inst[property2], type2)
										if typeof(temp_value) ~= "nil" then
											inst.Instance[property2] = temp_value
										-- else warn("Ignoring "..inst.Name.."'s "..property2.." because its"..type2.." value was "..tostring(temp_value))
										end
										
									end
									-- print("That was safe. Next!")
								end
							else	-- If this is a property listed inline for this class, just try to store its value in the dictionary entry.
								-- Intentionally avoid updating any properties with nil values; When in doubt, stick to the defaults.
								temp_value = GetValue(inst[property1], type1)
								-- print(GetValue(inst[property1], type1), temp_value)
								if typeof(temp_value) ~= "nil" then
									inst.Instance[property1] = temp_value
								-- else
									-- warn("Ignoring "..inst.Name.."'s "..property1.." because its"..type1.." value was "..tostring(temp_value))
								end
							end
						end
						
						-- Finally, find this Instance's parent and move it into them. First, see if any generated Instance is its parent.
						local ParentMatch : Instance? = GetValue(inst.Parent, "Instance")
						if ParentMatch then
							inst.Instance.Parent	= ParentMatch
						elseif ImposterDB[Header.PieceInfo[i].InsertLocation] then
							-- If this is an orphan, at least try to place it in the most appropriate container.
							inst.Instance.Parent = ImposterDB[Header.PieceInfo[i].InsertLocation]
						else
							warn("Xane's Model Recreator (Plugin) - Couldn't find a parent for " .. inst.Name .. "(of piece " .. i .. "). It's removed.")
							inst.Instance:Destroy()
						end
					else
						warn("Xane's Model Recreator (Plugin) - Unknown class " ..temp_classname .. " encountered. An instance wasn't included!")
						if inst.Instance then inst.Instance:Destroy() end	-- Delete the Instance to reduce garbage buildup.
					end
				end)
				if not success2 then
					warn("Xane's Model Recreator (Plugin) - Couldn't finish creating piece "..i.." entry "..entry.." because "..errormsg2)
				end
			end
		end)
		if not success1 then
			warn("Xane's Model Recreator (Plugin) - Failed to create piece "..i.." because "..errormsg1)
		end
	end
	
	if Header.LightingProperties and Setting.UseLighting then
		Lighting.Ambient							= GetValue(Header.LightingProperties.Ambient, "Color3")
		Lighting.Brightness							= GetValue(Header.LightingProperties.Brightness, "number")
		Lighting.ColorShift_Bottom					= GetValue(Header.LightingProperties.ColorShift_Bottom, "Color3")
		Lighting.ColorShift_Top						= GetValue(Header.LightingProperties.ColorShift_Top, "Color3")
		Lighting.EnvironmentDiffuseScale			= GetValue(Header.LightingProperties.EnvironmentDiffuseScale, "number")
		Lighting.EnvironmentSpecularScale			= GetValue(Header.LightingProperties.EnvironmentSpecularScale, "number")
		Lighting.GlobalShadows						= GetValue(Header.LightingProperties.GlobalShadows, "boolean")
		Lighting.OutdoorAmbient						= GetValue(Header.LightingProperties.OutdoorAmbient, "Color3")
		Lighting.ShadowSoftness						= GetValue(Header.LightingProperties.ShadowSoftness, "number")
		Lighting.ClockTime							= GetValue(Header.LightingProperties.ClockTime, "number")
		Lighting.GeographicLatitude					= GetValue(Header.LightingProperties.GeographicLatitude, "number")
		Lighting.FogColor							= GetValue(Header.LightingProperties.FogColor, "Color3")
		Lighting.FogEnd								= GetValue(Header.LightingProperties.FogEnd, "number")
		Lighting.FogStart							= GetValue(Header.LightingProperties.FogStart, "number")
	end
	
	-- If auto selection is enabled, select the new workspace Model (imposter).
	if Setting.AutoSelect then
		Selection:Set({ImposterDB[ImposterDestInfo[#Header.ImposterIds][1].AbbrevDestName]})
	end
	
	-- Check each container too see if any Instances ewere created inside of them. If nothing's found, remove it.
	for i,destInfo in ImposterDestInfo[#Header.ImposterIds] do
		if #ImposterDB[destInfo.AbbrevDestName]:GetChildren() < 1 then ImposterDB[destInfo.AbbrevDestName]:Destroy() end
	end
	if TempDirectory then TempDirectory:Destroy() end	-- Lastly, remove the MeshPart that everything was intiially created in. It's not needed now.
	
	-- Thank the user for using this great plugin (and exploit script) then return to the first page, in case the player wants to save another one.
	Page4_Message.Text = "Finished importing "..Header.Metadata.Name.."! Thank you for using Xane's Asset Importer."
	ChangeHistoryService:FinishRecording(currentAction, Enum.FinishRecordingOperation.Commit)	-- Finalize the changes but let the user undo them.
	
	task.wait(5)
	ResetGui()
end

-- The second major function of this script, which parses through decoded terrain JSON data to rebuild it inside Roblox Studio.
function ImportTerrain()
	if Setting.TerrainColors then
		for index,material in TerrainMaterialList do
			workspace.Terrain:SetMaterialColor(
				Enum.Material[material],
				GetValue(TempDataStorage.Properties.MaterialColors[index], "Color3")
			)
		end
	end
	
	--[[
		HARDCODED VALUES 🤮 (Consider eventually supporting variable terrian capture sizes and offsets in the script!) instead
		of assuming every save is always 102x50x102 terrain voxels big.
	]]--
	local terrainPos = GetValue(TempDataStorage.Position, "Vector3")
	for x = 1, 102 do
		for y = 1, 50 do
			-- Split this Z slice's string into a list of occupancies and materials.
			local temp_relevantTerrainList = TempDataStorage.Data[x*y]:split(",")
			local temp_relevantRegions = {}	-- Pre-generate all 102 rcell locations for this slice.
			for offset = 1, 102 do
				temp_relevantRegions[offset] = Region3.new(
					(terrainPos + ((Vector3.xAxis*(x-1))*4) + ((Vector3.xAxis*(y-1))*4) * ((offset-1) * 4) - Vector3.one),
					(terrainPos + ((Vector3.xAxis*(x-1))*4) + ((Vector3.xAxis*(y-1))*4) * ((offset-1) * 4) + Vector3.one)
				):ExpandToGrid(4)
			end
			for z = 1, 102 do	-- With all of the regions calculated, generate their terrain, one cell at a time! (Unoptimized!)
				local temp_parts = temp_relevantTerrainList[z]:split("!")	-- Occupancy is [1], followed by material [2].
				
				if temp_parts[1] == 0 and temp_parts[2] == "Air" and not Setting.TerrainAddAir then print("Skipping air block.")
				else
					workspace.Terrain:WriteVoxels(temp_relevantRegions[z], 4, {{{Enum.Material[temp_parts[2]]}}}, {{{temp_parts[1]}}})
				end
				wait()
			end
		end
	end
	ResetGui()
end

print("Xane's Model Recreator (Plugin) - Main script initialized successfully!")