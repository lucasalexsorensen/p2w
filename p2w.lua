---@class p2w
local AddonName, Private = ...

----------------------------------------------
-- Configuration
----------------------------------------------

-- Exchange rate: 1 gold = 0.3 DKK
local GOLD_TO_DKK = 0.3

-- DKK display format (green colored)
local DKK_FORMAT = " |cff00ff00(%.2f kr)|r"
local DKK_FORMAT_PLAIN = "(%.2f kr)"

----------------------------------------------
-- SavedVariables
----------------------------------------------

p2wDB = p2wDB or { enabled = true }

----------------------------------------------
-- Core Conversion Functions
----------------------------------------------

---Convert copper to DKK
---@param copper number Total copper value
---@return number dkk DKK equivalent
local function copperToDKK(copper)
  local gold = copper / 10000
  return gold * GOLD_TO_DKK
end

---Format copper as DKK string (with color codes)
---@param copper number Total copper value
---@return string Formatted DKK string
local function formatDKK(copper)
  if not copper or copper == 0 then
    return ""
  end
  return string.format(DKK_FORMAT, copperToDKK(copper))
end

---Format copper as DKK string (plain, for FontStrings)
---@param copper number Total copper value
---@return string Formatted DKK string without color codes
local function formatDKKPlain(copper)
  if not copper or copper == 0 then
    return ""
  end
  return string.format(DKK_FORMAT_PLAIN, copperToDKK(copper))
end

----------------------------------------------
-- Hook: GetMoneyString
----------------------------------------------

local originalGetMoneyString = GetMoneyString
GetMoneyString = function(money, separateThousands)
  local result = originalGetMoneyString(money, separateThousands)
  if p2wDB.enabled and money and money > 0 then
    result = result .. formatDKK(money)
  end
  return result
end

----------------------------------------------
-- Hook: C_CurrencyInfo.GetCoinTextureString
----------------------------------------------

if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
  local originalGetCoinTextureString = C_CurrencyInfo.GetCoinTextureString
  C_CurrencyInfo.GetCoinTextureString = function(copper)
    local result = originalGetCoinTextureString(copper)
    if p2wDB.enabled and copper and copper > 0 then
      result = result .. formatDKK(copper)
    end
    return result
  end
end

----------------------------------------------
-- Hook: GetCoinText (fallback for older APIs)
----------------------------------------------

if GetCoinText then
  local originalGetCoinText = GetCoinText
  GetCoinText = function(money, separator)
    local result = originalGetCoinText(money, separator)
    if p2wDB.enabled and money and money > 0 then
      result = result .. formatDKK(money)
    end
    return result
  end
end

----------------------------------------------
-- Hook: MoneyFrame_Update
-- This is the main function used by SmallMoneyFrameTemplate
-- and most Blizzard money frames
----------------------------------------------

-- Store DKK labels we create for money frames
local dkkLabels = {}

---Get or create a DKK label for a money frame
---@param moneyFrame table|string The money frame or its name
---@return FontString? The DKK label
local function getOrCreateDKKLabel(moneyFrame)
  if type(moneyFrame) == "string" then
    moneyFrame = _G[moneyFrame]
  end
  if not moneyFrame then return nil end

  local frameName = moneyFrame:GetName() or tostring(moneyFrame)

  if not dkkLabels[frameName] then
    local label = moneyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", moneyFrame, "TOP", 0, 2)
    label:SetTextColor(0, 1, 0) -- Green
    dkkLabels[frameName] = label
  end

  return dkkLabels[frameName]
end

---Update DKK label for a money frame
---@param moneyFrame table|string The money frame
---@param copper number The copper amount
local function updateDKKLabel(moneyFrame, copper)
  if not p2wDB.enabled then
    local label = dkkLabels[type(moneyFrame) == "string" and moneyFrame or (moneyFrame:GetName() or tostring(moneyFrame))]
    if label then
      label:SetText("")
    end
    return
  end

  local label = getOrCreateDKKLabel(moneyFrame)
  if label and copper and copper > 0 then
    label:SetText(formatDKKPlain(copper))
  elseif label then
    label:SetText("")
  end
end

-- Hook MoneyFrame_Update if it exists
if MoneyFrame_Update then
  hooksecurefunc("MoneyFrame_Update", function(frameName, money, forceShow)
    if money then
      updateDKKLabel(frameName, money)
    end
  end)
end

----------------------------------------------
-- Hook: SetMoneyFrame (alternative update method)
----------------------------------------------

if SetMoneyFrame then
  hooksecurefunc("SetMoneyFrame", function(frameName, money, ...)
    if money then
      updateDKKLabel(frameName, money)
    end
  end)
end

----------------------------------------------
-- Chat Message Filter
----------------------------------------------

---Parse money values from chat message strings
---@param msg string Chat message containing money textures
---@return number copper Total copper value found
local function parseChatMoney(msg)
  local copper = 0

  -- Match gold: "5|TInterface\MoneyFrame\UI-GoldIcon..."
  for amount in msg:gmatch("(%d+)|TInterface\\MoneyFrame\\UI%-GoldIcon") do
    copper = copper + (tonumber(amount) or 0) * 10000
  end

  -- Match silver: "23|TInterface\MoneyFrame\UI-SilverIcon..."
  for amount in msg:gmatch("(%d+)|TInterface\\MoneyFrame\\UI%-SilverIcon") do
    copper = copper + (tonumber(amount) or 0) * 100
  end

  -- Match copper: "10|TInterface\MoneyFrame\UI-CopperIcon..."
  for amount in msg:gmatch("(%d+)|TInterface\\MoneyFrame\\UI%-CopperIcon") do
    copper = copper + (tonumber(amount) or 0)
  end

  return copper
