pcall(function() loadstring("if getgenv().LPH_NO_VIRTUALIZE == nil then getgenv().LPH_NO_VIRTUALIZE = function(f) return f end end")() end)
pcall(function() loadstring("if getgenv().LPH_JIT == nil then getgenv().LPH_JIT = function(f) return f end end")() end)
pcall(function() loadstring("if getgenv().LPH_JIT_MAX == nil then getgenv().LPH_JIT_MAX = function(f) return f end end")() end)

if not LPS_OBFUSCATED then
    LPS_OBFUSCATED = false
    LPS_CRASH         = function() error("LPS_CRASH triggered", 2) end
    LPS_ENCRYPT       = function(v) return v end
    LPS_EQ            = function(a, b) return a == b end
    LPH_NO_VIRTUALIZE = function(f) return f end
    LPH_NO_UPVALUES   = function(f) return f end
    LPS_GET_ARGUMENTS = function(...) return {...} end
end

-- Ensure these are always defined locally if still nil
pcall(function() loadstring("if getgenv().LPH_NO_VIRTUALIZE == nil then getgenv().LPH_NO_VIRTUALIZE = function(f) return f end end")() end)
pcall(function() loadstring("if getgenv().LPH_JIT == nil then getgenv().LPH_JIT = function(f) return f end end")() end)
pcall(function() loadstring("if getgenv().LPH_JIT_MAX == nil then getgenv().LPH_JIT_MAX = function(f) return f end end")() end)

if _G._TRXReanimConns then
    for k, conn in pairs(_G._TRXReanimConns) do
        if conn then
            pcall(function() conn:Disconnect() end)
            _G._TRXReanimConns[k] = nil
        end
    end
end
if _G._ReanimRawConn then
    pcall(function() _G._ReanimRawConn:Disconnect() end)
    _G._ReanimRawConn = nil
end

pcall(function()
    settings().Physics.PhysicsEnvironmentalThrottle = Enum.EnviromentalPhysicsThrottle.Disabled
end)
pcall(function()
    settings().Physics.PhysicsEnvironmentalThrottle = Enum.EnvironmentalPhysicsThrottle.Disabled
end)

pcall(function()
    for _, child in ipairs(game:GetService("SoundService"):GetChildren()) do
        if child.Name == "TRXEmoteSound" or child.Name == "TRXClickSound" then
            child:Stop()
            child:Destroy()
        end
    end
end)

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local plr       = Players.LocalPlayer
local PlayerGui = plr:WaitForChild("PlayerGui")
local Mouse     = plr:GetMouse()

-- Helper functions for parsing JSON and table animations
function toCFrame(val)
    if typeof(val) == "CFrame" then
        return val
    elseif type(val) == "table" then
        if #val == 12 then
            return CFrame.new(table.unpack(val))
        elseif #val == 7 then
            return CFrame.new(val[1], val[2], val[3], val[4], val[5], val[6], val[7])
        elseif val.Position or val.position or val.pos or val.Orientation or val.orientation or val.rotation or val.angles or val.CFrame then
            -- Handle {CFrame: {Position: [], Orientation: []}} nested structure
            local cfData = val.CFrame or val
            local pos = cfData.Position or cfData.position or cfData.pos or val.Position or val.position or val.pos or {0,0,0}
            local ori = cfData.Orientation or cfData.orientation or cfData.rotation or cfData.angles or val.Orientation or val.orientation or val.rotation or val.angles or {0,0,0}
            
            local px, py, pz = 0, 0, 0
            if typeof(pos) == "Vector3" then
                px, py, pz = pos.X, pos.Y, pos.Z
            elseif type(pos) == "table" then
                px, py, pz = pos[1] or 0, pos[2] or 0, pos[3] or 0
            end
            
            local rx, ry, rz = 0, 0, 0
            if typeof(ori) == "Vector3" then
                rx, ry, rz = ori.X, ori.Y, ori.Z
            elseif type(ori) == "table" then
                rx, ry, rz = ori[1] or 0, ori[2] or 0, ori[3] or 0
            end
            
            return CFrame.new(px, py, pz) * CFrame.fromEulerAnglesXYZ(rx, ry, rz)
        else
            local ok, cf = pcall(function() return CFrame.new(table.unpack(val)) end)
            if ok then return cf end
        end
    end
    return nil
end

function parseTableAnimation(raw)
    if type(raw) ~= "table" then return nil end
    -- Unwrap root-object formats: {keyframes=[...]}, {Keyframes=[...]}, etc.
    local arrayRoot = raw
    if type(raw[1]) ~= "table" then
        for _, key in ipairs({"keyframes","Keyframes","animations","frames","data","Frames","KeyframeSequence","animData"}) do
            if type(raw[key]) == "table" then 
                local sub = raw[key]
                if key == "animData" and type(sub.KeyframeSequence) == "table" then
                    arrayRoot = sub.KeyframeSequence
                else
                    arrayRoot = sub
                end
                break 
            end
        end
    end
    local keyframes = {}

    -- Helper: extract bone CFrame data from a single keyframe entry
    local function extractSingleFrame(frame, key)
        if type(frame) ~= "table" then return end
        local t = frame.Time or frame.time or frame.timestamp or frame.t
        if t == nil and key then
            t = tonumber(key)
        end
        -- Look for poses/bones in multiple property names
        local posesRaw = frame.Poses or frame.poses or frame.joints or frame.bones or frame.Joints or frame.Data or frame.data
        if not posesRaw then posesRaw = frame end
        if t ~= nil and type(posesRaw) == "table" then
            local kf = {Time = tonumber(t) or 0, Data = {}}
            for boneName, boneData in pairs(posesRaw) do
                if type(boneName) == "string" and (boneName:lower() == "time" or boneName:lower() == "t") then continue end
                if type(boneData) ~= "table" and typeof(boneData) ~= "CFrame" then continue end
                -- If boneData is already a CFrame, use it directly — DO NOT index it with .CFrame
                -- (that throws "CFrame is not a valid member of CFrame")
                local rawVal
                if typeof(boneData) == "CFrame" then
                    rawVal = boneData
                else
                    -- Try to get CFrame from various property names
                    rawVal = boneData.CFrame or boneData.cframe or boneData.transform or boneData
                end
                local cf = toCFrame(rawVal)
                if cf then
                    kf.Data[boneName] = cf
                end
            end
            if next(kf.Data) then
                table.insert(keyframes, kf)
            end
        end
    end

    -- Yield every 50 keyframes so the game scheduler can breathe on large animations
    local processed = 0
    for key, frame in pairs(arrayRoot) do
        if type(frame) ~= "table" then continue end
        -- Format-2 support: if this value is an array of keyframe objects (named sequence),
        -- iterate through the sub-array instead of treating it as a single frame
        if type(frame[1]) == "table" then
            for subIdx, subFrame in ipairs(frame) do
                extractSingleFrame(subFrame, subIdx)
                processed = processed + 1
                if processed % 50 == 0 then task.wait() end
            end
        else
            extractSingleFrame(frame, key)
            processed = processed + 1
            if processed % 50 == 0 then task.wait() end
        end
    end
    if #keyframes == 0 then 
        warn("[AnimEditor] parseTableAnimation produced 0 keyframes from", #arrayRoot or 0, "input frames")
        return nil 
    end
    table.sort(keyframes, function(a, b) return a.Time < b.Time end)
    return keyframes
end

function parseJsonAnimation(content)
    local ok, raw = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok then 
        warn("[AnimEditor] JSON decode failed:", raw)
        return nil 
    end
    local result = parseTableAnimation(raw)
    if not result then
        warn("[AnimEditor] parseTableAnimation failed for JSON data. Raw structure:", typeof(raw), type(raw))
        if type(raw) == "table" then
            local keys = {}
            for k, v in pairs(raw) do table.insert(keys, tostring(k)) end
            warn("[AnimEditor] Keys in JSON:", table.concat(keys, ", "))
            if raw[1] then
                warn("[AnimEditor] First element type:", type(raw[1]))
                if type(raw[1]) == "table" then
                    local firstKeys = {}
                    for k, v in pairs(raw[1]) do table.insert(firstKeys, tostring(k)) end
                    warn("[AnimEditor] First element keys:", table.concat(firstKeys, ", "))
                end
            end
        end
    end
    return result
end

-- Load API (embedded)
local ReanimateAPI
do
    local halo = {
        services = {
            players = game:GetService("Players");
            workspace = game:GetService("Workspace");
            replicated = game:GetService("ReplicatedStorage");
            run_service = game:GetService("RunService");
            http_service = game:GetService("HttpService");
        };
        flags = {
            reanimated = false;
            switching = false;
        };
        clones = {};
        connections = {
            hb = nil;
            died = nil;
            real_char_child_removed = nil;
            character_removing = nil;
            clone_died = nil;
            clone_char_child_removed = nil;
            animation_hb = nil;
            zero_delay = nil;
            zero_delay_hrp_sync = nil;
            shiftlock_hb = nil;
        };
        real_chars = {};
        callbacks = {
            on_play = nil;
            on_stop = nil;
        };
        animation = {
            cache = {};
            constraints_cache = nil;
            state = {
                is_playing = false;
                current_url = nil;
                speed = 1.0;
                keyframes = nil;
                total_duration = 0;
                elapsed_time = 0;
            };
            original_transforms = {};
            constraints = {};
        };
    };

    local API = {};

    local get_game_ragdoll_info = function(enable)
        local place_id = game.PlaceId;
        if place_id == 15546218972 or place_id == 6884319169 or place_id == 14104248348 then
            -- Mic Up / On Tap (voice chat hangout)
            local remote = halo.services.replicated:WaitForChild("event_rag");
            return remote, {"Ball"}, false;
        elseif place_id == 5991163185 then
            local remote = halo.services.replicated.Remotes.Physics.Ragdoll;
            return remote, {}, false;
        elseif place_id == 5683833663 then
            local local_event = halo.services.replicated:WaitForChild("LocalRagdollEvent");
            return local_event, {enable}, true;
        elseif place_id == 82743296934947 then
            local remote = halo.services.replicated:WaitForChild("Ragdoll");
            return remote, {}, false;
        elseif place_id == 13416514259 then
            -- Shadow Boxing Battles - no ragdoll remote, reanimate works without it
            return nil, nil, false;
        end;
        return nil, nil, false;
    end;

    local set_model_transparency = function(model, transparency)
        if not model then return end;
        for _, part in model:GetDescendants() do
            if part:IsA("BasePart") then
                part.Transparency = transparency;
            end;
        end;
    end;

    local set_model_query = function(model, state)
        if not model then return end;
        for _, part in model:GetDescendants() do
            if part:IsA("BasePart") then
                part.CanQuery = state;
            end;
        end;
    end;

    local disable_model_collision = function(model)
        if not model then return end;
        for _, part in model:GetDescendants() do
            if part:IsA("BasePart") then
                part.CanCollide = false;
                part.CanQuery = false;
            end;
        end;
    end;

    local get_local_player = function()
        local player = halo.services.players.LocalPlayer;
        if not player then
            return "bad argument to 'get_local_player' (LocalPlayer not found; must run in a LocalScript)";
        end;
        return player;
    end;

    local get_char = function(player)
        if typeof(player) ~= "Instance" or not player:IsA("Player") then
            return ("bad argument #1 to 'get_char' (Player expected, got %s)"):format(typeof(player));
        end;
        local character = player.Character;
        if not character or not character.Parent then
            return ("Player %s has no active character."):format(player.Name);
        end;
        return character;
    end;

    local clone_char = function(model)
        if typeof(model) ~= "Instance" then
            return ("bad argument #1 to 'clone_char' (Instance expected, got %s)"):format(typeof(model));
        end;
        -- Stop all playing animation tracks on the real character first
        local realHum = model:FindFirstChildOfClass("Humanoid");
        if realHum then
            local realAnimator = realHum:FindFirstChildOfClass("Animator");
            if realAnimator then
                for _, track in ipairs(realAnimator:GetPlayingAnimationTracks()) do
                    pcall(function() track:Stop(0) end);
                end;
            end;
        end;
        local realAnimate = model:FindFirstChild("Animate");
        if realAnimate then realAnimate.Disabled = true end;

        model.Archivable = true;
        local new_clone = model:Clone();
        model.Archivable = false;
        new_clone.Name = "Reanimation";
        
        -- Pre-configure before parenting
        local animate_script = new_clone:FindFirstChild("Animate");
        if animate_script then animate_script.Disabled = true; end;
        local humanoid = new_clone:FindFirstChildOfClass("Humanoid");
        if humanoid then
            humanoid.RequiresNeck = false;
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None;
        end;
        local force_field = new_clone:FindFirstChildWhichIsA("ForceField");
        if force_field then force_field:Destroy(); end;
        -- Anchor all parts before parenting so physics doesn't run before the swap
        for _, part in ipairs(new_clone:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = true;
            end;
        end;

        new_clone.Parent = halo.services.workspace;
        return new_clone;
    end;

    local fire_remote = function(remote, is_local, ...)
        if typeof(remote) ~= "Instance" then
            return ("bad argument to 'fire_remote' (Instance expected, got %s)"):format(typeof(remote));
        end;
        if is_local then
            if not remote:IsA("BindableEvent") then
                return ("bad argument to 'fire_remote' (BindableEvent expected for local event, got %s)"):format(remote.ClassName);
            end;
            remote:Fire(...);
        else
            if not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
                return ("bad argument to 'fire_remote' (RemoteEvent or RemoteFunction expected, got %s)"):format(remote.ClassName);
            end;
            if remote:IsA("RemoteEvent") then
                remote:FireServer(...);
            else
                remote:InvokeServer(...);
            end;
        end;
    end;

    local get_animator = function(character)
        local humanoid = character:FindFirstChildOfClass("Humanoid");
        if not humanoid then return nil end;
        return humanoid:FindFirstChildOfClass("Animator");
    end;

    API.play_raw_animation = function(name, script_content, speed, force_reload)
        if not halo.flags.reanimated then
            return "Cannot play animation, not reanimated.";
        end;

        local player = get_local_player();
        if typeof(player) == "string" then return player end;

        local clone = API.get_clone(player);
        if not clone then
            return "Cannot play animation, clone character not found.";
        end;

        if halo.animation.state.is_playing and halo.animation.state.current_url == name then
            API.stop_animation();
            return;
        end;

        API.stop_animation();

        local clone_humanoid = clone:FindFirstChildOfClass("Humanoid");
        if clone_humanoid then
            local animator = clone_humanoid:FindFirstChildOfClass("Animator");
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    track:Stop();
                end;
            end;
        end;

        local clone_animate_script = clone:FindFirstChild("Animate");
        if clone_animate_script then
            clone_animate_script.Enabled = false;
        end;

        local anim = halo.animation;
        anim.state.speed = tonumber(speed) or 1.0;

        -- Check cache first to avoid loadstring lag
        local keyframe_data = (not force_reload) and anim.cache[name] or nil;
        
        if not keyframe_data then
            -- Not in cache, need to compile
            local cleaned_content = script_content:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
            if cleaned_content:match("^%s*return%s*{%s*local") then
                cleaned_content = cleaned_content:gsub("^%s*return%s*{%s*local", "local")
                local varName = cleaned_content:match("^%s*local%s+([%w_]+)%s*=")
                if varName then
                    cleaned_content = cleaned_content .. "\nreturn " .. varName
                end
            end
            local loaded_fn, err = loadstring(cleaned_content);
            if not loaded_fn then 
                return "Animation Error: Invalid script content. " .. tostring(err);
            end;

            local ok, data = pcall(function() return loaded_fn() end);
            if not ok then 
                return "Animation Error: Script failed to execute. " .. tostring(data);
            end;

            if typeof(data) ~= "table" then 
                return "Animation Error: Script did not return a table.";
            end;
            
            keyframe_data = data;
            anim.cache[name] = keyframe_data;
        end;

        local keyframes = keyframe_data[next(keyframe_data)];
        if not keyframes or type(keyframes) ~= "table" or #keyframes == 0 then
            if type(keyframe_data) == "table" then
                if keyframe_data[1] and type(keyframe_data[1]) == "table" and keyframe_data[1].Time then
                    keyframes = keyframe_data;
                else
                    keyframes = keyframe_data.Keyframes or keyframe_data.keyframes or keyframe_data.data or keyframe_data.frames;
                end
            end
            
            if not keyframes or type(keyframes) ~= "table" or #keyframes == 0 then
                return "No valid keyframes array found for animation: " .. name;
            end
        end;

        anim.state.keyframes = keyframes;

        table.clear(anim.constraints);
        table.clear(anim.original_transforms);

        -- Build constraint lookup once per clone; reuse on every subsequent play
        if not anim.constraints_cache then
            anim.constraints_cache = {};
            for _, descendant in ipairs(clone:GetDescendants()) do
                if descendant:IsA("AnimationConstraint") then
                    local attachment = descendant.Attachment1;
                    if attachment and attachment.Parent then
                        anim.constraints_cache[attachment.Parent.Name] = descendant;
                    end;
                end;
            end;
        end;
        for partName, constraint in pairs(anim.constraints_cache) do
            if constraint and constraint.Parent then
                anim.constraints[partName] = constraint;
                anim.original_transforms[constraint] = constraint.Transform;
            end;
        end;

        anim.state.is_playing = true;
        anim.state.current_url = name;
        anim.state.total_duration = keyframes[#keyframes].Time;
        if anim.state.total_duration <= 0 then 
            API.stop_animation(); 
            return;
        end;

        anim.state.elapsed_time = 0;

        if halo.callbacks.on_play then
            pcall(halo.callbacks.on_play, anim.state.current_url);
        end;

        local last_index = 1
        halo.connections.animation_hb = halo.services.run_service.PreSimulation:Connect(LPH_NO_VIRTUALIZE(function(deltaTime)
            if not anim.state.is_playing then return end;

            local animator = get_animator(clone);
            if animator and animator.EvaluationThrottled then return end;

            anim.state.elapsed_time = (anim.state.elapsed_time + (deltaTime * anim.state.speed)) % anim.state.total_duration;

            local keyframes = anim.state.keyframes
            local elapsed = anim.state.elapsed_time
            local num_keyframes = #keyframes
            local current_frame, next_frame;

            if not last_index or last_index >= num_keyframes then
                last_index = 1
            end

            if elapsed >= keyframes[last_index].Time and (last_index == num_keyframes or elapsed < keyframes[last_index + 1].Time) then
                current_frame = keyframes[last_index]
                next_frame = keyframes[last_index == num_keyframes and 1 or last_index + 1]
            elseif last_index < num_keyframes and elapsed >= keyframes[last_index + 1].Time and (last_index + 1 == num_keyframes or elapsed < keyframes[last_index + 2].Time) then
                last_index = last_index + 1
                current_frame = keyframes[last_index]
                next_frame = keyframes[last_index == num_keyframes and 1 or last_index + 1]
            else
                local low = 1
                local high = num_keyframes - 1
                local found = 1
                while low <= high do
                    local mid = math.floor((low + high) / 2)
                    if elapsed >= keyframes[mid].Time then
                        found = mid
                        low = mid + 1
                    else
                        high = mid - 1
                    end
                end
                last_index = found
                current_frame = keyframes[last_index]
                next_frame = keyframes[last_index == num_keyframes and 1 or last_index + 1]
            end

            if not current_frame then
                current_frame = keyframes[num_keyframes];
                next_frame = keyframes[1];
            end;

            local frame_duration = next_frame.Time - current_frame.Time;
            if frame_duration <= 0 then frame_duration = anim.state.total_duration end;

            local alpha = (frame_duration > 0) and (anim.state.elapsed_time - current_frame.Time) / frame_duration or 0;
            alpha = math.clamp(alpha, 0, 1);

            for partName, pose_cframe in pairs(current_frame.Data) do
                local constraint = anim.constraints[partName];
                if constraint and constraint.Parent and anim.original_transforms[constraint] then
                    local next_pose_cframe = next_frame.Data and next_frame.Data[partName];
                    local interpolated_transform;
                    if next_pose_cframe then
                        interpolated_transform = pose_cframe:Lerp(next_pose_cframe, alpha);
                    else
                        interpolated_transform = pose_cframe;
                    end;
                    constraint.Transform = interpolated_transform;
                end;
            end;
        end))
    end;

    API.stop_animation = function()
        if not halo.animation.state.is_playing then return end;

        local stopped_url = halo.animation.state.current_url;

        if halo.connections.animation_hb then
            halo.connections.animation_hb:Disconnect();
            halo.connections.animation_hb = nil;
        end;

        local player = get_local_player();
        if typeof(player) == "string" then return player end;

        local real_char = halo.real_chars[player];
        if real_char then
            for _, part in ipairs(real_char:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function()
                        part.Velocity = Vector3.zero;
                        part.RotVelocity = Vector3.zero;
                        part.AssemblyLinearVelocity = Vector3.zero;
                        part.AssemblyAngularVelocity = Vector3.zero;
                    end);
                end;
            end;
        end;

        local clone = API.get_clone(player);
        if clone then
            for _, part in ipairs(clone:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function()
                        part.Velocity = Vector3.zero;
                        part.RotVelocity = Vector3.zero;
                        part.AssemblyLinearVelocity = Vector3.zero;
                        part.AssemblyAngularVelocity = Vector3.zero;
                    end);
                end;
            end;
            for constraint, orig_transform in pairs(halo.animation.original_transforms) do
                if constraint and constraint.Parent then
                    constraint.Transform = orig_transform;
                end;
            end;
            local clone_humanoid = clone:FindFirstChildOfClass("Humanoid");
            if clone_humanoid then
                local animator = clone_humanoid:FindFirstChildOfClass("Animator");
                if animator then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        track:Stop();
                        pcall(function() track:Destroy() end)
                    end;
                end;
            end;
            local clone_animate_script = clone:FindFirstChild("Animate");
            if clone_animate_script then
                clone_animate_script.Enabled = true;
            end;
        end;

        table.clear(halo.animation.original_transforms);
        table.clear(halo.animation.constraints);
        halo.animation.state = {
            is_playing = false;
            current_url = nil;
            speed = 1.0;
            keyframes = nil;
            total_duration = 0;
            elapsed_time = 0;
        };

        if halo.callbacks.on_stop then
            pcall(halo.callbacks.on_stop, stopped_url);
        end;
    end;

    -- Lightweight stop used between state transitions — disconnects the animation
    -- heartbeat and clears state WITHOUT snapping bones back to bind pose.
    -- The next animation will overwrite the constraint transforms on its first tick.
    API.stop_animation_for_transition = function()
        if not halo.animation.state.is_playing then return end;
        local stopped_url = halo.animation.state.current_url;
        if halo.connections.animation_hb then
            halo.connections.animation_hb:Disconnect();
            halo.connections.animation_hb = nil;
        end;
        -- Do NOT restore original_transforms — leave bones in their current pose
        -- so the new animation fades in from where we are, not from T-pose.
        table.clear(halo.animation.original_transforms);
        table.clear(halo.animation.constraints);
        halo.animation.state = {
            is_playing = false;
            current_url = nil;
            speed = 1.0;
            keyframes = nil;
            total_duration = 0;
            elapsed_time = 0;
        };
        if halo.callbacks.on_stop then
            pcall(halo.callbacks.on_stop, stopped_url);
        end;
    end;

    API.reanimate = function(bool, remote, args)
        if bool ~= true and bool ~= false then
            return ("bad argument #1 to 'reanimate' (boolean expected, got %s)"):format(typeof(bool));
        end;
        local player = get_local_player();
        if typeof(player) == "string" then return player end;

        local is_local_event = false;
        if not remote then
            local game_remote, game_args, is_local = get_game_ragdoll_info(bool);
            if game_remote then
                remote = game_remote;
                args = game_args;
                is_local_event = is_local;
            end;
        end;

        if bool then
            -- Store remote/args so rebuild_clone can re-enable without needing them passed in
            halo.flags.active_remote   = remote;
            halo.flags.active_args     = args;
            halo.flags.active_is_local = is_local_event;
            -- Disconnect any previous swap watcher before registering a new one
            if halo.swap_conn then halo.swap_conn:Disconnect(); halo.swap_conn = nil; end;
            if halo.flags.reanimated then
                return "Already reanimated.";
            end;
            local real_char = get_char(player);
            if typeof(real_char) == "string" then return real_char end;
            if not real_char:FindFirstChild("Humanoid") then
                return "Real character is missing a Humanoid.";
            end;
            local real_hrp = real_char:FindFirstChild("HumanoidRootPart");
            if not real_hrp then
                return "Real character is missing a HumanoidRootPart, cannot reanimate.";
            end;

            -- Save camera state
            local camera = halo.services.workspace.CurrentCamera;
            local saved_camera_cframe = camera.CFrame;
            local saved_camera_focus = camera.Focus;

            halo.real_chars[player] = real_char;
            
            -- Safety net: destroy any stale clone left from a previous session
            local staleClone = halo.clones[player];
            if staleClone then
                pcall(function() staleClone:Destroy() end);
                halo.clones[player] = nil;
            end;

            -- Clone BEFORE hiding the real char so the clone inherits correct
            -- transparency (0) instead of inheriting the hidden state (1).
            local cloned_char = clone_char(real_char);
            if typeof(cloned_char) == "string" then return cloned_char end;
            if not cloned_char:FindFirstChild("Humanoid") then
                return "Cloned character failed to create or is missing a Humanoid.";
            end;
            halo.clones[player] = cloned_char;

            -- Single pass on real_char: hide + disable collision/query
            for _, part in ipairs(real_char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Transparency = 1;
                    part.CanCollide   = false;
                    part.CanTouch     = false;
                    part.CanQuery     = false;
                end;
            end;

            -- Single pass on clone: set visibility + disable collision/query
            for _, part in ipairs(cloned_char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false;
                    part.CanQuery   = false;
                    part.Transparency = (part.Name == "HumanoidRootPart") and 1 or 0;
                end;
            end;
            
            -- Match clone position to real character before swapping to prevent jitter
            local cloned_hrp = cloned_char:FindFirstChild("HumanoidRootPart");
            if cloned_hrp and real_hrp then
                cloned_hrp.CFrame = real_hrp.CFrame;
                cloned_hrp.Velocity = Vector3.zero;
                cloned_hrp.RotVelocity = Vector3.zero;
                -- HRP is already anchored from clone_char; just keep it that way until after the swap
            end;

            -- Pre-build part pairs once so the heartbeat never calls GetChildren/FindFirstChild
            local part_pairs = {};
            for _, p in ipairs(real_char:GetChildren()) do
                if p:IsA("BasePart") then
                    local clone_part = cloned_char:FindFirstChild(p.Name);
                    if clone_part then
                        table.insert(part_pairs, { real = p, clone = clone_part });
                    end;
                end;
            end;

            -- Stop the real humanoid from fighting us during the transition
            local real_humanoid_pre = real_char:FindFirstChildOfClass("Humanoid");
            local savedWalkSpeed, savedJumpPower = 16, 50;
            if real_humanoid_pre then
                savedWalkSpeed = real_humanoid_pre.WalkSpeed;
                savedJumpPower = real_humanoid_pre.JumpPower;
                real_humanoid_pre.WalkSpeed = 0;
                real_humanoid_pre.JumpPower = 0;
                
                -- Disable default animations on the real character to prevent animator track build-ups
                local real_animate = real_char:FindFirstChild("Animate")
                if real_animate then
                    real_animate.Enabled = false
                end
                local real_animator = real_humanoid_pre:FindFirstChildOfClass("Animator")
                if real_animator then
                    for _, track in ipairs(real_animator:GetPlayingAnimationTracks()) do
                        track:Stop()
                        pcall(function() track:Destroy() end)
                    end
                end

                -- Zero out real HRP velocity so the freeze is instant
                if real_hrp then
                    real_hrp.Velocity = Vector3.zero;
                    real_hrp.RotVelocity = Vector3.zero;
                end;
            end;
            
            -- Clone is already anchored at the real char's CFrame with correct position.
            -- Do NOT hide it — real char is already invisible, so keeping clone visible
            -- prevents the disappear flash during the character swap.
            -- set_model_transparency(cloned_char, 1) -- intentionally removed

            local originalResetOnSpawnStates = {}
            local player_gui = player:FindFirstChildWhichIsA("PlayerGui");
            if player_gui then
                for _, gui in ipairs(player_gui:GetChildren()) do
                    if gui:IsA("ScreenGui") then
                        originalResetOnSpawnStates[gui] = gui.ResetOnSpawn
                        if gui.ResetOnSpawn then
                            gui.ResetOnSpawn = false;
                        end
                    end;
                end;
            end;
            
            player.Character = cloned_char;

            -- Set camera subject explicitly to prevent engine from resetting the camera
            local clonedHum = cloned_char:FindFirstChildOfClass("Humanoid");
            if clonedHum then
                camera.CameraSubject = clonedHum;
            end;

            -- Restore camera on the very next render step (after the engine has processed the character swap)
            local restoreConn;
            restoreConn = halo.services.run_service.RenderStepped:Connect(LPH_JIT_MAX(function()
                restoreConn:Disconnect();
                camera.CFrame = saved_camera_cframe;
                camera.Focus = saved_camera_focus;
                -- Unanchor all clone parts now that the swap is complete.
                if cloned_char and cloned_char.Parent then
                    for _, part in ipairs(cloned_char:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.Anchored = false;
                        end;
                    end;
                end;
                -- Hide the real character so only the clone is visible
                if real_char and real_char.Parent then
                    set_model_transparency(real_char, 1);
                end;
                -- Restore real humanoid movement
                local rh = real_char and real_char:FindFirstChildOfClass("Humanoid");
                if rh then
                    rh.WalkSpeed = savedWalkSpeed;
                    rh.JumpPower = savedJumpPower;
                end;
                -- Re-enable real Animate script now that the swap is done
                -- (it was disabled before cloning to prevent track leaks into the clone)
                local rAnimate = real_char and real_char:FindFirstChild("Animate");
                if rAnimate then rAnimate.Disabled = false end;
                -- Restore original ResetOnSpawn states
                for gui, originalVal in pairs(originalResetOnSpawnStates) do
                    if gui and gui.Parent then
                        gui.ResetOnSpawn = originalVal
                    end
                end
            end))

            local camera = halo.services.workspace.CurrentCamera;

            pcall(function()
                settings().Physics.AllowPhysicsSimulation = true
                settings().Physics.PhysicsEnvironmentalThrottle = Enum.EnviromentalPhysicsThrottle.Disabled
            end)

            halo.connections.hb = halo.services.run_service.Heartbeat:Connect(LPH_JIT_MAX(function()
                if not real_char or not real_char.Parent or not cloned_char or not cloned_char.Parent then
                    API.reanimate(false, remote, args);
                    return;
                end;

                for _, pair in ipairs(part_pairs) do
                    local p = pair.real;
                    local clone_part = pair.clone;
                    if p.Parent and clone_part.Parent then
                        p.CFrame = clone_part.CFrame;
                        -- Do NOT copy the clone's velocity onto the ragdolled real
                        -- character. Copying it lets residual/jump velocity dump into
                        -- the loose ragdoll and fling you (worst at enable). The CFrame
                        -- sync alone is enough to keep the bodies visually aligned.
                        p.AssemblyLinearVelocity  = Vector3.zero;
                        p.AssemblyAngularVelocity = Vector3.zero;
                    end;
                end;

                if halo.animation.state.is_playing then
                    local real_hrp = real_char:FindFirstChild("HumanoidRootPart");
                    if real_hrp then
                        real_hrp.AssemblyLinearVelocity  = Vector3.zero;
                        real_hrp.AssemblyAngularVelocity = Vector3.zero;
                    end;
                end;
            end));

            -- Shift lock rotation (RenderStepped so it applies before the frame is drawn)
            halo.connections.shiftlock_hb = halo.services.run_service.RenderStepped:Connect(LPH_JIT_MAX(function()
                if not cloned_char or not cloned_char.Parent then return end;
                local cloneHRP = cloned_char:FindFirstChild("HumanoidRootPart");
                local cloneHum = cloned_char:FindFirstChild("Humanoid");
                if cloneHRP and cloneHum and camera and camera.CameraType == Enum.CameraType.Custom then
                    local isShiftLock = false;
                    pcall(function() isShiftLock = UserInputService.IsMouseLocked end);
                    if isShiftLock then
                        local camLook = camera.CFrame.LookVector;
                        local flatLook = Vector3.new(camLook.X, 0, camLook.Z);
                        if flatLook.Magnitude > 0.001 then
                            flatLook = flatLook.Unit;
                            local rightVec = Vector3.new(flatLook.Z, 0, -flatLook.X);
                            cloneHRP.CFrame = CFrame.fromMatrix(cloneHRP.Position, rightVec, Vector3.new(0, 1, 0), -flatLook);
                        end;
                    end;
                end;
            end));

            local real_humanoid = real_char.Humanoid;
            local cloned_humanoid = cloned_char.Humanoid;

            halo.connections.died = real_humanoid.Died:Connect(function()
                API.reanimate(false, remote, args);
            end);
            halo.connections.real_char_child_removed = real_char.ChildRemoved:Connect(function(child)
                if child == real_humanoid or child == real_hrp then
                    API.reanimate(false, remote, args);
                end;
            end);
            halo.connections.clone_char_child_removed = cloned_char.ChildRemoved:Connect(function(child)
                if child == cloned_humanoid then
                    API.reanimate(false, remote, args);
                end;
            end);
            halo.connections.clone_died = cloned_humanoid.Died:Connect(function()
                local current_real_humanoid = real_char and real_char:FindFirstChild("Humanoid");
                if current_real_humanoid and current_real_humanoid.Health > 0 then
                    current_real_humanoid.Health = 0;
                else
                    API.reanimate(false, remote, args);
                end;
            end);
            -- Avatar swap: disconnect first, destroy old clone, then immediately
            -- re-clone the new character so clone_char = player.Character.
            local _savedRemote = remote;
            local _savedArgs   = args;
            halo.connections.character_removing = player.CharacterRemoving:Connect(function()
                -- Disconnect all connections BEFORE destroying anything
                for key, conn in pairs(halo.connections) do
                    if conn then conn:Disconnect(); halo.connections[key] = nil; end;
                end;
                halo.flags.reanimated = false;
                -- Destroy old clone now that callbacks are gone
                local oldClone = halo.clones[player];
                if oldClone then pcall(function() oldClone:Destroy() end); halo.clones[player] = nil; end;
                halo.real_chars[player] = nil;
                -- Immediately re-enable once new character is assigned
                local reEnableConn;
                reEnableConn = player.CharacterAdded:Connect(function()
                    reEnableConn:Disconnect();
                    API.reanimate(true, _savedRemote, _savedArgs);
                end);
            end);

            halo.flags.reanimated = true;
            if remote then
                local err = fire_remote(remote, is_local_event, unpack(args or {}));
                if err then return err end;
            end;
        else
            if not halo.flags.reanimated then return end;
            API.stop_animation();
            halo.animation.constraints_cache = nil;

            local camera = halo.services.workspace.CurrentCamera;
            local saved_camera_cframe = camera.CFrame;
            local saved_camera_focus  = camera.Focus;

            if remote then
                local err = fire_remote(remote, is_local_event, unpack(args or {}));
                if err then return err end;
            end;
            for key, connection in pairs(halo.connections) do
                if connection then connection:Disconnect(); halo.connections[key] = nil; end;
            end;
            local cloned_char = halo.clones[player];
            if cloned_char then
                local clone_hrp = cloned_char:FindFirstChild("HumanoidRootPart");
                if clone_hrp then pcall(sethiddenproperty, clone_hrp, "PhysicsRepRootPart", nil); end;
            end;
            local real_char = halo.real_chars[player];

            -- Match real_char position to clone before swapping back
            if cloned_char and cloned_char.Parent and real_char and real_char.Parent then
                local clone_hrp = cloned_char:FindFirstChild("HumanoidRootPart");
                local real_hrp  = real_char:FindFirstChild("HumanoidRootPart");
                if clone_hrp and real_hrp then
                    clone_hrp.Velocity    = Vector3.zero;
                    clone_hrp.RotVelocity = Vector3.zero;
                    real_hrp.CFrame       = clone_hrp.CFrame;
                    real_hrp.Velocity     = Vector3.zero;
                    real_hrp.RotVelocity  = Vector3.zero;
                    real_hrp.Anchored     = true;
                end;
                local clone_hum = cloned_char:FindFirstChildOfClass("Humanoid");
                if clone_hum then clone_hum.WalkSpeed = 0; clone_hum.JumpPower = 0; end;
            end;

            if real_char and real_char.Parent then
                set_model_transparency(real_char, 0);
                set_model_query(real_char, true);
                for _, part in real_char:GetDescendants() do
                    if part:IsA("BasePart") then
                        part.CanCollide = true; part.CanTouch = true; part.CanQuery = true;
                    end;
                end;
                local hrp = real_char:FindFirstChild("HumanoidRootPart");
                if hrp then hrp.Transparency = 1; hrp.CanCollide = false; end;
                local originalResetOnSpawnStates2 = {};
                local player_gui = player:FindFirstChildWhichIsA("PlayerGui");
                if player_gui then
                    for _, gui in ipairs(player_gui:GetChildren()) do
                        if gui:IsA("ScreenGui") then
                            originalResetOnSpawnStates2[gui] = gui.ResetOnSpawn;
                            if gui.ResetOnSpawn then gui.ResetOnSpawn = false; end;
                        end;
                    end;
                end;
                local realHum = real_char:FindFirstChildOfClass("Humanoid");
                if realHum then camera.CameraSubject = realHum; end;
                player.Character = real_char;
                if cloned_char and cloned_char.Parent then
                    cloned_char:Destroy(); halo.clones[player] = nil;
                end;
                local restoreConn2;
                restoreConn2 = halo.services.run_service.RenderStepped:Connect(LPH_JIT_MAX(function()
                    restoreConn2:Disconnect();
                    camera.CFrame = saved_camera_cframe;
                    camera.Focus  = saved_camera_focus;
                    local real_animate = real_char and real_char:FindFirstChild("Animate");
                    if real_animate then real_animate.Enabled = true; end;
                    local rhrp = real_char and real_char:FindFirstChild("HumanoidRootPart");
                    if rhrp then rhrp.Anchored = false; end;
                    for gui, originalVal in pairs(originalResetOnSpawnStates2) do
                        if gui and gui.Parent then gui.ResetOnSpawn = originalVal; end;
                    end;
                end));
            else
                if cloned_char and cloned_char.Parent then
                    cloned_char:Destroy(); halo.clones[player] = nil;
                end;
            end;
            halo.flags.reanimated = false;
        end;
    end;

    API.play_animation = function(url, speed)
        if not halo.flags.reanimated then
            return "Cannot play animation, not reanimated.";
        end;

        local player = get_local_player();
        if typeof(player) == "string" then return player end;

        local clone = API.get_clone(player);
        if not clone then
            return "Cannot play animation, clone character not found.";
        end;

        if halo.animation.state.is_playing and halo.animation.state.current_url == url then
            API.stop_animation();
            return;
        end;

        API.stop_animation();

        local clone_humanoid = clone:FindFirstChildOfClass("Humanoid");
        if clone_humanoid then
            local animator = clone_humanoid:FindFirstChildOfClass("Animator");
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    track:Stop();
                end;
            end;
        end;

        local clone_animate_script = clone:FindFirstChild("Animate");
        if clone_animate_script then
            clone_animate_script.Enabled = false;
        end;

        local anim = halo.animation;
        anim.state.speed = tonumber(speed) or 1.0;

        local keyframe_data = anim.cache[url];
        if not keyframe_data then
            local success, response = pcall(game.HttpGet, game, url);
            if not success then return "Animation Error: Failed to fetch URL." end;

            local loaded_fn, err = loadstring(response);
            if not loaded_fn then return "Animation Error: Invalid script from URL. " .. tostring(err) end;

            local ok, data = pcall(function() return loaded_fn() end);
            if not ok then return "Animation Error: Script from URL failed to execute. " .. tostring(data) end;
            keyframe_data = data;

            if typeof(keyframe_data) ~= "table" then return "Animation Error: Script from URL did not return a table." end;

            anim.cache[url] = keyframe_data;
        end;

        local keyframes = keyframe_data[next(keyframe_data)];
        if not keyframes or #keyframes == 0 then
            return "No keyframes array found for animation URL: " .. url;
        end;

        anim.state.keyframes = keyframes;

        table.clear(anim.constraints);
        table.clear(anim.original_transforms);

        -- Build constraint lookup once per clone; reuse on every subsequent play
        if not anim.constraints_cache then
            anim.constraints_cache = {};
            for _, descendant in ipairs(clone:GetDescendants()) do
                if descendant:IsA("AnimationConstraint") then
                    local attachment = descendant.Attachment1;
                    if attachment and attachment.Parent then
                        anim.constraints_cache[attachment.Parent.Name] = descendant;
                    end;
                end;
            end;
        end;
        for partName, constraint in pairs(anim.constraints_cache) do
            if constraint and constraint.Parent then
                anim.constraints[partName] = constraint;
                anim.original_transforms[constraint] = constraint.Transform;
            end;
        end;

        anim.state.is_playing = true;
        anim.state.current_url = url;
        anim.state.total_duration = keyframes[#keyframes].Time;
        if anim.state.total_duration <= 0 then API.stop_animation(); return end;

        anim.state.elapsed_time = 0;

        if halo.callbacks.on_play then
            pcall(halo.callbacks.on_play, anim.state.current_url);
        end;

        local last_index = 1
        halo.connections.animation_hb = halo.services.run_service.PreSimulation:Connect(LPH_NO_VIRTUALIZE(function(deltaTime)
            if not anim.state.is_playing then return end;

            local animator = get_animator(clone);
            if animator and animator.EvaluationThrottled then return end;

            anim.state.elapsed_time = (anim.state.elapsed_time + (deltaTime * anim.state.speed)) % anim.state.total_duration;

            local keyframes = anim.state.keyframes
            local elapsed = anim.state.elapsed_time
            local num_keyframes = #keyframes
            local current_frame, next_frame;

            if not last_index or last_index >= num_keyframes then
                last_index = 1
            end

            if elapsed >= keyframes[last_index].Time and (last_index == num_keyframes or elapsed < keyframes[last_index + 1].Time) then
                current_frame = keyframes[last_index]
                next_frame = keyframes[last_index == num_keyframes and 1 or last_index + 1]
            elseif last_index < num_keyframes and elapsed >= keyframes[last_index + 1].Time and (last_index + 1 == num_keyframes or elapsed < keyframes[last_index + 2].Time) then
                last_index = last_index + 1
                current_frame = keyframes[last_index]
                next_frame = keyframes[last_index == num_keyframes and 1 or last_index + 1]
            else
                local low = 1
                local high = num_keyframes - 1
                local found = 1
                while low <= high do
                    local mid = math.floor((low + high) / 2)
                    if elapsed >= keyframes[mid].Time then
                        found = mid
                        low = mid + 1
                    else
                        high = mid - 1
                    end
                end
                last_index = found
                current_frame = keyframes[last_index]
                next_frame = keyframes[last_index == num_keyframes and 1 or last_index + 1]
            end

            if not current_frame then
                current_frame = keyframes[num_keyframes];
                next_frame = keyframes[1];
            end;

            local frame_duration = next_frame.Time - current_frame.Time;
            if frame_duration <= 0 then frame_duration = anim.state.total_duration end;

            local alpha = (frame_duration > 0) and (anim.state.elapsed_time - current_frame.Time) / frame_duration or 0;
            alpha = math.clamp(alpha, 0, 1);

            for partName, pose_cframe in pairs(current_frame.Data) do
                local constraint = anim.constraints[partName];
                if constraint and constraint.Parent and anim.original_transforms[constraint] then
                    local next_pose_cframe = next_frame.Data and next_frame.Data[partName];
                    local interpolated_transform;
                    if next_pose_cframe then
                        interpolated_transform = pose_cframe:Lerp(next_pose_cframe, alpha);
                    else
                        interpolated_transform = pose_cframe;
                    end;
                    constraint.Transform = interpolated_transform;
                end;
            end;
        end))
    end;

    API.set_animation_speed = function(speed)
        halo.animation.state.speed = tonumber(speed) or 1.0;
    end;

    API.on_animation_play = function(callback)
        if type(callback) == "function" then
            halo.callbacks.on_play = callback;
        end;
    end;

    API.on_animation_stop = function(callback)
        if type(callback) == "function" then
            halo.callbacks.on_stop = callback;
        end;
    end;

    API.is_animation_playing = function()
        return halo.animation.state.is_playing, halo.animation.state.current_url;
    end;

    API.is_reanimated = function()
        return halo.flags.reanimated;
    end;

    API.get_clone = function(player)
        player = player or get_local_player();
        if typeof(player) == "string" then return nil end;
        return halo.clones[player];
    end;

    API.get_real_character = function(player)
        player = player or get_local_player();
        if typeof(player) == "string" then return nil end;
        return halo.real_chars[player];
    end;

    API.seed_animation_cache = function(name, keyframe_data)
        if name then
            halo.animation.cache[name] = keyframe_data;
        end;
    end;

    API.get_animation_cache = function(name)
        return name and halo.animation.cache[name] or nil;
    end;

    API.invalidate_constraint_cache = function()
        -- Called after ApplyDescription/avatar change so the next animation
        -- rebuilds the AnimationConstraint lookup against the new geometry.
        halo.animation.constraints_cache = nil;
        table.clear(halo.animation.constraints);
        table.clear(halo.animation.original_transforms);
    end;

    -- Rebuild the clone from scratch using the current real_char appearance.
    -- Call this after avatar appearance changes (e.g. after event_modify_refresh fires).
    API.rebuild_clone = function()
        if not halo.flags.reanimated then return end;
        local player = get_local_player();
        if typeof(player) == "string" then return end;

        local savedRemote = halo.flags.active_remote;
        local savedArgs   = halo.flags.active_args;

        local old_real  = halo.real_chars[player];
        local old_clone = halo.clones[player];

        if not old_real or not old_real.Parent then return end;

        -- Stop animation and tear down all connections
        API.stop_animation();
        halo.animation.constraints_cache = nil;
        for key, conn in pairs(halo.connections) do
            if conn then conn:Disconnect(); halo.connections[key] = nil; end;
        end;

        -- Restore real_char visibility and collision
        for _, part in ipairs(old_real:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Transparency = 0;
                part.CanCollide   = true;
                part.CanTouch     = true;
                part.CanQuery     = true;
            end;
        end;
        local hrp = old_real:FindFirstChild("HumanoidRootPart");
        if hrp then hrp.Transparency = 1; hrp.CanCollide = false; hrp.Anchored = false; end;
        local real_animate = old_real:FindFirstChild("Animate");
        if real_animate then real_animate.Enabled = true; end;

        -- Point camera at real char before swap
        local camera = halo.services.workspace.CurrentCamera;
        local realHum = old_real:FindFirstChildOfClass("Humanoid");
        if realHum and camera then camera.CameraSubject = realHum; end;

        -- Restore real char as player.Character then destroy the stale clone
        player.Character = old_real;
        -- Destroy regardless of Parent (Roblox may have detached it already)
        if old_clone then
            pcall(function() old_clone:Destroy() end);
        end;
        halo.clones[player]     = nil;
        halo.real_chars[player] = nil;
        halo.flags.reanimated   = false;

        -- Brief wait for the engine to settle, then re-enable with updated appearance
        task.wait(0.2);
        API.reanimate(true, savedRemote, savedArgs);
    end;

    ReanimateAPI = API;
    _G._TRXReanimateAPI = API;
end

local CONFIG = {
    -- Basic Settings
    TITLE          = "TRX Reanim",
    VERSION        = "1.0.0",
    ANIMATIONS_URL = "https://onyxv2.lol/Animations.lua",
    FOLDER         = "TRXReanimData",
    CACHE_FOLDER   = "TRXReanimData/cache",
    
    -- Icon Asset IDs (Easy to change!)
    ICONS = {
        STAR_FILLED    = "rbxthumb://type=Asset&id=127142872239507&w=150&h=150",  -- Favorited star icon
        STAR_OUTLINE   = "rbxthumb://type=Asset&id=76957491777613&w=150&h=150",   -- Not favorited star icon
        KEYBOARD       = "rbxthumb://type=Asset&id=78118938629142&w=150&h=150",   -- Keyboard icon for unbound keys
        RESIZE_HANDLE  = "rbxassetid://90832689936120",
    },
    
    -- UI Customization (Optional - you can also edit these!)
    UI = {
        DEFAULT_WIDTH  = 360,   -- Window width
        DEFAULT_HEIGHT = 520,   -- Window height
        MIN_WIDTH      = 320,   -- Minimum window width when resizing
        MIN_HEIGHT     = 400,   -- Minimum window height when resizing
    }
}


-- Compatibility helpers for executor environments missing these globals
local function getSafeScrollingDirection(dir)
    local ok, result = pcall(function() return Enum.ScrollingDirection[dir] end)
    if ok then return result end
    return Enum.ScrollingDirection.Y
end

local function getSafeAutomaticSize()
    local ok, result = pcall(function() return Enum.AutomaticSize.Y end)
    if ok then return result end
    return nil
end


-- Clear reanimation cache on startup
pcall(function()
    local deleteFunc = delfile or delete_file
    local listFilesFunc = listfiles or list_files
    
    if deleteFunc and listFilesFunc then
        -- Clear the cache folder completely
        local okCache, cacheFiles = pcall(function()
            if listFilesFunc then return listFilesFunc("ReanimData/cache") end
            return {}
        end)
        
        if okCache and cacheFiles then
            for _, filePath in ipairs(cacheFiles) do
                pcall(deleteFunc, filePath)
            end
        end
    end
end)

pcall(function() makefolder(CONFIG.FOLDER) end)
pcall(function() makefolder(CONFIG.CACHE_FOLDER) end)

function GetCachePath(animName)
    local safeName = animName:gsub("[^%%w%%-_%%. ]", "_")
    return CONFIG.CACHE_FOLDER .. "/" .. safeName .. ".cache"
end

local RunService   = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local HttpService  = game:GetService("HttpService")

local State = {
    isReanimated   = false,
    currentSpeed   = 1.0,
    stateSpeed     = 1.0,
    selectedAnim   = nil,
    rawAnimPlaying = false,
    currentTab     = "All",
}

local rawAnimCache = _G._TRXRawAnimCache or {}
_G._TRXRawAnimCache = rawAnimCache
_G._ReanimRawAnimCache = rawAnimCache

local serializeAnimData = LPH_NO_VIRTUALIZE(function(data)
    local out = {}
    for animKey, frames in pairs(data) do
        local frameArr = {}
        for i, frame in ipairs(frames) do
            local boneData = {}
            for boneName, cf in pairs(frame.Data) do
                boneData[boneName] = {cf:GetComponents()}
            end
            frameArr[i] = { Time = frame.Time, Data = boneData }
        end
        out[animKey] = frameArr
    end
    return out
end)

local deserializeAnimData = LPH_NO_VIRTUALIZE(function(jsonData)
    local out = {}
    for animKey, frames in pairs(jsonData) do
        local frameArr = {}
        for i, frame in ipairs(frames) do
            local boneData = {}
            for boneName, nums in pairs(frame.Data) do
                boneData[boneName] = CFrame.new(table.unpack(nums))
            end
            frameArr[i] = { Time = frame.Time, Data = boneData }
        end
        out[animKey] = frameArr
    end
    return out
end)
_G._ReanimDeserializeAnimData = deserializeAnimData

local _customAnimsLoaded = false
local presetList = {}


local AnimationList      = {}
for name, url in pairs(presetList) do
    AnimationList[name] = url
end
_G._ReanimAnimationList = AnimationList
local Favorites          = {}
local Keybinds           = {}
local SpeedKeybinds      = {}
local ReverseSpeedKeybinds = {}
local listeningSpeedIdx  = nil
local listeningRevSpeedIdx = nil
local speedKeyWidgets    = {}
local revSpeedKeyWidgets = {}
local linkRevToNormal    = false
local CustomAnims        = {}
_G._ReanimCustomAnims = CustomAnims
local CustomAnimations     = {}
_G._ReanimCustomAnimations = CustomAnimations
local AnimationCache       = {}
local StateAnims         = {}

function request_get(url)
    local req = (type(request) == "function" and request) or (type(http_request) == "function" and http_request) or (type(syn) == "table" and type(syn.request) == "function" and syn.request) or (type(http) == "table" and type(http.request) == "function" and http.request)
    if req then
        local ok, res = pcall(req, {
            Url = url,
            Method = "GET",
            Headers = {
                ["User-Agent"] = "Roblox"
            },
            Timeout = 4
        })
        if ok and res and res.StatusCode == 200 then
            return res.Body
        end
    end
    local ok, res = pcall(function()
        return game:HttpGet(url, true)
    end)
    if ok and res and res ~= "" then
        return res
    end
    return nil
end

local FOLDER = "TRXReanimData"
pcall(function() makefolder(FOLDER) end)

function fpath(name) return FOLDER .. "/" .. name end

function parseLargeCustomFile(content)
    local anims = {}
    local pos = 1
    local len = #content
    while pos <= len do
        local entryPos = content:find("{%s*name%s*=", pos)
        if not entryPos then break end
        local advanced = false
        repeat
            local _, nameEnd, name = content:find('name%s*=%s*"(.-)"', entryPos)
            if not name then advanced = true; break end
            local _, _, rawStr = content:find('raw%s*=%s*(true)', nameEnd)
            local isRaw = rawStr == "true"
            local urlPos = content:find("url%s*=%s*%[", nameEnd)
            if not urlPos then advanced = true; break end
            local bracketOpen = content:find("%[", urlPos)
            if not bracketOpen then advanced = true; break end
            local eqCount = 0
            local p = bracketOpen + 1
            while content:sub(p, p) == "=" do eqCount = eqCount + 1; p = p + 1 end
            local urlStart = p + 1
            local closePattern = "%]" .. string.rep("=", eqCount) .. "%]"
            local closeS, closeE = content:find(closePattern, urlStart, true)
            if not closeS then advanced = true; break end
            local url = content:sub(urlStart, closeS - 1)
            table.insert(anims, { name = name, url = url, raw = isRaw })
            pos = closeE + 1; advanced = true
        until true
        if not advanced or pos <= entryPos then pos = entryPos + 1 end
    end
    return anims
end

local _SAVE_INLINE_MAX = 4000 -- animations larger than this are stored in their own .dat file (keeps the JSON index tiny so saving never freezes)
local _saveCustomAnimsPending = false
function SaveCustomAnims()
    _G._ReanimSaveCustomAnims = SaveCustomAnims
    if not _customAnimsLoaded then return end
    _G._ReanimCustomAnims = CustomAnims
    -- Debounce: if a save is already queued, don't queue another
    if _saveCustomAnimsPending then return end
    _saveCustomAnimsPending = true
    task.delay(0.5, function()
        _saveCustomAnimsPending = false
        task.spawn(function()
            pcall(function()
                local dataToSave = {}
                local _saveFrameStart = os.clock()
                for i, ca in ipairs(CustomAnims) do
                    local content = ca.url or ""
                    -- Already stored in one of our .dat files? Just reference it.
                    -- Never re-read or re-write it — doing that on every save (and
                    -- delete triggers a save) was the freeze.
                    local isOurFile = type(content) == "string"
                        and not content:match("^https?://")
                        and content:match("%.dat$") ~= nil
                    if isOurFile then
                        table.insert(dataToSave, {
                            name = ca.name, file = content,
                            raw = ca.raw ~= false, isJson = ca.isJson or nil
                        })
                    elseif type(content) == "string" and #content > _SAVE_INLINE_MAX then
                        -- Large inline content: externalize ONCE to a .dat file and
                        -- switch the live entry to the file ref so future saves are
                        -- cheap and never JSON-encode the big string again.
                        local safeFileName = fpath("custom_" .. ca.name:gsub("[^%w_%-]", "_") .. ".dat")
                        pcall(function() writefile(safeFileName, content) end)
                        ca.url = safeFileName
                        CustomAnimations[ca.name] = safeFileName
                        table.insert(dataToSave, {
                            name = ca.name, file = safeFileName,
                            raw = ca.raw ~= false, isJson = ca.isJson or nil
                        })
                    else
                        table.insert(dataToSave, {
                            name = ca.name, url = content,
                            raw = ca.raw ~= false, isJson = ca.isJson or nil
                        })
                    end
                    -- Yield periodically so externalizing many large animations
                    -- (e.g. a big AK import) never blocks a frame.
                    if os.clock() - _saveFrameStart >= 0.004 then
                        task.wait()
                        _saveFrameStart = os.clock()
                    end
                end
                writefile(fpath("ReanimCustomAnims.json"), HttpService:JSONEncode(dataToSave))
            end)
        end)
    end)
end

-- Helper functions for parsing JSON and table animations are defined at the top of the file.

local function autoImportAKFiles()
    if not readfile then return end
    
    -- Check if auto-import has already been done
    local autoImportFlag = fpath("ReanimAutoImportDone.txt")
    local hasAutoImported = false
    pcall(function()
        if isfile and isfile(autoImportFlag) then
            hasAutoImported = true
        elseif not isfile then
            local ok, content = pcall(readfile, autoImportFlag)
            if ok then hasAutoImported = true end
        end
    end)
    
    -- Skip auto-import if already done once
    if hasAutoImported then
        return
    end
    
    pcall(function()
        local pathsToCheck = {
            " custom_animations.json",
            "custom_animations.json",
            "workspace/ custom_animations.json",
            "workspace/custom_animations.json",
            "ak/custom_animations.json",
            "ak/ custom_animations.json",
            "../workspace/ custom_animations.json",
            "../workspace/custom_animations.json"
        }
        local raw = nil
        for _, path in ipairs(pathsToCheck) do
            local ok, content
            if isfile then
                local isF = false
                pcall(function() isF = isfile(path) end)
                if isF then ok, content = pcall(readfile, path) end
            else
                ok, content = pcall(readfile, path)
            end
            if ok and content and content ~= "" then
                raw = content
                break
            end
        end
        
        if raw then
            local cleaned = raw:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
            local ok2, data = pcall(function() return HttpService:JSONDecode(cleaned) end)
            if ok2 and type(data) == "table" then
                local kbData = {}
                local kbPaths = {
                    "animation_keybinds.json",
                    "workspace/animation_keybinds.json",
                    "ak/animation_keybinds.json",
                    "../workspace/animation_keybinds.json"
                }
                for _, path in ipairs(kbPaths) do
                    local ok, content
                    if isfile then
                        local isF = false
                        pcall(function() isF = isfile(path) end)
                        if isF then ok, content = pcall(readfile, path) end
                    else
                        ok, content = pcall(readfile, path)
                    end
                    if ok and content and content ~= "" then
                        local kbCleaned = content:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
                        local ok3, parsedKb = pcall(function() return HttpService:JSONDecode(kbCleaned) end)
                        if ok3 and type(parsedKb) == "table" then
                            kbData = parsedKb
                            break
                        end
                    end
                end

                -- Read existing custom anims from ReanimCustomAnims.json first to know what exists
                local existingAnims = {}
                local okC, rawC = pcall(readfile, fpath("ReanimCustomAnims.json"))
                local currentList = {}
                if okC and type(rawC) == "string" and rawC ~= "" then
                    local okJ, decoded = pcall(function() return HttpService:JSONDecode(rawC) end)
                    if okJ and type(decoded) == "table" then
                        currentList = decoded
                        for _, entry in ipairs(decoded) do
                            existingAnims[entry.name] = true
                        end
                    end
                end

                -- Also load existing keybinds so we don't overwrite user custom Halo binds
                local currentKeybinds = {}
                local okK, rawK = pcall(readfile, fpath("ReanimKeybinds.json"))
                if okK and type(rawK) == "string" and rawK ~= "" then
                    local okJ, decoded = pcall(function() return HttpService:JSONDecode(rawK) end)
                    if okJ and type(decoded) == "table" then
                        currentKeybinds = decoded
                    end
                end

                local didImportNew = false
                for key, val in pairs(data) do
                    local animName, animScript
                    if type(key) == "string" and type(val) == "string" then
                        animName, animScript = key, val
                    elseif type(val) == "table" then
                        animName = val.name or val.Name or val.title or val.Title or val.key or val.Key
                        animScript = val.script or val.Script or val.content or val.Content or val.code or val.Code or val.data or val.Data
                    end

                    if animName and animScript and animName ~= "" and animScript ~= "" then
                        local sanitizedName = animName:gsub("[^%w%s%-_]",""):match("^%s*(.-)%s*$")
                        if sanitizedName ~= "" and not existingAnims[sanitizedName] then
                            -- Auto-import animation
                            pcall(function() ReanimateAPI.seed_animation_cache(sanitizedName, nil) end)
                            table.insert(currentList, { name = sanitizedName, url = animScript, raw = true })
                            CustomAnimations[sanitizedName] = animScript
                            didImportNew = true

                            -- Auto-import keybind
                            local kbKey = kbData[animName] or kbData[sanitizedName]
                            if type(kbKey) == "string" then
                                local keyName = kbKey
                                if #keyName == 1 then keyName = keyName:upper() end
                                local kc = Enum.KeyCode[keyName]
                                if kc then
                                    local keybindName = "[Custom] " .. sanitizedName
                                    currentKeybinds[keybindName] = kc.Name
                                    Keybinds[keybindName] = { key = kc, btn = nil }
                                end
                            end
                        end
                    end
                end

                if didImportNew then
                    -- Save synced files to disk immediately
                    pcall(function() writefile(fpath("ReanimCustomAnims.json"), HttpService:JSONEncode(currentList)) end)
                    pcall(function() writefile(fpath("ReanimKeybinds.json"), HttpService:JSONEncode(currentKeybinds)) end)
                    -- Mark that auto-import has been completed
                    pcall(function() writefile(fpath("ReanimAutoImportDone.txt"), "1") end)
                end
            end
        end
    end)
end

function LoadCustomAnims()
    _customAnimsLoaded = true
    -- Auto-import of AK files disabled: animations the user deletes/unbinds
    -- were reappearing on every execute because the source files kept coming back.
    -- Use the "Import" button in Reanimation > Settings to import on demand.
    local anims = {}

    -- 1. Load unified JSON file ReanimCustomAnims.json first
    local okC, rawC = pcall(readfile, fpath("ReanimCustomAnims.json"))
    if okC and type(rawC) == "string" and rawC ~= "" then
        local okJ, decoded = pcall(function() return HttpService:JSONDecode(rawC) end)
        if okJ and type(decoded) == "table" then
            for _, entry in ipairs(decoded) do
                local entryUrl = entry.url
                -- File-based storage for larger animations: keep the file PATH
                -- rather than reading the (possibly large) content into memory.
                -- PlayAnimation reads + parses it on first play, and SaveCustomAnims
                -- just references the path — so loading and saving never freeze.
                if not entryUrl and entry.file then
                    local exists = false
                    pcall(function() exists = isfile and isfile(entry.file) end)
                    if exists then
                        entryUrl = entry.file
                    else
                        -- Fallback: file missing, try reading whatever is there
                        local okF, fileContent = pcall(readfile, entry.file)
                        if okF and type(fileContent) == "string" and fileContent ~= "" then
                            entryUrl = fileContent
                        end
                    end
                end
                local animEntry = { name = entry.name, url = entryUrl or "", raw = entry.raw ~= false, isJson = entry.isJson }
                -- LAZY: store the serialized animData on the entry instead of
                -- deserializing it now. Deserialization happens on first play
                -- (see prefetchCustomAnim) so opening the window never freezes.
                if entry.format == 2 and entry.animData then
                    animEntry.format = 2
                    animEntry.animData = entry.animData
                end
                table.insert(anims, animEntry)
            end
        end
    else
        -- Fallback & Migration: check index.json if unified file doesn't exist
        local okI, rawI = pcall(readfile, fpath("index.json"))
        if okI and type(rawI) == "string" and rawI ~= "" then
            local okJ, index = pcall(function() return HttpService:JSONDecode(rawI) end)
            if okJ and type(index) == "table" and #index > 0 then
                print("[Reanim] Migrating custom animations from index.json to ReanimCustomAnims.json...")
                for _, entry in ipairs(index) do
                    if entry.file then
                        local okF, src = pcall(readfile, fpath(entry.file))
                        if okF and type(src) == "string" and src ~= "" then
                            local animEntry = { name = entry.name, url = entry.url or src, raw = entry.raw ~= false }
                            table.insert(anims, animEntry)
                            if entry.format == 2 then
                                local okDec, fileData = pcall(function() return HttpService:JSONDecode(src) end)
                                if okDec and type(fileData) == "table" and fileData.animData then
                                    local okD, deserialized = pcall(deserializeAnimData, fileData.animData)
                                    if okD then
                                        rawAnimCache[animEntry.url] = { src = animEntry.url, data = deserialized }
                                    end
                                end
                            end
                        end
                    end
                end
                -- Save unified immediately to complete migration
                task.spawn(function()
                    _customAnimsLoaded = true
                    CustomAnims = anims
                    SaveCustomAnims()
                    -- Clean up old files
                    local deleteFunc = delfile or delete_file or (function(path) pcall(writefile, path, "") end)
                    for _, entry in ipairs(index) do
                        if entry.file then pcall(deleteFunc, fpath(entry.file)) end
                    end
                    pcall(deleteFunc, fpath("index.json"))
                end)
            end
        end
    end

    -- 2. Scan folder for manually placed files (skip files already loaded from ReanimCustomAnims.json)
    local listFilesFunc = listfiles or list_files
    local ok, files = pcall(function()
        if listFilesFunc then
            return listFilesFunc(FOLDER)
        end
        return {}
    end)
    if ok and type(files) == "table" then
        local ignored = {
            reanimfavorites = true,
            reanimkeybinds = true,
            reanimspeedkeys = true,
            reanimstates = true,
            onlineanimationscache = true,
            index = true,
            reanimreversekey = true,
            reanimreversespeed = true,
            reanimrevspeedkeys = true,
            reanimfortnitewheelkey = true,
            reanimmobilewheelbtn = true,
            reanimcustomanims = true
        }
        for _, f in ipairs(files) do
            local isLua  = f:match("%.lua$")
            local isJson = f:match("%.json$") or f:match("%.txt$")
            if (isLua or isJson) and not f:match("[Ss]ettings") and not f:match("[Cc]onfig") then
                local n = f:match("([^/\\]+)%.[%w]+$")
                if n then
                    local lowerName = n:lower()
                    if not lowerName:match("^anim_%d+$") and not ignored[lowerName] then
                        -- Check for duplicate already loaded from ReanimCustomAnims.json
                        -- FIX: Compare both raw and sanitized names to prevent AK import dupes
                        local alreadyLoaded = false
                        local sanitizedN = n:gsub("[^%w_%-]", "_")
                        for _, existing in ipairs(anims) do
                            local sanitizedExisting = existing.name:gsub("[^%w_%-]", "_")
                            if existing.name == n or sanitizedExisting == sanitizedN or sanitizedExisting == n or existing.name == sanitizedN then
                                alreadyLoaded = true
                                break
                            end
                        end
                        if not alreadyLoaded then
                            table.insert(anims, { name = n, url = f, raw = true })
                        end
                    end
                end
            end
        end
    end

    if #anims == 0 then
        local okR, raw = pcall(readfile, fpath("TRXCustom.lua"))
        if okR and type(raw) == "string" and #raw > 20 and raw ~= "return {}" then
            print("[Reanim] Migrating from ReanimCustom.lua...")
            local data = parseLargeCustomFile(raw)
            if #data > 0 then
                anims = data
                task.spawn(function()
                    _customAnimsLoaded = true
                    CustomAnims = anims
                    SaveCustomAnims()
                    pcall(function() writefile(fpath("TRXCustom.lua"), "return {}") end)
                end)
            end
        end
    end

    if #anims > 0 then
        print("[Reanim] Loaded " .. #anims .. " animations.")
        return anims
    end
    if type(_G._ReanimCustomAnims) == "table" then
        return _G._ReanimCustomAnims
    end
    return {}
end

function LoadData()
    local function safeRead(fname, default)
        local ok, v = pcall(function()
            local okR, raw = pcall(readfile, fpath(fname))
            if not okR or type(raw) ~= "string" or raw == "" then
                okR, raw = pcall(readfile, fname)
            end
            if not okR or type(raw) ~= "string" or raw == "" then return default end
            return HttpService:JSONDecode(raw)
        end)
        return (ok and type(v) == "table") and v or default
    end
    local rawFavs = safeRead("ReanimFavorites.json", {})
    Favorites = {}
    for name, _ in pairs(rawFavs) do
        Favorites[name] = true
    end
    
    CustomAnims = LoadCustomAnims()
    _G._ReanimCustomAnims = CustomAnims
    for _, ca in ipairs(CustomAnims) do
        CustomAnimations[ca.name] = ca.url
    end
    
    -- Update Custom tab count after loading animations
    task.defer(function()
        if UpdateCustomTabCount then
            UpdateCustomTabCount()
        end
    end)
    StateAnims  = safeRead("ReanimStates.json", {})
    for k, v in pairs(StateAnims) do
        if type(v) == "string" then StateAnims[k] = { url = v, raw = false } end
    end
    local rawBinds = safeRead("ReanimKeybinds.json", {})
    Keybinds = {}
    for name, keyData in pairs(rawBinds) do
        local keyName
        if type(keyData) == "table" and keyData.key then
            keyName = keyData.key
        elseif type(keyData) == "string" then
            keyName = keyData
        end
        if keyName then
            local ok, kc = pcall(function() return Enum.KeyCode[keyName] end)
            if ok and kc then Keybinds[name] = { key = kc, btn = nil } end
        end
    end
    -- Try to load from old reanimation location if no keybinds found
    if next(Keybinds) == nil then
        local okOld, oldBinds = pcall(readfile, "keybinds.json")
        if okOld and type(oldBinds) == "string" and oldBinds ~= "" then
            local okDecode, decoded = pcall(function() return HttpService:JSONDecode(oldBinds) end)
            if okDecode and type(decoded) == "table" then
                for name, keyName in pairs(decoded) do
                    local ok, kc = pcall(function() return Enum.KeyCode[keyName] end)
                    if ok and kc then Keybinds[name] = { key = kc, btn = nil } end
                end
            end
        end
    end
    pcall(function()
        local ok, keyName = pcall(readfile, fpath("ReanimReverseKey.txt"))
        if not ok or not keyName or keyName == "" then
            ok, keyName = pcall(readfile, "ReanimReverseKey.txt")
        end
        if ok and keyName and keyName ~= "" then
            -- Some executors append a trailing newline / whitespace when
            -- writing a text file. Trim it before looking up the KeyCode,
            -- otherwise Enum.KeyCode["F\n"] returns nil and the rewind key
            -- silently stops working.
            keyName = keyName:match("^%s*(.-)%s*$")
            if keyName and keyName ~= "" then
                local ok4, kc = pcall(function() return Enum.KeyCode[keyName] end)
                if ok4 and kc then GlobalReverseKeybind = kc end
            end
        end
        local ok2, speedVal = pcall(readfile, fpath("ReanimReverseSpeed.txt"))
        if not ok2 or not speedVal or speedVal == "" then
            ok2, speedVal = pcall(readfile, "ReanimReverseSpeed.txt")
        end
        if ok2 and speedVal and speedVal ~= "" then
            GlobalReverseSpeed = tonumber((speedVal:match("^%s*(.-)%s*$"))) or GlobalReverseSpeed or 1.0
        end
        local ok3, rawWheel = pcall(readfile, fpath("ReanimFortniteWheelKey.json"))
        if not ok3 or not rawWheel or rawWheel == "" then
            ok3, rawWheel = pcall(readfile, "ReanimFortniteWheelKey.json")
        end
        if ok3 and rawWheel and rawWheel ~= "" then
            local data = HttpService:JSONDecode(rawWheel)
            if data and data.key then
                _G._FortniteWheelKey = Enum.KeyCode[data.key]
            end
        end
    end)
    local rawSK = safeRead("ReanimSpeedKeys.json", {})
    for i = 1, 6 do
        local s = rawSK[i] or {}
        local kc = nil
        if s.key then pcall(function() kc = Enum.KeyCode[s.key] end) end
        SpeedKeybinds[i] = { speed = tonumber(s.speed) or (i * 0.5), key = kc, btn = nil }
    end
    local rawRSK = safeRead("ReanimRevSpeedKeys.json", {})
    for i = 1, 6 do
        local s = rawRSK[i] or {}
        local kc = nil
        if s.key then pcall(function() kc = Enum.KeyCode[s.key] end) end
        ReverseSpeedKeybinds[i] = { speed = tonumber(s.speed) or (i * 0.5), key = kc, btn = nil }
    end
    if rawRSK.linkToNormal ~= nil then linkRevToNormal = rawRSK.linkToNormal == true end
end

function _rawSaveFavorites()
    local toSave = {}
    for name, _ in pairs(Favorites) do toSave[name] = true end
    pcall(function() writefile(fpath("ReanimFavorites.json"), HttpService:JSONEncode(toSave)) end)
end

local _saveFavPending = false
function SaveFavoritesOnly()
    if _saveFavPending then return end
    _saveFavPending = true
    task.delay(0.3, function()
        _saveFavPending = false
        _rawSaveFavorites()
    end)
end

function _rawSaveKeybinds()
    local toSave = {}
    for name, data in pairs(Keybinds) do
        if data.key then toSave[name] = data.key.Name end
    end
    pcall(function() writefile(fpath("ReanimKeybinds.json"), HttpService:JSONEncode(toSave)) end)
end

local _saveKbPending = false
function SaveKeybindsOnly()
    if _saveKbPending then return end
    _saveKbPending = true
    task.delay(0.3, function()
        _saveKbPending = false
        _rawSaveKeybinds()
    end)
end

local _saveDataPending = false
function SaveData()
    _rawSaveFavorites()
    _rawSaveKeybinds()
    -- Run all blocking writefile calls off the main thread
    task.spawn(function()
        pcall(function() writefile(fpath("ReanimStates.json"), HttpService:JSONEncode(StateAnims)) end)
        local skSave = {}
        for i = 1, 6 do
            local s = SpeedKeybinds[i] or {}
            skSave[i] = { speed = s.speed, key = s.key and s.key.Name or nil }
        end
        pcall(function() writefile(fpath("ReanimSpeedKeys.json"), HttpService:JSONEncode(skSave)) end)
        local rskSave = { linkToNormal = linkRevToNormal }
        for i = 1, 6 do
            local s = ReverseSpeedKeybinds[i] or {}
            rskSave[i] = { speed = s.speed, key = s.key and s.key.Name or nil }
        end
        pcall(function() writefile(fpath("ReanimRevSpeedKeys.json"), HttpService:JSONEncode(rskSave)) end)
        pcall(function()
            if GlobalReverseKeybind then
                writefile(fpath("ReanimReverseKey.txt"), GlobalReverseKeybind.Name)
            else
                local deleteFunc = delfile or delete_file or (function(p) pcall(writefile, p, "") end)
                pcall(deleteFunc, fpath("ReanimReverseKey.txt"))
            end
            writefile(fpath("ReanimReverseSpeed.txt"), tostring(GlobalReverseSpeed))
            if _G._FortniteWheelKey then
                writefile(fpath("ReanimFortniteWheelKey.json"), HttpService:JSONEncode({key = _G._FortniteWheelKey.Name}))
            end
        end)
    end)
end

LoadData()
_customAnimsLoaded = true

function prefetchCustomAnim(ca)
    if not ca then return end
    local src = ca.url
    if not src or src == "" then return end
    if rawAnimCache[src] then return end

    -- Format-2 entries carry pre-serialized animData; deserialize lazily here
    -- (this was previously done eagerly in LoadCustomAnims and froze the game on open)
    if ca.format == 2 and ca.animData then
        task.spawn(function()
            local okD, deserialized = pcall(deserializeAnimData, ca.animData)
            if okD and type(deserialized) == "table" then
                rawAnimCache[src] = { src = src, data = deserialized }
                ca.format = nil
                ca.animData = nil
            end
        end)
        return
    end

    if not ca.raw then return end
    task.spawn(function()
        local cleaned = src:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
        local firstChar = cleaned:match("^%s*(.)")
        -- Try JSON parsing first
        if firstChar == "{" or firstChar == "[" then
            local parsed = parseJsonAnimation(cleaned)
            if parsed then
                rawAnimCache[src] = { src = src, data = parsed, isJson = true }
                return
            end
        end
        local fn = loadstring(cleaned)
        if not fn then return end
        local ok, data = pcall(fn)
        if not ok or type(data) ~= "table" then return end
        rawAnimCache[src] = { src = src, data = data }
        ca.format = nil
    end)
end

function prefetchAllCustomAnims()
    task.spawn(function()
        for _, ca in ipairs(CustomAnims) do
            prefetchCustomAnim(ca)
            task.wait()
        end
    end)
end

-- Disabled automatic prefetching to reduce lag on startup
-- task.delay(0.5, prefetchAllCustomAnims)

local stopStateSystem
local startStateSystem
local prefetchStateAnim
local prefetchAllStates
local stateSystemActive = false
local listeningKeyBtn   = nil
local listenTarget      = nil
local isDraggingSpeed   = false
function new(cls, parent, props)
    local obj = Instance.new(cls)
    if parent then obj.Parent = parent end
    if props then
        for k, v in pairs(props) do
            pcall(function() obj[k] = v end)
        end
    end
    return obj
end

function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = parent
    return c
end

function stroke(parent, col, thick, trans)
    local ok, s = pcall(function() return Instance.new("UIStroke") end)
    if not ok then return nil end
    s.Color = col or Color3.fromRGB(60, 50, 90)
    s.Thickness = thick or 1
    s.Transparency = trans or 0
    s.Parent = parent
    return s
end

function tw(obj, t, props, style, dir)
    local filteredProps = {}
    for k, v in pairs(props) do
        local ok = pcall(function() return obj[k] end)
        if ok then
            filteredProps[k] = v
        end
    end
    return game:GetService("TweenService"):Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), filteredProps)
end

local C = {
    bg0         = Color3.fromRGB(10, 10, 14),     -- Main frame background (deep slate)
    bg1         = Color3.fromRGB(18, 18, 24),     -- Header and cards background
    bg2         = Color3.fromRGB(26, 26, 34),     -- Playable lists / list elements
    bg3         = Color3.fromRGB(34, 34, 44),     -- Speed inputs / sliders background
    border      = Color3.fromRGB(50, 50, 65),     -- Inner frame outlines
    glassBorder = Color3.fromRGB(60, 80, 140),    -- Outer glow/border (soft indigo)
    text        = Color3.fromRGB(245, 245, 250),  -- White body text
    text2       = Color3.fromRGB(180, 180, 200),  -- Light gray text
    text3       = Color3.fromRGB(110, 110, 130),  -- Dim gray text
    accent      = Color3.fromRGB(88, 101, 242),   -- Main accent (modern indigo)
    bg4         = Color3.fromRGB(20, 20, 28),     -- Toggle backgrounds
    red         = Color3.fromRGB(237, 66, 69),    -- Close dot
    yellow      = Color3.fromRGB(88, 101, 242),   -- Minimize dot / Favs (indigo)
    green       = Color3.fromRGB(59, 165, 93),    -- Success / Active (green)
    white       = Color3.fromRGB(255, 255, 255),  -- Pure white
}

local ScreenGui, Menu, body, NowPlayingLabel, StopBtn, TabButtons, SearchBox, hintLbl, AnimListFrame, StatesPanel, CustomPanel, customSearchBox, customOpenModalBtn, customListFrame, SettingsPanel, SpeedPanel, SetTabActive, updateFnWheelBtnText, updateRevBtnText, revFill, revHandle, revSpdLbl, Notify, _screenGuiTarget
do
ScreenGui = Instance.new("ScreenGui")

ScreenGui.Name           = "TRXReanimMenu"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true

_screenGuiTarget = nil
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local PlayerGui = localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui")
do
    -- Use PlayerGui instead of CoreGui — CoreGui ScreenGuis intercept all input
    -- before the game world even when no Active=true is set on child frames.
    _screenGuiTarget = PlayerGui
end

Notify = function(msg, dur, extra)
    _G._ReanimNotify = Notify
    local realMsg = msg
    local realDur = dur
    if type(dur) == "string" then
        realMsg = msg .. ": " .. dur
        realDur = extra
    end
    realDur = tonumber(realDur) or 2.5

    local n = Instance.new("Frame")
    n.Parent = ScreenGui
    n.Size   = UDim2.new(0, 280, 0, 44)
    n.Position = UDim2.new(1, 20, 0, 20)
    n.BackgroundColor3 = C.bg1
    n.BackgroundTransparency = 0.05
    n.BorderSizePixel = 0
    n.ZIndex = 1000
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = n
        local s = Instance.new("UIStroke"); s.Color = C.accent
        s.Transparency = 0.3; s.Thickness = 1.5; s.Parent = n
        -- Gold accent bar on left
        local bar = Instance.new("Frame"); bar.Parent = n
        bar.BackgroundColor3 = C.accent; bar.BackgroundTransparency = 0
        bar.BorderSizePixel = 0; bar.Size = UDim2.new(0,3,0.6,0)
        bar.Position = UDim2.new(0,0,0.5,0); bar.AnchorPoint = Vector2.new(0,0.5)
        bar.ZIndex = 1001
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0,2)
    end
    local t = Instance.new("TextLabel"); t.Parent = n
    t.BackgroundTransparency = 1; t.Position = UDim2.new(0,14,0,0)
    t.Size = UDim2.new(1,-20,1,0); t.Font = Enum.Font.GothamSemibold
    t.Text = realMsg; t.TextColor3 = C.text
    t.TextSize = 12; t.TextWrapped = true; t.ZIndex = 1001
    do
        local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,8)
        p.PaddingRight = UDim.new(0,12); p.PaddingTop = UDim.new(0,8)
        p.PaddingBottom = UDim.new(0,8); p.Parent = t
    end
    -- Slide in from right
    TweenService:Create(n, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(1,-300,0,20)}):Play()
    task.delay(realDur, function()
        TweenService:Create(n, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {Position = UDim2.new(1,20,0,20)}):Play()
        game:GetService("Debris"):AddItem(n, 0.4)
    end)
end

Menu = Instance.new("Frame")
Menu.Name               = "TRXReanimMenu"
Menu.Parent             = ScreenGui
Menu.BackgroundColor3   = C.bg0
Menu.BackgroundTransparency = 0.02
Menu.BorderSizePixel    = 0
Menu.AnchorPoint        = Vector2.new(0.5, 0.5)
Menu.Position           = UDim2.new(0.5, 0, 0.5, 0)
Menu.Size               = UDim2.new(0, 0, 0, 0) -- Start invisible for entrance anim
Menu.Visible            = true
Menu.Active             = false
Menu.ZIndex             = 30
Menu.ClipsDescendants   = true
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = Menu
    local s = Instance.new("UIStroke"); s.Color = C.glassBorder
    s.Transparency = 0.25; s.Thickness = 1.5; s.Parent = Menu
    -- Drop shadow
    local shadow = Instance.new("ImageLabel"); shadow.Name = "Shadow"
    shadow.Parent = Menu; shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://131604521937076"
    shadow.ImageColor3 = Color3.fromRGB(0,0,0)
    shadow.ImageTransparency = 0.35
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(50,50,50,50)
    shadow.Size = UDim2.new(1,60,1,60)
    shadow.Position = UDim2.new(0.5,0,0.5,0)
    shadow.AnchorPoint = Vector2.new(0.5,0.5)
    shadow.ZIndex = 29
end

-- Resize Handle (curved grip bottom-right)
local ResizeGrip = Instance.new("Frame")
ResizeGrip.Name = "ResizeGrip"
ResizeGrip.Parent = Menu
ResizeGrip.BackgroundColor3 = C.accent
ResizeGrip.BackgroundTransparency = 0.6
ResizeGrip.BorderSizePixel = 0
ResizeGrip.Size = UDim2.new(0, 18, 0, 18)
ResizeGrip.Position = UDim2.new(1, -18, 1, -18)
ResizeGrip.ZIndex = 35
ResizeGrip.Active = true
local gripCorner = Instance.new("UICorner", ResizeGrip)
gripCorner.CornerRadius = UDim.new(0, 6)
local gripStroke = Instance.new("UIStroke", ResizeGrip)
gripStroke.Color = C.glassBorder
gripStroke.Thickness = 1.5
gripStroke.Transparency = 0.3

-- Curved diagonal lines on grip for visual flair
for i = 0, 2 do
    local line = Instance.new("Frame", ResizeGrip)
    line.BackgroundColor3 = C.text
    line.BackgroundTransparency = 0.4
    line.BorderSizePixel = 0
    line.Size = UDim2.new(0, 8, 0, 1.5)
    line.Position = UDim2.new(0, 3 + i*2.5, 0, 12 - i*2.5)
    line.Rotation = -45
    line.ZIndex = 36
end

-- Resize logic
local resizing = false
local resizeStartPos
local resizeStartSize

ResizeGrip.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        resizing = true
        resizeStartPos = input.Position
        resizeStartSize = Menu.AbsoluteSize
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                resizing = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - resizeStartPos
        local newW = math.clamp(resizeStartSize.X + delta.X, CONFIG.UI.MIN_WIDTH, 700)
        local newH = math.clamp(resizeStartSize.Y + delta.Y, CONFIG.UI.MIN_HEIGHT, 800)
        Menu.Size = UDim2.new(0, newW, 0, newH)
        FULL_SIZE = UDim2.new(0, newW, 0, newH)
        if not isMinimized then
            MINI_SIZE = UDim2.new(0, newW, 0, 40)
        end
    end
end)

ResizeGrip.MouseEnter:Connect(function()
    TweenService:Create(ResizeGrip, TweenInfo.new(0.15), {BackgroundTransparency = 0.3}):Play()
end)
ResizeGrip.MouseLeave:Connect(function()
    TweenService:Create(ResizeGrip, TweenInfo.new(0.15), {BackgroundTransparency = 0.6}):Play()
end)


-- Entrance animation
Menu.Size = UDim2.new(0, CONFIG.UI.DEFAULT_WIDTH, 0, CONFIG.UI.DEFAULT_HEIGHT)
Menu.BackgroundTransparency = 1
pcall(function()
    TweenService:Create(Menu, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.02
    }):Play()
end)

local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"; TitleBar.Parent = Menu
TitleBar.BackgroundColor3 = C.bg1
TitleBar.BackgroundTransparency = 0.15; TitleBar.BorderSizePixel = 0
TitleBar.Size = UDim2.new(1,0,0,36); TitleBar.ZIndex = 31; TitleBar.Active = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,16); c.Parent = TitleBar
    local t = Instance.new("TextLabel"); t.Parent = TitleBar
    t.BackgroundTransparency = 1; t.Position = UDim2.new(0,16,0,0)
    t.Size = UDim2.new(1,-80,1,0); t.Font = Enum.Font.GothamBold
    t.Text = "TRX Reanimation"; t.TextColor3 = C.accent
    t.TextSize = 16; t.TextXAlignment = Enum.TextXAlignment.Left; t.ZIndex = 32
    -- Gold accent line under title
    local div = Instance.new("Frame"); div.Parent = TitleBar
    div.BackgroundColor3 = C.accent; div.BackgroundTransparency = 0.3
    div.BorderSizePixel = 0; div.Position = UDim2.new(0,16,1,-2)
    div.Size = UDim2.new(0,80,0,2); div.ZIndex = 33
end

local minimizeBtn = Instance.new("TextButton"); minimizeBtn.Parent = TitleBar
minimizeBtn.Name = "MinimizeBtn"
minimizeBtn.BackgroundColor3 = C.yellow; minimizeBtn.BackgroundTransparency = 0
minimizeBtn.BorderSizePixel = 0; minimizeBtn.AnchorPoint = Vector2.new(1,0.5)
minimizeBtn.Position = UDim2.new(1,-32,0.5,0); minimizeBtn.Size = UDim2.new(0,14,0,14)
minimizeBtn.Font = Enum.Font.GothamBold; minimizeBtn.Text = ""
minimizeBtn.TextColor3 = Color3.fromRGB(255,255,255); minimizeBtn.TextSize = 18
minimizeBtn.ZIndex = 32; minimizeBtn.AutoButtonColor = false
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = minimizeBtn end

local closeBtn = Instance.new("TextButton"); closeBtn.Parent = TitleBar
closeBtn.Name = "CloseBtn"
closeBtn.BackgroundColor3 = C.red; closeBtn.BackgroundTransparency = 0
closeBtn.BorderSizePixel = 0; closeBtn.AnchorPoint = Vector2.new(1,0.5)
closeBtn.Position = UDim2.new(1,-10,0.5,0); closeBtn.Size = UDim2.new(0,14,0,14)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.Text = ""
closeBtn.TextColor3 = Color3.fromRGB(255,255,255); closeBtn.TextSize = 18
closeBtn.ZIndex = 32; closeBtn.AutoButtonColor = false
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = closeBtn end

-- Reanimate toggle lives in the title bar so it's always visible even when minimized
local ToggleBtn = Instance.new("TextButton"); ToggleBtn.Parent = TitleBar
ToggleBtn.Name = "ReanimToggleBtn"
ToggleBtn.AnchorPoint = Vector2.new(1, 0.5)
ToggleBtn.Position = UDim2.new(1, -58, 0.5, 0)
ToggleBtn.Size = UDim2.new(0, 54, 0, 22)
ToggleBtn.BackgroundColor3 = C.bg2; ToggleBtn.BackgroundTransparency = 0.1
ToggleBtn.BorderSizePixel = 0; ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Text = "OFF"; ToggleBtn.TextColor3 = C.text2
ToggleBtn.TextSize = 11; ToggleBtn.ZIndex = 33; ToggleBtn.AutoButtonColor = false
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = ToggleBtn end


-- AnimRecorder Button (right side of title bar)
local AnimRecorderBtn = Instance.new("TextButton"); AnimRecorderBtn.Parent = TitleBar
AnimRecorderBtn.Name = "AnimRecorderBtn"
AnimRecorderBtn.AnchorPoint = Vector2.new(1, 0.5)
AnimRecorderBtn.Position = UDim2.new(1, -118, 0.5, 0)
AnimRecorderBtn.Size = UDim2.new(0, 80, 0, 22)
AnimRecorderBtn.BackgroundColor3 = C.bg2; AnimRecorderBtn.BackgroundTransparency = 0.1
AnimRecorderBtn.BorderSizePixel = 0; AnimRecorderBtn.Font = Enum.Font.GothamBold
AnimRecorderBtn.Text = "Record"; AnimRecorderBtn.TextColor3 = C.accent
AnimRecorderBtn.TextSize = 10; AnimRecorderBtn.ZIndex = 33; AnimRecorderBtn.AutoButtonColor = false
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = AnimRecorderBtn end

-- AnimRecorder System
local AnimRecorder = {
    isRecording = false,
    recordedFrames = {},
    startTime = 0,
    recordingConn = nil,
    lastRecordedTime = 0,
    frameInterval = 1/30, -- 30 FPS recording
}

local function getCloneConstraints()
    local clone = ReanimateAPI and ReanimateAPI.get_clone and ReanimateAPI.get_clone(plr)
    if not clone then return nil end

    local constraints = {}
    for _, descendant in ipairs(clone:GetDescendants()) do
        if descendant:IsA("AnimationConstraint") then
            local attachment = descendant.Attachment1
            if attachment and attachment.Parent then
                constraints[attachment.Parent.Name] = descendant
            end
        end
    end
    return constraints
end

local function startRecording()
    if AnimRecorder.isRecording then return end
    if not ReanimateAPI or not ReanimateAPI.is_reanimated() then
        Notify("Recorder", "Please reanimate first!", 3)
        return
    end

    AnimRecorder.isRecording = true
    AnimRecorder.recordedFrames = {}
    AnimRecorder.startTime = tick()
    AnimRecorder.lastRecordedTime = 0

    AnimRecorderBtn.Text = "Stop"
    TweenService:Create(AnimRecorderBtn, TweenInfo.new(0.25), {
        BackgroundColor3 = C.red,
        TextColor3 = C.white
    }):Play()
    Notify("Recorder", "Recording started! Perform your animation.", 3)

    AnimRecorder.recordingConn = RunService.Heartbeat:Connect(function()
        if not AnimRecorder.isRecording then return end

        local elapsed = tick() - AnimRecorder.startTime
        if elapsed - AnimRecorder.lastRecordedTime < AnimRecorder.frameInterval then return end
        AnimRecorder.lastRecordedTime = elapsed

        local constraints = getCloneConstraints()
        if not constraints then return end

        local frameData = {}
        for boneName, constraint in pairs(constraints) do
            if constraint and constraint.Parent then
                frameData[boneName] = constraint.Transform
            end
        end

        table.insert(AnimRecorder.recordedFrames, {
            Time = elapsed,
            Data = frameData
        })
    end)
end

local function stopRecording()
    if not AnimRecorder.isRecording then return end

    AnimRecorder.isRecording = false
    if AnimRecorder.recordingConn then
        AnimRecorder.recordingConn:Disconnect()
        AnimRecorder.recordingConn = nil
    end

    AnimRecorderBtn.Text = "Record"
    TweenService:Create(AnimRecorderBtn, TweenInfo.new(0.25), {
        BackgroundColor3 = C.bg2,
        TextColor3 = C.accent
    }):Play()

    local frameCount = #AnimRecorder.recordedFrames
    if frameCount == 0 then
        Notify("Recorder", "No frames recorded.", 2)
        return
    end

    Notify("Recorder", "Processing " .. tostring(frameCount) .. " frames...", 2)

    -- Offload the heavy string building to a spawned task so the game doesn't freeze
    task.spawn(function()
        local recordedFrames = AnimRecorder.recordedFrames
        local outputParts = {}
        local totalDuration = recordedFrames[#recordedFrames].Time
        table.insert(outputParts, "-- " .. tostring(frameCount) .. " keyframes\n")
        table.insert(outputParts, "-- " .. string.format("%.3f", totalDuration) .. " seconds\n")
        table.insert(outputParts, "return {\n")
        table.insert(outputParts, '  ["Animation"] = {\n')

        local yieldEvery = 50
        for i, frame in ipairs(recordedFrames) do
            table.insert(outputParts, "    {Time = " .. string.format("%.3f", frame.Time) .. ", Data = {\n")

            for boneName, cf in pairs(frame.Data) do
                table.insert(outputParts, '      ["' .. boneName .. '"] = CFrame.new(')
                local comps = {cf:GetComponents()}
                for j = 1, 12 do
                    table.insert(outputParts, string.format("%.6f", comps[j]))
                    if j < 12 then table.insert(outputParts, ", ") end
                end
                table.insert(outputParts, "),\n")
            end

            table.insert(outputParts, "    }},\n")

            -- Yield every N frames so the scheduler can breathe
            if i % yieldEvery == 0 then
                task.wait()
            end
        end

        table.insert(outputParts, "  }\n")
        table.insert(outputParts, "}\n")
        local output = table.concat(outputParts)
        outputParts = nil

        -- Save to file
        local filename = CONFIG.FOLDER .. "/RecordedAnim_" .. tostring(math.floor(tick())) .. ".lua"
        pcall(function()
            makefolder("ReanimData")
            writefile(filename, output)
        end)

        -- Also copy to clipboard
        pcall(function()
            if setclipboard then setclipboard(output) end
        end)

        Notify("Recorder", "Saved " .. tostring(frameCount) .. " frames! Copied to clipboard.", 4)
    end)
end

AnimRecorderBtn.MouseButton1Click:Connect(function()
    if AnimRecorder.isRecording then
        stopRecording()
    else
        startRecording()
    end
end)

AnimRecorderBtn.MouseEnter:Connect(function()
    if not AnimRecorder.isRecording then
        TweenService:Create(AnimRecorderBtn, TweenInfo.new(0.12), {BackgroundTransparency = 0}):Play()
    end
end)
AnimRecorderBtn.MouseLeave:Connect(function()
    if not AnimRecorder.isRecording then
        TweenService:Create(AnimRecorderBtn, TweenInfo.new(0.12), {BackgroundTransparency = 0.1}):Play()
    end
end)

function UpdateToggleBtn()
    if State.isReanimated then
        TweenService:Create(ToggleBtn, TweenInfo.new(0.25), {
            BackgroundColor3 = C.accent,
            BackgroundTransparency = 0,
            TextColor3 = Color3.fromRGB(0, 0, 0)
        }):Play()
        ToggleBtn.Text = "ON"
    else
        TweenService:Create(ToggleBtn, TweenInfo.new(0.25), {
            BackgroundColor3 = C.bg2,
            BackgroundTransparency = 0.1,
            TextColor3 = C.text2
        }):Play()
        ToggleBtn.Text = "OFF"
    end
end

ToggleBtn.MouseButton1Click:Connect(function()
    if type(_G._TRXDoReanimToggle) == "function" then
        _G._TRXDoReanimToggle()
    end
end)
ToggleBtn.MouseEnter:Connect(function()
    if not State.isReanimated then
        pcall(function()
            TweenService:Create(ToggleBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
        end)
    end
end)
ToggleBtn.MouseLeave:Connect(function()
    if not State.isReanimated then
        pcall(function()
            TweenService:Create(ToggleBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency = 0.1}):Play()
        end)
    end
end)

local isMinimized = false
local FULL_SIZE   = UDim2.new(0, CONFIG.UI.DEFAULT_WIDTH, 0, CONFIG.UI.DEFAULT_HEIGHT)
local MINI_SIZE   = UDim2.new(0, CONFIG.UI.DEFAULT_WIDTH, 0, 40)
Menu.Size         = FULL_SIZE

closeBtn.MouseButton1Click:Connect(function()
    Menu.Visible = false
    ScreenGui.Enabled = false
end)

do
    -- DRAG + SCREEN CLAMP (exact pattern from user example)
    -- absolute-pixel based, Scale/AnchorPoint/Inset safe
    local dragging = false
    local dragInputStart
    local startAnchorAbsPos

    local function getAnchorAbsPosition()
        local parent = Menu.Parent
        local parentAbsPos = parent.AbsolutePosition
        local parentAbsSize = parent.AbsoluteSize
        local pos = Menu.Position
        local x = parentAbsPos.X + pos.X.Scale * parentAbsSize.X + pos.X.Offset
        local y = parentAbsPos.Y + pos.Y.Scale * parentAbsSize.Y + pos.Y.Offset
        return Vector2.new(x, y)
    end

    local function setClampedPosition(targetAbsX, targetAbsY)
        local parent = Menu.Parent
        local parentAbsPos = parent.AbsolutePosition
        local parentAbsSize = parent.AbsoluteSize
        local absSize = Menu.AbsoluteSize
        local anchor = Menu.AnchorPoint
        local minX = parentAbsPos.X + anchor.X * absSize.X
        local maxX = parentAbsPos.X + parentAbsSize.X - (1 - anchor.X) * absSize.X
        local minY = parentAbsPos.Y + anchor.Y * absSize.Y
        local maxY = parentAbsPos.Y + parentAbsSize.Y - (1 - anchor.Y) * absSize.Y
        local x = math.clamp(targetAbsX, minX, maxX)
        local y = math.clamp(targetAbsY, minY, maxY)
        Menu.Position = UDim2.new(0, x - parentAbsPos.X, 0, y - parentAbsPos.Y)
    end

    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInputStart = input.Position
            startAnchorAbsPos = getAnchorAbsPosition()
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragInputStart
            setClampedPosition(startAnchorAbsPos.X + delta.X, startAnchorAbsPos.Y + delta.Y)
        end
    end)
end

body = Instance.new("Frame"); body.Parent = Menu
body.BackgroundTransparency = 1; body.Position = UDim2.new(0,0,0,36)
body.Size = UDim2.new(1,0,1,-48); body.ZIndex = 31

minimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    if isMinimized then
        body.Visible = false
        TweenService:Create(Menu, ti, {Size = MINI_SIZE, Position = _TRXTopFixedPos(Menu, MINI_SIZE.Y.Offset)}):Play()
        minimizeBtn.Text = ""
    else
        TweenService:Create(Menu, ti, {Size = FULL_SIZE, Position = _TRXTopFixedPos(Menu, FULL_SIZE.Y.Offset)}):Play()
        task.delay(0.28, function() body.Visible = true end)
        minimizeBtn.Text = ""
    end
end)

local toggleBar = Instance.new("Frame"); toggleBar.Parent = body
toggleBar.BackgroundColor3 = C.bg1; toggleBar.BackgroundTransparency = 0.4
toggleBar.BorderSizePixel = 0; toggleBar.Size = UDim2.new(1,-20,0,26)
toggleBar.Position = UDim2.new(0,10,0,4); toggleBar.ZIndex = 32
do 
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = toggleBar
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.6; s.Thickness = 1; s.Parent = toggleBar
end

local reanimLabel = Instance.new("TextLabel"); reanimLabel.Parent = toggleBar
reanimLabel.BackgroundTransparency = 1; reanimLabel.Position = UDim2.new(0,12,0,0)
reanimLabel.Size = UDim2.new(0.55,0,1,0); reanimLabel.Font = Enum.Font.GothamBold
reanimLabel.Text = "Reanimation"; reanimLabel.TextColor3 = C.text
reanimLabel.TextSize = 12; reanimLabel.TextXAlignment = Enum.TextXAlignment.Left; reanimLabel.ZIndex = 33

-- ToggleBtn is now in the TitleBar (always visible). The toggleBar in the body
-- keeps its label for context but no longer holds a second button.

function _attachPlayRawAnimation()
    -- disabled
end

local _activating = false
local _lastToggleAt = 0

function _smoothToggle(callFn)
    local cam = workspace.CurrentCamera
    local char = plr.Character
    local savedHRP, savedCam

    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then savedHRP = hrp.CFrame end
    end
    if cam then savedCam = cam.CFrame end

    callFn()

    local frames = 0
    local conn
    conn = RunService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
        frames = frames + 1
        local c2 = plr.Character
        local hrp2 = c2 and c2:FindFirstChild("HumanoidRootPart")
        if hrp2 and savedHRP then
            hrp2.CFrame = savedHRP
        end
        local cam2 = workspace.CurrentCamera
        if cam2 and savedCam then
            cam2.CFrame = savedCam
        end
        if frames >= 6 then
            conn:Disconnect()
        end
    end))
end

-- Shared reanimate toggle logic — called by ToggleBtn in TitleBar
local function doReanimToggle()
    if _activating then return end
    if tick() - _lastToggleAt < 0.75 then return end
    _lastToggleAt = tick()

    if State.isReanimated then
        _activating = true
        task.spawn(function()
            stopStateSystem()
            _smoothToggle(function()
                pcall(function() ReanimateAPI.reanimate(false) end)
            end)
            State.isReanimated = false
            State.selectedAnim = nil
            _activating = false
            UpdateToggleBtn()
            Notify("TRX Reanimation disabled")
        end)
        return
    end

    _activating = true
    task.spawn(function()
        local err
        local ok = pcall(function()
            _smoothToggle(function()
                if ReanimateAPI == nil then
                    error("ReanimateAPI is nil")
                elseif ReanimateAPI.reanimate == nil then
                    error("ReanimateAPI.reanimate is nil")
                end
                local res = ReanimateAPI.reanimate(true)
                if type(res) == "string" then
                    err = res
                    error(res)
                end
            end)
        end)

        State.isReanimated = ReanimateAPI and ReanimateAPI.is_reanimated() or false
        UpdateToggleBtn()

        if not State.isReanimated then
            _activating = false
            Notify("Reanimation failed: " .. tostring(err or "Unknown error"), 4)
            return
        end

        task.spawn(function()
            prefetchAllStates()
            if next(StateAnims) then
                startStateSystem()
            elseif _applyReanimDefaultAnimate then
                -- No custom states: fall back to the player's default Roblox animations.
                task.wait(0.1)
                _applyReanimDefaultAnimate(true)
            end
        end)
        _activating = false
        Notify("TRX Reanimation enabled!", 2)
    end)
end

-- Expose for the title-bar toggle button
_G._TRXDoReanimToggle = doReanimToggle

-- GrabStatus click fix: when reanimated, your own clone/real character can
-- block the game's click raycast. We do our OWN raycast from the camera through
-- the mouse position, explicitly excluding both your clone and real character,
-- then fire GrabStatus:InvokeServer(userId) for whichever player we hit.
do
    local _grabRemote = nil

    local function _getGrabRemote()
        if _grabRemote and _grabRemote.Parent then return _grabRemote end
        local ok, r = pcall(function()
            return game:GetService("ReplicatedStorage"):FindFirstChild("GrabStatus")
        end)
        if ok and r then _grabRemote = r end
        return _grabRemote
    end

    -- Find which player owns the model that contains `inst`
    local function _getPlayerFromInstance(inst)
        local Players = game:GetService("Players")
        local model = inst and inst:FindFirstAncestorOfClass("Model")
        while model do
            local p = Players:GetPlayerFromCharacter(model)
            if p and p ~= plr then return p end
            model = model:FindFirstAncestorOfClass("Model")
        end
        -- Fallback: descendant check
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= plr and p.Character and inst and inst:IsDescendantOf(p.Character) then
                return p
            end
        end
        return nil
    end

    local _mouse = plr:GetMouse()
    _mouse.Button1Down:Connect(function()
        if not State.isReanimated then return end
        local remote = _getGrabRemote()
        if not remote then return end

        local cam = workspace.CurrentCamera
        if not cam then return end

        -- Build exclusion list: our clone + real char (and current Character)
        local exclude = {}
        pcall(function()
            if _G._TRXReanimateAPI then
                local clone = _G._TRXReanimateAPI.get_clone and _G._TRXReanimateAPI.get_clone(plr)
                local realc = _G._TRXReanimateAPI.get_real_character and _G._TRXReanimateAPI.get_real_character(plr)
                if clone then table.insert(exclude, clone) end
                if realc then table.insert(exclude, realc) end
            end
        end)
        if plr.Character then table.insert(exclude, plr.Character) end

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = exclude
        rayParams.IgnoreWater = true

        local unitRay = cam:ViewportPointToRay(_mouse.X, _mouse.Y)
        local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 5000, rayParams)

        local targetPlayer = nil
        if result and result.Instance then
            targetPlayer = _getPlayerFromInstance(result.Instance)
        end
        -- Fallback to Mouse.Target if raycast missed
        if not targetPlayer and _mouse.Target then
            targetPlayer = _getPlayerFromInstance(_mouse.Target)
        end

        if targetPlayer then
            pcall(function() remote:InvokeServer(targetPlayer.UserId) end)
        end
    end)
end

local npBar = Instance.new("Frame"); npBar.Parent = body
npBar.BackgroundColor3 = C.bg1; npBar.BackgroundTransparency = 0.4
npBar.BorderSizePixel = 0; npBar.Size = UDim2.new(1,-20,0,24)
npBar.Position = UDim2.new(0,10,0,34); npBar.ZIndex = 32
do 
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = npBar
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = npBar
end

NowPlayingLabel = Instance.new("TextLabel"); NowPlayingLabel.Parent = npBar
NowPlayingLabel.BackgroundTransparency = 1; NowPlayingLabel.Position = UDim2.new(0,8,0,0)
NowPlayingLabel.Size = UDim2.new(1,-70,1,0); NowPlayingLabel.Font = Enum.Font.Gotham
NowPlayingLabel.Text = "No animation playing"
NowPlayingLabel.TextColor3 = C.text2
NowPlayingLabel.TextSize = 11; NowPlayingLabel.TextXAlignment = Enum.TextXAlignment.Left
NowPlayingLabel.TextTruncate = Enum.TextTruncate.AtEnd; NowPlayingLabel.ZIndex = 33

StopBtn = Instance.new("TextButton"); StopBtn.Parent = npBar
StopBtn.AnchorPoint = Vector2.new(1,0.5); StopBtn.BackgroundColor3 = C.red
StopBtn.BackgroundTransparency = 0.2; StopBtn.BorderSizePixel = 0
StopBtn.Position = UDim2.new(1,-6,0.5,0); StopBtn.Size = UDim2.new(0,58,0,20)
StopBtn.Font = Enum.Font.GothamBold; StopBtn.Text = "Stop"
StopBtn.TextColor3 = C.white; StopBtn.TextSize = 10
StopBtn.ZIndex = 33; StopBtn.AutoButtonColor = false
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = StopBtn end

local tabRow = Instance.new("Frame"); tabRow.Parent = body
tabRow.BackgroundTransparency = 1; tabRow.Size = UDim2.new(1,-20,0,22)
tabRow.Position = UDim2.new(0,10,0,62); tabRow.ZIndex = 32
do
    local l = Instance.new("UIListLayout"); l.Parent = tabRow
    l.FillDirection = Enum.FillDirection.Horizontal
    l.HorizontalAlignment = Enum.HorizontalAlignment.Left
    l.Padding = UDim.new(0,5)
end

local TAB_DEFS = { "All", "Favs", "Custom", "Binds", "States", "Speed", "Settings", "Testing" }
TabButtons = {}
local activeTab = nil

SetTabActive = function(btn)
    if activeTab then
        local oldLine = activeTab:FindFirstChild("Underline")
        TweenService:Create(activeTab, TweenInfo.new(0.2), {TextColor3 = C.text3}):Play()
        if oldLine then
            TweenService:Create(oldLine, TweenInfo.new(0.2), {BackgroundTransparency = 1, Size = UDim2.new(0,0,0,2)}):Play()
        end
    end
    activeTab = btn
    local newLine = btn:FindFirstChild("Underline")
    TweenService:Create(btn, TweenInfo.new(0.2), {TextColor3 = C.accent}):Play()
    if newLine then
        TweenService:Create(newLine, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {BackgroundTransparency = 0, Size = UDim2.new(0.7,0,0,2)}):Play()
    end
end

for _, tname in ipairs(TAB_DEFS) do
    local tb = Instance.new("TextButton"); tb.Parent = tabRow
    tb.BackgroundColor3 = C.bg2; tb.BackgroundTransparency = 1
    tb.BorderSizePixel = 0; tb.Size = UDim2.new(1/#TAB_DEFS,-4,1,0)
    tb.Font = Enum.Font.GothamMedium; tb.Text = tname
    tb.TextColor3 = C.text3; tb.TextSize = 10
    tb.ZIndex = 33; tb.AutoButtonColor = false
    do 
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = tb
    end
    -- Animated underline indicator
    local underline = Instance.new("Frame"); underline.Name = "Underline"
    underline.Parent = tb; underline.BackgroundColor3 = C.accent
    underline.BackgroundTransparency = 1; underline.BorderSizePixel = 0
    underline.Position = UDim2.new(0.5,0,1,-2); underline.AnchorPoint = Vector2.new(0.5,0)
    underline.Size = UDim2.new(0,0,0,2); underline.ZIndex = 34
    tb.MouseEnter:Connect(function()
        if activeTab ~= tb then
            TweenService:Create(tb, TweenInfo.new(0.15), {TextColor3 = C.text2}):Play()
            TweenService:Create(underline, TweenInfo.new(0.15), {BackgroundTransparency = 0.5, Size = UDim2.new(0.5,0,0,2)}):Play()
        end
    end)
    tb.MouseLeave:Connect(function()
        if activeTab ~= tb then
            TweenService:Create(tb, TweenInfo.new(0.15), {TextColor3 = C.text3}):Play()
            TweenService:Create(underline, TweenInfo.new(0.15), {BackgroundTransparency = 1, Size = UDim2.new(0,0,0,2)}):Play()
        end
    end)
    TabButtons[tname] = tb
end

-- Function to update Custom tab text with animation count
local function UpdateCustomTabCount()
    local customBtn = TabButtons["Custom"]
    if customBtn then
        local count = #CustomAnims
        customBtn.Text = "Custom" .. (count > 0 and " (" .. count .. ")" or "")
    end
end

SearchBox = Instance.new("TextBox"); SearchBox.Parent = body
SearchBox.BackgroundColor3 = C.bg1; SearchBox.BackgroundTransparency = 0.4
SearchBox.BorderSizePixel = 0; SearchBox.Size = UDim2.new(1,-20,0,24)
SearchBox.Position = UDim2.new(0,10,0,88); SearchBox.ZIndex = 32
SearchBox.Font = Enum.Font.GothamMedium; SearchBox.PlaceholderText = "Search..."
SearchBox.PlaceholderColor3 = C.text3; SearchBox.Text = ""
SearchBox.TextColor3 = C.text; SearchBox.TextSize = 11
SearchBox.ClearTextOnFocus = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = SearchBox
    local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,10); p.Parent = SearchBox
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = SearchBox
end

hintLbl = Instance.new("TextLabel"); hintLbl.Parent = body
hintLbl.BackgroundTransparency = 1; hintLbl.Size = UDim2.new(1,-20,0,12)
hintLbl.Position = UDim2.new(0,10,0,114); hintLbl.ZIndex = 32; hintLbl.Font = Enum.Font.Gotham
hintLbl.Text = "Click [+] to bind key  |  Click bound key to unbind"
hintLbl.TextColor3 = C.text3; hintLbl.TextSize = 10
hintLbl.TextXAlignment = Enum.TextXAlignment.Left

AnimListFrame = Instance.new("ScrollingFrame"); AnimListFrame.Parent = body
AnimListFrame.BackgroundColor3 = C.bg0; AnimListFrame.BackgroundTransparency = 0.5
AnimListFrame.BorderSizePixel = 0
AnimListFrame.Size = UDim2.new(1,-20,1,-210)
AnimListFrame.Position = UDim2.new(0,10,0,128)
AnimListFrame.ScrollBarThickness = 4; AnimListFrame.ScrollBarImageColor3 = C.accent
AnimListFrame.ScrollBarImageTransparency = 0.5; AnimListFrame.ZIndex = 32
AnimListFrame.CanvasSize = UDim2.new(0,0,0,0)
AnimListFrame.ScrollingDirection = getSafeScrollingDirection("Y")
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = AnimListFrame end

-- States panel stays inside the main reanim UI and expands inline pickers.
StatesPanel = Instance.new("ScrollingFrame"); StatesPanel.Name = "StatesSection"
StatesPanel.BackgroundTransparency = 1; StatesPanel.BorderSizePixel = 0
StatesPanel.Size = UDim2.new(1,0,0,0); StatesPanel.AutomaticSize = getSafeAutomaticSize()
StatesPanel.ZIndex = 32; StatesPanel.LayoutOrder = 100
StatesPanel.ScrollBarThickness = 4; StatesPanel.ScrollBarImageColor3 = C.accent
StatesPanel.ScrollBarImageTransparency = 0.5; StatesPanel.CanvasSize = UDim2.new(0,0,0,0)
do
    local l = Instance.new("UIListLayout"); l.Parent = StatesPanel
    l.Padding = UDim.new(0,4); l.SortOrder = Enum.SortOrder.LayoutOrder
    local p = Instance.new("UIPadding"); p.Parent = StatesPanel
    p.PaddingTop = UDim.new(0,4); p.PaddingLeft = UDim.new(0,2); p.PaddingRight = UDim.new(0,2); p.PaddingBottom = UDim.new(0,8)
    l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        StatesPanel.CanvasSize = UDim2.new(0,0,0,l.AbsoluteContentSize.Y+16)
    end)
end

CustomPanel = Instance.new("Frame"); CustomPanel.Parent = body
CustomPanel.BackgroundTransparency = 1
CustomPanel.Size = UDim2.new(1,-20,1,-210)
CustomPanel.Position = UDim2.new(0,10,0,128)
CustomPanel.ZIndex = 32; CustomPanel.Visible = false

-- BindsPanel: shows all animations with keybinds set
BindsPanel = Instance.new("ScrollingFrame"); BindsPanel.Parent = body
BindsPanel.Name = "BindsPanel"
BindsPanel.BackgroundColor3 = C.bg0; BindsPanel.BackgroundTransparency = 0.5
BindsPanel.BorderSizePixel = 0
BindsPanel.Size = UDim2.new(1,-20,1,-136)
BindsPanel.Position = UDim2.new(0,10,0,128)
BindsPanel.ScrollBarThickness = 4; BindsPanel.ScrollBarImageColor3 = C.accent
BindsPanel.ScrollBarImageTransparency = 0.5; BindsPanel.ZIndex = 32
BindsPanel.CanvasSize = UDim2.new(0,0,0,0); BindsPanel.Visible = false
BindsPanel.ScrollingDirection = getSafeScrollingDirection("Y")
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = BindsPanel end

customSearchBox = Instance.new("TextBox"); customSearchBox.Parent = CustomPanel
customSearchBox.BackgroundColor3 = C.bg1; customSearchBox.BackgroundTransparency = 0.4
customSearchBox.BorderSizePixel = 0; customSearchBox.Size = UDim2.new(1,0,0,26)
customSearchBox.Position = UDim2.new(0,0,0,0); customSearchBox.ZIndex = 32
customSearchBox.Font = Enum.Font.GothamMedium; customSearchBox.PlaceholderText = "Search custom animations..."
customSearchBox.PlaceholderColor3 = C.text3; customSearchBox.Text = ""
customSearchBox.TextColor3 = C.text; customSearchBox.TextSize = 11
customSearchBox.ClearTextOnFocus = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = customSearchBox
    local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,10); p.Parent = customSearchBox
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = customSearchBox
end

customOpenModalBtn = Instance.new("TextButton"); customOpenModalBtn.Parent = CustomPanel
customOpenModalBtn.BackgroundColor3 = C.bg2
customOpenModalBtn.BackgroundTransparency = 0.3; customOpenModalBtn.BorderSizePixel = 0
customOpenModalBtn.Size = UDim2.new(1,-92,0,36); customOpenModalBtn.Position = UDim2.new(0,0,0,30)
customOpenModalBtn.Font = Enum.Font.GothamBold; customOpenModalBtn.Text = "+  Add Custom Animation"
customOpenModalBtn.TextColor3 = C.accent; customOpenModalBtn.TextSize = 12
customOpenModalBtn.ZIndex = 33; customOpenModalBtn.AutoButtonColor = false
do 
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = customOpenModalBtn
    local s = Instance.new("UIStroke"); s.Color = C.accent; s.Transparency = 0.7; s.Thickness = 1; s.Parent = customOpenModalBtn
end
customOpenModalBtn.MouseEnter:Connect(function()
    TweenService:Create(customOpenModalBtn, TweenInfo.new(0.12), {BackgroundColor3 = C.accent, BackgroundTransparency = 0.2, TextColor3 = Color3.fromRGB(10,10,10)}):Play()
    TweenService:Create(customOpenModalBtn:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.12), {Transparency = 0}):Play()
end)
customOpenModalBtn.MouseLeave:Connect(function()
    TweenService:Create(customOpenModalBtn, TweenInfo.new(0.12), {BackgroundColor3 = C.bg2, BackgroundTransparency = 0.3, TextColor3 = C.accent}):Play()
    TweenService:Create(customOpenModalBtn:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.12), {Transparency = 0.7}):Play()
end)

-- Refresh button: re-scan the ReanimData folder for newly added custom animations
local customRefreshBtn = Instance.new("TextButton"); customRefreshBtn.Parent = CustomPanel
customRefreshBtn.BackgroundColor3 = C.bg2
customRefreshBtn.BackgroundTransparency = 0.3; customRefreshBtn.BorderSizePixel = 0
customRefreshBtn.Size = UDim2.new(0,84,0,36); customRefreshBtn.Position = UDim2.new(1,-84,0,30)
customRefreshBtn.Font = Enum.Font.GothamBold; customRefreshBtn.Text = "Refresh"
customRefreshBtn.TextColor3 = C.accent; customRefreshBtn.TextSize = 11
customRefreshBtn.ZIndex = 33; customRefreshBtn.AutoButtonColor = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = customRefreshBtn
    local s = Instance.new("UIStroke"); s.Color = C.accent; s.Transparency = 0.7; s.Thickness = 1; s.Parent = customRefreshBtn
end
customRefreshBtn.MouseEnter:Connect(function()
    TweenService:Create(customRefreshBtn, TweenInfo.new(0.12), {BackgroundColor3 = C.accent, BackgroundTransparency = 0.2, TextColor3 = Color3.fromRGB(10,10,10)}):Play()
    TweenService:Create(customRefreshBtn:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.12), {Transparency = 0}):Play()
end)
customRefreshBtn.MouseLeave:Connect(function()
    TweenService:Create(customRefreshBtn, TweenInfo.new(0.12), {BackgroundColor3 = C.bg2, BackgroundTransparency = 0.3, TextColor3 = C.accent}):Play()
    TweenService:Create(customRefreshBtn:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.12), {Transparency = 0.7}):Play()
end)
customRefreshBtn.MouseButton1Click:Connect(function()
    customRefreshBtn.Text = "..."
    task.spawn(function()
        local prevCount = #CustomAnims
        -- Re-run the loader: it rescans the ReanimData folder for new .lua/.json
        -- files (plus the saved list) and returns the merged set.
        local ok, result = pcall(LoadCustomAnims)
        if ok and type(result) == "table" then
            CustomAnims = result
            table.clear(CustomAnimations)
            for _, ca in ipairs(CustomAnims) do
                CustomAnimations[ca.name] = ca.url
            end
            pcall(SaveCustomAnims)
            -- Update Custom tab count after rescanning
            if UpdateCustomTabCount then
                UpdateCustomTabCount()
            end
        end
        if RebuildCustomList then pcall(RebuildCustomList) end
        local added = #CustomAnims - prevCount
        customRefreshBtn.Text = "Refresh"
        if Notify then
            if added > 0 then
                Notify("Found " .. added .. " new animation" .. (added == 1 and "" or "s"), 2.5)
            else
                Notify("No new animations found", 2)
            end
        end
    end)
end)

customListFrame = Instance.new("ScrollingFrame"); customListFrame.Parent = CustomPanel
customListFrame.BackgroundColor3 = C.bg0; customListFrame.BackgroundTransparency = 0.5
customListFrame.BorderSizePixel = 0; customListFrame.Position = UDim2.new(0,0,0,70)
customListFrame.Size = UDim2.new(1,0,1,-74)
customListFrame.ScrollBarThickness = 4; customListFrame.ScrollBarImageColor3 = C.accent
customListFrame.ScrollBarImageTransparency = 0.5; customListFrame.ZIndex = 33
customListFrame.CanvasSize = UDim2.new(0,0,0,0)
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = customListFrame
    -- No UIListLayout: rows are positioned absolutely so the custom list can be
    -- virtualized (only visible rows exist). CanvasSize is managed manually in
    -- RebuildCustomList.
end

SettingsPanel = Instance.new("ScrollingFrame"); SettingsPanel.Parent = body
SettingsPanel.Name = "SettingsPanel"
SettingsPanel.BackgroundColor3 = C.bg0; SettingsPanel.BackgroundTransparency = 0.5
SettingsPanel.BorderSizePixel = 0
SettingsPanel.Size = UDim2.new(1,-20,1,-210)
SettingsPanel.Position = UDim2.new(0,10,0,128)
SettingsPanel.ScrollBarThickness = 4; SettingsPanel.ScrollBarImageColor3 = C.accent
SettingsPanel.ScrollBarImageTransparency = 0.5; SettingsPanel.ZIndex = 32
SettingsPanel.CanvasSize = UDim2.new(0,0,0,0); SettingsPanel.Visible = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = SettingsPanel
    local l = Instance.new("UIListLayout"); l.Parent = SettingsPanel
    l.Padding = UDim.new(0,8); l.SortOrder = Enum.SortOrder.LayoutOrder
    local p = Instance.new("UIPadding"); p.Parent = SettingsPanel
    p.PaddingTop = UDim.new(0,8); p.PaddingLeft = UDim.new(0,8); p.PaddingRight = UDim.new(0,8)
    l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        SettingsPanel.CanvasSize = UDim2.new(0,0,0,l.AbsoluteContentSize.Y+16)
    end)
end

SpeedPanel = Instance.new("ScrollingFrame"); SpeedPanel.Parent = body
SpeedPanel.Name = "SpeedPanel"
SpeedPanel.BackgroundColor3 = C.bg0; SpeedPanel.BackgroundTransparency = 0.5
SpeedPanel.BorderSizePixel = 0
SpeedPanel.Size = UDim2.new(1,-20,1,-96)
SpeedPanel.Position = UDim2.new(0,10,0,88)
SpeedPanel.ScrollBarThickness = 4; SpeedPanel.ScrollBarImageColor3 = C.accent
SpeedPanel.ScrollBarImageTransparency = 0.5; SpeedPanel.ZIndex = 32
SpeedPanel.CanvasSize = UDim2.new(0,0,0,0); SpeedPanel.Visible = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = SpeedPanel
    local l = Instance.new("UIListLayout"); l.Parent = SpeedPanel
    l.Padding = UDim.new(0,8); l.SortOrder = Enum.SortOrder.LayoutOrder
    local p = Instance.new("UIPadding"); p.Parent = SpeedPanel
    p.PaddingTop = UDim.new(0,8); p.PaddingLeft = UDim.new(0,8); p.PaddingRight = UDim.new(0,8); p.PaddingBottom = UDim.new(0,8)
    l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        SpeedPanel.CanvasSize = UDim2.new(0,0,0,l.AbsoluteContentSize.Y+16)
    end)
end

-- States panel as a separate panel (not embedded in Settings)

-- Testing Panel (diagnostics & debug)
TestingPanel = Instance.new("ScrollingFrame"); TestingPanel.Parent = body
TestingPanel.Name = "TestingPanel"
TestingPanel.BackgroundColor3 = C.bg0; TestingPanel.BackgroundTransparency = 0.5
TestingPanel.BorderSizePixel = 0
TestingPanel.Size = UDim2.new(1,-20,1,-96)
TestingPanel.Position = UDim2.new(0,10,0,88)
TestingPanel.ScrollBarThickness = 4; TestingPanel.ScrollBarImageColor3 = C.accent
TestingPanel.ScrollBarImageTransparency = 0.5; TestingPanel.ZIndex = 32
TestingPanel.CanvasSize = UDim2.new(0,0,0,0); TestingPanel.Visible = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = TestingPanel
    local l = Instance.new("UIListLayout"); l.Parent = TestingPanel
    l.Padding = UDim.new(0,8); l.SortOrder = Enum.SortOrder.LayoutOrder
    local p = Instance.new("UIPadding"); p.Parent = TestingPanel
    p.PaddingTop = UDim.new(0,8); p.PaddingLeft = UDim.new(0,8); p.PaddingRight = UDim.new(0,8); p.PaddingBottom = UDim.new(0,8)
    l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        TestingPanel.CanvasSize = UDim2.new(0,0,0,l.AbsoluteContentSize.Y+16)
    end)
end

-- Testing Header
local testHeader = Instance.new("TextLabel"); testHeader.Parent = TestingPanel
testHeader.BackgroundTransparency = 1; testHeader.Size = UDim2.new(1,0,0,18)
testHeader.Font = Enum.Font.GothamBold; testHeader.TextSize = 12
testHeader.Text = "Diagnostics & Testing"; testHeader.TextColor3 = C.accent
testHeader.TextXAlignment = Enum.TextXAlignment.Left; testHeader.ZIndex = 33

-- FPS Counter Frame
local fpsFrame = Instance.new("Frame"); fpsFrame.Parent = TestingPanel
fpsFrame.Size = UDim2.new(1,0,0,54); fpsFrame.BackgroundColor3 = C.bg1
fpsFrame.BackgroundTransparency = 0.4; fpsFrame.BorderSizePixel = 0
fpsFrame.LayoutOrder = 1
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = fpsFrame
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = fpsFrame
end
local fpsLbl = Instance.new("TextLabel", fpsFrame)
fpsLbl.BackgroundTransparency = 1; fpsLbl.Position = UDim2.new(0,10,0,6)
fpsLbl.Size = UDim2.new(1,-20,0,16); fpsLbl.Font = Enum.Font.GothamBold
fpsLbl.Text = "FPS: --"; fpsLbl.TextColor3 = C.text; fpsLbl.TextSize = 11
fpsLbl.TextXAlignment = Enum.TextXAlignment.Left; fpsLbl.ZIndex = 33
local fpsSub = Instance.new("TextLabel", fpsFrame)
fpsSub.BackgroundTransparency = 1; fpsSub.Position = UDim2.new(0,10,0,24)
fpsSub.Size = UDim2.new(1,-20,0,24); fpsSub.Font = Enum.Font.Gotham
fpsSub.Text = "Live frame rate monitor"; fpsSub.TextColor3 = C.text3; fpsSub.TextSize = 9
fpsSub.TextXAlignment = Enum.TextXAlignment.Left; fpsSub.TextWrapped = true; fpsSub.ZIndex = 33

-- Memory Frame
local memFrame = Instance.new("Frame"); memFrame.Parent = TestingPanel
memFrame.Size = UDim2.new(1,0,0,54); memFrame.BackgroundColor3 = C.bg1
memFrame.BackgroundTransparency = 0.4; memFrame.BorderSizePixel = 0
memFrame.LayoutOrder = 2
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = memFrame
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = memFrame
end
local memLbl = Instance.new("TextLabel", memFrame)
memLbl.BackgroundTransparency = 1; memLbl.Position = UDim2.new(0,10,0,6)
memLbl.Size = UDim2.new(1,-20,0,16); memLbl.Font = Enum.Font.GothamBold
memLbl.Text = "Memory: -- MB"; memLbl.TextColor3 = C.text; memLbl.TextSize = 11
memLbl.TextXAlignment = Enum.TextXAlignment.Left; memLbl.ZIndex = 33
local memSub = Instance.new("TextLabel", memFrame)
memSub.BackgroundTransparency = 1; memSub.Position = UDim2.new(0,10,0,24)
memSub.Size = UDim2.new(1,-20,0,24); memSub.Font = Enum.Font.Gotham
memSub.Text = "Lua heap usage"; memSub.TextColor3 = C.text3; memSub.TextSize = 9
memSub.TextXAlignment = Enum.TextXAlignment.Left; memSub.TextWrapped = true; memSub.ZIndex = 33

-- Clone Status Frame
local cloneFrame = Instance.new("Frame"); cloneFrame.Parent = TestingPanel
cloneFrame.Size = UDim2.new(1,0,0,80); cloneFrame.BackgroundColor3 = C.bg1
cloneFrame.BackgroundTransparency = 0.4; cloneFrame.BorderSizePixel = 0
cloneFrame.LayoutOrder = 3
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = cloneFrame
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = cloneFrame
end
local cloneLbl = Instance.new("TextLabel", cloneFrame)
cloneLbl.BackgroundTransparency = 1; cloneLbl.Position = UDim2.new(0,10,0,6)
cloneLbl.Size = UDim2.new(1,-20,0,16); cloneLbl.Font = Enum.Font.GothamBold
cloneLbl.Text = "Clone Status: Inactive"; cloneLbl.TextColor3 = C.text; cloneLbl.TextSize = 11
cloneLbl.TextXAlignment = Enum.TextXAlignment.Left; cloneLbl.ZIndex = 33
local cloneSub = Instance.new("TextLabel", cloneFrame)
cloneSub.BackgroundTransparency = 1; cloneSub.Position = UDim2.new(0,10,0,24)
cloneSub.Size = UDim2.new(1,-20,0,50); cloneSub.Font = Enum.Font.Gotham
cloneSub.Text = "Parts: 0 | Bones: 0 | Active Animation: None"; cloneSub.TextColor3 = C.text3; cloneSub.TextSize = 9
cloneSub.TextXAlignment = Enum.TextXAlignment.Left; cloneSub.TextWrapped = true; cloneSub.ZIndex = 33

-- Quick Actions Frame
local actionsFrame = Instance.new("Frame"); actionsFrame.Parent = TestingPanel
actionsFrame.Size = UDim2.new(1,0,0,90); actionsFrame.BackgroundColor3 = C.bg1
actionsFrame.BackgroundTransparency = 0.4; actionsFrame.BorderSizePixel = 0
actionsFrame.LayoutOrder = 4
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = actionsFrame
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = actionsFrame
end
local actLbl = Instance.new("TextLabel", actionsFrame)
actLbl.BackgroundTransparency = 1; actLbl.Position = UDim2.new(0,10,0,6)
actLbl.Size = UDim2.new(1,-20,0,16); actLbl.Font = Enum.Font.GothamBold
actLbl.Text = "Quick Actions"; actLbl.TextColor3 = C.accent; actLbl.TextSize = 11
actLbl.TextXAlignment = Enum.TextXAlignment.Left; actLbl.ZIndex = 33

local function makeTestBtn(text, xPos, color)
    local btn = Instance.new("TextButton", actionsFrame)
    btn.Size = UDim2.new(0, (actionsFrame.AbsoluteSize.X > 0 and actionsFrame.AbsoluteSize.X or 260)/2 - 12, 0, 26)
    btn.Position = UDim2.new(0, xPos, 0, 30)
    btn.BackgroundColor3 = color or C.bg2
    btn.BackgroundTransparency = 0.3; btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold; btn.Text = text
    btn.TextColor3 = C.text; btn.TextSize = 9; btn.ZIndex = 33; btn.AutoButtonColor = false
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = btn
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = btn
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0.1}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0.3}):Play()
    end)
    return btn
end

local rebuildBtn = makeTestBtn("Rebuild Clone", 10, C.bg2)
rebuildBtn.MouseButton1Click:Connect(function()
    if ReanimateAPI and ReanimateAPI.rebuild_clone then
        pcall(function() ReanimateAPI.rebuild_clone() end)
        Notify("Testing", "Clone rebuilt!", 2)
    else
        Notify("Testing", "API not ready", 2)
    end
end)

local invCacheBtn = makeTestBtn("Invalidate Cache", 10, C.bg2)
invCacheBtn.Position = UDim2.new(0.5, 4, 0, 30)
invCacheBtn.MouseButton1Click:Connect(function()
    if ReanimateAPI and ReanimateAPI.invalidate_constraint_cache then
        pcall(function() ReanimateAPI.invalidate_constraint_cache() end)
        Notify("Testing", "Constraint cache cleared!", 2)
    else
        Notify("Testing", "API not ready", 2)
    end
end)

local stopAllBtn = makeTestBtn("Stop All Anims", 10, Color3.fromRGB(180,60,60))
stopAllBtn.Position = UDim2.new(0, 10, 0, 60)
stopAllBtn.MouseButton1Click:Connect(function()
    pcall(function() ReanimateAPI.stop_animation() end)
    State.selectedAnim = nil
    if NowPlayingLabel then NowPlayingLabel.Text = "No animation playing" end
    Notify("Testing", "All animations stopped!", 2)
end)

local dumpBtn = makeTestBtn("Dump Bones", 10, C.bg2)
dumpBtn.Position = UDim2.new(0.5, 4, 0, 60)
dumpBtn.MouseButton1Click:Connect(function()
    local clone = ReanimateAPI and ReanimateAPI.get_clone and ReanimateAPI.get_clone(plr)
    if not clone then Notify("Testing", "No clone found", 2); return end
    local count = 0
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("AnimationConstraint") then count = count + 1 end
    end
    Notify("Testing", "Found " .. count .. " AnimationConstraints", 3)
end)

-- Stress Test Toggle
local stressFrame = Instance.new("Frame"); stressFrame.Parent = TestingPanel
stressFrame.Size = UDim2.new(1,0,0,54); stressFrame.BackgroundColor3 = C.bg1
stressFrame.BackgroundTransparency = 0.4; stressFrame.BorderSizePixel = 0
stressFrame.LayoutOrder = 5
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = stressFrame
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = stressFrame
end
local stressLbl = Instance.new("TextLabel", stressFrame)
stressLbl.BackgroundTransparency = 1; stressLbl.Position = UDim2.new(0,10,0,6)
stressLbl.Size = UDim2.new(1,-120,0,16); stressLbl.Font = Enum.Font.GothamBold
stressLbl.Text = "Stress Test"; stressLbl.TextColor3 = C.text; stressLbl.TextSize = 11
stressLbl.TextXAlignment = Enum.TextXAlignment.Left; stressLbl.ZIndex = 33
local stressSub = Instance.new("TextLabel", stressFrame)
stressSub.BackgroundTransparency = 1; stressSub.Position = UDim2.new(0,10,0,24)
stressSub.Size = UDim2.new(1,-120,0,24); stressSub.Font = Enum.Font.Gotham
stressSub.Text = "Rapidly cycles animations to test stability"; stressSub.TextColor3 = C.text3; stressSub.TextSize = 9
stressSub.TextXAlignment = Enum.TextXAlignment.Left; stressSub.TextWrapped = true; stressSub.ZIndex = 33
local stressToggleBg = Instance.new("Frame", stressFrame)
stressToggleBg.Size = UDim2.new(0,44,0,22); stressToggleBg.Position = UDim2.new(1,-54,0,16)
stressToggleBg.BackgroundColor3 = C.bg4; stressToggleBg.BorderSizePixel = 0; stressToggleBg.ZIndex = 33
local stc = Instance.new("UICorner", stressToggleBg); stc.CornerRadius = UDim.new(0,11)
local stressKnob = Instance.new("Frame", stressToggleBg)
stressKnob.Size = UDim2.new(0,16,0,16); stressKnob.Position = UDim2.new(0,3,0,3)
stressKnob.BackgroundColor3 = C.white; stressKnob.BorderSizePixel = 0; stressKnob.ZIndex = 34
local stck = Instance.new("UICorner", stressKnob); stck.CornerRadius = UDim.new(0,8)
local stressToggleBtn = Instance.new("TextButton", stressToggleBg)
stressToggleBtn.Size = UDim2.new(1,0,1,0); stressToggleBtn.BackgroundTransparency = 1; stressToggleBtn.Text = ""; stressToggleBtn.ZIndex = 35

local stressEnabled = false
local stressConn = nil
local function updateStressState()
    if stressEnabled then
        TweenService:Create(stressToggleBg, TweenInfo.new(0.2), {BackgroundColor3 = C.accent}):Play()
        TweenService:Create(stressKnob, TweenInfo.new(0.2), {Position = UDim2.new(1,-19,0,3)}):Play()
        local animNames = {}
        for name, _ in pairs(AnimationList) do table.insert(animNames, name) end
        stressConn = task.spawn(function()
            while stressEnabled and #animNames > 0 do
                local pick = animNames[math.random(1, #animNames)]
                pcall(function() PlayAnimation(pick, 1.0, false) end)
                task.wait(0.8)
            end
        end)
    else
        TweenService:Create(stressToggleBg, TweenInfo.new(0.2), {BackgroundColor3 = C.bg4}):Play()
        TweenService:Create(stressKnob, TweenInfo.new(0.2), {Position = UDim2.new(0,3,0,3)}):Play()
        if stressConn then stressConn = nil end
    end
end
stressToggleBtn.MouseButton1Click:Connect(function()
    stressEnabled = not stressEnabled
    updateStressState()
end)

-- Live diagnostics update loop
local lastTestUpdate = 0
RunService.RenderStepped:Connect(function()
    local now = tick()
    if now - lastTestUpdate < 0.5 then return end
    lastTestUpdate = now

    -- FPS (rough estimate from delta)
    local fps = math.floor(1 / math.max(RunService.RenderStepped:Wait(), 0.001))
    fpsLbl.Text = "FPS: " .. fps
    if fps >= 55 then fpsLbl.TextColor3 = C.accent
    elseif fps >= 30 then fpsLbl.TextColor3 = C.yellow
    else fpsLbl.TextColor3 = C.red end

    -- Memory
    local mem = math.floor(collectgarbage("count") / 1024 * 10) / 10
    memLbl.Text = "Memory: " .. mem .. " MB"

    -- Clone status
    local clone = ReanimateAPI and ReanimateAPI.get_clone and ReanimateAPI.get_clone(plr)
    if clone then
        local parts = 0
        local bones = 0
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then parts = parts + 1 end
            if d:IsA("AnimationConstraint") then bones = bones + 1 end
        end
        local playing = "None"
        if State.selectedAnim then playing = State.selectedAnim end
        cloneLbl.Text = "Clone Status: Active"
        cloneLbl.TextColor3 = C.accent
        cloneSub.Text = "Parts: " .. parts .. " | Bones: " .. bones .. " | Active: " .. playing
    else
        cloneLbl.Text = "Clone Status: Inactive"
        cloneLbl.TextColor3 = C.text3
        cloneSub.Text = "Parts: 0 | Bones: 0 | Active Animation: None"
    end
end)

StatesPanel.Parent = body
StatesPanel.Size = UDim2.new(1,-20,1,-128)
StatesPanel.Position = UDim2.new(0,10,0,88)
StatesPanel.BackgroundTransparency = 1; StatesPanel.BorderSizePixel = 0
StatesPanel.ZIndex = 32

-- States header label inside the StatesPanel
local statesHeader = Instance.new("TextLabel"); statesHeader.Parent = StatesPanel
statesHeader.BackgroundTransparency = 1; statesHeader.Size = UDim2.new(1,0,0,18)
statesHeader.Font = Enum.Font.GothamBold; statesHeader.TextSize = 11
statesHeader.Text = "State Animations"; statesHeader.TextColor3 = C.text
statesHeader.TextXAlignment = Enum.TextXAlignment.Left; statesHeader.ZIndex = 35

-- 1. Import from AK Frame
local akFrame = Instance.new("Frame", SettingsPanel)
akFrame.Size = UDim2.new(1,0,0,54)
akFrame.BackgroundColor3 = C.bg1; akFrame.BackgroundTransparency = 0.4; akFrame.BorderSizePixel = 0
akFrame.LayoutOrder = 1
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = akFrame
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = akFrame
end

local akLbl = Instance.new("TextLabel", akFrame)
akLbl.BackgroundTransparency = 1; akLbl.Position = UDim2.new(0,10,0,6)
akLbl.Size = UDim2.new(1,-120,0,16); akLbl.Font = Enum.Font.GothamBold
akLbl.Text = "Import Animations"; akLbl.TextColor3 = C.text; akLbl.TextSize = 11
akLbl.TextXAlignment = Enum.TextXAlignment.Left

local akSub = Instance.new("TextLabel", akFrame)
akSub.BackgroundTransparency = 1; akSub.Position = UDim2.new(0,10,0,24)
akSub.Size = UDim2.new(1,-120,0,24); akSub.Font = Enum.Font.Gotham
akSub.Text = "Import custom animations from AK config files"; akSub.TextColor3 = C.text3; akSub.TextSize = 9
akSub.TextXAlignment = Enum.TextXAlignment.Left; akSub.TextWrapped = true

local akBtn = Instance.new("TextButton", akFrame)
akBtn.Size = UDim2.new(0,96,0,24); akBtn.Position = UDim2.new(1,-102,0.5,-12)
akBtn.BackgroundColor3 = C.bg2; akBtn.BackgroundTransparency = 0.2; akBtn.BorderSizePixel = 0
akBtn.Font = Enum.Font.GothamBold; akBtn.Text = "Import"; akBtn.TextColor3 = C.accent; akBtn.TextSize = 10
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = akBtn
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = akBtn
end

-- 2. Fortnite Emote Wheel Keybind Frame
local fnWheelFrame = Instance.new("Frame", SettingsPanel)
fnWheelFrame.Size = UDim2.new(1,0,0,54)
fnWheelFrame.BackgroundColor3 = C.bg1; fnWheelFrame.BackgroundTransparency = 0.4; fnWheelFrame.BorderSizePixel = 0
fnWheelFrame.LayoutOrder = 2
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = fnWheelFrame
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = fnWheelFrame
end

local fnLbl = Instance.new("TextLabel", fnWheelFrame)
fnLbl.BackgroundTransparency = 1; fnLbl.Position = UDim2.new(0,10,0,6)
fnLbl.Size = UDim2.new(1,-120,0,16); fnLbl.Font = Enum.Font.GothamBold
fnLbl.Text = "Fortnite Emote Wheel"; fnLbl.TextColor3 = C.text; fnLbl.TextSize = 11
fnLbl.TextXAlignment = Enum.TextXAlignment.Left

local fnSub = Instance.new("TextLabel", fnWheelFrame)
fnSub.BackgroundTransparency = 1; fnSub.Position = UDim2.new(0,10,0,24)
fnSub.Size = UDim2.new(1,-120,0,24); fnSub.Font = Enum.Font.Gotham
fnSub.Text = "Hold bound key in-game to open Fortnite Wheel"; fnSub.TextColor3 = C.text3; fnSub.TextSize = 9
fnSub.TextXAlignment = Enum.TextXAlignment.Left; fnSub.TextWrapped = true

local fnWheelBtn = Instance.new("TextButton", fnWheelFrame)
fnWheelBtn.Size = UDim2.new(0,96,0,24); fnWheelBtn.Position = UDim2.new(1,-102,0.5,-12)
fnWheelBtn.BackgroundColor3 = C.bg2; fnWheelBtn.BackgroundTransparency = 0.2; fnWheelBtn.BorderSizePixel = 0
fnWheelBtn.Font = Enum.Font.GothamBold; fnWheelBtn.Text = "Key: None"; fnWheelBtn.TextColor3 = C.accent; fnWheelBtn.TextSize = 10
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = fnWheelBtn
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = fnWheelBtn
end

-- 3. Reverse Animation Frame
local revFrame = Instance.new("Frame", SettingsPanel)
revFrame.Size = UDim2.new(1,0,0,90)
revFrame.BackgroundColor3 = C.bg1; revFrame.BackgroundTransparency = 0.4; revFrame.BorderSizePixel = 0
revFrame.LayoutOrder = 3
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = revFrame
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = revFrame
end

local revLbl = Instance.new("TextLabel", revFrame)
revLbl.BackgroundTransparency = 1; revLbl.Position = UDim2.new(0,10,0,6)
revLbl.Size = UDim2.new(1,-120,0,16); revLbl.Font = Enum.Font.GothamBold
revLbl.Text = "Hold to Reverse Animation"; revLbl.TextColor3 = C.text; revLbl.TextSize = 11
revLbl.TextXAlignment = Enum.TextXAlignment.Left

local revSub = Instance.new("TextLabel", revFrame)
revSub.BackgroundTransparency = 1; revSub.Position = UDim2.new(0,10,0,24)
revSub.Size = UDim2.new(1,-120,0,24); revSub.Font = Enum.Font.Gotham
revSub.Text = "Hold key to reverse play direction"; revSub.TextColor3 = C.text3; revSub.TextSize = 9
revSub.TextXAlignment = Enum.TextXAlignment.Left; revSub.TextWrapped = true

local revBtn = Instance.new("TextButton", revFrame)
revBtn.Size = UDim2.new(0,96,0,24); revBtn.Position = UDim2.new(1,-102,0,16)
revBtn.BackgroundColor3 = C.bg2; revBtn.BackgroundTransparency = 0.2; revBtn.BorderSizePixel = 0
revBtn.Font = Enum.Font.GothamBold; revBtn.Text = "Key: None"; revBtn.TextColor3 = C.accent; revBtn.TextSize = 10
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = revBtn
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = revBtn
end

revSpdLbl = Instance.new("TextLabel", revFrame)
revSpdLbl.BackgroundTransparency = 1; revSpdLbl.Position = UDim2.new(0,10,0,54)
revSpdLbl.Size = UDim2.new(0,120,0,20); revSpdLbl.Font = Enum.Font.GothamBold
revSpdLbl.Text = "Reverse Speed: 1.0x"; revSpdLbl.TextColor3 = C.text2; revSpdLbl.TextSize = 9
revSpdLbl.TextXAlignment = Enum.TextXAlignment.Left

local revTrack = Instance.new("Frame", revFrame)
revTrack.BackgroundColor3 = C.bg2; revTrack.BackgroundTransparency = 0.3; revTrack.BorderSizePixel = 0
revTrack.Position = UDim2.new(0,125,0,60)
revTrack.Size = UDim2.new(1,-140,0,8)
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = revTrack
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = revTrack
end

revFill = Instance.new("Frame", revTrack)
revFill.BackgroundColor3 = C.accent; revFill.BackgroundTransparency = 0.1; revFill.BorderSizePixel = 0
revFill.Size = UDim2.new(0.31,0,1,0)
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = revFill end

revHandle = Instance.new("Frame", revTrack)
revHandle.AnchorPoint = Vector2.new(0.5,0.5)
revHandle.BackgroundColor3 = C.accent; revHandle.BackgroundTransparency = 0; revHandle.BorderSizePixel = 0
revHandle.Position = UDim2.new(0.31,0,0.5,0)
revHandle.Size = UDim2.new(0,12,0,12)
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = revHandle
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.4; s.Thickness = 1; s.Parent = revHandle
end

-- Reverse Drag and speed setting logic
local revDrag = false
revTrack.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        revDrag = true
        local pct = math.clamp((inp.Position.X - revTrack.AbsolutePosition.X) / revTrack.AbsoluteSize.X, 0, 1)
        GlobalReverseSpeed = math.floor((0.1 + pct * 2.9) * 10 + 0.5) / 10
        revFill.Size = UDim2.new(pct, 0, 1, 0)
        revHandle.Position = UDim2.new(pct, 0, 0.5, 0)
        revSpdLbl.Text = "Reverse Speed: " .. string.format("%.1f", GlobalReverseSpeed) .. "x"
    end
end)

UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 and revDrag then
        revDrag = false
        SaveData()
    end
end)

UserInputService.InputChanged:Connect(function(inp)
    if revDrag and inp.UserInputType == Enum.UserInputType.MouseMovement then
        local pct = math.clamp((inp.Position.X - revTrack.AbsolutePosition.X) / revTrack.AbsoluteSize.X, 0, 1)
        GlobalReverseSpeed = math.floor((0.1 + pct * 2.9) * 10 + 0.5) / 10
        revFill.Size = UDim2.new(pct, 0, 1, 0)
        revHandle.Position = UDim2.new(pct, 0, 0.5, 0)
        revSpdLbl.Text = "Reverse Speed: " .. string.format("%.1f", GlobalReverseSpeed) .. "x"
    end
end)

-- Keybind update function
updateFnWheelBtnText = function()
    local keyName = _G._FortniteWheelKey and _G._FortniteWheelKey.Name or "None"
    fnWheelBtn.Text = "Key: " .. keyName
end

updateRevBtnText = function()
    local keyName = GlobalReverseKeybind and GlobalReverseKeybind.Name or "None"
    revBtn.Text = "Key: " .. keyName
end

-- Wire up Fortnite keybind dialog
local settingWheelKey = false
fnWheelBtn.MouseButton1Click:Connect(function()
    if settingWheelKey then return end
    settingWheelKey = true
    fnWheelBtn.Text = "Listening..."
    fnWheelBtn.BackgroundColor3 = C.yellow
    local keyConn
    keyConn = UserInputService.InputBegan:Connect(LPH_NO_VIRTUALIZE(function(i, gp)
        if gp then return end
        keyConn:Disconnect()
        settingWheelKey = false
        fnWheelBtn.BackgroundColor3 = C.bg2
        if i.KeyCode == Enum.KeyCode.Escape then
            updateFnWheelBtnText()
            return
        end
        _G._FortniteWheelKey = i.KeyCode
        SaveData()
        updateFnWheelBtnText()
    end))
end)

-- Wire up Reverse keybind dialog
local settingRevKey = false
revBtn.MouseButton1Click:Connect(function()
    if settingRevKey then return end
    -- If a key is already bound, clicking the button unbinds it. The user has
    -- to click again to enter listening mode and pick a new key.
    if GlobalReverseKeybind then
        GlobalReverseKeybind = nil
        SaveData()
        updateRevBtnText()
        return
    end
    settingRevKey = true
    revBtn.Text = "Listening..."
    revBtn.BackgroundColor3 = C.yellow
    local keyConn
    keyConn = UserInputService.InputBegan:Connect(LPH_NO_VIRTUALIZE(function(i, gp)
        if gp then return end
        keyConn:Disconnect()
        settingRevKey = false
        revBtn.BackgroundColor3 = C.bg2
        if i.KeyCode == Enum.KeyCode.Escape then
            updateRevBtnText()
            return
        end
        GlobalReverseKeybind = i.KeyCode
        SaveData()
        updateRevBtnText()
    end))
end)

-- Wire up Import from AK button
akBtn.MouseButton1Click:Connect(function()
    -- Run the whole import on its own thread so a heavy file never blocks the UI,
    -- and so we can yield during processing.
    task.spawn(function()
    local success, errorMsg = pcall(function()
        local function notifyUser(msg, isError)
            if WindUI and WindUI.Notify then
                pcall(function()
                    WindUI:Notify({
                        Title = isError and "Import Error" or "Animation Import",
                        Content = msg,
                        Duration = 5,
                        Icon = isError and "alert-triangle" or "download"
                    })
                end)
            elseif NotifyLib and NotifyLib.send then
                pcall(function()
                    NotifyLib.send(msg, { duration = 5 })
                end)
            end
        end

        if not readfile then
            notifyUser("Executor doesn't support file reading.", true)
            return
        end
        local raw, foundPath = nil, nil
        local pathsToCheck = {
            "workspace/ custom_animations.json",         -- Potassium format with space
            "workspace/custom_animations.json",          -- Standard format
            " custom_animations.json",                   -- Direct with space
            "custom_animations.json",                    -- Direct without space
            "ak/custom_animations.json",
            "ak/ custom_animations.json",
            "../workspace/ custom_animations.json",
            "../workspace/custom_animations.json",
            "../../workspace/ custom_animations.json",   -- Two levels up
            "../../workspace/custom_animations.json",
        }
        for _, path in ipairs(pathsToCheck) do
            local ok, content
            if isfile then
                local isF = false
                pcall(function() isF = isfile(path) end)
                if isF then ok, content = pcall(readfile, path) end
            else
                ok, content = pcall(readfile, path)
            end
            if ok and content and content ~= "" then
                raw = content
                foundPath = path
                break
            end
        end
        if not raw then
            notifyUser("Could not locate custom_animations.json in workspace folder.", true)
            return
        end

        -- Strip optional UTF-8 BOM cheaply (no whole-string :gsub, which doubles
        -- memory). The CR/LF normalization that used to follow was unnecessary
        -- because JSONDecode handles those fine anyway.
        if raw:sub(1, 3) == "\xEF\xBB\xBF" then
            raw = raw:sub(4)
        end

        local data
        do
            local ok2, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
            if not ok2 or type(decoded) ~= "table" then
                notifyUser("Failed to parse JSON. File may be too large or malformed.", true)
                return
            end
            data = decoded
        end
        -- Drop the raw string reference so GC can reclaim its memory before we
        -- start building thousands of entries / writing thousands of files.
        raw = nil
        task.wait()
        if collectgarbage then pcall(collectgarbage, "collect") end

        local kbData = {}
        local kbPaths = {
            "workspace/animation_keybinds.json",         -- Potassium standard
            "workspace/ animation_keybinds.json",        -- With space
            "animation_keybinds.json",
            "ak/animation_keybinds.json",
            "../workspace/animation_keybinds.json",
            "../../workspace/animation_keybinds.json",   -- Two levels up
        }
        for _, path in ipairs(kbPaths) do
            local ok, content
            if isfile then
                local isF = false
                pcall(function() isF = isfile(path) end)
                if isF then ok, content = pcall(readfile, path) end
            else
                ok, content = pcall(readfile, path)
            end
            if ok and content and content ~= "" then
                if content:sub(1, 3) == "\xEF\xBB\xBF" then content = content:sub(4) end
                local ok3, parsedKb = pcall(function() return HttpService:JSONDecode(content) end)
                if ok3 and type(parsedKb) == "table" then
                    kbData = parsedKb
                    break
                end
            end
        end

        local count = 0
        local boundCount = 0
        local _byName = {}
        for _, val in ipairs(CustomAnims) do _byName[val.name] = val end

        -- Yield budget: yield a frame whenever we've used 12ms of CPU so the
        -- game never freezes even with thousands of animations.
        local _frameStart = os.clock()
        local function _maybeYield()
            if os.clock() - _frameStart > 0.012 then
                task.wait()
                _frameStart = os.clock()
            end
        end

        local function addAnim(name, script)
            if type(name) == "string" and type(script) == "string" and name ~= "" and script ~= "" then
                -- Keep the EXACT name from the AK file (trim surrounding whitespace only)
                local animName = name:match("^%s*(.-)%s*$")
                if animName ~= "" then
                    pcall(function() ReanimateAPI.seed_animation_cache(animName, nil) end)

                    -- Detect if the data is JSON keyframe data
                    local firstChar = script:match("^%s*(.)")
                    local isJson = (firstChar == "{" or firstChar == "[")

                    -- Write each animation to its OWN file in the ReanimData folder.
                    -- Only the FILENAME is sanitized (filesystem safety); the animation
                    -- name itself stays exactly as it is in the AK file.
                    local ext = isJson and ".json" or ".lua"
                    local safeBase = animName:gsub("[^%w_%-]", "_")
                    local filePath = fpath(safeBase .. ext)
                    local wrote = false
                    pcall(function()
                        writefile(filePath, script)
                        wrote = true
                    end)
                    local storedValue = wrote and filePath or script

                    local existing = _byName[animName]
                    if existing then
                        existing.url = storedValue
                        existing.raw = true
                        existing.isJson = isJson
                        CustomAnimations[animName] = storedValue
                    else
                        local entry = { name = animName, url = storedValue, raw = true, isJson = isJson }
                        table.insert(CustomAnims, entry)
                        _byName[animName] = entry
                        CustomAnimations[animName] = storedValue
                    end
                    count = count + 1

                    -- Auto-bind keybind if one exists for this animation.
                    -- Try the exact name and a few common key-name formats.
                    local kbKey = kbData[name] or kbData[animName]
                    if type(kbKey) == "string" and kbKey ~= "" then
                        local kc = nil
                        local attempts = {
                            kbKey,
                            kbKey:upper(),
                            (#kbKey == 1 and kbKey:upper() or kbKey),
                            "Key" .. kbKey:upper(),
                        }
                        for _, kn in ipairs(attempts) do
                            local ok, res = pcall(function() return Enum.KeyCode[kn] end)
                            if ok and res then kc = res; break end
                        end
                        if kc then
                            local keybindName = "[Custom] " .. animName
                            Keybinds[keybindName] = { key = kc, btn = nil }
                            boundCount = boundCount + 1
                        end
                    end
                end
            end
        end

        -- Snapshot the keys, then process and DELETE each entry from the source
        -- table as we consume it. Releasing entries one-by-one lets the GC
        -- reclaim each animation's memory as we go, which is what prevents
        -- "block too big" / "memory allocation" failures on huge AK exports.
        local keysToProcess = {}
        for k in pairs(data) do keysToProcess[#keysToProcess + 1] = k end
        for i = 1, #keysToProcess do
            local key = keysToProcess[i]
            local val = data[key]
            if type(key) == "string" and type(val) == "string" then
                addAnim(key, val)
            elseif type(val) == "table" then
                local animName = val.name or val.Name or val.title or val.Title
                local animScript = val.script or val.Script or val.content or val.Content or val.code or val.Code or val.data or val.Data
                if type(animName) == "string" and type(animScript) == "string" then
                    addAnim(animName, animScript)
                elseif type(animScript) == "table" then
                    local ok, enc = pcall(function() return HttpService:JSONEncode(animScript) end)
                    if ok and enc then addAnim(animName or key, enc) end
                else
                    local ok, encoded = pcall(function() return HttpService:JSONEncode(val) end)
                    if ok and encoded then addAnim(key, encoded) end
                end
            end
            -- Drop the consumed entry so the source JSON table can shrink
            data[key] = nil
            _maybeYield()
        end
        data = nil
        keysToProcess = nil
        if collectgarbage then pcall(collectgarbage, "collect") end

        SaveCustomAnims()
        SaveKeybindsOnly()
        SaveData()
        
        pcall(function()
            if RebuildCustomList then
                RebuildCustomList()
            elseif _G._ReanimRebuildCustomList then
                _G._ReanimRebuildCustomList()
            end
        end)
        pcall(function()
            if RebuildVisible then
                RebuildVisible()
            end
        end)
        
        if UpdateCustomTabCount then
            UpdateCustomTabCount()
        end
        
        if count > 0 then
            notifyUser("Imported " .. count .. " animation(s), bound " .. boundCount .. " key(s)!")
        else
            notifyUser("No new animations imported.")
        end
    end)
    
    if not success then
        if WindUI and WindUI.Notify then
            pcall(function()
                WindUI:Notify({
                    Title = "Import Error",
                    Content = tostring(errorMsg),
                    Duration = 5,
                    Icon = "alert-triangle"
                })
            end)
        end
    end
    end) -- close the outer task.spawn that wraps the whole import
end)
end

local VROW_H     = 28
local VPAD       = 3
local VPOOL_SIZE = 16

local visibleAnims     = {}
local vPool            = {}
local animRowWidgets   = {}
local _rebuildAnimVer  = 0
local RefreshVirtualRows
local _createAnimRow
local customRowWidgets = {}
local RefreshCustomRows
-- Virtualization state: which slice of each list is currently built, and the
-- filtered/sorted custom-animation list that the custom window draws from.
local visibleCustom    = {}
local _animWinStart    = -1
local _customWinStart  = -1

local function CancelListening()
    if listeningKeyBtn then
        local id    = listenTarget and listenTarget.name
        local bound = id and Keybinds[id]
        listeningKeyBtn.Text             = bound and ("[" .. bound.key.Name .. "]") or "[+]"
        listeningKeyBtn.BackgroundColor3 = bound and C.bg3 or C.bg2
        listeningKeyBtn.TextColor3       = bound and C.accent or C.text3
        listeningKeyBtn = nil
    end
    listenTarget = nil
end

local function BindKey(keyCode)
    if not listenTarget then return end
    local name = listenTarget.name
    local btn  = listenTarget.keyBtn
    for existName, data in pairs(Keybinds) do
        if data.key == keyCode and existName ~= name then
            data.key = nil
            if data.btn and data.btn.Parent then
                data.btn.Text = "[+]"; data.btn.BackgroundColor3 = C.bg2
                data.btn.TextColor3 = C.text3
            end
        end
    end
    Keybinds[name] = { key = keyCode, btn = btn }
    btn.Text = "[" .. keyCode.Name .. "]"
    btn.BackgroundColor3 = C.bg3
    btn.TextColor3 = C.accent
    listeningKeyBtn = nil; listenTarget = nil
    SaveKeybindsOnly()
    Notify(keyCode.Name .. " -> " .. name, 2)
    
    -- Refresh Binds tab if it's currently active
    if State.currentTab == "Binds" then
        task.defer(RebuildBindsList)
    end
end

function UnbindKey(name, btn)
    Keybinds[name] = nil
    btn.Text = "[+]"; btn.BackgroundColor3 = C.bg2
    btn.TextColor3 = C.text3
    SaveKeybindsOnly()
end

function StopAnimation()
    ReanimateAPI.stop_animation()
    State.currentlyPlaying = nil
    State.selectedAnim     = nil
    if NowPlayingLabel then NowPlayingLabel.Text = "No animation playing" end
    if stopEmoteAudio then
        stopEmoteAudio(true)
    end
    -- Re-kick the state system so states resume immediately after manual stop
    if stateSystemActive and State.isReanimated then
        currentStateAnim = nil
        lastLogical = nil
    end
end

StopBtn.MouseButton1Click:Connect(StopAnimation)

local pendingAnim    = nil
local animWorkerBusy = false

function PlayAnimation(animName, speed, isCustom)
    if not ReanimateAPI.is_reanimated() then 
        Notify("TRX Error", "Cannot play animation, not reanimated.", 3)
        return false 
    end

    local cleanName = animName:gsub("^%[Custom%] ", "")
    local isCustomAnim = isCustom or (CustomAnimations[cleanName] ~= nil)

    local function runPlay()
        local content
        if isCustomAnim then
            local fp = CustomAnimations[cleanName]
            if not fp then 
                Notify("Play Error", "Custom animation file path not found.", 4)
                return false 
            end
            -- Cache custom animations in memory; only re-read/re-parse on cache miss
            if not ReanimateAPI.get_animation_cache(cleanName) then
                local ok2, fileContent
                if type(fp) == "table" and fp.type == "ak" then
                    ok2, fileContent = true, fp.script
                else
                    local fpIsFile = false
                    if type(fp) == "string" then
                        if isfile then
                            local okF, resF = pcall(isfile, fp)
                            if okF and resF then
                                fpIsFile = true
                            end
                        end
                    end
                    if fpIsFile then
                        ok2, fileContent = pcall(readfile, fp)
                    else
                        ok2, fileContent = true, fp
                    end
                end
                if not ok2 or not fileContent or fileContent == "" then
                    Notify("Play Error", "Failed to read custom animation file.", 4)
                    return false
                end
                content = fileContent
                content = content:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
                local firstChar = content:match("^%s*(.)")
                if firstChar == "[" or firstChar == "{" then
                    local parsed = parseJsonAnimation(content)
                    if not parsed then
                        local loaded_fn, err = loadstring("return " .. content)
                        if not loaded_fn then
                            loaded_fn, err = loadstring(content)
                        end
                        if loaded_fn then
                            local ok, data = pcall(function() return loaded_fn() end)
                            if ok and type(data) == "table" then
                                parsed = parseTableAnimation(data)
                            end
                        end
                    end
                    if not parsed then
                        Notify("Format Error", "Failed to parse custom animation.", 6)
                        return false
                    end
                    ReanimateAPI.seed_animation_cache(cleanName, parsed)
                else
                    -- Fix return-wrapped compiler syntax issues
                    if content:match("^%s*return%s*{%s*local") then
                        content = content:gsub("^%s*return%s*{%s*local", "local")
                        local varName = content:match("^%s*local%s+([%w_]+)%s*=")
                        if varName then
                            content = content:gsub("}%s*$", "")
                            content = content:gsub("return%s+[%w_]+%s*$", "")
                            content = content .. "\nreturn " .. varName
                        end
                    end

                    local loaded_fn, err = loadstring(content)
                    if not loaded_fn then
                        Notify("Compile Error", "Syntax error in custom animation: " .. tostring(err), 6)
                        return false
                    end
                    local ok, data = pcall(function() return loaded_fn() end)
                    if not ok then
                        Notify("Execution Error", "Failed to run custom animation: " .. tostring(data), 6)
                        return false
                    end
                    if typeof(data) ~= "table" then
                        Notify("Format Error", "Custom animation must return a table.", 6)
                        return false
                    end
                    local parsed = parseTableAnimation(data)
                    if not parsed then
                        parsed = data
                    end
                    ReanimateAPI.seed_animation_cache(cleanName, parsed)
                end
            end
            content = content or "cached"
        else
            -- Online animations - use cache
            content = AnimationCache[cleanName]
            if not content then
                local cachePath = GetCachePath(cleanName)
                local ok, cached = pcall(readfile, cachePath)
                if ok and cached and cached ~= "" then
                    content = cached
                    AnimationCache[cleanName] = content
                end
            end
            
            if not content then
                local url = AnimationList[cleanName]
                if not url then return false end
                local downloaded = request_get(url)
                if downloaded and downloaded ~= "" then
                    content = downloaded
                    AnimationCache[cleanName] = content
                    task.spawn(function()
                        pcall(writefile, GetCachePath(cleanName), content)
                    end)
                else
                    Notify("Download Error", "Failed to download animation.", 4)
                    return false
                end
            end
            
            -- Pre-compile and seed API cache on first load so play_raw_animation never calls loadstring again
            if not ReanimateAPI.get_animation_cache(cleanName) then
                -- Strip UTF-8 BOM and normalize line endings to prevent parse errors
                content = content:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
                
                -- Fix return-wrapped compiler syntax issues
                if content:match("^%s*return%s*{%s*local") then
                    content = content:gsub("^%s*return%s*{%s*local", "local")
                    local varName = content:match("^%s*local%s+([%w_]+)%s*=")
                    if varName then
                        content = content:gsub("}%s*$", "")
                        content = content:gsub("return%s+[%w_]+%s*$", "")
                        content = content .. "\nreturn " .. varName
                    end
                end

                local loaded_fn, err = loadstring(content)
                if not loaded_fn then
                    Notify("Compile Error", tostring(err), 5)
                    return false
                end
                local ok, data = pcall(function() return loaded_fn() end)
                if not ok then
                    Notify("Execution Error", tostring(data), 5)
                    return false
                end
                if typeof(data) ~= "table" then
                    Notify("Format Error", "Animation did not return a table.", 5)
                    return false
                end
                ReanimateAPI.seed_animation_cache(cleanName, data)
            end
        end

        -- Cache is always seeded above; force_reload=false so API uses it directly
        local result = ReanimateAPI.play_raw_animation(cleanName, content or "", speed or State.currentSpeed, false)
        if type(result) == "string" then 
            Notify("Play Error", result, 5)
            return false 
        end
        return true
    end

    -- If this exact animation is already playing, pressing the keybind/button again should stop it
    if State.selectedAnim == animName then
        StopAnimation()
        return true
    end

    -- Stop any active state animation first, before setting selectedAnim,
    -- so the heartbeat cannot race-stop the animation we are about to start.
    if currentStateAnim then
        pcall(function() ReanimateAPI.stop_animation() end)
        currentStateAnim = nil
    end

    -- Stop any animation currently playing before we begin the new one
    pcall(function() ReanimateAPI.stop_animation() end)

    State.currentlyPlaying = cleanName
    State.selectedAnim     = animName
    if NowPlayingLabel then NowPlayingLabel.Text = cleanName end

    -- Run the heavy loadstring/parse work off the main thread to avoid freezing
    task.spawn(function()
        local success = runPlay()
        if not success then
            State.currentlyPlaying = nil
            State.selectedAnim     = nil
            if NowPlayingLabel then NowPlayingLabel.Text = "No animation playing" end
            -- Re-kick the state system so states resume after a failed play
            if stateSystemActive and State.isReanimated then
                currentStateAnim = nil
                lastLogical = nil
            end
        end
    end)
    return true
end

-- Create a single real row for one animation. Closures capture `anim` directly
-- (no virtual pool). Returns the widget table.
_createAnimRow = function(anim, yPos)
    local displayName = anim.name:gsub("%.lua$", "")

    local row = Instance.new("Frame")
    row.Name = "AnimRow"; row.Parent = AnimListFrame
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1,-10,0,VROW_H-4)
    row.Position = UDim2.new(0,5,0,yPos)
    row.ZIndex = 33; row.Visible = true

    local playBtn = Instance.new("TextButton"); playBtn.Parent = row
    playBtn.BackgroundColor3 = C.bg2
    playBtn.BackgroundTransparency = 0.5; playBtn.BorderSizePixel = 0
    playBtn.Size = UDim2.new(1,-82,1,0)
    playBtn.Font = Enum.Font.GothamMedium; playBtn.Text = displayName
    playBtn.TextColor3 = C.text2; playBtn.TextSize = 11
    playBtn.TextXAlignment = Enum.TextXAlignment.Left
    playBtn.TextTruncate = Enum.TextTruncate.AtEnd
    playBtn.ZIndex = 34; playBtn.AutoButtonColor = false
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = playBtn
        local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,10); p.Parent = playBtn
        local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.8; s.Thickness = 1; s.Parent = playBtn
    end

    local favBtn = Instance.new("TextButton"); favBtn.Parent = row
    favBtn.BackgroundColor3 = C.bg2
    favBtn.BackgroundTransparency = 0.3; favBtn.BorderSizePixel = 0
    favBtn.Position = UDim2.new(1,-80,0,0)
    favBtn.Size = UDim2.new(0,26,1,0); favBtn.Font = Enum.Font.GothamBold
    favBtn.Text = ""; favBtn.ZIndex = 34; favBtn.AutoButtonColor = false
    local favIcon
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = favBtn
        local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.8; s.Thickness = 1; s.Parent = favBtn
        favIcon = Instance.new("ImageLabel"); favIcon.Name = "Icon"; favIcon.Parent = favBtn
        favIcon.BackgroundTransparency = 1; favIcon.AnchorPoint = Vector2.new(0.5,0.5)
        favIcon.Position = UDim2.new(0.5,0,0.5,0); favIcon.Size = UDim2.new(0,14,0,14)
        favIcon.Image = CONFIG.ICONS.STAR_OUTLINE; favIcon.ZIndex = 35
    end

    local keyBtn = Instance.new("TextButton"); keyBtn.Parent = row
    keyBtn.BackgroundColor3 = C.bg2
    keyBtn.BackgroundTransparency = 0.3; keyBtn.BorderSizePixel = 0
    keyBtn.Position = UDim2.new(1,-50,0,0)
    keyBtn.Size = UDim2.new(0,46,1,0); keyBtn.Font = Enum.Font.GothamBold
    keyBtn.Text = ""; keyBtn.TextColor3 = C.text3
    keyBtn.TextSize = 9; keyBtn.ZIndex = 34; keyBtn.AutoButtonColor = false
    local keyIcon
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = keyBtn
        local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.8; s.Thickness = 1; s.Parent = keyBtn
        keyIcon = Instance.new("ImageLabel"); keyIcon.Name = "Icon"; keyIcon.Parent = keyBtn
        keyIcon.BackgroundTransparency = 1; keyIcon.AnchorPoint = Vector2.new(0.5,0.5)
        keyIcon.Position = UDim2.new(0.5,0,0.5,0); keyIcon.Size = UDim2.new(0,14,0,14)
        keyIcon.Image = CONFIG.ICONS.KEYBOARD; keyIcon.ZIndex = 35
    end

    local widget = { row=row, playBtn=playBtn, favBtn=favBtn, keyBtn=keyBtn,
                     favIcon=favIcon, keyIcon=keyIcon, anim=anim }

    -- Apply initial visual state
    local function refresh()
        local isPlaying = State.selectedAnim == anim.name
        playBtn.Text = (isPlaying and "> " or "") .. displayName
        playBtn.BackgroundColor3 = isPlaying and C.accent or C.bg2
        playBtn.BackgroundTransparency = isPlaying and 0.2 or 0.5
        playBtn.TextColor3 = isPlaying and Color3.fromRGB(0,0,0) or C.text2

        local isFav = Favorites[anim.name] ~= nil
        if favIcon then favIcon.Image = isFav and CONFIG.ICONS.STAR_FILLED or CONFIG.ICONS.STAR_OUTLINE end
        favBtn.BackgroundColor3 = isFav and C.yellow or C.bg2
        favBtn.BackgroundTransparency = isFav and 0 or 0.3

        local bound = Keybinds[anim.name]
        if listenTarget and listenTarget.name == anim.name then
            listeningKeyBtn = keyBtn
            listenTarget.keyBtn = keyBtn
            keyBtn.Text = "[ ? ]"
            if keyIcon then keyIcon.Visible = false end
            keyBtn.BackgroundColor3 = Color3.fromRGB(0,140,255)
            keyBtn.BackgroundTransparency = 0.1
            keyBtn.TextColor3 = Color3.fromRGB(255,255,255)
        elseif bound then
            keyBtn.Text = "["..bound.key.Name.."]"
            if keyIcon then keyIcon.Visible = false end
            Keybinds[anim.name].btn = keyBtn
            keyBtn.BackgroundColor3 = C.bg3
            keyBtn.BackgroundTransparency = 0.1
            keyBtn.TextColor3 = C.accent
        else
            keyBtn.Text = ""
            if keyIcon then keyIcon.Visible = true; keyIcon.Image = CONFIG.ICONS.KEYBOARD end
            keyBtn.BackgroundColor3 = C.bg2
            keyBtn.BackgroundTransparency = 0.3
            keyBtn.TextColor3 = C.text3
        end
    end
    widget.refresh = refresh
    refresh()

    playBtn.MouseEnter:Connect(function()
        local isPlaying = State.selectedAnim == anim.name
        TweenService:Create(playBtn, TweenInfo.new(0.15), {
            BackgroundTransparency = isPlaying and 0.1 or 0.35,
            Size = UDim2.new(1,-78,1,2)
        }):Play()
    end)
    playBtn.MouseLeave:Connect(function()
        local isPlaying = State.selectedAnim == anim.name
        TweenService:Create(playBtn, TweenInfo.new(0.15), {
            BackgroundTransparency = isPlaying and 0.2 or 0.5,
            Size = UDim2.new(1,-82,1,0)
        }):Play()
    end)
    playBtn.MouseButton1Click:Connect(function()
        if anim.name and anim.url then
            PlayAnimation(anim.name, State.currentSpeed, anim.raw)
            task.defer(function() if RefreshVirtualRows then RefreshVirtualRows() end end)
        end
    end)

    favBtn.MouseButton1Click:Connect(function()
        if Favorites[anim.name] then
            Favorites[anim.name] = nil
            Notify("Removed from favourites", 1.5)
        else
            Favorites[anim.name] = true
            Notify("Added to favourites!", 1.5)
        end
        refresh()
        SaveFavoritesOnly()
        if State.currentTab == "Favs" then task.defer(RebuildVisible) end
    end)

    keyBtn.MouseButton1Click:Connect(function()
        if Keybinds[anim.name] and listeningKeyBtn ~= keyBtn then
            UnbindKey(anim.name, keyBtn)
            refresh()
            return
        end
        if listeningKeyBtn then CancelListening() end
        listeningKeyBtn = keyBtn
        listenTarget = { name=anim.name, url=anim.url, keyBtn=keyBtn }
        keyBtn.Text = "[ ? ]"; keyBtn.BackgroundColor3 = Color3.fromRGB(0,140,255)
        keyBtn.TextColor3 = Color3.fromRGB(255,255,255)
    end)

    return widget
end

-- BuildRowPool is no longer needed (rows are real, created by RebuildVisible).
function BuildRowPool() end

-- Windowed virtualization: only build rows for the slice of animations that are
-- actually visible in the scroll viewport (plus a small buffer), and rebuild
-- that slice as the user scrolls. This keeps the number of live UI Instances
-- tiny (~a dozen) no matter how many animations are imported, which is what
-- stops large AK imports from freezing / crashing the game.
local updatingVirtual = false
RefreshVirtualRows = function()
    if not AnimListFrame or updatingVirtual then return end
    updatingVirtual = true

    local winH = 320
    pcall(function()
        local aws = AnimListFrame.AbsoluteWindowSize
        if aws and aws.Y > 0 then
            winH = aws.Y
        else
            winH = AnimListFrame.AbsoluteSize.Y
        end
    end)
    if winH <= 0 then winH = 320 end
    local scrollY  = AnimListFrame.CanvasPosition.Y
    local visCount = math.ceil(winH / VROW_H) + 3  -- rows on screen + buffer
    local startIdx = math.max(1, math.floor((scrollY - VPAD) / VROW_H))  -- 1 row of top buffer
    local endIdx   = math.min(#visibleAnims, startIdx + visCount)

    if startIdx == _animWinStart then
        for _, w in ipairs(animRowWidgets) do
            if w and w.refresh and w.row and w.row.Parent then pcall(w.refresh) end
        end
        updatingVirtual = false
        return
    end
    _animWinStart = startIdx

    -- Rebuild the slice: destroy the old rows and create only the visible ones.
    _rebuildAnimVer = (_rebuildAnimVer or 0) + 1
    for _, c in ipairs(AnimListFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    animRowWidgets = {}
    local wi = 1
    for i = startIdx, endIdx do
        local anim = visibleAnims[i]
        if anim then
            local yPos = VPAD + (i - 1) * VROW_H
            animRowWidgets[wi] = _createAnimRow(anim, yPos)
            wi = wi + 1
        end
    end

    task.spawn(function()
        pcall(function()
            AnimListFrame.CanvasPosition = Vector2.new(0, scrollY)
        end)
        task.wait()
        pcall(function()
            AnimListFrame.CanvasPosition = Vector2.new(0, scrollY)
        end)
        updatingVirtual = false
    end)
end

local RebuildVisible
RebuildVisible = function()
    visibleAnims = {}
    local term = SearchBox.Text:lower()
    local tab  = State.currentTab

    if tab == "Custom" or tab == "Settings" or tab == "States" or tab == "Speed" or tab == "Testing" then
        AnimListFrame.Visible = false
        CustomPanel.Visible   = (tab == "Custom")
        StatesPanel.Visible   = (tab == "States")
        SettingsPanel.Visible = (tab == "Settings")
        SpeedPanel.Visible    = (tab == "Speed")
        TestingPanel.Visible  = (tab == "Testing")
        return
    end

    AnimListFrame.Visible = true
    CustomPanel.Visible   = false
    StatesPanel.Visible   = false
    SettingsPanel.Visible = false
    SpeedPanel.Visible    = false

    local source = {}
    if tab == "All" then
        for name, url in pairs(AnimationList) do
            table.insert(source, { name=name, url=url, raw=false })
        end
    elseif tab == "Favs" then
        for name, _ in pairs(Favorites) do
            local url = AnimationList[name]
            if url then
                table.insert(source, { name=name, url=url, raw=false })
            else
                local plain = name:match("^%[Custom%] (.+)$") or name
                for _, ca in ipairs(CustomAnims) do
                    if ca.name == plain then
                        table.insert(source, { name=name, url=ca.url, raw=ca.raw })
                        break
                    end
                end
            end
        end
    end

    table.sort(source, function(a, b) return a.name < b.name end)

    for _, e in ipairs(source) do
        if term == "" or e.name:lower():find(term, 1, true) then
            table.insert(visibleAnims, e)
        end
    end

    -- Virtualized list: set the canvas to the full height, reset scroll, then
    -- let RefreshVirtualRows build only the rows visible in the viewport.
    local totalH = VPAD*2 + #visibleAnims * VROW_H
    AnimListFrame.CanvasSize = UDim2.new(0,0,0,totalH)
    AnimListFrame.CanvasPosition = Vector2.new(0,0)
    _animWinStart = -1  -- force a fresh window build
    RefreshVirtualRows()
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(RebuildVisible)

-- Rebuild the visible row window whenever the list is scrolled.
AnimListFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(RefreshVirtualRows)

-- Build one custom-anim row and wire up its buttons.
-- Returns the widget table so the caller can store it.
local function _createCustomRow(ca, yPos)
    local row = Instance.new("Frame"); row.Parent = customListFrame
    row.BackgroundTransparency = 1; row.BorderSizePixel = 0
    row.Size = UDim2.new(1,-12,0,VROW_H-4); row.ZIndex = 34
    row.Position = UDim2.new(0,6,0,yPos or 0)

    local playBtn = Instance.new("TextButton"); playBtn.Parent = row
    playBtn.BackgroundColor3 = C.bg2
    playBtn.BackgroundTransparency = 0.5; playBtn.BorderSizePixel = 0
    playBtn.Size = UDim2.new(1,-114,1,0)
    playBtn.Font = Enum.Font.GothamMedium; playBtn.Text = ca.name:gsub("%.lua$","")
    playBtn.TextColor3 = C.text2; playBtn.TextSize = 11
    playBtn.TextXAlignment = Enum.TextXAlignment.Left
    playBtn.TextTruncate = Enum.TextTruncate.AtEnd
    playBtn.ZIndex = 35; playBtn.AutoButtonColor = false
    do
        local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0,8); c2.Parent = playBtn
        local p  = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,10); p.Parent = playBtn
        local s2 = Instance.new("UIStroke"); s2.Color = C.border; s2.Transparency = 0.8; s2.Thickness = 1; s2.Parent = playBtn
    end

    local favBtn = Instance.new("TextButton"); favBtn.Parent = row
    favBtn.BackgroundColor3 = C.bg2; favBtn.BackgroundTransparency = 0.3
    favBtn.BorderSizePixel = 0; favBtn.Position = UDim2.new(1,-110,0,0)
    favBtn.Size = UDim2.new(0,26,1,0); favBtn.Font = Enum.Font.GothamBold
    favBtn.Text = ""; favBtn.ZIndex = 35; favBtn.AutoButtonColor = false
    do
        local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0,5); c2.Parent = favBtn
        local ico = Instance.new("ImageLabel"); ico.Name = "Icon"; ico.Parent = favBtn
        ico.BackgroundTransparency = 1; ico.AnchorPoint = Vector2.new(0.5,0.5)
        ico.Position = UDim2.new(0.5,0,0.5,0); ico.Size = UDim2.new(0,14,0,14)
        ico.Image = CONFIG.ICONS.STAR_OUTLINE; ico.ZIndex = 36
    end

    local keyBtn = Instance.new("TextButton"); keyBtn.Parent = row
    keyBtn.BackgroundColor3 = C.bg2; keyBtn.BackgroundTransparency = 0.2
    keyBtn.BorderSizePixel = 0; keyBtn.Position = UDim2.new(1,-80,0,0)
    keyBtn.Size = UDim2.new(0,46,1,0); keyBtn.Font = Enum.Font.GothamBold
    keyBtn.Text = ""; keyBtn.TextColor3 = C.text3
    keyBtn.TextSize = 9; keyBtn.ZIndex = 35; keyBtn.AutoButtonColor = false
    do
        local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0,5); c2.Parent = keyBtn
        local ico = Instance.new("ImageLabel"); ico.Name = "Icon"; ico.Parent = keyBtn
        ico.BackgroundTransparency = 1; ico.AnchorPoint = Vector2.new(0.5,0.5)
        ico.Position = UDim2.new(0.5,0,0.5,0); ico.Size = UDim2.new(0,14,0,14)
        ico.Image = CONFIG.ICONS.KEYBOARD; ico.ZIndex = 36
    end

    local delBtn = Instance.new("TextButton"); delBtn.Parent = row
    delBtn.BackgroundColor3 = Color3.fromRGB(200,70,70); delBtn.BackgroundTransparency = 0.3
    delBtn.BorderSizePixel = 0; delBtn.Position = UDim2.new(1,-30,0,0)
    delBtn.Size = UDim2.new(0,26,1,0); delBtn.Text = ""
    delBtn.ZIndex = 35; delBtn.AutoButtonColor = false
    do
        local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0,5); c2.Parent = delBtn
        local ico = Instance.new("ImageLabel"); ico.Parent = delBtn
        ico.BackgroundTransparency = 1; ico.AnchorPoint = Vector2.new(0.5,0.5)
        ico.Position = UDim2.new(0.5,0,0.5,0); ico.Size = UDim2.new(0,12,0,12)
        ico.Image = "rbxassetid://6031094678"
        ico.ImageColor3 = Color3.fromRGB(255,255,255); ico.ZIndex = 36
    end

    -- Hover / press visuals
    playBtn.MouseEnter:Connect(function()
        if State.selectedAnim ~= ca.name then
            TweenService:Create(playBtn, TweenInfo.new(0.15), {BackgroundTransparency = 0.35, Size = UDim2.new(1,-110,1,2)}):Play()
        end
    end)
    playBtn.MouseLeave:Connect(function()
        TweenService:Create(playBtn, TweenInfo.new(0.15), {
            BackgroundTransparency = (State.selectedAnim == ca.name) and 0.2 or 0.5,
            Size = UDim2.new(1,-114,1,0)
        }):Play()
    end)
    playBtn.MouseButton1Down:Connect(function()
        TweenService:Create(playBtn, TweenInfo.new(0.08), {BackgroundTransparency = 0.25}):Play()
    end)
    delBtn.MouseEnter:Connect(function()
        TweenService:Create(delBtn, TweenInfo.new(0.1), {BackgroundTransparency = 0}):Play()
    end)
    delBtn.MouseLeave:Connect(function()
        TweenService:Create(delBtn, TweenInfo.new(0.1), {BackgroundTransparency = 0.3}):Play()
    end)

    -- Widget table (caIdx is mutable via upvalue trick — use a holder table)
    local w = { playBtn=playBtn, favBtn=favBtn, keyBtn=keyBtn, delBtn=delBtn,
                name=ca.name, row=row }

    playBtn.MouseButton1Click:Connect(function()
        PlayAnimation(ca.name, State.currentSpeed, true)
        task.defer(function() if RefreshCustomRows then RefreshCustomRows() end end)
    end)

    favBtn.MouseButton1Click:Connect(function()
        local favKey = "[Custom] " .. ca.name
        local favIcon = favBtn:FindFirstChild("Icon")
        if Favorites[favKey] then
            Favorites[favKey] = nil
            TweenService:Create(favBtn, TweenInfo.new(0.15), {
                BackgroundColor3 = C.bg2, BackgroundTransparency = 0.3 }):Play()
            if favIcon then favIcon.Image = CONFIG.ICONS.STAR_OUTLINE end
            Notify("Removed from favourites", 1.5)
        else
            Favorites[favKey] = true
            TweenService:Create(favBtn, TweenInfo.new(0.15), {
                BackgroundColor3 = C.yellow, BackgroundTransparency = 0 }):Play()
            if favIcon then favIcon.Image = CONFIG.ICONS.STAR_FILLED end
            Notify("Added to favourites!", 1.5)
        end
        SaveFavoritesOnly()
        if State.currentTab == "Favs" then task.defer(RebuildVisible) end
    end)

    keyBtn.MouseButton1Click:Connect(function()
        local ckName = "[Custom] " .. ca.name
        local keyIcon = keyBtn:FindFirstChild("Icon")
        if Keybinds[ckName] and listeningKeyBtn ~= keyBtn then
            UnbindKey(ckName, keyBtn)
            local bound = Keybinds[ckName]
            if bound then
                keyBtn.Text = "["..bound.key.Name.."]"
                if keyIcon then keyIcon.Visible = false end
            else
                keyBtn.Text = ""
                if keyIcon then keyIcon.Visible = true; keyIcon.Image = CONFIG.ICONS.KEYBOARD end
            end
            keyBtn.BackgroundColor3 = bound and C.bg3 or C.bg2
            keyBtn.TextColor3 = bound and C.accent or C.text3
            return
        end
        if listeningKeyBtn then CancelListening() end
        listeningKeyBtn = keyBtn
        listenTarget = { name = ckName, url = ca.url, keyBtn = keyBtn }
        keyBtn.Text = "[ ? ]"; keyBtn.BackgroundColor3 = Color3.fromRGB(0,140,255)
        keyBtn.TextColor3 = Color3.fromRGB(255,255,255)
        if keyIcon then keyIcon.Visible = false end
    end)

    delBtn.MouseButton1Click:Connect(function()
        -- Find current index of this anim in case the list shifted
        local currentIdx = nil
        for i, v in ipairs(CustomAnims) do
            if v.name == ca.name then currentIdx = i; break end
        end
        if not currentIdx then 
            return 
        end
        if State.selectedAnim == ca.name then StopAnimation() end
        local animName = ca.name
        
        -- Delete the actual file(s) from disk
        local animEntry = CustomAnims[currentIdx]
        if animEntry then
            local content = animEntry.url or animEntry.file
            local deleteFunc = delfile or deletefile or function() end
            
            if type(content) == "string" then
                pcall(function() deleteFunc(content) end)
                
                -- Also try variations of the filename
                local baseName = animName:gsub("%.lua$", ""):gsub("%.json$", "")
                local possiblePaths = {
                    content,
                    fpath("custom_" .. baseName .. ".dat"),
                    fpath(baseName .. ".lua"),
                    fpath(baseName .. ".json"),
                    "ReanimData/" .. baseName .. ".lua",
                    "ReanimData/" .. baseName .. ".json",
                    "ReanimData/" .. animName,
                }
                
                for _, path in ipairs(possiblePaths) do
                    pcall(function() deleteFunc(path) end)
                end
            end
        end
        
        table.remove(CustomAnims, currentIdx)
        CustomAnimations[animName] = nil
        
        SaveCustomAnims()
        SaveData()
        
        if UpdateCustomTabCount then
            UpdateCustomTabCount()
        end
        
        if RebuildCustomList then RebuildCustomList() end
        
        Notify("Deleted: " .. animName, 2)
    end)

    -- Apply / refresh visual state (also used by RefreshCustomRows on scroll).
    local function refresh()
        local isFav = Favorites["[Custom] " .. ca.name] ~= nil
        local favIcon = favBtn:FindFirstChild("Icon")
        if favIcon then
            favIcon.Image = isFav and CONFIG.ICONS.STAR_FILLED or CONFIG.ICONS.STAR_OUTLINE
        end
        favBtn.BackgroundColor3 = isFav and C.yellow or C.bg2
        favBtn.BackgroundTransparency = isFav and 0 or 0.3
        favBtn.TextColor3 = isFav and Color3.fromRGB(0,0,0) or C.yellow

        local ckName = "[Custom] " .. ca.name
        local bound = Keybinds[ckName]
        local keyIcon = keyBtn:FindFirstChild("Icon")
        if listenTarget and listenTarget.name == ckName then
            listeningKeyBtn = keyBtn
            listenTarget.keyBtn = keyBtn
            keyBtn.Text = "[ ? ]"
            if keyIcon then keyIcon.Visible = false end
            keyBtn.BackgroundColor3 = Color3.fromRGB(0,140,255)
            keyBtn.TextColor3 = Color3.fromRGB(255,255,255)
        elseif bound then
            keyBtn.Text = "["..bound.key.Name.."]"
            if keyIcon then keyIcon.Visible = false end
            Keybinds[ckName].btn = keyBtn
            keyBtn.BackgroundColor3 = C.bg3
            keyBtn.TextColor3 = C.accent
        else
            keyBtn.Text = ""
            if keyIcon then keyIcon.Visible = true; keyIcon.Image = CONFIG.ICONS.KEYBOARD end
            keyBtn.BackgroundColor3 = C.bg2
            keyBtn.TextColor3 = C.text3
        end

        local isPlaying = State.selectedAnim == ca.name
        playBtn.Text = (isPlaying and "> " or "") .. ca.name
        playBtn.BackgroundTransparency = isPlaying and 0.2 or 0.93
        playBtn.TextColor3 = isPlaying and Color3.fromRGB(0,0,0) or Color3.fromRGB(215,215,235)
    end
    w.refresh = refresh
    refresh()

    return w
end

-- Full rebuild: filter + sort the custom animations into the visible list, set
-- the canvas height, then let RefreshCustomRows build only the rows currently
-- on screen. Virtualized, so it never freezes regardless of how many exist.
function RebuildCustomList()
    _G._ReanimRebuildCustomList = RebuildCustomList
    local searchTerm = customSearchBox.Text:lower()
    visibleCustom = {}
    for _, ca in ipairs(CustomAnims) do
        local displayName = ca.name:gsub("%.lua$","")
        if searchTerm == "" or displayName:lower():find(searchTerm, 1, true) then
            table.insert(visibleCustom, ca)
        end
    end
    table.sort(visibleCustom, function(a, b) return a.name:lower() < b.name:lower() end)

    local totalH = VPAD*2 + #visibleCustom * VROW_H
    customListFrame.CanvasSize = UDim2.new(0,0,0,totalH)
    customListFrame.CanvasPosition = Vector2.new(0,0)
    _customWinStart = -1  -- force a fresh window build
    RefreshCustomRows()
end

-- Fast path after a single add: the list is virtualized now, so a full rebuild
-- is cheap (it only ever creates the visible rows).
function AppendCustomRow(ca)
    RebuildCustomList()
end

local _rebuildCustomDebounce = nil
customSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    if _rebuildCustomDebounce then task.cancel(_rebuildCustomDebounce) end
    _rebuildCustomDebounce = task.delay(0.15, function()
        _rebuildCustomDebounce = nil
        RebuildCustomList()
    end)
end)

-- Windowed virtualization for the custom list: only build rows for the slice
-- visible in the viewport, rebuilding as the user scrolls. Keeps the live
-- instance count tiny no matter how many custom animations exist.
local updatingCustom = false
RefreshCustomRows = function()
    if not customListFrame or updatingCustom then return end
    updatingCustom = true

    local winH = 320
    pcall(function()
        local aws = customListFrame.AbsoluteWindowSize
        if aws and aws.Y > 0 then
            winH = aws.Y
        else
            winH = customListFrame.AbsoluteSize.Y
        end
    end)
    if winH <= 0 then winH = 320 end
    local scrollY  = customListFrame.CanvasPosition.Y
    local visCount = math.ceil(winH / VROW_H) + 3
    local startIdx = math.max(1, math.floor((scrollY - VPAD) / VROW_H))
    local endIdx   = math.min(#visibleCustom, startIdx + visCount)

    -- Window unchanged: just refresh the visuals of the existing rows.
    if startIdx == _customWinStart then
        for _, w in ipairs(customRowWidgets) do
            if w and w.refresh and w.row and w.row.Parent then pcall(w.refresh) end
        end
        updatingCustom = false
        return
    end
    _customWinStart = startIdx

    for _, c in ipairs(customListFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    customRowWidgets = {}
    local wi = 1
    for i = startIdx, endIdx do
        local ca = visibleCustom[i]
        if ca then
            local yPos = VPAD + (i - 1) * VROW_H
            customRowWidgets[wi] = _createCustomRow(ca, yPos)
            wi = wi + 1
        end
    end

    task.spawn(function()
        pcall(function()
            customListFrame.CanvasPosition = Vector2.new(0, scrollY)
        end)
        task.wait()
        pcall(function()
            customListFrame.CanvasPosition = Vector2.new(0, scrollY)
        end)
        updatingCustom = false
    end)
end

-- Rebuild the visible window whenever the custom list is scrolled.
customListFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    if RefreshCustomRows then RefreshCustomRows() end
end)

-- RebuildBindsList: shows all animations with keybinds set
function RebuildBindsList()
    -- Clear existing rows
    for _, child in ipairs(BindsPanel:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end
    
    -- Add header with instructions
    local headerLabel = Instance.new("TextLabel")
    headerLabel.Name = "HeaderLabel"
    headerLabel.Parent = BindsPanel
    headerLabel.BackgroundTransparency = 1
    headerLabel.Size = UDim2.new(1, -10, 0, 20)
    headerLabel.Position = UDim2.new(0, 5, 0, 8)
    headerLabel.Font = Enum.Font.GothamMedium
    headerLabel.Text = "Click key button to rebind  |  Click Unbind to remove"
    headerLabel.TextColor3 = C.text3
    headerLabel.TextSize = 10
    headerLabel.TextXAlignment = Enum.TextXAlignment.Left
    headerLabel.ZIndex = 33
    
    -- Collect all animations with keybinds
    local boundAnims = {}
    for name, data in pairs(Keybinds) do
        if data and data.key then
            local displayName = name:gsub("^%[Custom%] ", ""):gsub("%.lua$", "")
            local isCustom = name:find("^%[Custom%]") ~= nil
            local url = nil
            
            if isCustom then
                -- Find the URL from CustomAnimations
                for _, ca in ipairs(CustomAnims) do
                    if "[Custom] " .. ca.name == name then
                        url = ca.url
                        break
                    end
                end
            else
                -- Find the URL from AnimationList
                url = AnimationList[name]
            end
            
            if url then
                table.insert(boundAnims, {
                    name = name,
                    displayName = displayName,
                    keyName = data.key.Name,
                    isCustom = isCustom,
                    url = url
                })
            end
        end
    end
    
    -- Sort alphabetically
    table.sort(boundAnims, function(a, b)
        return a.displayName:lower() < b.displayName:lower()
    end)
    
    -- Create rows for each bound animation
    local yPos = 34
    for _, anim in ipairs(boundAnims) do
        local row = Instance.new("Frame")
        row.Name = "BindRow"
        row.Parent = BindsPanel
        row.BackgroundTransparency = 1
        row.Size = UDim2.new(1, -10, 0, 30)
        row.Position = UDim2.new(0, 5, 0, yPos)
        row.ZIndex = 33
        
        -- Play button
        local playBtn = Instance.new("TextButton")
        playBtn.Parent = row
        playBtn.BackgroundColor3 = C.bg2
        playBtn.BackgroundTransparency = 0.5
        playBtn.BorderSizePixel = 0
        playBtn.Size = UDim2.new(1, -120, 1, 0)
        playBtn.Font = Enum.Font.GothamMedium
        playBtn.Text = anim.displayName
        playBtn.TextColor3 = C.text2
        playBtn.TextSize = 11
        playBtn.TextXAlignment = Enum.TextXAlignment.Left
        playBtn.TextTruncate = Enum.TextTruncate.AtEnd
        playBtn.ZIndex = 34
        playBtn.AutoButtonColor = false
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 5)
            c.Parent = playBtn
            local p = Instance.new("UIPadding")
            p.PaddingLeft = UDim.new(0, 8)
            p.Parent = playBtn
            local s = Instance.new("UIStroke")
            s.Color = C.border
            s.Transparency = 0.8
            s.Thickness = 1
            s.Parent = playBtn
        end
        
        -- Key display button (click to rebind)
        local keyBtn = Instance.new("TextButton")
        keyBtn.Parent = row
        keyBtn.BackgroundColor3 = C.bg3
        keyBtn.BackgroundTransparency = 0
        keyBtn.BorderSizePixel = 0
        keyBtn.Position = UDim2.new(1, -114, 0, 0)
        keyBtn.Size = UDim2.new(0, 56, 1, 0)
        keyBtn.Font = Enum.Font.GothamBold
        keyBtn.Text = "[" .. anim.keyName .. "]"
        keyBtn.TextColor3 = C.accent
        keyBtn.TextSize = 10
        keyBtn.ZIndex = 34
        keyBtn.AutoButtonColor = false
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 5)
            c.Parent = keyBtn
            local s = Instance.new("UIStroke")
            s.Color = C.border
            s.Transparency = 0.8
            s.Thickness = 1
            s.Parent = keyBtn
        end
        
        -- Hover effect for key button
        keyBtn.MouseEnter:Connect(function()
            if listeningKeyBtn ~= keyBtn then
                TweenService:Create(keyBtn, TweenInfo.new(0.1), {
                    BackgroundColor3 = C.accent, TextColor3 = Color3.fromRGB(10,10,10)
                }):Play()
            end
        end)
        keyBtn.MouseLeave:Connect(function()
            if listeningKeyBtn ~= keyBtn then
                TweenService:Create(keyBtn, TweenInfo.new(0.1), {
                    BackgroundColor3 = C.bg3, TextColor3 = C.accent
                }):Play()
            end
        end)
        
        -- Unbind button
        local unbindBtn = Instance.new("TextButton")
        unbindBtn.Parent = row
        unbindBtn.BackgroundColor3 = C.red
        unbindBtn.BackgroundTransparency = 0.3
        unbindBtn.BorderSizePixel = 0
        unbindBtn.Position = UDim2.new(1, -54, 0, 0)
        unbindBtn.Size = UDim2.new(0, 48, 1, 0)
        unbindBtn.Font = Enum.Font.GothamBold
        unbindBtn.Text = "Unbind"
        unbindBtn.TextColor3 = C.white
        unbindBtn.TextSize = 9
        unbindBtn.ZIndex = 34
        unbindBtn.AutoButtonColor = false
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 5)
            c.Parent = unbindBtn
        end
        
        -- Hover effects
        playBtn.MouseEnter:Connect(function()
            TweenService:Create(playBtn, TweenInfo.new(0.1), {
                BackgroundTransparency = 0.2, TextColor3 = C.text
            }):Play()
        end)
        playBtn.MouseLeave:Connect(function()
            TweenService:Create(playBtn, TweenInfo.new(0.1), {
                BackgroundTransparency = 0.5, TextColor3 = C.text2
            }):Play()
        end)
        
        unbindBtn.MouseEnter:Connect(function()
            TweenService:Create(unbindBtn, TweenInfo.new(0.1), {
                BackgroundTransparency = 0
            }):Play()
        end)
        unbindBtn.MouseLeave:Connect(function()
            TweenService:Create(unbindBtn, TweenInfo.new(0.1), {
                BackgroundTransparency = 0.3
            }):Play()
        end)
        
        -- Click handlers
        playBtn.MouseButton1Click:Connect(function()
            PlayAnimation(anim.name:gsub("^%[Custom%] ", ""), State.currentSpeed, anim.isCustom)
        end)
        
        keyBtn.MouseButton1Click:Connect(function()
            -- Start listening for new key
            if listeningKeyBtn then CancelListening() end
            listeningKeyBtn = keyBtn
            listenTarget = { name = anim.name, url = anim.url, keyBtn = keyBtn }
            keyBtn.Text = "[ ? ]"
            keyBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
            keyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        end)
        
        unbindBtn.MouseButton1Click:Connect(function()
            Keybinds[anim.name] = nil
            SaveData()
            Notify("Unbound: " .. anim.displayName, 2)
            RebuildBindsList()
        end)
        
        yPos = yPos + 34
    end
    
    -- Update canvas size
    BindsPanel.CanvasSize = UDim2.new(0, 0, 0, yPos + 8)
    
    -- Show message if no keybinds are set
    if #boundAnims == 0 then
        local noBindsLabel = Instance.new("TextLabel")
        noBindsLabel.Name = "NoBindsLabel"
        noBindsLabel.Parent = BindsPanel
        noBindsLabel.BackgroundTransparency = 1
        noBindsLabel.Size = UDim2.new(1, -20, 0, 80)
        noBindsLabel.Position = UDim2.new(0, 10, 0, 40)
        noBindsLabel.Font = Enum.Font.GothamMedium
        noBindsLabel.Text = "No keybinds set yet\n\nGo to the All or Custom tab\nand click [+] to bind keys to animations"
        noBindsLabel.TextColor3 = C.text3
        noBindsLabel.TextSize = 12
        noBindsLabel.TextWrapped = true
        noBindsLabel.ZIndex = 33
        
        BindsPanel.CanvasSize = UDim2.new(0, 0, 0, 140)
    end
end

local STATE_TYPES = { "Idle", "Walk", "Run", "Jump", "Fall", "Climb", "SwimIdle", "Swim" }

local currentStateAnim = nil
local stateWatchConn   = nil
local stateHumConn     = nil
-- True while we've handed control back to the clone's default Animate script
-- because the current logical state has no custom animation assigned (e.g. you
-- jump but only set Idle/Run). Lets default jump/fall/etc. play instead of
-- freezing the previous custom animation.
local _stateFallbackActive = false

local getLogicalState = LPH_NO_VIRTUALIZE(function(hum)
    local hs = hum:GetState()
    -- The Jumping state is only active for the first instant of a jump, before
    -- upward velocity has been applied — so map it straight to "Jump" instead of
    -- letting the near-zero velocity fall through to Idle/Walk (which made jump
    -- animations never trigger).
    if hs == Enum.HumanoidStateType.Jumping then
        return "Jump"
    elseif hs == Enum.HumanoidStateType.Freefall then
        -- While airborne we are EITHER rising (jump) or descending/at-apex (fall).
        -- Never return a ground state here: the old "near-zero velocity" branch
        -- reported Idle at the apex of every jump, which made jumping look like it
        -- was playing the idle animation. Landing is handled when the humanoid
        -- leaves the Freefall state (the else branch below).
        local hrp = hum.RootPart
        if hrp and hrp.AssemblyLinearVelocity.Y > 0.1 then
            return "Jump"
        end
        return "Fall"
    elseif hs == Enum.HumanoidStateType.Climbing then
        return "Climb"
    elseif hs == Enum.HumanoidStateType.Swimming then
        local speed = hum.WalkSpeed > 0 and hum.MoveDirection.Magnitude > 0.1
        return speed and "Swim" or "SwimIdle"
    else
        -- Use horizontal velocity magnitude rather than MoveDirection so brief
        -- directional pauses (where MoveDirection momentarily zeros) don't
        -- register as Idle and flash the idle animation mid-movement.
        local hrp = hum.RootPart
        local horizSpeed = 0
        if hrp then
            local vel = hrp.AssemblyLinearVelocity
            horizSpeed = Vector2.new(vel.X, vel.Z).Magnitude
        end
        if horizSpeed > 14 then return "Run"
        elseif horizSpeed > 1.5 then return "Walk"
        else return "Idle" end
    end
end)

local stateScriptCache = {}

prefetchStateAnim = function(stKey)
    local entry = StateAnims[stKey]
    if not entry then return end
    local url = type(entry) == "table" and entry.url or entry
    if not url or url == "" then return end
    if stateScriptCache[url] then return end
    
    local isHttp = url:match("^https?://")
    local isLocalFile = not isHttp and isfile and readfile and isfile(url)
    
    task.spawn(function()
        local src = ""
        if isHttp then
            local ok, content = pcall(function() return game:HttpGet(url, true) end)
            if not ok or type(content) ~= "string" or #content == 0 then return end
            src = content
        elseif isLocalFile then
            local ok, content = pcall(readfile, url)
            if not ok or not content or content == "" then return end
            src = content
        else
            src = url
        end
        
        src = src:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
        
        -- Try JSON parsing first
        local firstChar = src:match("^%s*(.)")
        if firstChar == "{" or firstChar == "[" then
            local parsed = parseJsonAnimation(src)
            if parsed then
                stateScriptCache[url] = { src = src, data = parsed }
                return
            end
        end
        local fn = loadstring(src)
        if not fn then return end
        local ok2, data = pcall(fn)
        if not ok2 or type(data) ~= "table" then return end
        stateScriptCache[url] = { src = src, data = data }
    end)
end

prefetchAllStates = function()
    for _, stKey in ipairs(STATE_TYPES) do
        prefetchStateAnim(stKey)
    end
end

local STATE_SPEED_MULT = 1.0
local stateLoading = {}

-- Hand control to (true) or take it back from (false) the clone's default
-- Animate script for un-assigned states. Idempotent so we only toggle on change.
local function _setStateFallback(active)
    if active == _stateFallbackActive then return end
    _stateFallbackActive = active
    if active then
        -- Stop the lingering custom animation so the default Animate (jump/fall
        -- /etc.) is what's visible, then re-enable the default Animate script.
        currentStateAnim = nil
        pcall(function() ReanimateAPI.stop_animation_for_transition() end)
        if _applyReanimDefaultAnimate then _applyReanimDefaultAnimate(true) end
    else
        -- Returning to a custom state: turn the default Animate back off so it
        -- doesn't fight the constraint-driven custom animation.
        if _applyReanimDefaultAnimate then _applyReanimDefaultAnimate(false) end
    end
end

function playStateAnim(stKey)
    local entry = StateAnims[stKey]
    local url   = type(entry) == "table" and entry.url or entry
    local raw   = type(entry) == "table" and entry.raw or false
    if not entry or not url or url == "" then
        -- No custom animation assigned for this state (e.g. you jump but only set
        -- Idle/Run). Fall back to the clone's default Animate so the correct
        -- default jump/fall/etc. plays instead of freezing the previous anim.
        _setStateFallback(true)
        return
    end
    -- A custom animation exists for this state: make sure the default Animate
    -- fallback is disabled before we drive the custom animation ourselves.
    _setStateFallback(false)
    if currentStateAnim == stKey then return end
    pcall(function() ReanimateAPI.stop_animation_for_transition() end)
    currentStateAnim = stKey
    local cachedEntry = stateScriptCache[url]
    
    local isHttp = url:match("^https?://")
    local isLocalFile = not isHttp and isfile and readfile and isfile(url)
    
    if isHttp or raw or isLocalFile then
        if not cachedEntry then
            if stateLoading[url] then return end
            stateLoading[url] = true
            task.spawn(function()
                local src = ""
                if isHttp then
                    local ok, content = pcall(function() return game:HttpGet(url, true) end)
                    if not ok or type(content) ~= "string" or #content == 0 then
                        warn("[StateAnim] HTTP fetch failed for", stKey, ":", content)
                        stateLoading[url] = nil
                        if currentStateAnim == stKey then currentStateAnim = nil end
                        return
                    end
                    src = content
                elseif isLocalFile then
                    local ok, content = pcall(readfile, url)
                    if not ok or not content or content == "" then
                        warn("[StateAnim] File read failed for", stKey, ":", url)
                        stateLoading[url] = nil
                        if currentStateAnim == stKey then currentStateAnim = nil end
                        return
                    end
                    src = content
                else
                    src = url
                end
                
                src = src:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
                
                local data
                local parseMethod = "none"
                -- Try JSON parsing first
                local firstChar = src:match("^%s*(.)")
                warn("[StateAnim] Loading", stKey, "- first char:", firstChar, "- length:", #src)
                
                if firstChar == "{" or firstChar == "[" then
                    parseMethod = "json"
                    warn("[StateAnim] Attempting JSON parse for", stKey)
                    local parsed = parseJsonAnimation(src)
                    if parsed and #parsed > 0 then 
                        data = parsed
                        warn("[StateAnim] JSON parsed successfully for", stKey, "- frames:", #data)
                        -- Log first frame structure
                        if data[1] then
                            local boneCount = 0
                            for _ in pairs(data[1].Data or {}) do boneCount = boneCount + 1 end
                            warn("[StateAnim] First frame - Time:", data[1].Time, "- Bones:", boneCount)
                        end
                    else
                        warn("[StateAnim] JSON parsing returned nil or empty for", stKey)
                    end
                end
                
                if not data then
                    parseMethod = "lua"
                    local fn = loadstring(src)
                    if not fn then
                        warn("[StateAnim] loadstring failed for", stKey)
                        stateLoading[url] = nil
                        if currentStateAnim == stKey then currentStateAnim = nil end
                        return
                    end
                    local ok2, luaData = pcall(fn)
                    if not ok2 or type(luaData) ~= "table" then
                        warn("[StateAnim] Lua execution failed for", stKey, ":", luaData)
                        stateLoading[url] = nil
                        if currentStateAnim == stKey then currentStateAnim = nil end
                        return
                    end
                    
                    -- If luaData is already keyframes array, use it directly
                    if type(luaData[1]) == "table" and luaData[1].Time and luaData[1].Data then
                        data = luaData
                        warn("[StateAnim] Lua data is already keyframes format for", stKey)
                    else
                        -- Parse as table animation
                        data = parseTableAnimation(luaData)
                        if not data then
                            warn("[StateAnim] parseTableAnimation failed for", stKey)
                        end
                    end
                end
                
                if not data or #data == 0 then
                    warn("[StateAnim] No valid animation data for", stKey, "- method:", parseMethod)
                    stateLoading[url] = nil
                    if currentStateAnim == stKey then currentStateAnim = nil end
                    return
                end
                
                cachedEntry = { src = src, data = data }
                stateScriptCache[url] = cachedEntry
                stateLoading[url] = nil
                
                warn("[StateAnim] Successfully loaded", stKey, "with", #data, "frames via", parseMethod)
                
                -- Check if we are still matching the requested state
                if currentStateAnim == stKey then
                    if ReanimateAPI.play_keyframes and data then
                        pcall(function()
                            ReanimateAPI.play_keyframes(data, State.currentSpeed * STATE_SPEED_MULT)
                        end)
                    else
                        pcall(function()
                            ReanimateAPI.play_raw_animation(url, src, State.currentSpeed * STATE_SPEED_MULT)
                        end)
                    end
                end
            end)
        else
            if ReanimateAPI.play_keyframes and cachedEntry.data then
                pcall(function()
                    ReanimateAPI.play_keyframes(cachedEntry.data, State.currentSpeed * STATE_SPEED_MULT)
                end)
            else
                pcall(function()
                    ReanimateAPI.play_raw_animation(url, cachedEntry.src, State.currentSpeed * STATE_SPEED_MULT)
                end)
            end
        end
    else
        pcall(function()
            ReanimateAPI.play_animation(url, State.currentSpeed * STATE_SPEED_MULT)
        end)
    end
end

stopStateSystem = function()
    if stateWatchConn then stateWatchConn:Disconnect(); stateWatchConn = nil end
    if stateHumConn   then stateHumConn:Disconnect();   stateHumConn   = nil end
    stateSystemActive = false
    currentStateAnim  = nil
    _stateFallbackActive = false
    pcall(function() ReanimateAPI.stop_animation() end)
end

-- Enable/disable the reanimated clone's default Roblox Animate script.
-- When enabled, the clone plays the player's equipped animation pack
-- (idle/walk/run/jump/etc.) exactly like a normal character. We use this as the
-- fallback when the user has NO custom state animations set.
local function _setCloneDefaultAnimate(enabled)
    if not ReanimateAPI or not ReanimateAPI.get_clone then return end
    local clone = ReanimateAPI.get_clone(plr)
    if not clone then return end
    pcall(function()
        local animate = clone:FindFirstChild("Animate")
        if animate then animate.Disabled = (enabled == false) end
    end)
end
-- Expose so the enable flow / CharacterAdded handler can reach it.
_applyReanimDefaultAnimate = _setCloneDefaultAnimate

-- When suspended, ALL reanimation-driven animation is stopped and prevented from
-- restarting (used by Face Bang so the clone holds still instead of animating).
local _reanimAnimsSuspended = false

startStateSystem = function()
    if stateSystemActive then stopStateSystem() end
    if _reanimAnimsSuspended then return end
    local char = plr.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if not next(StateAnims) then return end

    -- Custom states take over: turn OFF the default Animate so it doesn't fight
    -- the constraint-driven state animations.
    _setCloneDefaultAnimate(false)

    stateSystemActive = true
    _stateFallbackActive = false
    local lastLogical = nil

    stateWatchConn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
        if not State.isReanimated then stopStateSystem(); return end
        -- FPS optimization: throttle state checks to 10Hz instead of every frame
        _stateCheckThrottle = (_stateCheckThrottle or 0) + 1
        if _stateCheckThrottle % 6 ~= 0 then return end
        if State.selectedAnim then
            if currentStateAnim then currentStateAnim = nil end
            -- A manually selected animation takes priority — make sure the
            -- default-Animate fallback isn't left on fighting it.
            _setStateFallback(false)
            lastLogical = nil
            return
        end
        local logical = getLogicalState(hum)
        if logical ~= lastLogical then
            lastLogical = logical
            playStateAnim(logical)
        end
    end))
end

plr.CharacterAdded:Connect(function(character)
    stopStateSystem()
    currentStateAnim = nil
    character:WaitForChild("HumanoidRootPart", 10)
    task.wait(0.5)
    if State.isReanimated and not _reanimAnimsSuspended then
        if next(StateAnims) then
            startStateSystem()
        else
            -- No custom states: play the player's default Roblox animations.
            _setCloneDefaultAnimate(true)
        end
    end
end)

-- Stop EVERY reanimation animation (state system, any playing clip, and the
-- clone's default Animate) and keep them stopped until resumed. Used by Face Bang.
_G._TRXStopReanimAnims = function()
    _reanimAnimsSuspended = true
    pcall(stopStateSystem)
    pcall(function() ReanimateAPI.stop_animation() end)
    _setCloneDefaultAnimate(false)
    -- Also stop any tracks playing on the clone's own Animator
    pcall(function()
        local clone = ReanimateAPI.get_clone and ReanimateAPI.get_clone(plr)
        if clone then
            local h  = clone:FindFirstChildOfClass("Humanoid")
            local an = h and h:FindFirstChildOfClass("Animator")
            if an then
                for _, t in ipairs(an:GetPlayingAnimationTracks()) do pcall(function() t:Stop(0) end) end
            end
        end
    end)
end

-- Re-allow reanimation animations and restore the correct mode.
_G._TRXResumeReanimAnims = function()
    _reanimAnimsSuspended = false
    if not State.isReanimated then return end
    if next(StateAnims) then
        startStateSystem()
    else
        _setCloneDefaultAnimate(true)
    end
end

local DropdownOverlay = Instance.new("Frame"); DropdownOverlay.Parent = StatesPanel
DropdownOverlay.Name = "DropdownOverlay"
DropdownOverlay.BackgroundColor3 = C.bg0
DropdownOverlay.BackgroundTransparency = 0.05
DropdownOverlay.BorderSizePixel = 0
DropdownOverlay.Size = UDim2.new(1, 0, 0, 240)
DropdownOverlay.Position = UDim2.new(0, 0, 0, 0)
DropdownOverlay.LayoutOrder = 99
DropdownOverlay.ZIndex = 200
DropdownOverlay.Visible = false
DropdownOverlay.ClipsDescendants = true
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = DropdownOverlay
    local s = Instance.new("UIStroke"); s.Color = C.border
    s.Transparency = 0.5; s.Thickness = 1.2; s.Parent = DropdownOverlay
end

local ddHeader = Instance.new("Frame"); ddHeader.Parent = DropdownOverlay
ddHeader.BackgroundColor3 = Color3.fromRGB(255,255,255); ddHeader.BackgroundTransparency = 0.95
ddHeader.BorderSizePixel = 0; ddHeader.Size = UDim2.new(1,0,0,32); ddHeader.ZIndex = 201
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = ddHeader end

local ddTitle = Instance.new("TextLabel"); ddTitle.Parent = ddHeader
ddTitle.BackgroundTransparency = 1; ddTitle.Position = UDim2.new(0,10,0,0)
ddTitle.Size = UDim2.new(1,-40,1,0); ddTitle.Font = Enum.Font.GothamBold
ddTitle.Text = "Select Animation"; ddTitle.TextColor3 = Color3.fromRGB(255,255,255)
ddTitle.TextSize = 12; ddTitle.TextXAlignment = Enum.TextXAlignment.Left; ddTitle.ZIndex = 202

local ddClose = Instance.new("TextButton"); ddClose.Parent = ddHeader
ddClose.AnchorPoint = Vector2.new(1,0.5); ddClose.Position = UDim2.new(1,-6,0.5,0)
ddClose.Size = UDim2.new(0,22,0,22); ddClose.BackgroundColor3 = Color3.fromRGB(255,80,80)
ddClose.BackgroundTransparency = 0.3; ddClose.BorderSizePixel = 0
ddClose.Font = Enum.Font.GothamBold; ddClose.Text = "X"
ddClose.TextColor3 = Color3.fromRGB(255,255,255); ddClose.TextSize = 14
ddClose.ZIndex = 202; ddClose.AutoButtonColor = false
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = ddClose end

local ddSearch = Instance.new("TextBox"); ddSearch.Parent = DropdownOverlay
ddSearch.BackgroundColor3 = C.bg1; ddSearch.BackgroundTransparency = 0.4
ddSearch.BorderSizePixel = 0; ddSearch.Position = UDim2.new(0,8,0,38)
ddSearch.Size = UDim2.new(1,-16,0,28); ddSearch.ZIndex = 201
ddSearch.Font = Enum.Font.Gotham; ddSearch.PlaceholderText = "Search animations..."
ddSearch.PlaceholderColor3 = C.text3; ddSearch.Text = ""
ddSearch.TextColor3 = C.text; ddSearch.TextSize = 11
ddSearch.ClearTextOnFocus = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = ddSearch
    local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,8); p.Parent = ddSearch
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = ddSearch
end

local ddList = Instance.new("ScrollingFrame"); ddList.Parent = DropdownOverlay
ddList.BackgroundTransparency = 1; ddList.BorderSizePixel = 0
ddList.Position = UDim2.new(0,8,0,72); ddList.Size = UDim2.new(1,-16,1,-80)
ddList.ScrollBarThickness = 3; ddList.ScrollBarImageColor3 = C.accent
ddList.ScrollBarImageTransparency = 0.5; ddList.ZIndex = 201
ddList.CanvasSize = UDim2.new(0,0,0,0)
do
    local l = Instance.new("UIListLayout"); l.Parent = ddList; l.Padding = UDim.new(0,3)
    l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        ddList.CanvasSize = UDim2.new(0,0,0,l.AbsoluteContentSize.Y+6)
    end)
end

local ddCallback   = nil
local ddStateLabel = nil
local ddAllEntries = {}

function CloseDropdown()
    DropdownOverlay.Visible = false
    ddSearch.Text = ""; ddCallback = nil; ddStateLabel = nil
    for _, c in ipairs(ddList:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end
end

ddClose.MouseButton1Click:Connect(CloseDropdown)

local DD_MAX_ITEMS = 60
function PopulateDropdown(term)
    for _, c in ipairs(ddList:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end
    term = (term or ""):lower()
    local count = 0
    for _, entry in ipairs(ddAllEntries) do
        if count >= DD_MAX_ITEMS then
            local hint = Instance.new("TextLabel"); hint.Parent = ddList
            hint.BackgroundTransparency = 1; hint.Size = UDim2.new(1,0,0,22); hint.ZIndex = 202
            hint.Font = Enum.Font.GothamMedium; hint.Text = "Type to search for more..."
            hint.TextColor3 = C.text3; hint.TextSize = 10
            break
        end
        if term == "" or entry.name:lower():find(term, 1, true) then
            count = count + 1
            local btn = Instance.new("TextButton"); btn.Parent = ddList
            btn.BackgroundColor3 = C.bg2; btn.BackgroundTransparency = 0.5
            btn.BorderSizePixel = 0; btn.Size = UDim2.new(1,0,0,28); btn.ZIndex = 202
            btn.Font = Enum.Font.GothamMedium; btn.Text = entry.name
            btn.TextColor3 = C.text2; btn.TextSize = 11
            btn.TextXAlignment = Enum.TextXAlignment.Left; btn.AutoButtonColor = false
            btn.TextTruncate = Enum.TextTruncate.AtEnd
            do
                local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0,5); c2.Parent = btn
                local p2 = Instance.new("UIPadding"); p2.PaddingLeft = UDim.new(0,8); p2.Parent = btn
                local s2 = Instance.new("UIStroke"); s2.Color = C.border; s2.Transparency = 0.8; s2.Thickness = 1; s2.Parent = btn
            end
            btn.MouseEnter:Connect(function()
                TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0.7}):Play()
            end)
            btn.MouseLeave:Connect(function()
                TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0.93}):Play()
            end)
            local e = entry
            btn.MouseButton1Click:Connect(function()
                if ddCallback then ddCallback(e.name, e.url) end
                CloseDropdown()
            end)
        end
    end
end

local _ddSearchDebounce = nil
ddSearch:GetPropertyChangedSignal("Text"):Connect(function()
    if _ddSearchDebounce then task.cancel(_ddSearchDebounce) end
    _ddSearchDebounce = task.delay(0.12, function()
        _ddSearchDebounce = nil
        PopulateDropdown(ddSearch.Text)
    end)
end)

function OpenDropdown(stateType, displayBtn, onPick)
    ddAllEntries = {}
    for name, url in pairs(AnimationList) do
        table.insert(ddAllEntries, { name=name, url=url })
    end
    for _, ca in ipairs(CustomAnims) do
        table.insert(ddAllEntries, { name="[Custom] "..ca.name, url=ca.url })
    end
    table.sort(ddAllEntries, function(a,b) return a.name < b.name end)

    ddCallback   = onPick
    ddStateLabel = displayBtn
    ddTitle.Text = "Pick: " .. stateType
    ddSearch.Text = ""
    local row = displayBtn and displayBtn.Parent
    DropdownOverlay.LayoutOrder = ((row and row.LayoutOrder) or 0) + 0.1
    DropdownOverlay.Parent = StatesPanel
    DropdownOverlay.Size = UDim2.new(1, -4, 0, 240)
    DropdownOverlay.Position = UDim2.new(0, 2, 0, 0)
    DropdownOverlay.Visible  = true
    PopulateDropdown("")
    ddSearch:CaptureFocus()
end

local AddCustomModal = Instance.new("Frame"); AddCustomModal.Parent = Menu
AddCustomModal.Name = "AddCustomModal"
AddCustomModal.BackgroundColor3 = C.bg1
AddCustomModal.BackgroundTransparency = 0.05; AddCustomModal.BorderSizePixel = 0
AddCustomModal.Size = UDim2.new(1, 0, 1, -40); AddCustomModal.Position = UDim2.new(0, 0, 0, 40)
AddCustomModal.ZIndex = 100; AddCustomModal.Visible = false; AddCustomModal.ClipsDescendants = true
-- Modal backdrop for blur effect
local ModalBackdrop = Instance.new("Frame"); ModalBackdrop.Name = "Backdrop"
ModalBackdrop.Parent = AddCustomModal; ModalBackdrop.BackgroundColor3 = Color3.fromRGB(0,0,0)
ModalBackdrop.BackgroundTransparency = 0; ModalBackdrop.BorderSizePixel = 0
ModalBackdrop.Size = UDim2.new(1,0,1,0); ModalBackdrop.ZIndex = 99
ModalBackdrop.Visible = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = AddCustomModal
    local s = Instance.new("UIStroke"); s.Color = C.accent
    s.Transparency = 0.4; s.Thickness = 1.5; s.Parent = AddCustomModal
end

local acmHeader = Instance.new("Frame"); acmHeader.Parent = AddCustomModal
acmHeader.BackgroundColor3 = C.bg2; acmHeader.BackgroundTransparency = 0.4
acmHeader.BorderSizePixel = 0; acmHeader.Size = UDim2.new(1,0,0,38); acmHeader.ZIndex = 101
do
    local div = Instance.new("Frame"); div.Parent = acmHeader
    div.BackgroundColor3 = C.accent; div.BackgroundTransparency = 0.7
    div.BorderSizePixel = 0; div.Position = UDim2.new(0,0,1,-1)
    div.Size = UDim2.new(1,0,0,1); div.ZIndex = 102
end

local acmTitle = Instance.new("TextLabel"); acmTitle.Parent = acmHeader
acmTitle.BackgroundTransparency = 1; acmTitle.Position = UDim2.new(0,14,0,0)
acmTitle.Size = UDim2.new(1,-50,1,0); acmTitle.Font = Enum.Font.GothamBold
acmTitle.Text = "Add Custom Animation"; acmTitle.TextColor3 = Color3.fromRGB(255,255,255)
acmTitle.TextSize = 13; acmTitle.TextXAlignment = Enum.TextXAlignment.Left; acmTitle.ZIndex = 102

local acmCloseBtn = Instance.new("TextButton"); acmCloseBtn.Parent = acmHeader
acmCloseBtn.AnchorPoint = Vector2.new(1,0.5); acmCloseBtn.Position = UDim2.new(1,-10,0.5,0)
acmCloseBtn.Size = UDim2.new(0,22,0,22); acmCloseBtn.BackgroundColor3 = C.accent
acmCloseBtn.BackgroundTransparency = 0.3; acmCloseBtn.BorderSizePixel = 0
acmCloseBtn.Font = Enum.Font.GothamBold; acmCloseBtn.Text = ""
acmCloseBtn.TextColor3 = Color3.fromRGB(10,10,10); acmCloseBtn.TextSize = 14
acmCloseBtn.ZIndex = 102; acmCloseBtn.AutoButtonColor = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = acmCloseBtn
    local ico = Instance.new("ImageLabel"); ico.Parent = acmCloseBtn
    ico.BackgroundTransparency = 1; ico.AnchorPoint = Vector2.new(0.5,0.5)
    ico.Position = UDim2.new(0.5,0,0.5,0); ico.Size = UDim2.new(0,10,0,10)
    ico.Image = "rbxassetid://6031094678"; ico.ImageColor3 = Color3.fromRGB(10,10,10); ico.ZIndex = 103
end

local acmBody = Instance.new("Frame"); acmBody.Parent = AddCustomModal
acmBody.BackgroundTransparency = 1; acmBody.Position = UDim2.new(0,12,0,46)
acmBody.Size = UDim2.new(1,-24,1,-96); acmBody.ZIndex = 101

local acmNameLbl = Instance.new("TextLabel"); acmNameLbl.Parent = acmBody
acmNameLbl.BackgroundTransparency = 1; acmNameLbl.Position = UDim2.new(0,0,0,0)
acmNameLbl.Size = UDim2.new(1,0,0,16); acmNameLbl.Font = Enum.Font.GothamSemibold
acmNameLbl.Text = "Animation Name"; acmNameLbl.TextColor3 = C.accent
acmNameLbl.TextSize = 10; acmNameLbl.TextXAlignment = Enum.TextXAlignment.Left; acmNameLbl.ZIndex = 102

local acmNameBox = Instance.new("TextBox"); acmNameBox.Parent = acmBody
acmNameBox.BackgroundColor3 = C.bg2; acmNameBox.BackgroundTransparency = 0.3
acmNameBox.BorderSizePixel = 0; acmNameBox.Position = UDim2.new(0,0,0,18)
acmNameBox.Size = UDim2.new(1,0,0,28); acmNameBox.ZIndex = 102
acmNameBox.Font = Enum.Font.Gotham; acmNameBox.PlaceholderText = "Leave empty to auto-generate"
acmNameBox.PlaceholderColor3 = C.text3
acmNameBox.Text = ""; acmNameBox.TextColor3 = C.text; acmNameBox.TextSize = 11
acmNameBox.ClearTextOnFocus = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = acmNameBox
    local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,9); p.Parent = acmNameBox
    local s = Instance.new("UIStroke"); s.Color = C.accent; s.Transparency = 0.7; s.Thickness = 1; s.Parent = acmNameBox
end

local acmDataLbl = Instance.new("TextLabel"); acmDataLbl.Parent = acmBody
acmDataLbl.BackgroundTransparency = 1; acmDataLbl.Position = UDim2.new(0,0,0,54)
acmDataLbl.Size = UDim2.new(1,0,0,16); acmDataLbl.Font = Enum.Font.GothamSemibold
acmDataLbl.Text = "Keyframes Script"; acmDataLbl.TextColor3 = C.accent
acmDataLbl.TextSize = 10; acmDataLbl.TextXAlignment = Enum.TextXAlignment.Left; acmDataLbl.ZIndex = 102

local acmDataSub = Instance.new("TextLabel"); acmDataSub.Parent = acmBody
acmDataSub.BackgroundTransparency = 1; acmDataSub.Position = UDim2.new(0,0,0,70)
acmDataSub.Size = UDim2.new(1,0,0,12); acmDataSub.Font = Enum.Font.Gotham
acmDataSub.Text = "Click the box below, then Ctrl+V to paste"
acmDataSub.TextColor3 = C.text3; acmDataSub.TextSize = 9
acmDataSub.TextXAlignment = Enum.TextXAlignment.Left; acmDataSub.ZIndex = 102

local acmDataBox = Instance.new("TextBox"); acmDataBox.Parent = acmBody
acmDataBox.BackgroundColor3 = C.bg2; acmDataBox.BackgroundTransparency = 0.3
acmDataBox.BorderSizePixel = 0; acmDataBox.Position = UDim2.new(0,0,0,84)
acmDataBox.Size = UDim2.new(1,0,1,-148); acmDataBox.ZIndex = 102
acmDataBox.Font = Enum.Font.Code; acmDataBox.MultiLine = true; acmDataBox.ClearTextOnFocus = false
acmDataBox.TextWrapped = true; acmDataBox.ClipsDescendants = true
acmDataBox.PlaceholderText = "Paste keyframe script here..."
acmDataBox.PlaceholderColor3 = C.text3
acmDataBox.Text = ""; acmDataBox.TextColor3 = C.green; acmDataBox.TextSize = 10
acmDataBox.TextXAlignment = Enum.TextXAlignment.Left; acmDataBox.TextYAlignment = Enum.TextYAlignment.Top
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = acmDataBox
    local s = Instance.new("UIStroke"); s.Color = C.accent; s.Transparency = 0.7; s.Thickness = 1; s.Parent = acmDataBox
    local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,8); p.PaddingTop = UDim.new(0,8); p.Parent = acmDataBox
end

local acmStatusLbl = Instance.new("TextLabel"); acmStatusLbl.Parent = acmBody
acmStatusLbl.BackgroundTransparency = 1; acmStatusLbl.Position = UDim2.new(0,0,1,-52)
acmStatusLbl.Size = UDim2.new(1,0,0,12); acmStatusLbl.Font = Enum.Font.GothamSemibold
acmStatusLbl.Text = "Status"; acmStatusLbl.TextColor3 = C.accent
acmStatusLbl.TextSize = 9; acmStatusLbl.TextXAlignment = Enum.TextXAlignment.Left; acmStatusLbl.ZIndex = 102

local acmStatus = Instance.new("TextLabel"); acmStatus.Parent = acmBody
acmStatus.BackgroundTransparency = 1; acmStatus.Position = UDim2.new(0,0,1,-38)
acmStatus.Size = UDim2.new(1,0,0,30); acmStatus.Font = Enum.Font.Gotham; acmStatus.TextWrapped = true
acmStatus.Text = "Enter keyframes data to add custom animation"
acmStatus.TextColor3 = C.text3; acmStatus.TextSize = 10
acmStatus.TextXAlignment = Enum.TextXAlignment.Left; acmStatus.ZIndex = 102

local acmBtnRow = Instance.new("Frame"); acmBtnRow.Parent = AddCustomModal
acmBtnRow.BackgroundTransparency = 1; acmBtnRow.BorderSizePixel = 0
acmBtnRow.AnchorPoint = Vector2.new(0,1); acmBtnRow.Position = UDim2.new(0,12,1,-10)
acmBtnRow.Size = UDim2.new(1,-24,0,34); acmBtnRow.ZIndex = 101

local acmCancelBtn = Instance.new("TextButton"); acmCancelBtn.Parent = acmBtnRow
acmCancelBtn.BackgroundColor3 = C.bg2; acmCancelBtn.BackgroundTransparency = 0.3
acmCancelBtn.BorderSizePixel = 0; acmCancelBtn.Size = UDim2.new(0.44,0,1,0)
acmCancelBtn.Font = Enum.Font.GothamSemibold; acmCancelBtn.Text = "Cancel"
acmCancelBtn.TextColor3 = C.text2; acmCancelBtn.TextSize = 11
acmCancelBtn.ZIndex = 102; acmCancelBtn.AutoButtonColor = false
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = acmCancelBtn
    local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Parent = acmCancelBtn
end
acmCancelBtn.MouseEnter:Connect(function()
    TweenService:Create(acmCancelBtn, TweenInfo.new(0.1), {BackgroundColor3 = C.bg3, BackgroundTransparency = 0.2}):Play()
end)
acmCancelBtn.MouseLeave:Connect(function()
    TweenService:Create(acmCancelBtn, TweenInfo.new(0.1), {BackgroundColor3 = C.bg2, BackgroundTransparency = 0.3}):Play()
end)

local acmAddBtn = Instance.new("TextButton"); acmAddBtn.Parent = acmBtnRow
acmAddBtn.AnchorPoint = Vector2.new(1,0); acmAddBtn.Position = UDim2.new(1,0,0,0)
acmAddBtn.BackgroundColor3 = C.accent; acmAddBtn.BackgroundTransparency = 0.2
acmAddBtn.BorderSizePixel = 0; acmAddBtn.Size = UDim2.new(0.52,0,1,0)
acmAddBtn.Font = Enum.Font.GothamBold; acmAddBtn.Text = "Add Animation"
acmAddBtn.TextColor3 = Color3.fromRGB(10,10,10); acmAddBtn.TextSize = 11
acmAddBtn.ZIndex = 102; acmAddBtn.AutoButtonColor = false
do 
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = acmAddBtn
    local s = Instance.new("UIStroke"); s.Color = C.accent; s.Transparency = 0.5; s.Thickness = 1; s.Parent = acmAddBtn
end
acmAddBtn.MouseEnter:Connect(function()
    TweenService:Create(acmAddBtn, TweenInfo.new(0.1), {BackgroundTransparency = 0}):Play()
end)
acmAddBtn.MouseLeave:Connect(function()
    TweenService:Create(acmAddBtn, TweenInfo.new(0.1), {BackgroundTransparency = 0.15}):Play()
end)

local acmBoxFocused = false
local _pendingPasteData = nil
acmDataBox.Focused:Connect(function() acmBoxFocused = true end)
acmDataBox.FocusLost:Connect(function() acmBoxFocused = false end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not acmBoxFocused then return end
    if input.KeyCode == Enum.KeyCode.V
    and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
      or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
        task.spawn(function()
            local ok, clip = pcall(getclipboard)
            if ok and type(clip) == "string" and #clip > 0 then
                _pendingPasteData = clip
                local preview = #clip > 200 and clip:sub(1, 200) .. "..." or clip
                acmDataBox.Text = preview
                acmStatus.Text = "Loaded " .. tostring(#clip) .. " chars"
                acmStatus.TextColor3 = Color3.fromRGB(100,220,140)
            end
        end)
    end
end)

function CloseAddCustomModal()
    -- Animate out
    TweenService:Create(AddCustomModal, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        BackgroundTransparency = 1
    }):Play()
    if ModalBackdrop then
        TweenService:Create(ModalBackdrop, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
    end
    task.delay(0.22, function()
        AddCustomModal.Visible = false
        if ModalBackdrop then ModalBackdrop.Visible = false end
        AddCustomModal.BackgroundTransparency = 0.05
        acmNameBox.Text = ""; acmDataBox.Text = ""
        acmStatus.Text = "Enter keyframes data to add custom animation"
        acmStatus.TextColor3 = C.text3
    end)
end

acmCloseBtn.MouseButton1Click:Connect(CloseAddCustomModal)
acmCancelBtn.MouseButton1Click:Connect(CloseAddCustomModal)

customOpenModalBtn.MouseButton1Click:Connect(function()
    _pendingPasteData = nil
    acmNameBox.Text = ""; acmDataBox.Text = ""
    acmStatus.Text = "Enter keyframes data to add custom animation"
    acmStatus.TextColor3 = C.text3
    AddCustomModal.Visible = true
    AddCustomModal.BackgroundTransparency = 1
    if ModalBackdrop then ModalBackdrop.Visible = true; ModalBackdrop.BackgroundTransparency = 1 end
    TweenService:Create(AddCustomModal, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {BackgroundTransparency = 0.05}):Play()
    if ModalBackdrop then
        TweenService:Create(ModalBackdrop, TweenInfo.new(0.25), {BackgroundTransparency = 0.5}):Play()
    end
    acmNameBox:CaptureFocus()
end)

acmAddBtn.MouseButton1Click:Connect(function()
    -- Use _pendingPasteData if available (large pastes), else use TextBox text
    local rawData = _pendingPasteData or acmDataBox.Text
    rawData = rawData and rawData:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if rawData == "" then
        acmStatus.Text = "Please paste keyframe data first."
        acmStatus.TextColor3 = Color3.fromRGB(255,160,80); return
    end
    -- Grab name immediately before spawning (TextBox state may change)
    local capturedName = acmNameBox.Text:match("^%s*(.-)%s*$")
    local capturedRaw  = rawData
    local capturedPaste = _pendingPasteData

    acmStatus.Text = "Validating..."; acmStatus.TextColor3 = Color3.fromRGB(180,180,220)
    -- Disable button to prevent double-submit
    acmAddBtn.Active = false

    task.spawn(function()
        local isJson = false

        -- Check if it's a file path
        if capturedRaw:match("^[A-Za-z]:\\") or capturedRaw:match("^/") then
            acmStatus.Text = "Reading file..."
            local fileContent
            local ok, err = pcall(function()
                if isfile and isfile(capturedRaw) then
                    fileContent = readfile(capturedRaw)
                else
                    local file = io.open(capturedRaw, "r")
                    if file then fileContent = file:read("*a"); file:close() end
                end
            end)
            if not ok or not fileContent then
                acmStatus.Text = "Failed to read file: " .. tostring(err or "file not found")
                acmStatus.TextColor3 = Color3.fromRGB(255,90,90)
                acmAddBtn.Active = true; return
            end
            capturedRaw = fileContent
        end

        -- NON-BLOCKING ADD: do NOT parse the animation here. Parsing/JSON-decoding
        -- and building keyframe CFrames for a large animation froze the game. We
        -- just store the raw data; PlayAnimation parses it (and seeds the cache)
        -- on the first play, then it's cached like normal.
        local firstChar = capturedRaw:match("^%s*(.)")
        isJson = (firstChar == "{" or firstChar == "[")

        -- Cheap sanity check only (no parsing): keyframe data always has a table.
        if not capturedRaw:find("{", 1, true) then
            acmStatus.Text = "That doesn't look like keyframe data."
            acmStatus.TextColor3 = Color3.fromRGB(255,90,90)
            acmAddBtn.Active = true; return
        end

        local name = capturedName ~= "" and capturedName or ("Custom_" .. tostring(#CustomAnims + 1))

        -- Insert into live tables immediately so the UI sees the new anim
        if #capturedRaw > _SAVE_INLINE_MAX then
            -- Write large data to its own file (we're already on a spawned thread)
            local safeFileName = fpath("custom_" .. name:gsub("[^%w_%-]", "_") .. ".dat")
            pcall(function() writefile(safeFileName, capturedRaw) end)
            table.insert(CustomAnims, { name = name, url = safeFileName, raw = true, isJson = isJson })
            CustomAnimations[name] = safeFileName
        else
            table.insert(CustomAnims, { name = name, url = capturedRaw, raw = true, isJson = isJson })
            CustomAnimations[name] = capturedRaw
        end

        -- Persist (SaveCustomAnims is already debounced + async internally)
        SaveCustomAnims()
        SaveData()

        -- Append the newly inserted entry to the UI
        local newEntry = CustomAnims[#CustomAnims]
        if newEntry and type(AppendCustomRow) == "function" then
            AppendCustomRow(newEntry)
        end
        
        -- Update Custom tab count after adding animation
        if UpdateCustomTabCount then
            UpdateCustomTabCount()
        end
        
        Notify("Added: " .. name, 2)
        _pendingPasteData = nil
        acmAddBtn.Active = true
        CloseAddCustomModal()
    end)
end)

local stateDisplayBtns = {}

function BuildStatesPanel()
    for _, c in ipairs(StatesPanel:GetChildren()) do
        if c ~= DropdownOverlay and not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    stateDisplayBtns = {}

    for i, stType in ipairs(STATE_TYPES) do
        local row = Instance.new("Frame"); row.Parent = StatesPanel
        row.BackgroundColor3 = C.bg1; row.BackgroundTransparency = 0.2
        row.BorderSizePixel = 0; row.Size = UDim2.new(1,0,0,44); row.ZIndex = 34
        row.LayoutOrder = i
        do
            local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0,10); cr.Parent = row
            local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.5; s.Thickness = 1; s.Parent = row
        end

        local typeLbl = Instance.new("TextLabel"); typeLbl.Parent = row
        typeLbl.BackgroundTransparency = 1; typeLbl.Position = UDim2.new(0,14,0,0)
        typeLbl.Size = UDim2.new(0,65,1,0); typeLbl.Font = Enum.Font.GothamBold
        typeLbl.Text = stType; typeLbl.TextColor3 = C.accent; typeLbl.TextSize = 12
        typeLbl.TextXAlignment = Enum.TextXAlignment.Left; typeLbl.ZIndex = 35

        local currentName = "None"
        if StateAnims[stType] then
            local entry   = StateAnims[stType]
            local savedUrl = type(entry) == "table" and entry.url or entry
            for name, url in pairs(AnimationList) do
                if url == savedUrl then currentName = name; break end
            end
            if currentName == "None" then
                for _, ca in ipairs(CustomAnims) do
                    if ca.url == savedUrl then currentName = ca.name; break end
                end
            end
            if currentName == "None" then currentName = "Saved" end
        end

        local displayBtn = Instance.new("TextButton"); displayBtn.Parent = row
        displayBtn.Position = UDim2.new(0,85,0,8); displayBtn.Size = UDim2.new(1,-145,0,28)
        displayBtn.BackgroundColor3 = C.bg2; displayBtn.BackgroundTransparency = 0.4
        displayBtn.BorderSizePixel = 0; displayBtn.ZIndex = 35
        displayBtn.Font = Enum.Font.GothamMedium; displayBtn.Text = currentName
        displayBtn.TextColor3 = currentName == "None" and C.text3 or Color3.fromRGB(100, 200, 100)
        displayBtn.TextSize = 11; displayBtn.TextXAlignment = Enum.TextXAlignment.Left
        displayBtn.TextTruncate = Enum.TextTruncate.AtEnd; displayBtn.AutoButtonColor = false
        do
            local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0,7); cr.Parent = displayBtn
            local pd = Instance.new("UIPadding"); pd.PaddingLeft = UDim.new(0,12); pd.PaddingRight = UDim.new(0,24); pd.Parent = displayBtn
            local chev = Instance.new("ImageLabel"); chev.Parent = displayBtn
            chev.BackgroundTransparency = 1; chev.AnchorPoint = Vector2.new(1,0.5)
            chev.Position = UDim2.new(1,-2,0.5,0); chev.Size = UDim2.new(0,12,0,12)
            chev.Image = "rbxassetid://6034818372"
            chev.ImageColor3 = C.text3; chev.ZIndex = 36
        end

        local clrBtn = Instance.new("TextButton"); clrBtn.Parent = row
        clrBtn.AnchorPoint = Vector2.new(1,0.5); clrBtn.Position = UDim2.new(1,-10,0.5,0)
        clrBtn.Size = UDim2.new(0,52,0,28); clrBtn.BackgroundColor3 = C.bg2
        clrBtn.BackgroundTransparency = 0.3; clrBtn.BorderSizePixel = 0
        clrBtn.Font = Enum.Font.GothamBold; clrBtn.Text = "Clear"
        clrBtn.TextColor3 = C.text2; clrBtn.TextSize = 10; clrBtn.ZIndex = 35
        do
            local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0,7); cr.Parent = clrBtn
            local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.6; s.Thickness = 1; s.Parent = clrBtn
        end

        stateDisplayBtns[stType] = displayBtn

        displayBtn.MouseEnter:Connect(function()
            TweenService:Create(displayBtn, TweenInfo.new(0.15), {BackgroundColor3 = C.bg3, BackgroundTransparency = 0.2}):Play()
        end)
        displayBtn.MouseLeave:Connect(function()
            TweenService:Create(displayBtn, TweenInfo.new(0.15), {BackgroundColor3 = C.bg2, BackgroundTransparency = 0.4}):Play()
        end)

        clrBtn.MouseEnter:Connect(function()
            TweenService:Create(clrBtn, TweenInfo.new(0.15), {BackgroundColor3 = C.red, BackgroundTransparency = 0.2, TextColor3 = C.white}):Play()
        end)
        clrBtn.MouseLeave:Connect(function()
            TweenService:Create(clrBtn, TweenInfo.new(0.15), {BackgroundColor3 = C.bg2, BackgroundTransparency = 0.3, TextColor3 = C.text2}):Play()
        end)

        local st = stType; local db = displayBtn

        displayBtn.MouseButton1Click:Connect(function()
            if DropdownOverlay.Visible and ddStateLabel == db then CloseDropdown(); return end
            OpenDropdown(st, db, function(animName, animUrl)
                local isRaw = false
                for _, ca in ipairs(CustomAnims) do
                    if ca.url == animUrl then isRaw = ca.raw == true; break end
                end
                if not isRaw and type(animUrl) == "string" then
                    -- Check if it's Lua code (starts with return)
                    isRaw = animUrl:match("^%s*return") ~= nil
                end
                if not isRaw and type(animUrl) == "string" and animUrl:match("^https?://") then
                    -- HTTP URLs are raw
                    isRaw = true
                end
                if not isRaw and type(animUrl) == "string" and isfile and pcall(isfile, animUrl) and isfile(animUrl) then
                    -- Local file paths are raw (need to be loaded and parsed)
                    isRaw = true
                end
                warn("[StateAnim] Assigning", animName, "to", st, "- URL:", animUrl, "- isRaw:", isRaw)
                StateAnims[st] = { url = animUrl, raw = isRaw }
                SaveData()
                prefetchStateAnim(st)
                db.Text = animName; db.TextColor3 = Color3.fromRGB(100, 180, 255)
                if State.isReanimated then stopStateSystem(); startStateSystem() end
                Notify(st .. " -> " .. animName, 2)
            end)
        end)

        clrBtn.MouseButton1Click:Connect(function()
            StateAnims[st] = nil
            db.Text = "None"; db.TextColor3 = C.text3
            SaveData()
            if State.isReanimated then
                stopStateSystem()
                if next(StateAnims) then
                    startStateSystem()
                elseif _applyReanimDefaultAnimate then
                    -- Last custom state removed: revert to default Roblox animations.
                    _applyReanimDefaultAnimate(true)
                end
            end
            Notify(st .. " state cleared", 2)
            if DropdownOverlay.Visible and ddStateLabel == db then CloseDropdown() end
        end)
    end
end

local _statesPanelBuilt = false
function EnsureStatesPanelBuilt()
    if _statesPanelBuilt then return end
    _statesPanelBuilt = true
    BuildStatesPanel()
end

-- Lazy custom list — only build the custom-animation rows the first time the
-- Custom tab is actually opened, so opening the window never freezes building
-- rows for animations the user isn't even looking at yet.
local _customListBuilt = false
function EnsureCustomListBuilt()
    if _customListBuilt then return end
    _customListBuilt = true
    task.spawn(function()
        RebuildCustomList()
    end)
end

function SwitchTab(tabName)
    State.currentTab = tabName
    SetTabActive(TabButtons[tabName])
    if tabName == "States" then EnsureStatesPanelBuilt() end
    if tabName == "Custom" then EnsureCustomListBuilt() end
    if tabName == "Binds" then RebuildBindsList() end
    
    -- Hide all panels first
    AnimListFrame.Visible = false
    CustomPanel.Visible = false
    BindsPanel.Visible = false
    StatesPanel.Visible = false
    SettingsPanel.Visible = false
    SpeedPanel.Visible = false
    
    -- Show the appropriate panel
    if tabName == "All" or tabName == "Favs" then
        AnimListFrame.Visible = true
    elseif tabName == "Custom" then
        CustomPanel.Visible = true
    elseif tabName == "Binds" then
        BindsPanel.Visible = true
    elseif tabName == "States" then
        StatesPanel.Visible = true
    elseif tabName == "Speed" then
        SpeedPanel.Visible = true
    elseif tabName == "Settings" then
        SettingsPanel.Visible = true
    end
    
    local noSearch = (tabName == "Custom" or tabName == "Settings" or tabName == "States" or tabName == "Speed" or tabName == "Binds" or tabName == "Testing")
    SearchBox.Visible = not noSearch
    hintLbl.Visible   = not noSearch
    local listY = noSearch and 88 or 128
    AnimListFrame.Position = UDim2.new(0,10,0,listY)
    CustomPanel.Position   = UDim2.new(0,10,0,listY)
    BindsPanel.Position    = UDim2.new(0,10,0,listY)
    StatesPanel.Position   = UDim2.new(0,10,0,listY)
    SettingsPanel.Position = UDim2.new(0,10,0,listY)
    SpeedPanel.Position    = UDim2.new(0,10,0,listY)
    AnimListFrame.Size = UDim2.new(1,-20,1, noSearch and -96 or -136)
    CustomPanel.Size   = UDim2.new(1,-20,1, noSearch and -96 or -136)
    BindsPanel.Size    = UDim2.new(1,-20,1, noSearch and -96 or -136)
    StatesPanel.Size   = UDim2.new(1,-20,1, noSearch and -96 or -136)
    SettingsPanel.Size = UDim2.new(1,-20,1, noSearch and -96 or -136)
    SpeedPanel.Size    = UDim2.new(1,-20,1, noSearch and -96 or -136)
    RebuildVisible()
end

for tname, tb in pairs(TabButtons) do
    tb.MouseButton1Click:Connect(function() SwitchTab(tname) end)
end

local SpeedTrack
local SpeedValueBox
local SpeedFill
local SpeedHandle
local SpeedLabel

do
    local bottomBar = Instance.new("Frame"); bottomBar.Parent = SpeedPanel
    bottomBar.BackgroundColor3 = C.bg1; bottomBar.BackgroundTransparency = 0.35
    bottomBar.BorderSizePixel = 0; bottomBar.Size = UDim2.new(1,0,0,196)
    bottomBar.Position = UDim2.new(0,0,0,0); bottomBar.ZIndex = 40
    bottomBar.LayoutOrder = 1
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = bottomBar
    end

    -- Cover the top rounded corners of bottomBar to keep them flat
    local topCover = Instance.new("Frame"); topCover.Parent = bottomBar
    topCover.BackgroundColor3 = C.bg1; topCover.BackgroundTransparency = 0.35
    topCover.BorderSizePixel = 0; topCover.Size = UDim2.new(1,0,0,12)
    topCover.Position = UDim2.new(0,0,0,0); topCover.ZIndex = 40

    local sepLine = Instance.new("Frame"); sepLine.Parent = bottomBar
    sepLine.BackgroundColor3 = C.border; sepLine.BackgroundTransparency = 0.5
    sepLine.BorderSizePixel = 0; sepLine.Size = UDim2.new(1,0,0,1)
    sepLine.Position = UDim2.new(0,0,0,0); sepLine.ZIndex = 41

    local speedRow = Instance.new("Frame"); speedRow.Parent = bottomBar
    speedRow.BackgroundTransparency = 1; speedRow.Size = UDim2.new(1,-24,0,24)
    speedRow.AnchorPoint = Vector2.new(0,0); speedRow.Position = UDim2.new(0,12,0,14); speedRow.ZIndex = 41

    SpeedLabel = Instance.new("TextLabel"); SpeedLabel.Parent = speedRow
    SpeedLabel.BackgroundTransparency = 1; SpeedLabel.Size = UDim2.new(0,88,1,0)
    SpeedLabel.Font = Enum.Font.GothamBold; SpeedLabel.Text = "Speed: 1.0"
    SpeedLabel.TextColor3 = C.text
    SpeedLabel.TextSize = 10; SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left; SpeedLabel.ZIndex = 42

    SpeedTrack = Instance.new("Frame"); SpeedTrack.Parent = speedRow
    SpeedTrack.BackgroundColor3 = C.bg2; SpeedTrack.BackgroundTransparency = 0.3
    SpeedTrack.BorderSizePixel = 0; SpeedTrack.Position = UDim2.new(0,96,0.5,-4)
    SpeedTrack.Size = UDim2.new(1,-200,0,8); SpeedTrack.ZIndex = 42
    do 
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = SpeedTrack 
        local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = SpeedTrack
    end

    SpeedFill = Instance.new("Frame"); SpeedFill.Parent = SpeedTrack
    SpeedFill.BackgroundColor3 = C.accent; SpeedFill.BackgroundTransparency = 0.1
    SpeedFill.BorderSizePixel = 0; SpeedFill.Size = UDim2.new(0.231,0,1,0); SpeedFill.ZIndex = 43
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = SpeedFill end

    SpeedHandle = Instance.new("Frame"); SpeedHandle.Parent = SpeedTrack
    SpeedHandle.AnchorPoint = Vector2.new(0.5,0.5)
    SpeedHandle.BackgroundColor3 = C.accent; SpeedHandle.BackgroundTransparency = 0
    SpeedHandle.BorderSizePixel = 0; SpeedHandle.Position = UDim2.new(0.231,0,0.5,0)
    SpeedHandle.Size = UDim2.new(0,12,0,12); SpeedHandle.ZIndex = 44
    do 
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = SpeedHandle 
        local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.4; s.Thickness = 1; s.Parent = SpeedHandle
    end

    SpeedValueBox = Instance.new("TextBox"); SpeedValueBox.Parent = speedRow
    SpeedValueBox.AnchorPoint = Vector2.new(1,0.5)
    SpeedValueBox.BackgroundColor3 = C.bg2; SpeedValueBox.BackgroundTransparency = 0.3
    SpeedValueBox.BorderSizePixel = 0; SpeedValueBox.Position = UDim2.new(1,-54,0.5,0)
    SpeedValueBox.Size = UDim2.new(0,40,0,22); SpeedValueBox.Font = Enum.Font.GothamBold
    SpeedValueBox.Text = "1.0"; SpeedValueBox.TextColor3 = C.text2
    SpeedValueBox.TextSize = 9; SpeedValueBox.ZIndex = 42; SpeedValueBox.ClearTextOnFocus = false
    do 
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = SpeedValueBox 
        local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = SpeedValueBox
    end

    local SpeedResetBtn = Instance.new("TextButton"); SpeedResetBtn.Parent = speedRow
    SpeedResetBtn.AnchorPoint = Vector2.new(1,0.5)
    SpeedResetBtn.BackgroundColor3 = C.bg3; SpeedResetBtn.BackgroundTransparency = 0.2
    SpeedResetBtn.BorderSizePixel = 0; SpeedResetBtn.Position = UDim2.new(1,0,0.5,0)
    SpeedResetBtn.Size = UDim2.new(0,48,0,22); SpeedResetBtn.Font = Enum.Font.GothamBold
    SpeedResetBtn.Text = "Reset"; SpeedResetBtn.TextColor3 = C.accent
    SpeedResetBtn.TextSize = 9; SpeedResetBtn.ZIndex = 42; SpeedResetBtn.AutoButtonColor = false
    do 
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = SpeedResetBtn 
        local s = Instance.new("UIStroke"); s.Color = C.border; s.Transparency = 0.7; s.Thickness = 1; s.Parent = SpeedResetBtn
    end
    SpeedResetBtn.MouseEnter:Connect(function()
        TweenService:Create(SpeedResetBtn, TweenInfo.new(0.12), {BackgroundColor3 = C.accent, BackgroundTransparency = 0.2, TextColor3 = Color3.fromRGB(10,10,10)}):Play()
    end)
    SpeedResetBtn.MouseLeave:Connect(function()
        TweenService:Create(SpeedResetBtn, TweenInfo.new(0.12), {BackgroundColor3 = C.bg3, BackgroundTransparency = 0.2, TextColor3 = C.accent}):Play()
    end)
    SpeedResetBtn.MouseButton1Click:Connect(function()
        ApplySpeed(1.0)
    end)

    local spKeysHeader = Instance.new("TextLabel"); spKeysHeader.Parent = bottomBar
    spKeysHeader.BackgroundTransparency = 1; spKeysHeader.Size = UDim2.new(1,-24,0,14)
    spKeysHeader.AnchorPoint = Vector2.new(0,0); spKeysHeader.Position = UDim2.new(0,12,0,48); spKeysHeader.ZIndex = 41
    spKeysHeader.Font = Enum.Font.GothamSemibold
    spKeysHeader.Text = "Speed Presets - click a value to edit, [+] to bind"
    spKeysHeader.TextColor3 = C.text3; spKeysHeader.TextSize = 8
    spKeysHeader.TextXAlignment = Enum.TextXAlignment.Left

    local spValRow = Instance.new("Frame"); spValRow.Parent = bottomBar
    spValRow.BackgroundTransparency = 1; spValRow.Size = UDim2.new(1,-24,0,22)
    spValRow.AnchorPoint = Vector2.new(0,0); spValRow.Position = UDim2.new(0,12,0,68); spValRow.ZIndex = 41

    local spKeyRow = Instance.new("Frame"); spKeyRow.Parent = bottomBar
    spKeyRow.BackgroundTransparency = 1; spKeyRow.Size = UDim2.new(1,-24,0,22)
    spKeyRow.AnchorPoint = Vector2.new(0,0); spKeyRow.Position = UDim2.new(0,12,0,94); spKeyRow.ZIndex = 41

for i = 1, 6 do
    local xScale = (i-1) * (1/6)
    local xSzOff = -3

    local vbox = Instance.new("TextBox"); vbox.Parent = spValRow
    vbox.BackgroundColor3 = C.bg2
    vbox.BackgroundTransparency = 0.05; vbox.BorderSizePixel = 0
    vbox.Position = UDim2.new(xScale, i==1 and 0 or 2, 0, 0)
    vbox.Size = UDim2.new(1/6, i==1 and -2 or (i==6 and -2 or xSzOff), 1, 0)
    vbox.Font = Enum.Font.GothamBold
    vbox.Text = string.format("%.1f", SpeedKeybinds[i].speed)
    vbox.TextColor3 = C.accent; vbox.TextSize = 8
    vbox.ClearTextOnFocus = false; vbox.ZIndex = 42
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = vbox
        local s = Instance.new("UIStroke"); s.Color = C.border
        s.Transparency = 0.6; s.Thickness = 1; s.Parent = vbox
    end

    local kbtn = Instance.new("TextButton"); kbtn.Parent = spKeyRow
    local sk0 = SpeedKeybinds[i]
    kbtn.Position = UDim2.new(xScale, i==1 and 0 or 2, 0, 0)
    kbtn.Size = UDim2.new(1/6, i==1 and -2 or (i==6 and -2 or xSzOff), 1, 0)
    kbtn.Font = Enum.Font.GothamBold
    kbtn.Text = sk0.key and ("["..sk0.key.Name.."]") or "[+]"
    kbtn.BackgroundColor3 = sk0.key and C.bg3 or C.bg2
    kbtn.BackgroundTransparency = 0.2
    kbtn.TextColor3 = sk0.key and C.accent or C.text3
    kbtn.TextSize = 7; kbtn.ZIndex = 42; kbtn.AutoButtonColor = false
    kbtn.TextTruncate = Enum.TextTruncate.AtEnd; kbtn.BorderSizePixel = 0
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = kbtn end

    SpeedKeybinds[i].btn = kbtn
    speedKeyWidgets[i] = { vbox = vbox, kbtn = kbtn }

    local ci = i
    vbox.FocusLost:Connect(function()
        local v = tonumber((vbox.Text:gsub("[^%d%.]", "")))
        if v and v > 0 then
            SpeedKeybinds[ci].speed = v
        end
        vbox.Text = tostring(SpeedKeybinds[ci].speed)
        SaveData()
    end)

    kbtn.MouseButton1Click:Connect(function()
        if listeningSpeedIdx == ci then
            listeningSpeedIdx = nil
            local sk = SpeedKeybinds[ci]
            kbtn.Text = sk.key and ("["..sk.key.Name.."]") or "[+]"
            kbtn.BackgroundColor3 = sk.key and C.bg3 or C.bg2
            kbtn.TextColor3 = sk.key and C.accent or C.text3
            return
        end
        if SpeedKeybinds[ci].key then
            SpeedKeybinds[ci].key = nil; kbtn.Text = "[+]"
            kbtn.BackgroundColor3 = C.bg2; kbtn.TextColor3 = C.text3
            SaveData(); return
        end
        listeningSpeedIdx = ci
        kbtn.Text = "[?]"; kbtn.BackgroundColor3 = Color3.fromRGB(0,120,220)
        kbtn.TextColor3 = Color3.fromRGB(255,220,180)
    end)

    kbtn.MouseEnter:Connect(function()
        TweenService:Create(kbtn, TweenInfo.new(0.1), {BackgroundTransparency=0}):Play()
    end)
    kbtn.MouseLeave:Connect(function()
        TweenService:Create(kbtn, TweenInfo.new(0.1), {BackgroundTransparency=0.2}):Play()
    end)
end

    -- Link toggle
    local linkFrame = Instance.new("Frame"); linkFrame.Parent = bottomBar
    linkFrame.BackgroundTransparency = 1; linkFrame.Size = UDim2.new(1,-24,0,16)
    linkFrame.Position = UDim2.new(0,12,0,124); linkFrame.ZIndex = 41

    local linkLbl = Instance.new("TextLabel"); linkLbl.Parent = linkFrame
    linkLbl.BackgroundTransparency = 1; linkLbl.Size = UDim2.new(0,200,1,0)
    linkLbl.Font = Enum.Font.GothamSemibold; linkLbl.TextSize = 8
    linkLbl.Text = "Reverse Speed Keys"
    linkLbl.TextColor3 = C.text3; linkLbl.TextXAlignment = Enum.TextXAlignment.Left; linkLbl.ZIndex = 42

    local linkBtn = Instance.new("TextButton"); linkBtn.Parent = linkFrame
    linkBtn.AnchorPoint = Vector2.new(1,0.5); linkBtn.Position = UDim2.new(1,0,0.5,0)
    linkBtn.Size = UDim2.new(0,56,0,14); linkBtn.Font = Enum.Font.GothamBold; linkBtn.TextSize = 7
    linkBtn.BorderSizePixel = 0; linkBtn.AutoButtonColor = false; linkBtn.ZIndex = 42
    do local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0,4); cr.Parent = linkBtn end
    local function updateLinkBtn()
        if linkRevToNormal then
            linkBtn.Text = "Linked"; linkBtn.BackgroundColor3 = C.accent; linkBtn.TextColor3 = Color3.fromRGB(0,0,0)
            linkBtn.BackgroundTransparency = 0.1
        else
            linkBtn.Text = "Separate"; linkBtn.BackgroundColor3 = C.bg2; linkBtn.TextColor3 = C.text3
            linkBtn.BackgroundTransparency = 0.2
        end
    end
    updateLinkBtn()
    linkBtn.MouseButton1Click:Connect(function()
        linkRevToNormal = not linkRevToNormal
        updateLinkBtn()
        SaveData()
    end)

    -- Reverse speed keybind value row
    local rspValRow = Instance.new("Frame"); rspValRow.Parent = bottomBar
    rspValRow.BackgroundTransparency = 1; rspValRow.Size = UDim2.new(1,-24,0,22)
    rspValRow.Position = UDim2.new(0,12,0,146); rspValRow.ZIndex = 41

    local rspKeyRow = Instance.new("Frame"); rspKeyRow.Parent = bottomBar
    rspKeyRow.BackgroundTransparency = 1; rspKeyRow.Size = UDim2.new(1,-24,0,22)
    rspKeyRow.Position = UDim2.new(0,12,0,172); rspKeyRow.ZIndex = 41

    for i = 1, 6 do
        local xScale = (i-1) * (1/6)
        local xSzOff = -3

        local rvbox = Instance.new("TextBox"); rvbox.Parent = rspValRow
        rvbox.BackgroundColor3 = C.bg2; rvbox.BackgroundTransparency = 0.05; rvbox.BorderSizePixel = 0
        rvbox.Position = UDim2.new(xScale, i==1 and 0 or 2, 0, 0)
        rvbox.Size = UDim2.new(1/6, i==1 and -2 or (i==6 and -2 or xSzOff), 1, 0)
        rvbox.Font = Enum.Font.GothamBold
        rvbox.Text = string.format("%.1f", ReverseSpeedKeybinds[i].speed)
        rvbox.TextColor3 = Color3.fromRGB(255,130,130); rvbox.TextSize = 8
        rvbox.ClearTextOnFocus = false; rvbox.ZIndex = 42
        do
            local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0,4); cr.Parent = rvbox
            local st = Instance.new("UIStroke"); st.Color = C.border; st.Transparency = 0.6; st.Thickness = 1; st.Parent = rvbox
        end

        local rkbtn = Instance.new("TextButton"); rkbtn.Parent = rspKeyRow
        local rsk0 = ReverseSpeedKeybinds[i]
        rkbtn.Position = UDim2.new(xScale, i==1 and 0 or 2, 0, 0)
        rkbtn.Size = UDim2.new(1/6, i==1 and -2 or (i==6 and -2 or xSzOff), 1, 0)
        rkbtn.Font = Enum.Font.GothamBold
        rkbtn.Text = rsk0.key and ("["..rsk0.key.Name.."]") or "[+]"
        rkbtn.BackgroundColor3 = rsk0.key and C.bg3 or C.bg2
        rkbtn.BackgroundTransparency = 0.2
        rkbtn.TextColor3 = rsk0.key and Color3.fromRGB(255,130,130) or C.text3
        rkbtn.TextSize = 7; rkbtn.ZIndex = 42; rkbtn.AutoButtonColor = false
        rkbtn.TextTruncate = Enum.TextTruncate.AtEnd; rkbtn.BorderSizePixel = 0
        do local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0,4); cr.Parent = rkbtn end

        ReverseSpeedKeybinds[i].btn = rkbtn
        revSpeedKeyWidgets[i] = { vbox = rvbox, kbtn = rkbtn }

        local ci = i
        rvbox.FocusLost:Connect(function()
            local v = tonumber((rvbox.Text:gsub("[^%d%.]", "")))
            if v and v > 0 then
                ReverseSpeedKeybinds[ci].speed = v
            end
            rvbox.Text = tostring(ReverseSpeedKeybinds[ci].speed)
            SaveData()
        end)

        rkbtn.MouseButton1Click:Connect(function()
            if listeningRevSpeedIdx == ci then
                listeningRevSpeedIdx = nil
                local sk = ReverseSpeedKeybinds[ci]
                rkbtn.Text = sk.key and ("["..sk.key.Name.."]") or "[+]"
                rkbtn.BackgroundColor3 = sk.key and C.bg3 or C.bg2
                rkbtn.TextColor3 = sk.key and Color3.fromRGB(255,130,130) or C.text3
                return
            end
            if ReverseSpeedKeybinds[ci].key then
                ReverseSpeedKeybinds[ci].key = nil; rkbtn.Text = "[+]"
                rkbtn.BackgroundColor3 = C.bg2; rkbtn.TextColor3 = C.text3
                SaveData(); return
            end
            listeningRevSpeedIdx = ci
            rkbtn.Text = "[?]"; rkbtn.BackgroundColor3 = Color3.fromRGB(0,120,220)
            rkbtn.TextColor3 = Color3.fromRGB(255,220,180)
        end)

        rkbtn.MouseEnter:Connect(function()
            TweenService:Create(rkbtn, TweenInfo.new(0.1), {BackgroundTransparency=0}):Play()
        end)
        rkbtn.MouseLeave:Connect(function()
            TweenService:Create(rkbtn, TweenInfo.new(0.1), {BackgroundTransparency=0.2}):Play()
        end)
    end
end

function ApplySpeed(speed)
    speed = math.clamp(math.floor(speed * 10 + 0.5) / 10, 0.1, 4.0)
    State.currentSpeed   = speed
    local fraction = (speed - 0.1) / 3.9
    SpeedFill.Size       = UDim2.new(fraction, 0, 1, 0)
    SpeedHandle.Position = UDim2.new(fraction, 0, 0.5, 0)
    SpeedLabel.Text      = "Speed: " .. string.format("%.1f", speed)
    SpeedValueBox.Text   = string.format("%.1f", speed)
    if State.isReanimated then
        pcall(function() ReanimateAPI.set_animation_speed(speed) end)
    end
end

ApplySpeed(1.0)

SpeedTrack.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        isDraggingSpeed = true
        local pct = (inp.Position.X - SpeedTrack.AbsolutePosition.X) / SpeedTrack.AbsoluteSize.X
        ApplySpeed(0.1 + pct * 3.9)
    end
end)
SpeedTrack.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then isDraggingSpeed = false end
end)
UserInputService.InputChanged:Connect(function(inp)
    if isDraggingSpeed and inp.UserInputType == Enum.UserInputType.MouseMovement then
        local pct = (inp.Position.X - SpeedTrack.AbsolutePosition.X) / SpeedTrack.AbsoluteSize.X
        ApplySpeed(0.1 + pct * 3.9)
    end
end)
SpeedValueBox.FocusLost:Connect(function()
    local v = tonumber(SpeedValueBox.Text)
    if v then ApplySpeed(v)
    else SpeedValueBox.Text = string.format("%.1f", State.currentSpeed) end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local kc = input.KeyCode

    if GlobalReverseKeybind and kc == GlobalReverseKeybind then
        -- Don't trigger rewind while the user is typing in chat or another
        -- input box (gameProcessed is true).
        if gameProcessed then return end
        if State.isReanimated and ReanimateAPI and ReanimateAPI.set_animation_speed then
            local speed = tonumber(GlobalReverseSpeed) or 1.0
            if speed <= 0 then speed = 1.0 end
            pcall(ReanimateAPI.set_animation_speed, -speed)
        end
        return
    end

    if listeningSpeedIdx then
        local idx = listeningSpeedIdx; listeningSpeedIdx = nil
        if kc == Enum.KeyCode.Escape then
            local sk = SpeedKeybinds[idx]; local b = speedKeyWidgets[idx].kbtn
            b.Text = sk.key and ("["..sk.key.Name.."]") or "[+]"
            b.BackgroundColor3 = sk.key and C.bg3 or C.bg2
            b.TextColor3 = sk.key and C.accent or C.text3
            return
        end
        for j = 1, 6 do
            if j ~= idx and SpeedKeybinds[j].key == kc then
                SpeedKeybinds[j].key = nil
                speedKeyWidgets[j].kbtn.Text = "[+]"
                speedKeyWidgets[j].kbtn.BackgroundColor3 = C.bg2
                speedKeyWidgets[j].kbtn.TextColor3 = C.text3
            end
        end
        SpeedKeybinds[idx].key = kc
        local b = speedKeyWidgets[idx].kbtn
        b.Text = "["..kc.Name.."]"; b.BackgroundColor3 = C.bg3
        b.TextColor3 = C.accent
        -- If linked, also set the reverse speed keybind
        if linkRevToNormal and revSpeedKeyWidgets[idx] then
            ReverseSpeedKeybinds[idx].key = kc
            local rb = revSpeedKeyWidgets[idx].kbtn
            rb.Text = "["..kc.Name.."]"; rb.BackgroundColor3 = C.bg3
            rb.TextColor3 = Color3.fromRGB(255,130,130)
        end
        SaveData(); return
    end

    if listeningRevSpeedIdx then
        local idx = listeningRevSpeedIdx; listeningRevSpeedIdx = nil
        if kc == Enum.KeyCode.Escape then
            local sk = ReverseSpeedKeybinds[idx]; local b = revSpeedKeyWidgets[idx].kbtn
            b.Text = sk.key and ("["..sk.key.Name.."]") or "[+]"
            b.BackgroundColor3 = sk.key and C.bg3 or C.bg2
            b.TextColor3 = sk.key and Color3.fromRGB(255,130,130) or C.text3
            return
        end
        for j = 1, 6 do
            if j ~= idx and ReverseSpeedKeybinds[j].key == kc then
                ReverseSpeedKeybinds[j].key = nil
                revSpeedKeyWidgets[j].kbtn.Text = "[+]"
                revSpeedKeyWidgets[j].kbtn.BackgroundColor3 = C.bg2
                revSpeedKeyWidgets[j].kbtn.TextColor3 = C.text3
            end
        end
        ReverseSpeedKeybinds[idx].key = kc
        local b = revSpeedKeyWidgets[idx].kbtn
        b.Text = "["..kc.Name.."]"; b.BackgroundColor3 = C.bg3
        b.TextColor3 = Color3.fromRGB(255,130,130)
        SaveData(); return
    end

    if listeningKeyBtn then
        if kc == Enum.KeyCode.Escape then CancelListening(); Notify("Keybind cancelled", 1.5); return end
        BindKey(kc); return
    end

    for i = 1, 6 do
        if SpeedKeybinds[i].key == kc then
            ApplySpeed(SpeedKeybinds[i].speed)
            -- If linked, also check reverse
            if linkRevToNormal and State.isReanimated and ReanimateAPI and ReanimateAPI.set_animation_speed then
                pcall(ReanimateAPI.set_animation_speed, -ReverseSpeedKeybinds[i].speed)
            end
            return
        end
    end

    for i = 1, 6 do
        if ReverseSpeedKeybinds[i].key == kc then
            if State.isReanimated and ReanimateAPI and ReanimateAPI.set_animation_speed then
                pcall(ReanimateAPI.set_animation_speed, -ReverseSpeedKeybinds[i].speed)
            end
            return
        end
    end

    if gameProcessed then return end

    for animName, data in pairs(Keybinds) do
        if data.key == kc then
            if not State.isReanimated then return end
            local customPlain = animName:match("^%[Custom%] (.+)$")
            if customPlain then
                PlayAnimation(animName, State.currentSpeed, true)
            else
                local url = AnimationList[animName]
                if url then
                    PlayAnimation(animName, State.currentSpeed, false)
                end
            end
            break
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local kc = input.KeyCode
    if GlobalReverseKeybind and kc == GlobalReverseKeybind then
        if State.isReanimated and ReanimateAPI and ReanimateAPI.set_animation_speed then
            local resumeSpeed = tonumber(State.currentSpeed) or 1.0
            pcall(ReanimateAPI.set_animation_speed, resumeSpeed)
        end
    end
end)

local Camera = workspace.CurrentCamera

function isShiftLockActive()
    return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
        and Camera.CameraType == Enum.CameraType.Custom
end

local _lastApiCheck  = 0
local _lastAnimCheck = 0

    local function buildSettingsUI()
        local sc = SettingsPanel
        local fnGui


    -- FPS Limiter Toggle
    local fpsFrame = new("Frame",sc,{Size=UDim2.new(1,-10,0,60),BackgroundColor3=C.bg2,BackgroundTransparency=0.45,BorderSizePixel=0})
    corner(fpsFrame,8); stroke(fpsFrame,C.glassBorder,1,0.6)

    new("TextLabel",fpsFrame,{Size=UDim2.new(1,-120,0,18),Position=UDim2.new(0,10,0,10),
        BackgroundTransparency=1,Text="FPS Limiter",TextColor3=C.text,TextSize=11,
        Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left})

    new("TextLabel",fpsFrame,{Size=UDim2.new(1,-130,0,20),Position=UDim2.new(0,10,0,28),
        BackgroundTransparency=1,Text="Limits UI updates to improve performance on low-end devices.",
        TextColor3=C.text3,TextSize=9,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})

    local fpsToggleBg = new("Frame",fpsFrame,{Size=UDim2.new(0,44,0,22),Position=UDim2.new(1,-54,0,19),
        BackgroundColor3=C.bg4,BorderSizePixel=0}); corner(fpsToggleBg,11)
    local fpsToggleKnob = new("Frame",fpsToggleBg,{
        Size=UDim2.new(0,16,0,16),Position=UDim2.new(0,3,0,3),
        BackgroundColor3=C.white,BorderSizePixel=0}); corner(fpsToggleKnob,8)
    local fpsToggleBtn = new("TextButton",fpsToggleBg,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""})

    local FPSLimiterEnabled = false
    local function updateFPSLimiterState()
        if FPSLimiterEnabled then
            tw(fpsToggleBg, 0.2, {BackgroundColor3 = C.accent}):Play()
            tw(fpsToggleKnob, 0.2, {Position = UDim2.new(1,-18,0,3)}):Play()
            _G._TRXFPSLimit = true
        else
            tw(fpsToggleBg, 0.2, {BackgroundColor3 = C.bg4}):Play()
            tw(fpsToggleKnob, 0.2, {Position = UDim2.new(0,3,0,3)}):Play()
            _G._TRXFPSLimit = false
        end
    end
    fpsToggleBtn.MouseButton1Click:Connect(function()
        FPSLimiterEnabled = not FPSLimiterEnabled
        updateFPSLimiterState()
    end)

    -- Ghost Trails (Neon Visual Trail)
    local ghostFrame = new("Frame",sc,{Size=UDim2.new(1,-10,0,60),BackgroundColor3=C.bg2,BackgroundTransparency=0.45,BorderSizePixel=0})
    corner(ghostFrame,8); stroke(ghostFrame,C.glassBorder,1,0.6)

    new("TextLabel",ghostFrame,{Size=UDim2.new(1,-120,0,18),Position=UDim2.new(0,10,0,10),
        BackgroundTransparency=1,Text="Ghost Echo Trails",TextColor3=C.text,TextSize=11,
        Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left})

    new("TextLabel",ghostFrame,{Size=UDim2.new(1,-130,0,20),Position=UDim2.new(0,10,0,28),
        BackgroundTransparency=1,Text="Creates premium neon ghost trails that mimic your active animations with a smooth fade.",
        TextColor3=C.text3,TextSize=9,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})

    local ghostToggleBg = new("Frame",ghostFrame,{Size=UDim2.new(0,44,0,22),Position=UDim2.new(1,-54,0,19),
        BackgroundColor3=C.bg4,BorderSizePixel=0}); corner(ghostToggleBg,11)
    local ghostToggleKnob = new("Frame",ghostToggleBg,{
        Size=UDim2.new(0,16,0,16),Position=UDim2.new(0,3,0,3),
        BackgroundColor3=C.white,BorderSizePixel=0}); corner(ghostToggleKnob,8)
    local ghostToggleBtn = new("TextButton",ghostToggleBg,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""})

    local GhostTrailEnabled = false
    local ghostTrailConn = nil
    local lastGhostTime = 0

    local function spawnGhostClone()
        local char = plr.Character
        if not char then return end
        
        local ghostModel = Instance.new("Model")
        ghostModel.Name = "TRXGhostTrail"
        ghostModel.Parent = workspace
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 1 and part.Name ~= "HumanoidRootPart" and not part.Parent:IsA("Accessory") then
                local clone = Instance.new("Part")
                clone.Size = part.Size
                clone.CFrame = part.CFrame
                clone.Color = C.accent
                clone.Material = Enum.Material.Neon
                clone.CanCollide = false
                clone.Anchored = true
                clone.Transparency = 0.55
                clone.Parent = ghostModel
                
                local twInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local tw = game:GetService("TweenService"):Create(clone, twInfo, {Transparency = 1})
                tw:Play()
            end
        end
        
        task.delay(0.5, function()
            ghostModel:Destroy()
        end)
    end

    local function updateGhostTrailState()
    if GhostTrailEnabled then
            tw(ghostToggleBg, 0.2, {BackgroundColor3 = C.accent}):Play()
            tw(ghostToggleKnob, 0.2, {Position = UDim2.new(1,-18,0,3)}):Play()
            
            if ghostTrailConn then ghostTrailConn:Disconnect() end
            ghostTrailConn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                local now = tick()
                if now - lastGhostTime >= 0.25 then
                    lastGhostTime = now
                    pcall(spawnGhostClone)
                end
            end))
        else
            tw(ghostToggleBg, 0.2, {BackgroundColor3 = C.bg4}):Play()
            tw(ghostToggleKnob, 0.2, {Position = UDim2.new(0,3,0,3)}):Play()
            if ghostTrailConn then
                ghostTrailConn:Disconnect()
                ghostTrailConn = nil
            end
        end
    end

    ghostToggleBtn.MouseButton1Click:Connect(function()
        GhostTrailEnabled = not GhostTrailEnabled
        updateGhostTrailState()
    end)

    _G.TRXHiddenPlayers = _G.TRXHiddenPlayers or {}
    _G.FriendListenerEnabled = false
    _G.FriendListenerAutoExecute = false

    local friendCache = {}
    local function cacheFriendship(p)
        if p == plr then return end
        task.spawn(function()
            local success, result = pcall(function()
                return plr:IsFriendsWith(p.UserId)
            end)
            if success then
                friendCache[p.UserId] = result
            end
        end)
    end
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        cacheFriendship(p)
    end
    game:GetService("Players").PlayerAdded:Connect(cacheFriendship)

    local function isFriend(userId)
        if userId == plr.UserId then return true end
        if friendCache[userId] ~= nil then
            return friendCache[userId]
        end
        return false
    end

    -- Multi-layered State Manager
    local function getShouldMute(userId)
        if userId == plr.UserId then return false end
        _G.TRXHiddenPlayers = _G.TRXHiddenPlayers or {}
        local isHidden = _G.TRXHiddenPlayers[userId]
        local isFriendUser = isFriend(userId)
        local shouldMute = isHidden or (_G.FriendListenerEnabled and not isFriendUser)
        return shouldMute
    end

    local function updatePlayerState(p)
        if not p or p == plr then return end
        local shouldHide = _G.TRXHiddenPlayers and _G.TRXHiddenPlayers[p.UserId]
        local shouldMute = shouldHide or (_G.FriendListenerEnabled and not isFriend(p.UserId))

        -- 1. Roblox Core Muting (if supported by game setup)
        if shouldMute then
            pcall(function() game:GetService("StarterGui"):SetCore("ChatMutePlayer", p.Name) end)
        else
            pcall(function() game:GetService("StarterGui"):SetCore("ChatUnmutePlayer", p.Name) end)
        end

        -- 2. Visual Hiding (Local Parenting manipulation)
        local char = p.Character
        if char then
            if shouldHide then
                char.Parent = nil
            else
                if char.Parent == nil then
                    char.Parent = workspace
                end
            end
        end
    end

    local function applyAllMutes()
        for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
            updatePlayerState(p)
        end
    end
    _G.TRXApplyAllMutes = applyAllMutes

    -- Monitor Character additions
    local function hookCharacter(p)
        p.CharacterAdded:Connect(function(char)
            task.wait(0.1)
            updatePlayerState(p)
        end)
        if p.Character then
            updatePlayerState(p)
        end
    end
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        if p ~= plr then hookCharacter(p) end
    end
    game:GetService("Players").PlayerAdded:Connect(function(p)
        if p ~= plr then hookCharacter(p) end
    end)

    -- Modern Chat (TextChatService) Callback
    pcall(function()
        local TextChatService = game:GetService("TextChatService")
        local oldCallback = TextChatService.OnIncomingMessage
        TextChatService.OnIncomingMessage = function(message)
            local props = oldCallback and oldCallback(message) or Instance.new("TextChatMessageProperties")
            if message.TextSource then
                if getShouldMute(message.TextSource.UserId) then
                    props.Text = ""
                    props.PrefixText = ""
                end
            end
            return props
        end
    end)

    -- Modern Chat MessageReceived Hook
    pcall(function()
        local TextChatService = game:GetService("TextChatService")
        TextChatService.MessageReceived:Connect(function(textMessage)
            if textMessage.TextSource then
                if getShouldMute(textMessage.TextSource.UserId) then
                    local p = game:GetService("Players"):GetPlayerByUserId(textMessage.TextSource.UserId)
                    if p then
                        pcall(function() game:GetService("StarterGui"):SetCore("ChatMutePlayer", p.Name) end)
                    end
                end
            end
        end)
    end)

    -- Legacy Chat Scroller Listener (with Text property monitoring)
    local function setupScrollerListener(scroller)
        local function handleMessageFrame(child)
            if not child:IsA("Frame") then return end
            task.spawn(function()
                local textLabel = child:WaitForChild("TextLabel", 2)
                if textLabel and textLabel:IsA("TextLabel") then
                    local function checkText()
                        local text = textLabel.Text
                        if text ~= "" then
                            for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
                                if getShouldMute(p.UserId) then
                                    if text:find(p.Name) or text:find(p.DisplayName) then
                                        child:Destroy()
                                        break
                                    end
                                end
                            end
                        end
                    end
                    textLabel:GetPropertyChangedSignal("Text"):Connect(checkText)
                    checkText()
                end
            end)
        end
        scroller.ChildAdded:Connect(handleMessageFrame)
        for _, child in ipairs(scroller:GetChildren()) do
            handleMessageFrame(child)
        end
    end

    -- Hook legacy chat scroller immediately and if recreated
    task.spawn(function()
        local chatGui = plr:WaitForChild("PlayerGui"):WaitForChild("Chat", 10)
        if chatGui then
            local scroller = chatGui:FindFirstChild("Scroller", true)
            if scroller then setupScrollerListener(scroller) end
            chatGui.DescendantAdded:Connect(function(desc)
                if desc.Name == "Scroller" and desc:IsA("ScrollingFrame") then
                    setupScrollerListener(desc)
                end
            end)
        end
    end)

    -- Update mutes when players join/leave
    game:GetService("Players").PlayerAdded:Connect(function(p)
        applyAllMutes()
    end)

    -- Handle Toggle Calls
    _G.UpdateFriendListener = function(state)
        _G.FriendListenerEnabled = state
        applyAllMutes()
    end

    -- Load Friend Config
    pcall(function()
        if readfile and isfile and isfile("TRXReanimData/friend_listener_config.json") then
            local data = game:GetService("HttpService"):JSONDecode(readfile("TRXReanimData/friend_listener_config.json"))
            if data then
                _G.FriendListenerAutoExecute = data.autoExecute or false
                if _G.FriendListenerAutoExecute then
                    _G.FriendListenerEnabled = true
                    _G.UpdateFriendListener(true)
                end
            end
        end
    end)

    -- Fling Aura (Kill / Fling other players on contact)
    local flingAuraFrame = new("Frame",sc,{Size=UDim2.new(1,-10,0,60),BackgroundColor3=C.bg2,BackgroundTransparency=0.45,BorderSizePixel=0})
    corner(flingAuraFrame,8); stroke(flingAuraFrame,C.glassBorder,1,0.6)

    new("TextLabel",flingAuraFrame,{Size=UDim2.new(1,-120,0,18),Position=UDim2.new(0,10,0,10),
        BackgroundTransparency=1,Text="Fling Aura",TextColor3=C.text,TextSize=11,
        Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left})

    new("TextLabel",flingAuraFrame,{Size=UDim2.new(1,-130,0,20),Position=UDim2.new(0,10,0,28),
        BackgroundTransparency=1,Text="Spins your physical character parts at extreme velocity to fling players on touch.",
        TextColor3=C.text3,TextSize=9,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})

    local flingToggleBg = new("Frame",flingAuraFrame,{Size=UDim2.new(0,44,0,22),Position=UDim2.new(1,-54,0,19),
        BackgroundColor3=C.bg4,BorderSizePixel=0}); corner(flingToggleBg,11)
    local flingToggleKnob = new("Frame",flingToggleBg,{
        Size=UDim2.new(0,16,0,16),Position=UDim2.new(0,3,0,3),
        BackgroundColor3=C.white,BorderSizePixel=0}); corner(flingToggleKnob,8)
    local flingToggleBtn = new("TextButton",flingToggleBg,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""})

    local FlingAuraEnabled = false
    local flingAuraConn = nil

    local function updateFlingAuraState()
        if FlingAuraEnabled then
            tw(flingToggleBg, 0.2, {BackgroundColor3 = C.accent}):Play()
            tw(flingToggleKnob, 0.2, {Position = UDim2.new(1,-18,0,3)}):Play()
            
            -- Spin loop
            if flingAuraConn then flingAuraConn:Disconnect() end
            flingAuraConn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                local char = plr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.RotVelocity = Vector3.new(0, 15000, 0)
                    hrp.Velocity = Vector3.new(0, 0.1, 0)
                end
            end))
        else
            tw(flingToggleBg, 0.2, {BackgroundColor3 = C.bg4}):Play()
            tw(flingToggleKnob, 0.2, {Position = UDim2.new(0,3,0,3)}):Play()
            if flingAuraConn then
                flingAuraConn:Disconnect()
                flingAuraConn = nil
            end
        end
    end

    flingToggleBtn.MouseButton1Click:Connect(function()
        FlingAuraEnabled = not FlingAuraEnabled
        updateFlingAuraState()
    end)

    -- Mobile Emote Wheel Button (draggable, for mobile/touch players)
    local mobileWheelFrame = new("Frame",sc,{Size=UDim2.new(1,-10,0,60),BackgroundColor3=C.bg2,BackgroundTransparency=0.45,BorderSizePixel=0})
    corner(mobileWheelFrame,8); stroke(mobileWheelFrame,C.glassBorder,1,0.6)

    new("TextLabel",mobileWheelFrame,{Size=UDim2.new(1,-120,0,18),Position=UDim2.new(0,10,0,10),
        BackgroundTransparency=1,Text="Mobile Wheel Button",TextColor3=C.text,TextSize=11,
        Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left})

    new("TextLabel",mobileWheelFrame,{Size=UDim2.new(1,-130,0,20),Position=UDim2.new(0,10,0,28),
        BackgroundTransparency=1,Text="Draggable on-screen button to open the emote wheel.",
        TextColor3=C.text3,TextSize=9,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})

    local mobileToggleBg = new("Frame",mobileWheelFrame,{Size=UDim2.new(0,44,0,22),Position=UDim2.new(1,-54,0,19),
        BackgroundColor3=C.bg4,BorderSizePixel=0}); corner(mobileToggleBg,11)
    local mobileToggleKnob = new("Frame",mobileToggleBg,{
        Size=UDim2.new(0,16,0,16),Position=UDim2.new(0,3,0,3),
        BackgroundColor3=C.white,BorderSizePixel=0}); corner(mobileToggleKnob,8)
    local mobileToggleBtn = new("TextButton",mobileToggleBg,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""})

    -- 2. Clear Cache section
    local cacheFrame = new("Frame",sc,{Size=UDim2.new(1,-10,0,60),BackgroundColor3=C.bg2,BackgroundTransparency=0.45,BorderSizePixel=0})
    corner(cacheFrame,8); stroke(cacheFrame,C.glassBorder,1,0.6)
    
    new("TextLabel",cacheFrame,{Size=UDim2.new(1,-120,0,18),Position=UDim2.new(0,10,0,10),
        BackgroundTransparency=1,Text="Clear Cache",TextColor3=C.text,TextSize=11,
        Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left})
        
    new("TextLabel",cacheFrame,{Size=UDim2.new(1,-130,0,20),Position=UDim2.new(0,10,0,28),
        BackgroundTransparency=1,Text="Deletes all cache, including favourites. Keeps custom anims.",
        TextColor3=C.text3,TextSize=9,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})

    local clearCacheBtn = new("TextButton",cacheFrame,{Size=UDim2.new(0,100,0,28),Position=UDim2.new(1,-110,0,16),
        BackgroundColor3=C.red,BackgroundTransparency=0.3,Text="Clear Cache",TextColor3=C.white,
        TextSize=10,Font=Enum.Font.GothamBold,BorderSizePixel=0}); corner(clearCacheBtn,6)

    -- The draggable button itself
    local mobileBtnGui = Instance.new("ScreenGui")
    mobileBtnGui.Name = "TRXMobileWheelBtn"
    mobileBtnGui.ResetOnSpawn = false
    mobileBtnGui.IgnoreGuiInset = true
    mobileBtnGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    mobileBtnGui.DisplayOrder = 550
    pcall(function() mobileBtnGui.Parent = game:GetService("CoreGui") end)
    if not mobileBtnGui.Parent then mobileBtnGui.Parent = PlayerGui end

    local mobileBtn = Instance.new("ImageButton", mobileBtnGui)
    mobileBtn.Size = UDim2.new(0, 46, 0, 46)
    mobileBtn.Position = UDim2.new(1, -50, 0.5, 0)
    mobileBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    mobileBtn.BackgroundColor3 = C.bg0
    mobileBtn.BackgroundTransparency = 0.2
    mobileBtn.Image = ""
    mobileBtn.AutoButtonColor = false
    mobileBtn.BorderSizePixel = 0
    mobileBtn.Visible = false
    Instance.new("UICorner", mobileBtn).CornerRadius = UDim.new(0, 10)
    local mobileBtnStroke = Instance.new("UIStroke", mobileBtn)
    mobileBtnStroke.Color = C.glassBorder
    mobileBtnStroke.Thickness = 1
    mobileBtnStroke.Transparency = 0.4

    local mobileBtnIcon = Instance.new("TextLabel", mobileBtn)
    mobileBtnIcon.Size = UDim2.new(1, 0, 1, 0)
    mobileBtnIcon.BackgroundTransparency = 1
    mobileBtnIcon.Text = "E"
    mobileBtnIcon.TextColor3 = C.accent
    mobileBtnIcon.TextSize = 18
    mobileBtnIcon.Font = Enum.Font.GothamBold

    -- Dragging logic
    local draggingMobile = false
    local dragStartMobile, startPosMobile
    local dragMovedMobile = false
    mobileBtn.InputBegan:Connect(LPH_NO_VIRTUALIZE(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingMobile = true
            dragMovedMobile = false
            dragStartMobile = input.Position
            startPosMobile = mobileBtn.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    draggingMobile = false
                end
            end)
        end
    end))
    mobileBtn.InputChanged:Connect(LPH_JIT(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if draggingMobile and dragStartMobile then
                local delta = input.Position - dragStartMobile
                if delta.Magnitude > 4 then dragMovedMobile = true end
                
                -- Same clamp logic as the reanim window: keep the button fully on-screen.
                local parent = mobileBtn.Parent
                if not parent then return end
                local pap    = parent.AbsolutePosition
                local pas    = parent.AbsoluteSize
                local sz     = mobileBtn.AbsoluteSize
                local anchor = mobileBtn.AnchorPoint
                local scaleX = startPosMobile.X.Scale
                local scaleY = startPosMobile.Y.Scale
                local desiredOffsetX = startPosMobile.X.Offset + delta.X
                local desiredOffsetY = startPosMobile.Y.Offset + delta.Y
                local targetAbsX = pap.X + scaleX * pas.X + desiredOffsetX
                local targetAbsY = pap.Y + scaleY * pas.Y + desiredOffsetY
                local topLeftX = targetAbsX - anchor.X * sz.X
                local topLeftY = targetAbsY - anchor.Y * sz.Y
                topLeftX = math.clamp(topLeftX, pap.X, math.max(pap.X, pap.X + pas.X - sz.X))
                topLeftY = math.clamp(topLeftY, pap.Y, math.max(pap.Y, pap.Y + pas.Y - sz.Y))
                local newAbsX = topLeftX + anchor.X * sz.X
                local newAbsY = topLeftY + anchor.Y * sz.Y
                local newOffsetX = newAbsX - pap.X - scaleX * pas.X
                local newOffsetY = newAbsY - pap.Y - scaleY * pas.Y
                mobileBtn.Position = UDim2.new(scaleX, newOffsetX, scaleY, newOffsetY)
            end
        end
    end))

    mobileBtn.MouseButton1Click:Connect(function()
        if dragMovedMobile then return end
        if _G._OpenFortniteWheel then
            _G._OpenFortniteWheel()
        end
    end)

    local mobileEnabled = false

    pcall(function()
        local raw = readfile(CONFIG.FOLDER .. "/ReanimMobileWheelBtn.json")
        if raw then
            local data = HttpService:JSONDecode(raw)
            if data and (data.enabled == true or data.enabled == 1) then
                mobileEnabled = true
                _G._TRXMobileWheelEnabled = true
                mobileBtn.Visible = true
                mobileToggleBg.BackgroundColor3 = C.accent
                mobileToggleKnob.Position = UDim2.new(1,-18,0,3)
            end
            if data and data.posX and data.posY then
                mobileBtn.Position = UDim2.new(data.posX, data.posXO or 0, data.posY, data.posYO or 0)
            end
        end
    end)

    local mobileSavePath = CONFIG.FOLDER .. "/ReanimMobileWheelBtn.json"

    local function saveMobileBtnState()
        local jsonStr = HttpService:JSONEncode({
            enabled = mobileEnabled and 1 or 0,
            posX = mobileBtn.Position.X.Scale,
            posXO = mobileBtn.Position.X.Offset,
            posY = mobileBtn.Position.Y.Scale,
            posYO = mobileBtn.Position.Y.Offset,
        })
        pcall(function() makefolder(CONFIG.FOLDER) end)
        writefile(mobileSavePath, jsonStr)
    end

    local function doMobileToggle()
        mobileEnabled = not mobileEnabled
        mobileBtn.Visible = mobileEnabled
        _G._TRXMobileWheelEnabled = mobileEnabled
        if mobileEnabled then
            tw(mobileToggleBg, 0.2, {BackgroundColor3 = C.accent}):Play()
            tw(mobileToggleKnob, 0.2, {Position = UDim2.new(1,-18,0,3)}):Play()
        else
            tw(mobileToggleBg, 0.2, {BackgroundColor3 = C.bg4}):Play()
            tw(mobileToggleKnob, 0.2, {Position = UDim2.new(0,3,0,3)}):Play()
        end
        pcall(saveMobileBtnState)
        if _G._TRXUpdateMobileBtnText then pcall(_G._TRXUpdateMobileBtnText) end
    end

    _G._TRXToggleMobileWheel = doMobileToggle
    _G._TRXMobileWheelEnabled = mobileEnabled

    mobileToggleBtn.MouseButton1Click:Connect(function()
        doMobileToggle()
    end)

    if ScreenGui then
        ScreenGui.AncestryChanged:Connect(LPH_NO_VIRTUALIZE(function()
            if not ScreenGui.Parent then
                mobileBtn.Visible = false
                if ReanimateAPI and ReanimateAPI.stop_emote_audio then
                    pcall(ReanimateAPI.stop_emote_audio, true)
                end
                if fnGui then
                    pcall(function() fnGui:Destroy() end)
                end
                pcall(function()
                    for _, child in ipairs(game:GetService("SoundService"):GetChildren()) do
                        if child.Name == "TRXEmoteSound" or child.Name == "TRXClickSound" then
                            child:Stop(); child:Destroy()
                        end
                    end
                end)
            end
        end))
    end

    -- Version info / Credits
    local infoFrame = new("Frame",sc,{Size=UDim2.new(1,-10,0,50),BackgroundColor3=C.bg2,BackgroundTransparency=0.6,BorderSizePixel=0})
    corner(infoFrame,8); stroke(infoFrame,C.glassBorder,1,0.6)
    new("TextLabel",infoFrame,{Size=UDim2.new(1,-20,1,0),Position=UDim2.new(0,10,0,0),
        BackgroundTransparency=1,Text="TRX Reanim\nVersion: " .. CONFIG.VERSION .. " | Best reanim out",
        TextColor3=C.text3,TextSize=9,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})

    -- Wire up Import from AK button (merged into settings panel handler)

    -- Wire up Clear Cache button
    clearCacheBtn.MouseButton1Click:Connect(function()
        clearCacheBtn.Text = "Clearing..."
        pcall(function()
            local folder = CONFIG.FOLDER
            local cacheFolder = CONFIG.CACHE_FOLDER
            local deleteFunc = delfile or delete_file or (function(path) pcall(writefile, path, "") end)
            local listFilesFunc = listfiles or list_files

            -- 1. Delete known configuration files explicitly (both spellings/formats)
            local knownConfigs = {
                "ReanimFavorites.json",
                "ReanimFavourites.json",
                "ReanimStates.json",
                "ReanimKeybinds.json",
                "ReanimSpeedKeys.json",
                "ReanimRevSpeedKeys.json",
                "ReanimSpeed.json",
                "OnlineAnimationsCache.json",
                "ReanimCustomAnims.json"
            }
            for _, filename in ipairs(knownConfigs) do
                pcall(deleteFunc, folder .. "/" .. filename)
            end

            -- 2. Clear the cache folder completely (all cached online animation source files)
            local okCache, cacheFiles = pcall(function()
                if listFilesFunc then return listFilesFunc(cacheFolder) end
                return {}
            end)
            if okCache and type(cacheFiles) == "table" then
                for _, file in ipairs(cacheFiles) do
                    pcall(deleteFunc, file)
                end
            end

            -- 3. Delete any other configuration or non-animation files in ReanimData
            local okFolder, folderFiles = pcall(function()
                if listFilesFunc then return listFilesFunc(folder) end
                return {}
            end)
            if okFolder and type(folderFiles) == "table" then
                local ignored = {
                    reanimfavorites = true,
                    reanimfavourites = true,
                    reanimkeybinds = true,
                    reanimspeedkeys = true,
                    reanimstates = true,
                    reanimspeed = true,
                    onlineanimationscache = true
                }
                for _, file in ipairs(folderFiles) do
                    local n = file:match("([^/\\]+)%.[%w]+$")
                    if n then
                        local lowerName = n:lower()
                        local isLua = file:match("%.lua$")
                        local isJson = file:match("%.json$") or file:match("%.txt$")
                        local isAnim = (isLua or isJson) and not file:match("[Ss]ettings") and not file:match("[Cc]onfig") and not lowerName:match("^anim_%d+$") and not ignored[lowerName]
                        
                        if not isAnim then
                            pcall(deleteFunc, file)
                        end
                    elseif not file:match("/$") and not file:match("\\$") then
                        pcall(deleteFunc, file)
                    end
                end
            end

            -- 4. Reset in-memory state
            Favorites = {}
            StateAnims = {}
            Keybinds = {}
            SpeedKeybinds = {}
            for i = 1, 6 do
                SpeedKeybinds[i] = {speed = i * 0.5, key = nil}
            end
            table.clear(AnimationCache)

            -- 5. Reload data defaults and refresh UI
            LoadAnimationList()
            SaveData()
            RefreshCurrentList()
            Notify("Cache Cleared", "All settings and caches wiped except custom animations!", 4)
        end)
        clearCacheBtn.Text = "Clear Cache"
    end)
end
buildSettingsUI()

RunService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    if not _reanimAPIReady then return end

    local currentTime = tick()

    -- FPS optimization: skip every 3rd frame for non-critical checks
    _frameSkipCounter = (_frameSkipCounter or 0) + 1
    if _frameSkipCounter % 3 ~= 0 then return end

    if currentTime - _lastApiCheck >= 1.0 then
        local apiOk, apiVal = pcall(function() return ReanimateAPI.is_reanimated() end)
        local apiState = apiOk and apiVal or false
        if type(apiState) == "boolean" and apiState ~= State.isReanimated then
            State.isReanimated = apiState
            if not apiState then State.selectedAnim = nil end
            UpdateToggleBtn()
        end
        _lastApiCheck = currentTime
    end

    if State.isReanimated and not State.rawAnimPlaying then
        if currentTime - _lastAnimCheck >= 0.5 then
            local ok, playing = pcall(function() return ReanimateAPI.is_animation_playing() end)
            if ok and not playing and State.selectedAnim then
                State.selectedAnim = nil
                NowPlayingLabel.Text = "No animation playing"
                RefreshVirtualRows()
                RefreshCustomRows()
                if next(StateAnims) and not stateSystemActive then
                    startStateSystem()
                end
            end
            _lastAnimCheck = currentTime
        end
    end

    if State.isReanimated and isShiftLockActive() then
        local char = plr.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local _, camY, _ = Camera.CFrame:ToEulerAnglesYXZ()
                hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, camY, 0)
            end
        end
    end
end))

do
    -- Define the Fortnite Wheel UI structure
    task.spawn(LPH_NO_VIRTUALIZE(function()
        OriginalEmotes = {}

        local wheelPages = {}
        local CustomWheelPages = {}

        local function buildWheelPages(searchQuery)
            wheelPages = {}
            local q = (searchQuery and searchQuery ~= "") and string.lower(searchQuery) or ""
            
            if q == "" then
                for i, page in ipairs(CustomWheelPages) do
                    local pageCopy = {}
                    for _, e in ipairs(page) do table.insert(pageCopy, e) end
                    table.insert(wheelPages, { page = i, emotes = pageCopy })
                end
            else
                local filtered = {}
                for _, page in ipairs(CustomWheelPages) do
                    for _, e in ipairs(page) do
                        if string.find(string.lower(e), q, 1, true) then
                            table.insert(filtered, e)
                        end
                    end
                end
                
                local pageEmotes = {}
                for i, e in ipairs(filtered) do
                    table.insert(pageEmotes, e)
                    if #pageEmotes == 8 then
                        table.insert(wheelPages, { page = #wheelPages + 1, emotes = pageEmotes })
                        pageEmotes = {}
                    end
                end
                if #pageEmotes > 0 then
                    table.insert(wheelPages, { page = #wheelPages + 1, emotes = pageEmotes })
                end
            end
            
            if #wheelPages == 0 then
                table.insert(wheelPages, { page = 1, emotes = {} })
            end
        end

        buildWheelPages("")
-- Ensure local audio and icons cache directories exist
        local audioFolder = CONFIG.FOLDER .. "/fortniteaudios"
        local iconsFolder = CONFIG.FOLDER .. "/fortniteicons"
        pcall(function() makefolder(audioFolder) end)
        pcall(function() makefolder(iconsFolder) end)

        -- Audio session tracking to prevent overlapping/stale audio
        local audioSession = 0
        local currentSound = nil

        local function stopEmoteAudio(instant)
            audioSession = audioSession + 1
            if currentSound then
                local soundObj = currentSound
                currentSound = nil
                if instant then
                    pcall(function() soundObj:Stop(); soundObj:Destroy() end)
                else
                    task.spawn(function()
                        local tween = TweenService:Create(soundObj, TweenInfo.new(0.15, Enum.EasingStyle.Linear), {Volume = 0})
                        tween:Play()
                        tween.Completed:Wait()
                        pcall(function() soundObj:Stop(); soundObj:Destroy() end)
                    end)
                end
            end
        end
        if ReanimateAPI then
            ReanimateAPI.stop_emote_audio = stopEmoteAudio
        end

        -- Helper to download assets locally
        local function getLocalAsset(url, folder, filename)
            local localPath = folder .. "/" .. filename
            local ok, cached = pcall(readfile, localPath)
            local get_asset = getcustomasset or getsynasset
            if ok and cached and cached ~= "" then
                if type(get_asset) == "function" then
                    local ok2, res = pcall(get_asset, localPath)
                    if ok2 then return res end
                end
                return nil
            end
            local downloaded = request_get(url)
            if downloaded and downloaded ~= "" then
                pcall(function() writefile(localPath, downloaded) end)
                if type(get_asset) == "function" then
                    local ok2, res = pcall(get_asset, localPath)
                    if ok2 then return res end
                end
            end
            return nil
        end

        local function playEmoteAudio(emoteName)
            stopEmoteAudio(true)
            local session = audioSession
            task.spawn(function()
                local url = "" .. game:GetService("HttpService"):UrlEncode(emoteName) .. ".mp3"
                local assetId = getLocalAsset(url, audioFolder, emoteName .. ".mp3")
                if assetId and audioSession == session then
                    pcall(function()
                        local sound = Instance.new("Sound")
                        sound.Name = "TRXEmoteSound"
                        sound.SoundId = assetId
                        sound.Volume = 0
                        sound.Looped = true
                        sound.Parent = game:GetService("SoundService")
                        sound:Play()
                        if audioSession ~= session then
                            sound:Stop(); sound:Destroy()
                            return
                        end
                        currentSound = sound
                        TweenService:Create(sound, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Volume = 0.3}):Play()
                    end)
                end
            end)
        end

        -- Sound helper for menu hover/click sound effects
        local function playClickSound()
            task.spawn(function()
                local assetId = getLocalAsset("", audioFolder, "Click.mp3")
                if assetId then
                    pcall(function()
                        local sound = Instance.new("Sound")
                        sound.Name = "TRXClickSound"
                        sound.SoundId = assetId
                        sound.Volume = 0.2
                        sound.Parent = game:GetService("SoundService")
                        sound:Play()
                        task.delay(1, function()
                            pcall(function() sound:Destroy() end)
                        end)
                    end)
                end
            end)
        end

        -- Stop audio when animation stops
        if ReanimateAPI and ReanimateAPI.on_animation_stop then
            ReanimateAPI.on_animation_stop(function(stoppedName)
                stopEmoteAudio(false)
            end)
        end

        -- Create Fortnite Wheel UI ScreenGui
        fnGui = Instance.new("ScreenGui")
        fnGui.Name = "FortniteWheelUI"
        fnGui.ResetOnSpawn = false
        fnGui.IgnoreGuiInset = true
        fnGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        fnGui.DisplayOrder = 600

        local successParent = pcall(function() fnGui.Parent = game:GetService("CoreGui") end)
        if not successParent then fnGui.Parent = PlayerGui end

        -- Full-screen darken overlay
        local screenOverlay = Instance.new("Frame", fnGui)
        screenOverlay.Size = UDim2.new(1, 0, 1, 0)
        screenOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        screenOverlay.BackgroundTransparency = 0.55
        screenOverlay.BorderSizePixel = 0
        screenOverlay.ZIndex = 1
        screenOverlay.Visible = false

        -- Main wheel container
        local mainFrame = Instance.new("Frame", fnGui)
        mainFrame.Size = UDim2.new(0, 600, 0, 560)
        mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
        mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        mainFrame.BackgroundTransparency = 1
        mainFrame.Visible = false
        mainFrame.ZIndex = 2

        -- Fortnite colors
        local FN = {
            bgDark = Color3.fromRGB(12, 14, 22),
            bgMid = Color3.fromRGB(22, 26, 38),
            bgSegment = Color3.fromRGB(32, 36, 50),
            bgSegmentHover = Color3.fromRGB(0, 110, 220),
            stroke = Color3.fromRGB(48, 52, 68),
            strokeHover = Color3.fromRGB(30, 160, 255),
            textWhite = Color3.fromRGB(255, 255, 255),
            textGray = Color3.fromRGB(175, 180, 200),
            textDim = Color3.fromRGB(95, 100, 118),
            accentBlue = Color3.fromRGB(0, 140, 255),
            navBg = Color3.fromRGB(22, 26, 38),
            navHover = Color3.fromRGB(0, 110, 220),
            centerBg = Color3.fromRGB(8, 10, 18),
            dotActive = Color3.fromRGB(255, 255, 255),
            dotInactive = Color3.fromRGB(50, 55, 72),
        }

        -- Outer glow ring (subtle blue glow behind wheel)
        local glowRing = Instance.new("Frame", mainFrame)
        glowRing.Size = UDim2.new(0, 440, 0, 440)
        glowRing.Position = UDim2.new(0.5, 0, 0.5, -15)
        glowRing.AnchorPoint = Vector2.new(0.5, 0.5)
        glowRing.BackgroundTransparency = 1
        glowRing.BorderSizePixel = 0
        glowRing.ZIndex = 2
        Instance.new("UICorner", glowRing).CornerRadius = UDim.new(0.5, 0)
        local glowStroke = Instance.new("UIStroke", glowRing)
        glowStroke.Color = FN.accentBlue
        glowStroke.Thickness = 3
        glowStroke.Transparency = 0.7

        -- Outer wheel background circle
        local wheelBg = Instance.new("Frame", mainFrame)
        wheelBg.Size = UDim2.new(0, 420, 0, 420)
        wheelBg.Position = UDim2.new(0.5, 0, 0.5, -15)
        wheelBg.AnchorPoint = Vector2.new(0.5, 0.5)
        wheelBg.BackgroundColor3 = FN.bgDark
        wheelBg.BackgroundTransparency = 0
        wheelBg.BorderSizePixel = 0
        wheelBg.ZIndex = 3
        Instance.new("UICorner", wheelBg).CornerRadius = UDim.new(0.5, 0)
        local wheelBgStroke = Instance.new("UIStroke", wheelBg)
        wheelBgStroke.Color = FN.stroke
        wheelBgStroke.Thickness = 2
        wheelBgStroke.Transparency = 0.2

        -- Inner circle (center hole of donut)
        local innerCircle = Instance.new("Frame", mainFrame)
        innerCircle.Size = UDim2.new(0, 155, 0, 155)
        innerCircle.Position = UDim2.new(0.5, 0, 0.5, -15)
        innerCircle.AnchorPoint = Vector2.new(0.5, 0.5)
        innerCircle.BackgroundColor3 = FN.centerBg
        innerCircle.BackgroundTransparency = 0
        innerCircle.BorderSizePixel = 0
        innerCircle.ZIndex = 8
        Instance.new("UICorner", innerCircle).CornerRadius = UDim.new(0.5, 0)
        local innerStroke = Instance.new("UIStroke", innerCircle)
        innerStroke.Color = FN.stroke
        innerStroke.Thickness = 2
        innerStroke.Transparency = 0.3

        -- Center emote name label (inside inner circle)
        local centerLabel = Instance.new("TextLabel", mainFrame)
        centerLabel.Size = UDim2.new(0, 130, 0, 50)
        centerLabel.Position = UDim2.new(0.5, 0, 0.5, -15)
        centerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        centerLabel.BackgroundTransparency = 1
        centerLabel.Text = ""
        centerLabel.TextColor3 = FN.textWhite
        centerLabel.TextSize = 14
        centerLabel.Font = Enum.Font.GothamBold
        centerLabel.TextWrapped = true
        centerLabel.ZIndex = 9

        -- Title above wheel
        local wheelTitleIcon = Instance.new("ImageLabel", mainFrame)
        wheelTitleIcon.Name = "WheelTitle"
        wheelTitleIcon.Size = UDim2.new(0, 420, 0, 85)
        wheelTitleIcon.Position = UDim2.new(0.5, 0, 0, -26)
        wheelTitleIcon.AnchorPoint = Vector2.new(0.5, 1)
        wheelTitleIcon.BackgroundTransparency = 1
        wheelTitleIcon.ScaleType = Enum.ScaleType.Fit
        wheelTitleIcon.ZIndex = 11

        task.spawn(function()
            pcall(function() delfile(iconsFolder .. "/_wheel_title.png") end)
            local url = "https://i.postimg.cc/JzbXQrW0/halowheel.png"
            local assetId = getLocalAsset(url, iconsFolder, "halowheel.png")
            if assetId then
                wheelTitleIcon.Image = assetId
            end
        end)

        -- Page indicator dots container
        local dotsFrame = Instance.new("Frame", mainFrame)
        dotsFrame.Size = UDim2.new(0, 140, 0, 16)
        dotsFrame.Position = UDim2.new(0.5, 0, 1, -22)
        dotsFrame.AnchorPoint = Vector2.new(0.5, 0)
        dotsFrame.BackgroundTransparency = 1
        dotsFrame.ZIndex = 10
        local dotsLayout = Instance.new("UIListLayout", dotsFrame)
        dotsLayout.FillDirection = Enum.FillDirection.Horizontal
        dotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        dotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        dotsLayout.Padding = UDim.new(0, 8)

        local arrowLeftUrl = "https://i.postimg.cc/mkMJrzKw/ic-fluent-arrow-left-24-filled.png"
        local arrowRightUrl = "https://i.postimg.cc/2yvM5bg7/ic-fluent-arrow-right-24-filled.png"

            local createNavArrow = function(posX, anchorX)
            local btn = Instance.new("ImageButton", mainFrame)
            btn.Size = UDim2.new(0, 48, 0, 48)
            btn.Position = UDim2.new(posX, 0, 0.5, -15)
            btn.AnchorPoint = Vector2.new(anchorX, 0.5)
            btn.BackgroundColor3 = FN.navBg
            btn.BackgroundTransparency = 0.1
            btn.Image = ""
            btn.BorderSizePixel = 0
            btn.ZIndex = 10
            btn.AutoButtonColor = false
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)
            local navStroke = Instance.new("UIStroke", btn)
            navStroke.Color = FN.stroke
            navStroke.Thickness = 1.5
            navStroke.Transparency = 0.3
            local arrowIcon = Instance.new("ImageLabel", btn)
            arrowIcon.Name = "ArrowIcon"
            arrowIcon.Size = UDim2.new(0, 22, 0, 22)
            arrowIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
            arrowIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            arrowIcon.BackgroundTransparency = 1
            arrowIcon.ImageColor3 = FN.textWhite
            arrowIcon.ZIndex = 11
            btn.MouseEnter:Connect(function()
                TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = FN.navHover, BackgroundTransparency = 0}):Play()
                TweenService:Create(navStroke, TweenInfo.new(0.1), {Color = FN.strokeHover, Transparency = 0}):Play()
                TweenService:Create(btn, TweenInfo.new(0.08), {Size = UDim2.new(0, 52, 0, 52)}):Play()
            end)
            btn.MouseLeave:Connect(function()
                TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = FN.navBg, BackgroundTransparency = 0.1}):Play()
                TweenService:Create(navStroke, TweenInfo.new(0.12), {Color = FN.stroke, Transparency = 0.3}):Play()
                TweenService:Create(btn, TweenInfo.new(0.1), {Size = UDim2.new(0, 48, 0, 48)}):Play()
            end)
            return btn, arrowIcon
        end

        local leftArrow, leftArrowIcon = createNavArrow(0, 0.5)
        leftArrow.Position = UDim2.new(0, -8, 0.5, -15)
        leftArrow.AnchorPoint = Vector2.new(0.5, 0.5)
        local rightArrow, rightArrowIcon = createNavArrow(1, 0.5)
        rightArrow.Position = UDim2.new(1, 8, 0.5, -15)
        rightArrow.AnchorPoint = Vector2.new(0.5, 0.5)

        task.spawn(function()
            local asset = getLocalAsset(arrowLeftUrl, iconsFolder, "_arrow_left.png")
            if asset then pcall(function() leftArrowIcon.Image = asset end) end
        end)
        task.spawn(function()
            local asset = getLocalAsset(arrowRightUrl, iconsFolder, "_arrow_right.png")
            if asset then pcall(function() rightArrowIcon.Image = asset end) end
        end)

        local searchBox = Instance.new("TextBox", mainFrame)
        searchBox.Size = UDim2.new(0, 130, 0, 24)
        searchBox.Position = UDim2.new(0.5, 0, 0.5, -35)
        searchBox.AnchorPoint = Vector2.new(0.5, 0.5)
        searchBox.BackgroundColor3 = FN.bgDark
        searchBox.BackgroundTransparency = 0.2
        searchBox.BorderSizePixel = 0
        searchBox.Text = ""
        searchBox.PlaceholderText = "Search..."
        searchBox.TextColor3 = FN.textWhite
        searchBox.PlaceholderColor3 = FN.textDim
        searchBox.TextSize = 11
        searchBox.Font = Enum.Font.Gotham
        searchBox.ZIndex = 10
        searchBox.ClearTextOnFocus = false
        Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 6)
        
        centerLabel.Position = UDim2.new(0.5, 0, 0.5, 5)
        centerLabel.Size = UDim2.new(0, 130, 0, 30)
        local currentPageIdx = 1
        local currentHoveredEmote = nil
        local segmentFrames = {}
        local triggerEmote 

        local updateDots = function()
            for _, child in ipairs(dotsFrame:GetChildren()) do
                if child:IsA("Frame") then child:Destroy() end
            end
            for i = 1, #wheelPages do
                local dot = Instance.new("Frame", dotsFrame)
                dot.Size = UDim2.new(0, i == currentPageIdx and 18 or 8, 0, 8)
                dot.BackgroundColor3 = i == currentPageIdx and FN.dotActive or FN.dotInactive
                dot.BorderSizePixel = 0
                dot.ZIndex = 10
                Instance.new("UICorner", dot).CornerRadius = UDim.new(0, 4)
            end
        end

        local drawWheel = function()
           
            for _, seg in ipairs(segmentFrames) do
                pcall(function() seg:Destroy() end)
            end
            segmentFrames = {}

            local pageData = wheelPages[currentPageIdx]
            if not pageData then return end
            local emotes = pageData.emotes
            local totalEmotes = #emotes

            currentHoveredEmote = nil
            centerLabel.Text = ""
            updateDots()

            local outerRadius = 155
            local segSize = math.clamp(88 - (totalEmotes - 6) * 4, 64, 92)

            for i, emoteName in ipairs(emotes) do
                local angle = ((i - 1) / totalEmotes) * 360 - 90
                local rad = math.rad(angle)
                local xOffset = math.cos(rad) * outerRadius
                local yOffset = math.sin(rad) * outerRadius

                local seg = Instance.new("TextButton", mainFrame)
                seg.Name = "Seg_" .. i
                seg.Size = UDim2.new(0, segSize, 0, segSize)
                seg.Position = UDim2.new(0.5, xOffset, 0.5, yOffset - 15)
                seg.AnchorPoint = Vector2.new(0.5, 0.5)
                seg.BackgroundColor3 = FN.bgSegment
                seg.BackgroundTransparency = 0.1
                seg.Text = ""
                seg.BorderSizePixel = 0
                seg.AutoButtonColor = false
                seg.ZIndex = 6
                Instance.new("UICorner", seg).CornerRadius = UDim.new(0, 14)
                local segStroke = Instance.new("UIStroke", seg)
                segStroke.Color = FN.stroke
                segStroke.Thickness = 1.8
                segStroke.Transparency = 0.35

                -- Icon
                local icon = Instance.new("ImageLabel", seg)
                icon.Name = "Icon"
                icon.Size = UDim2.new(0.6, 0, 0.6, 0)
                icon.Position = UDim2.new(0.5, 0, 0.38, 0)
                icon.AnchorPoint = Vector2.new(0.5, 0.5)
                icon.BackgroundTransparency = 1
                icon.ImageColor3 = FN.textGray
                icon.ZIndex = 7

                task.spawn(function()
                    local url = "" .. game:GetService("HttpService"):UrlEncode(emoteName) .. ".png"
                    local assetId = getLocalAsset(url, iconsFolder, emoteName .. ".png")
                    if assetId then
                        icon.Image = assetId
                    end
                end)

                local segName = Instance.new("TextLabel", seg)
                segName.Size = UDim2.new(1, -4, 0, 14)
                segName.Position = UDim2.new(0.5, 0, 0.82, 0)
                segName.AnchorPoint = Vector2.new(0.5, 0.5)
                segName.BackgroundTransparency = 1
                segName.Text = emoteName
                segName.TextColor3 = FN.textDim
                segName.TextSize = 8
                segName.Font = Enum.Font.GothamSemibold
                segName.TextTruncate = Enum.TextTruncate.AtEnd
                segName.ZIndex = 7

                seg.MouseEnter:Connect(function()
                    playClickSound()
                    currentHoveredEmote = emoteName
                    centerLabel.Text = emoteName:upper()

                    for _, otherSeg in ipairs(segmentFrames) do
                        if otherSeg ~= seg and otherSeg.Parent then
                            TweenService:Create(otherSeg, TweenInfo.new(0.1), {
                                BackgroundColor3 = FN.bgSegment, BackgroundTransparency = 0.1
                            }):Play()
                            local os2 = otherSeg:FindFirstChildOfClass("UIStroke")
                            if os2 then TweenService:Create(os2, TweenInfo.new(0.1), {Color = FN.stroke, Transparency = 0.35}):Play() end
                            local oi = otherSeg:FindFirstChild("Icon")
                            if oi then TweenService:Create(oi, TweenInfo.new(0.1), {ImageColor3 = FN.textGray}):Play() end
                        end
                    end

                    TweenService:Create(seg, TweenInfo.new(0.08), {
                        BackgroundColor3 = FN.bgSegmentHover, BackgroundTransparency = 0
                    }):Play()
                    TweenService:Create(segStroke, TweenInfo.new(0.08), {Color = FN.strokeHover, Transparency = 0}):Play()
                    TweenService:Create(icon, TweenInfo.new(0.08), {ImageColor3 = FN.textWhite}):Play()
                    TweenService:Create(seg, TweenInfo.new(0.1), {Size = UDim2.new(0, segSize + 6, 0, segSize + 6)}):Play()
                end)

                seg.MouseLeave:Connect(function()
                    TweenService:Create(seg, TweenInfo.new(0.12), {
                        BackgroundColor3 = FN.bgSegment, BackgroundTransparency = 0.1,
                        Size = UDim2.new(0, segSize, 0, segSize)
                    }):Play()
                    TweenService:Create(segStroke, TweenInfo.new(0.12), {Color = FN.stroke, Transparency = 0.35}):Play()
                    TweenService:Create(icon, TweenInfo.new(0.12), {ImageColor3 = FN.textGray}):Play()
                end)

                seg.MouseButton1Click:Connect(function()
                    mainFrame.Visible = false
                    screenOverlay.Visible = false
                    triggerEmote(emoteName)
                end)

                table.insert(segmentFrames, seg)
            end
        end

        triggerEmote = function(emoteName)
            if not emoteName then return end
            task.spawn(function()
                if not ReanimateAPI.is_reanimated() then
                    Notify("Fortnite Wheel", "Please reanimate first!", 3)
                    return
                end

                stopEmoteAudio(true)

                local lowerName = emoteName:lower()
                local actualAnimName = nil
                local isCustom = false
                local animUrl = nil
                local isRaw = false

                for _, ca in ipairs(CustomAnims) do
                    if ca.name:lower() == lowerName then
                        actualAnimName = ca.name
                        isCustom = true
                        animUrl = ca.url
                        isRaw = ca.raw ~= false
                        break
                    end
                end

                if not actualAnimName then
                    for name, url in pairs(AnimationList) do
                        if name:lower() == lowerName then
                            actualAnimName = name
                            animUrl = url
                            isRaw = false
                            break
                        end
                    end
                end

                if not actualAnimName then
                    for name, url in pairs(presetList) do
                        if name:lower() == lowerName then
                            actualAnimName = name
                            animUrl = url
                            isRaw = false
                            break
                        end
                    end
                end

                if actualAnimName and animUrl then
                    local wasPlaying = State.selectedAnim == actualAnimName
                    PlayAnimation(actualAnimName, State.currentSpeed, isRaw)
                    
                    if not wasPlaying then
                        playEmoteAudio(actualAnimName)
                    end
                else
               
                    local fallbackUrl = "" .. game:GetService("HttpService"):UrlEncode(emoteName) .. ".lua"
                    local downloaded = request_get(fallbackUrl)
                    if downloaded and downloaded ~= "" then
                        AnimationList[emoteName] = fallbackUrl
                        pcall(function() writefile(GetCachePath(emoteName), downloaded) end)
                        local wasPlaying = State.selectedAnim == emoteName
                        PlayAnimation(emoteName, State.currentSpeed, false)
                        if not wasPlaying then
                            playEmoteAudio(emoteName)
                        end
                    else
                        Notify("Fortnite Wheel", "Animation not found!", 3)
                    end
                end
            end)
        end

        leftArrow.MouseButton1Click:Connect(function()
            playClickSound()
            currentPageIdx = currentPageIdx > 1 and currentPageIdx - 1 or #wheelPages
            drawWheel()
        end)
        rightArrow.MouseButton1Click:Connect(function()
            playClickSound()
            currentPageIdx = currentPageIdx < #wheelPages and currentPageIdx + 1 or 1
            drawWheel()
        end)

        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            buildWheelPages(searchBox.Text)
            drawWheel()
        end)

        drawWheel()

        local wheelScale = Instance.new("UIScale", mainFrame)
        wheelScale.Scale = 1

        local showWheel = function()
            mainFrame.Visible = true
            screenOverlay.Visible = true
            wheelScale.Scale = 0.85
            screenOverlay.BackgroundTransparency = 1
            TweenService:Create(wheelScale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
            TweenService:Create(screenOverlay, TweenInfo.new(0.15), {BackgroundTransparency = 0.55}):Play()
            searchBox.Text = ""
            buildWheelPages("")            currentPageIdx = currentPageIdx or 1
            drawWheel()
        end

        local hideWheel = function()
            TweenService:Create(wheelScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.85}):Play()
            TweenService:Create(screenOverlay, TweenInfo.new(0.1), {BackgroundTransparency = 1}):Play()
            task.delay(0.1, function()
                mainFrame.Visible = false
                screenOverlay.Visible = false
            end)
        end

        _G._OpenFortniteWheel = function()
            if not ScreenGui or not ScreenGui.Parent then return end
            if mainFrame.Visible then
                hideWheel()
            else
                showWheel()
            end
        end

        local isHolding = false
        local keyBeganConn = UserInputService.InputBegan:Connect(function(i, gp)
            if gp then return end
            if not ScreenGui or not ScreenGui.Parent then return end
            if _G._FortniteWheelKey and i.KeyCode == _G._FortniteWheelKey then
                isHolding = true
                showWheel()
            end
        end)

        local keyEndedConn = UserInputService.InputEnded:Connect(function(i, gp)
            if _G._FortniteWheelKey and i.KeyCode == _G._FortniteWheelKey then
                if isHolding and mainFrame.Visible then
                    isHolding = false
                    hideWheel()
                    if currentHoveredEmote then
                        triggerEmote(currentHoveredEmote)
                    end
                end
            end
        end)

        if _G._TRXReanimGlobalConns then
            table.insert(_G._TRXReanimGlobalConns, keyBeganConn)
            table.insert(_G._TRXReanimGlobalConns, keyEndedConn)
        end
    end))

end

pcall(function()
    ScreenGui.Parent = _screenGuiTarget
    if not ScreenGui.Parent then
        warn("[TRX Reanim] Failed to parent ScreenGui to " .. tostring(_screenGuiTarget))
        ScreenGui.Parent = PlayerGui
    end
    ScreenGui.Enabled = true
    Menu.Visible = true
end)

BuildRowPool()
SwitchTab("All")
-- RebuildCustomList() is now lazy — it builds the first time the Custom tab is
-- opened (via EnsureCustomListBuilt in SwitchTab), so the window opens instantly.
pcall(function()
    updateFnWheelBtnText()
    updateRevBtnText()
    local pct = math.clamp((GlobalReverseSpeed - 0.1) / 2.9, 0, 1)
    revFill.Size = UDim2.new(pct, 0, 1, 0)
    revHandle.Position = UDim2.new(pct, 0, 0.5, 0)
    revSpdLbl.Text = "Reverse Speed: " .. string.format("%.1f", GlobalReverseSpeed) .. "x"
end)

-- ═══════════════════════════════════════════════════════════════
--  TRX TAG SYSTEM v2.1 (Embedded)
--  Blue self-tag (stays on during reanimation)
--  Red remote warning tag — only applied to players you specify
-- ═══════════════════════════════════════════════════════════════

-- ═══ CONFIG: ADD BAD PEOPLE HERE ═══
-- Put the EXACT Roblox Name or DisplayName of anyone you want tagged.
-- You can add as many as you want. Remove the example when ready.
local BAD_PEOPLE = {
    "sstormykenziee",
    -- Add more names here like: "BadPerson123",
}

-- ═══ SELF TAG CONFIG (Blue TRX USER) ═══
local SELF_TAG = {
    TAG_TEXT = "TRX USER",
    SHOW_AT_SIGN = true,
    BADGE_COLOR = Color3.fromRGB(30, 100, 255),
    TEXT_COLOR = Color3.fromRGB(255, 255, 255),
    GLOW_COLOR = Color3.fromRGB(80, 170, 255),
    SUBTEXT_COLOR = Color3.fromRGB(200, 230, 255),
    FONT = Enum.Font.GothamBold,
    SIZE = UDim2.new(0, 180, 0, 50),
    OFFSET = Vector3.new(0, 1.6, 0),
}

-- ═══ REMOTE WARNING TAG CONFIG (Red Alert) ═══
local REMOTE_TAG = {
    TAG_TEXT = "ONLINE PREDATOR ALERT!",
    BADGE_COLOR = Color3.fromRGB(200, 0, 0),
    TEXT_COLOR = Color3.fromRGB(255, 255, 255),
    GLOW_COLOR = Color3.fromRGB(255, 50, 50),
    SUBTEXT_COLOR = Color3.fromRGB(255, 150, 150),
    FONT = Enum.Font.GothamBold,
    SIZE = UDim2.new(0, 260, 0, 56),
    OFFSET = Vector3.new(0, 1.6, 0),
}

local _tagBusy = false
local _remoteTagActive = true
local _remotePlayerData = {} -- [Player] = {conns = {}, instances = {}}

-- ═══ HELPERS ═══
local function cleanupTagsOnChar(char, tagNames)
    if not char then return end
    for _, c in ipairs(char:GetDescendants()) do
        for _, tagName in ipairs(tagNames) do
            if c.Name == tagName then
                pcall(function() c:Destroy() end)
                break
            end
        end
    end
end

local function isBadPerson(player)
    if player == plr then return false end
    for _, name in ipairs(BAD_PEOPLE) do
        if player.Name == name or player.DisplayName == name then
            return true
        end
    end
    return false
end

-- ═══ CREATE SELF TAG (Blue) ═══
local function createSelfTag(char)
    if _tagBusy then return end
    if not char then return end
    _tagBusy = true

    cleanupTagsOnChar(char, {"TRXUserTag", "TRXTagBillboard"})

    local head = char:WaitForChild("Head", 5)
    if not head then _tagBusy = false return end

    local bb = Instance.new("BillboardGui")
    bb.Name = "TRXTagBillboard"
    bb.Adornee = head
    bb.Size = SELF_TAG.SIZE
    bb.StudsOffset = SELF_TAG.OFFSET
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Parent = head

    local frame = Instance.new("Frame")
    frame.Name = "TRXUserTag"
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = SELF_TAG.BADGE_COLOR
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke")
    stroke.Color = SELF_TAG.GLOW_COLOR
    stroke.Thickness = 1.5
    stroke.Transparency = 0.3
    stroke.Parent = frame

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 100, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 50, 180))
    })
    gradient.Rotation = 90
    gradient.Parent = frame

    local iconFrame = Instance.new("Frame")
    iconFrame.Size = UDim2.new(0, 32, 0, 32)
    iconFrame.Position = UDim2.new(0, 6, 0.5, 0)
    iconFrame.AnchorPoint = Vector2.new(0, 0.5)
    iconFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    iconFrame.BackgroundTransparency = 0.9
    iconFrame.BorderSizePixel = 0
    iconFrame.Parent = frame
    Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(1, 0)

    local iconText = Instance.new("TextLabel")
    iconText.Size = UDim2.new(1, 0, 1, 0)
    iconText.BackgroundTransparency = 1
    iconText.Text = "⚡"
    iconText.TextColor3 = SELF_TAG.TEXT_COLOR
    iconText.TextSize = 16
    iconText.Font = Enum.Font.GothamBold
    iconText.Parent = iconFrame

    local tagLabel = Instance.new("TextLabel")
    tagLabel.Size = UDim2.new(1, -48, 0, 18)
    tagLabel.Position = UDim2.new(0, 42, 0, 4)
    tagLabel.BackgroundTransparency = 1
    tagLabel.Text = SELF_TAG.TAG_TEXT
    tagLabel.TextColor3 = SELF_TAG.TEXT_COLOR
    tagLabel.TextSize = 13
    tagLabel.Font = SELF_TAG.FONT
    tagLabel.TextXAlignment = Enum.TextXAlignment.Left
    tagLabel.Parent = frame

    local userText = (SELF_TAG.SHOW_AT_SIGN and "@" or "") .. plr.Name
    local userLabel = Instance.new("TextLabel")
    userLabel.Size = UDim2.new(1, -48, 0, 14)
    userLabel.Position = UDim2.new(0, 42, 0, 24)
    userLabel.BackgroundTransparency = 1
    userLabel.Text = userText
    userLabel.TextColor3 = SELF_TAG.SUBTEXT_COLOR
    userLabel.TextSize = 10
    userLabel.Font = Enum.Font.Gotham
    userLabel.TextXAlignment = Enum.TextXAlignment.Left
    userLabel.Parent = frame

    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Parent = bb
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://131604521937076"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.6
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(50, 50, 50, 50)
    shadow.Size = UDim2.new(1, 20, 1, 20)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.ZIndex = -1

    frame.Size = UDim2.new(0, 0, 1, 0)
    TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(1, 0, 1, 0)
    }):Play()

    local bobConn
    local startOffset = SELF_TAG.OFFSET
    local t = 0
    bobConn = RunService.RenderStepped:Connect(function(dt)
        if not bb or not bb.Parent then
            if bobConn then bobConn:Disconnect() end
            return
        end
        t = t + dt
        bb.StudsOffset = startOffset + Vector3.new(0, math.sin(t * 2) * 0.08, 0)
    end)

    _tagBusy = false
end

-- ═══ CREATE REMOTE WARNING TAG (Red) ═══
local function createRemoteTag(char, targetPlayer)
    if not char or not targetPlayer then return end
    cleanupTagsOnChar(char, {"TRXWarningTag", "TRXWarningBillboard"})

    local head = char:WaitForChild("Head", 5)
    if not head then return end

    local bb = Instance.new("BillboardGui")
    bb.Name = "TRXWarningBillboard"
    bb.Adornee = head
    bb.Size = REMOTE_TAG.SIZE
    bb.StudsOffset = REMOTE_TAG.OFFSET
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Parent = head

    local frame = Instance.new("Frame")
    frame.Name = "TRXWarningTag"
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = REMOTE_TAG.BADGE_COLOR
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    frame.Parent = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke")
    stroke.Color = REMOTE_TAG.GLOW_COLOR
    stroke.Thickness = 2.5
    stroke.Transparency = 0.1
    stroke.Parent = frame

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(130, 0, 0))
    })
    gradient.Rotation = 90
    gradient.Parent = frame

    local iconFrame = Instance.new("Frame")
    iconFrame.Size = UDim2.new(0, 36, 0, 36)
    iconFrame.Position = UDim2.new(0, 8, 0.5, 0)
    iconFrame.AnchorPoint = Vector2.new(0, 0.5)
    iconFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    iconFrame.BackgroundTransparency = 0.8
    iconFrame.BorderSizePixel = 0
    iconFrame.Parent = frame
    Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(1, 0)

    local iconText = Instance.new("TextLabel")
    iconText.Size = UDim2.new(1, 0, 1, 0)
    iconText.BackgroundTransparency = 1
    iconText.Text = "⚠"
    iconText.TextColor3 = Color3.fromRGB(255, 255, 0)
    iconText.TextSize = 22
    iconText.Font = Enum.Font.GothamBold
    iconText.Parent = iconFrame

    local tagLabel = Instance.new("TextLabel")
    tagLabel.Size = UDim2.new(1, -56, 0, 22)
    tagLabel.Position = UDim2.new(0, 50, 0, 3)
    tagLabel.BackgroundTransparency = 1
    tagLabel.Text = REMOTE_TAG.TAG_TEXT
    tagLabel.TextColor3 = REMOTE_TAG.TEXT_COLOR
    tagLabel.TextSize = 13
    tagLabel.Font = REMOTE_TAG.FONT
    tagLabel.TextXAlignment = Enum.TextXAlignment.Left
    tagLabel.Parent = frame

    local userText = "@" .. targetPlayer.Name
    local userLabel = Instance.new("TextLabel")
    userLabel.Size = UDim2.new(1, -56, 0, 16)
    userLabel.Position = UDim2.new(0, 50, 0, 28)
    userLabel.BackgroundTransparency = 1
    userLabel.Text = userText
    userLabel.TextColor3 = REMOTE_TAG.SUBTEXT_COLOR
    userLabel.TextSize = 11
    userLabel.Font = Enum.Font.Gotham
    userLabel.TextXAlignment = Enum.TextXAlignment.Left
    userLabel.Parent = frame

    -- CLICK TO TELEPORT BUTTON (invisible overlay)
    local tpBtn = Instance.new("TextButton")
    tpBtn.Name = "TRXTPButton"
    tpBtn.Size = UDim2.new(1, 0, 1, 0)
    tpBtn.BackgroundTransparency = 1
    tpBtn.Text = ""
    tpBtn.ZIndex = 10
    tpBtn.Parent = frame

    tpBtn.MouseButton1Click:Connect(function()
        local myChar = plr.Character
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local theirHRP = char and char:FindFirstChild("HumanoidRootPart")
        if myHRP and theirHRP then
            myHRP.CFrame = theirHRP.CFrame * CFrame.new(0, 0, 3)
            Notify("Teleported", "Warped to " .. targetPlayer.Name, 2)
        end
    end)

    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Parent = bb
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://131604521937076"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.5
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(50, 50, 50, 50)
    shadow.Size = UDim2.new(1, 24, 1, 24)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.ZIndex = -1

    frame.Size = UDim2.new(0, 0, 1, 0)
    TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(1, 0, 1, 0)
    }):Play()

    local pulseConn
    local t = 0
    pulseConn = RunService.RenderStepped:Connect(function(dt)
        if not bb or not bb.Parent then
            if pulseConn then pulseConn:Disconnect() end
            return
        end
        t = t + dt
        local pulse = 0.1 + math.sin(t * 3) * 0.15
        stroke.Transparency = math.clamp(pulse, 0, 0.5)
    end)

    if not _remotePlayerData[targetPlayer] then
        _remotePlayerData[targetPlayer] = {instances = {}, conns = {}}
    end
    table.insert(_remotePlayerData[targetPlayer].instances, bb)
end

-- ═══ SELF TAG LOGIC ═══
local function onSelfCharacter(char)
    cleanupTagsOnChar(char, {"TRXUserTag", "TRXTagBillboard"})
    task.wait(0.5)
    createSelfTag(char)
end

if plr.Character then
    task.spawn(function() onSelfCharacter(plr.Character) end)
end
plr.CharacterAdded:Connect(function(char)
    task.spawn(function() onSelfCharacter(char) end)
end)

-- ═══ REMOTE TAG LOGIC ═══
local function clearRemoteTagsForPlayer(targetPlayer)
    local data = _remotePlayerData[targetPlayer]
    if not data then return end
    for _, inst in ipairs(data.instances) do
        pcall(function() inst:Destroy() end)
    end
    for _, c in ipairs(data.conns) do
        pcall(function() c:Disconnect() end)
    end
    _remotePlayerData[targetPlayer] = nil
end

local function clearAllRemoteTags()
    local players = {}
    for player, _ in pairs(_remotePlayerData) do
        table.insert(players, player)
    end
    for _, player in ipairs(players) do
        clearRemoteTagsForPlayer(player)
    end
end

local function applyRemoteTagToPlayer(targetPlayer)
    if not targetPlayer then return end
    clearRemoteTagsForPlayer(targetPlayer)

    local data = {instances = {}, conns = {}}
    _remotePlayerData[targetPlayer] = data

    local function onTargetChar(char)
        if not _remoteTagActive then return end
        task.spawn(function()
            task.wait(0.5)
            if targetPlayer.Character == char and _remoteTagActive then
                createRemoteTag(char, targetPlayer)
            end
        end)
    end

    if targetPlayer.Character then
        onTargetChar(targetPlayer.Character)
    end

    local conn = targetPlayer.CharacterAdded:Connect(onTargetChar)
    table.insert(data.conns, conn)
end

local function scanAndTagBadPeople()
    if not _remoteTagActive then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if isBadPerson(p) then
            applyRemoteTagToPlayer(p)
        end
    end
end

local _remoteTagConns = nil
local function startRemoteTagSystem()
    scanAndTagBadPeople()

    if not _remoteTagConns then
        _remoteTagConns = {}
        local conn = Players.PlayerAdded:Connect(function(p)
            if _remoteTagActive and isBadPerson(p) then
                applyRemoteTagToPlayer(p)
                Notify("Remote Tag", "Warning tag applied to " .. p.Name, 3)
            end
        end)
        table.insert(_remoteTagConns, conn)

        local conn2 = Players.PlayerRemoving:Connect(function(p)
            clearRemoteTagsForPlayer(p)
        end)
        table.insert(_remoteTagConns, conn2)
    end
end

-- ═══ GLOBAL CONTROLS ═══
_G._TRXRemoveWarningTag = function()
    _remoteTagActive = false
    clearAllRemoteTags()
    Notify("Remote Tag", "All warning tags removed", 3)
end

_G._TRXApplyWarningTag = function()
    _remoteTagActive = true
    clearAllRemoteTags()
    startRemoteTagSystem()
end

-- Auto-start remote tag on load
startRemoteTagSystem()

-- Reanim-safe self tag: detect character swaps and re-apply cleanly
local _lastSelfChar = nil
RunService.RenderStepped:Connect(function()
    local char = plr.Character
    if char and char ~= _lastSelfChar then
        _lastSelfChar = char
        cleanupTagsOnChar(char, {"TRXUserTag", "TRXTagBillboard"})
        task.delay(0.6, function()
            if plr.Character == char then
                createSelfTag(char)
            end
        end)
    end
end)

print("[TRX Tag System] Loaded! Blue self-tag + Remote warning tags active.")
print("[TRX Tag System] Bad people list has " .. #BAD_PEOPLE .. " name(s). Edit BAD_PEOPLE to add more.")


Notify("TRX Reanimation loaded!", 2.5)

-- Onyx V2 Animation Loader with local caching
task.spawn(function()
    local onyxLoaded = 0
    local onyxCached = false

    -- Try loading from local cache first (so it works offline after first run)
    local cachePath = CONFIG.FOLDER .. "/OnyxAnimIndex.cache"
    local cachedOk, cachedRaw = pcall(function()
        if isfile and isfile(cachePath) then
            return readfile(cachePath)
        end
        return nil
    end)

    if cachedOk and cachedRaw and cachedRaw ~= "" then
        local ok, data = pcall(function() return loadstring(cachedRaw)() end)
        if ok and type(data) == "table" then
            for name, url in pairs(data) do
                local cleanName = name:gsub("%.lua$", "")
                AnimationList[cleanName] = url
                onyxLoaded = onyxLoaded + 1
            end
            onyxCached = true
        end
    end

    -- If no cache, fetch from Onyx server
    if onyxLoaded == 0 and CONFIG.ANIMATIONS_URL ~= "" then
        local ok, r = pcall(function()
            return loadstring(game:HttpGet(CONFIG.ANIMATIONS_URL, true))()
        end)
        if ok and type(r) == "table" and next(r) ~= nil then
            -- Save raw cache for offline use
            pcall(function()
                local encode = "return {\n"
                local items = {}
                for name, url in pairs(r) do
                    table.insert(items, '    ["' .. name .. '"]' .. ' = "' .. url .. '",')
                end
                table.sort(items)
                encode = encode .. table.concat(items, "\n") .. "\n}"
                writefile(cachePath, encode)
            end)

            for name, url in pairs(r) do
                local cleanName = name:gsub("%.lua$", "")
                AnimationList[cleanName] = url
                onyxLoaded = onyxLoaded + 1
            end
        end
    end

    if onyxLoaded > 0 then
        if State.currentTab == "All" or State.currentTab == "Favs" then
            pcall(RebuildVisible)
        end
        Notify("Onyx V2: " .. tostring(onyxLoaded) .. " dances loaded" .. (onyxCached and " (cached)" or ""), 3)
    end
end)

function _runEmbeddedReanimation()
    if _haloReanimHasRun then
        local found = pcall(function()
            local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
            local cg = game:GetService("CoreGui")
            if pg then
                for _, sg in ipairs(pg:GetChildren()) do
                    if sg:IsA("ScreenGui") and sg.Name == "TRXReanimMenu" then
                        sg.Enabled = true
                        for _, f in ipairs(sg:GetChildren()) do
                            if f:IsA("Frame") then f.Visible = true end
                        end
                        return true
                    end
                end
            end
            if cg then
                for _, sg in ipairs(cg:GetChildren()) do
                    if sg:IsA("ScreenGui") and sg.Name == "TRXReanimMenu" then
                        sg.Enabled = true
                        for _, f in ipairs(sg:GetChildren()) do
                            if f:IsA("Frame") then f.Visible = true end
                        end
                        return true
                    end
                end
            end
            return false
        end)
        if found then return end
    end
    _haloReanimHasRun = true
    if not _haloReanimCode then
        warn("[TRX Reanim] Code is nil - already loaded?")
        return
    end
    local ok, fn = pcall(loadstring, _haloReanimCode)
    if not ok then
        warn("[TRX Reanim] loadstring failed: " .. tostring(fn))
        return
    end
    if not fn then
        warn("[TRX Reanim] loadstring returned nil")
        return
    end
    local ok2, err = pcall(fn)
    if not ok2 then
        warn("[TRX Reanim] execution failed: " .. tostring(err))
    end
    _haloReanimCode = nil
    -- Wait a moment for the ScreenGui to be parented
    task.wait(0.1)
end
_G._TRXReanimShowMenu = _runEmbeddedReanimation