end

---Chat filter to append DKK to money messages
---@param self table ChatFrame
---@param event string Event name
---@param msg string Message text
---@param ... any Additional message args
---@return boolean blocked Whether to block the message
---@return string? newMsg Modified message
local function chatFilter(self, event, msg, ...)
  if not p2wDB.enabled then
    return false
  end

  local copper = parseChatMoney(msg)
  if copper > 0 then
    -- Append DKK to end of message
    local newMsg = msg .. formatDKK(copper)
    return false, newMsg, ...
  end

  return false
end

-- Register for money-related chat events
ChatFrame_AddMessageEventFilter("CHAT_MSG_MONEY", chatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_LOOT", chatFilter)

----------------------------------------------
-- Tooltip Hooks
-- Hook tooltips to show DKK for item prices
----------------------------------------------

local function hookTooltipMoney()
  -- Hook SetTooltipMoney for default vendor sell prices
  -- This function creates a money frame inside the tooltip
  if SetTooltipMoney then
    hooksecurefunc("SetTooltipMoney", function(tooltipFrame, money, moneyType, prefixText, suffixText)
      if p2wDB.enabled and money and money > 0 and tooltipFrame then
        -- Add a line below showing the DKK equivalent
        tooltipFrame:AddLine(formatDKK(money), 0, 1, 0)
        tooltipFrame:Show()
      end
    end)
  end
end

----------------------------------------------
-- Auctionator Integration
-- Hook Auctionator's money formatting function
----------------------------------------------

local function hookAuctionator()
  -- Wait for Auctionator to be loaded and hook its money string function
  if Auctionator and Auctionator.Utilities and Auctionator.Utilities.CreatePaddedMoneyString then
    local originalCreatePaddedMoneyString = Auctionator.Utilities.CreatePaddedMoneyString
    Auctionator.Utilities.CreatePaddedMoneyString = function(amount)
      local result = originalCreatePaddedMoneyString(amount)
      if p2wDB.enabled and amount and amount > 0 then
        result = result .. formatDKK(amount)
      end
      return result
    end
  end
end

----------------------------------------------
-- Player Money Frame Hook
-- Shows DKK next to character's gold display
----------------------------------------------

local function hookPlayerMoney()
  -- Try to find and hook the player's money frame on the character panel
  local function tryHookFrame(frameName)
    local frame = _G[frameName]
    if frame then
      -- Create persistent DKK label
      local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      label:SetPoint("TOP", frame, "BOTTOM", 0, -2)
      label:SetTextColor(0, 1, 0)
      dkkLabels[frameName] = label

      -- Update on PLAYER_MONEY event
      local updateFrame = CreateFrame("Frame")
      updateFrame:RegisterEvent("PLAYER_MONEY")
      updateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
      updateFrame:SetScript("OnEvent", function()
        if p2wDB.enabled then
          label:SetText(formatDKKPlain(GetMoney()))
        else
          label:SetText("")
        end
      end)
    end
  end

  -- Common money frame names
  tryHookFrame("CharacterFrameMoneyFrame")
  tryHookFrame("PlayerMoneyFrame")
end

----------------------------------------------
-- Slash Commands
----------------------------------------------

SLASH_P2W1 = "/p2w"

SlashCmdList["P2W"] = function(msg)
  msg = msg:lower():trim()

  if msg == "toggle" or msg == "" then
    p2wDB.enabled = not p2wDB.enabled
    print("|cff00ff00p2w:|r " .. (p2wDB.enabled and "Enabled" or "Disabled"))
  elseif msg == "on" then
    p2wDB.enabled = true
    print("|cff00ff00p2w:|r Enabled")
  elseif msg == "off" then
    p2wDB.enabled = false
    print("|cff00ff00p2w:|r Disabled")
  elseif msg == "rate" then
    local ratePerGold = GOLD_TO_DKK
    local goldPerKrone = 1 / GOLD_TO_DKK
    print("|cff00ff00p2w:|r Exchange rate:")
    print("  1g = " .. string.format("%.2f", ratePerGold) .. " kr")
    print("  1 kr = " .. string.format("%.2f", goldPerKrone) .. "g")
  elseif msg == "test" then
    -- Test display with sample values
    print("|cff00ff00p2w Test:|r")
    print("  1g = " .. formatDKK(10000))
    print("  100g = " .. formatDKK(1000000))
    print("  1000g = " .. formatDKK(10000000))
    print("  12g 34s 56c = " .. formatDKK(123456))
  else
    print("|cff00ff00p2w Commands:|r")
    print("  /p2w - Toggle on/off")
    print("  /p2w on - Enable")
    print("  /p2w off - Disable")
    print("  /p2w rate - Show exchange rate")
    print("  /p2w test - Test DKK display")
  end
end

----------------------------------------------
-- Addon Loaded Event
----------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, addon)
  if event == "ADDON_LOADED" then
    if addon == AddonName then
      -- Initialize saved variables
      p2wDB = p2wDB or { enabled = true }
      print("|cff00ff00p2w|r v1.0.0 loaded. Type |cff88ff88/p2w|r for options.")
    elseif addon == "Auctionator" then
      -- Hook Auctionator when it loads
      hookAuctionator()
    end

  elseif event == "PLAYER_LOGIN" then
    -- Hook UI elements after login when frames exist
    hookTooltipMoney()
    hookPlayerMoney()
    -- Also try to hook Auctionator in case it loaded before us
    hookAuctionator()
    self:UnregisterEvent("PLAYER_LOGIN")
  end
end)
