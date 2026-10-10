-- ============================================================================
-- V12 RAPTOR DOUGLAS 911 -- modules/formulae.lua
-- Core Calculation Engine
--
-- PRIVATE MODULE -- not exposed directly to players or other mods.
-- thermalV12, voiceTrigger, descentV12, cameraSystem all call into this.
-- The math lives here. The interfaces live in the calling modules.
-- Sliders in NativeSettings show abstracted human-readable controls,
-- never the raw formulae underneath.
--
-- Systems:
--   Nerve        : context-dependent nerve change calculation
--   Depravity    : per-category slow accumulation (violence/substances/sex/sloth/acquisition)
--   Dependency   : per-substance tolerance curve
--   Alignment    : intended-V vs current-V drift and capitulation
--   Voice        : diamond distribution probability curve
--   MoralFlip    : post-psychosis reward inversion detection
--   VehicleComfort: favorite vehicle time-based comfort system
--   DrugEffect   : substance relief formula with tolerance and depravity scaling
--
-- Pure ASCII. Lua 5.1.
-- ============================================================================

local Formulae = {}

-- ============================================================================
-- ACTION CLASSIFICATION
-- Maps game events to nerve change base values and depravity categories
-- ============================================================================

-- Base nerve change per action (before modifiers)
-- Positive = nerve gain. Negative = nerve loss.
local BASE_NERVE = {
    -- Driving
    red_good_shift        =  1.0,
    red_bad_shift         = -2.0,
    blue_good_shift       =  0.5,
    green_good_shift      =  0.3,
    clean_run_exit        =  8.0,
    near_miss_survived    = -1.5,
    crash_minor           = -4.0,
    crash_major           = -8.0,
    highway_hypnosis_stack=  6.0,
    speed_zone_sustained  =  2.0,

    -- Combat
    kill_clean            = -3.0,   -- costs nerve (pre-flip)
    kill_innocent         = -8.0,
    kill_self_defense     = -1.5,
    near_death_survived   =  5.0,   -- adrenaline recovery
    cop_engaged           = -2.0,
    cop_lost              =  4.0,

    -- Social/moral
    meditate              = 12.0,
    meditation_zone_idle  =  2.0,
    steal_vehicle         = -2.5,
    steal_owned_vehicle   = -5.0,   -- V's own car stolen by others = loss
    drug_use              =  0.0,   -- calculated separately via drugEffect()
    lizzie_visit          = -1.0,   -- uncomfortable if low sex depravity
    lizzie_visit_depraved =  2.0,   -- comfortable if high sex depravity

    -- Walking when V "prefers" to drive (laziness sub-category gate)
    forced_walk           = -0.5,   -- small nerve drain if sloth depravity high

    -- Silence (no trigger, just decay)
    calm_driving_decay    =  0.8,   -- per-interval while calm
}

-- Which depravity sub-category each action feeds
local ACTION_CATEGORY = {
    kill_clean            = "violence",
    kill_innocent         = "violence",
    kill_self_defense     = "violence",
    steal_vehicle         = "acquisition",
    steal_owned_vehicle   = "acquisition",
    drug_use              = "substances",
    lizzie_visit          = "sexuality",
    lizzie_visit_depraved = "sexuality",
    forced_walk           = "sloth",
    -- driving actions don't feed depravity directly
}

-- Base depravity accumulation rate per action (before modifiers)
local DEPRAVITY_RATES = {
    kill_clean            = 0.008,
    kill_innocent         = 0.025,
    kill_self_defense     = 0.002,
    steal_vehicle         = 0.006,
    steal_owned_vehicle   = 0.001,   -- minor: property crime
    drug_use              = 0.012,   -- feeds substances
    lizzie_visit          = 0.004,   -- feeds sexuality slowly
    forced_walk           = 0.001,   -- feeds sloth negligibly
}

-- Depravity decay rate per second while NOT doing the relevant action
-- History is permanent but can drift back very slowly
local DEPRAVITY_DECAY = {
    violence    = 0.000008,  -- extremely slow
    substances  = 0.000012,
    sexuality   = 0.000006,
    sloth       = 0.000020,  -- fastest -- physical habits break easier
    acquisition = 0.000010,
}

-- ============================================================================
-- NERVE CHANGE CALCULATION
-- Context-aware nerve delta for any action
-- ============================================================================

-- context = {
--   depravity    = depravity table (see Formulae.newDepravity())
--   alignment    = alignment table
--   isFlipped    = bool (post-psychosis)
--   dfNerve      = current DF nerve level 0-100
--   dependency   = dependency table
-- }
function Formulae.calcNerveChange(action, context)
    context = context or {}

    local base = BASE_NERVE[action] or 0
    if base == 0 then return 0 end

    local depravity = context.depravity or Formulae.newDepravity()
    local depTotal  = depravity.total or 0.0

    -- High depravity reduces nerve SENSITIVITY
    -- V stops feeling things as strongly -- blunted affect
    local sensitivityMod = 1.0 - (depTotal * 0.45)
    sensitivityMod = math.max(0.25, sensitivityMod)  -- floor at 25% sensitivity

    -- High alignment drift AMPLIFIES changes
    -- The internal battle makes everything feel bigger
    local drift = (context.alignment and context.alignment.drift) or 0.0
    local driftMod = 1.0 + (drift * 0.35)

    -- Sub-category consistency modifier
    -- Acting consistently with your depravity history costs/gains less
    local subCat = ACTION_CATEGORY[action]
    local consistency = subCat and (depravity[subCat] or 0.0) or 0.0
    local consistencyMod = 1.0
    if base < 0 and consistency > 0.3 then
        -- Depraved in this category: bad acts hurt less
        consistencyMod = 1.0 - (consistency * 0.6)
    elseif base > 0 and consistency > 0.3 then
        -- Depraved in this category: good acts feel less rewarding
        consistencyMod = 1.0 - (consistency * 0.3)
    end

    -- Moral flip: post-psychosis inversion for depraved-aligned actions
    if context.isFlipped and base < 0 and consistency > 0.5 then
        -- Bad acts in aligned category give POSITIVE nerve (dampened)
        base = math.abs(base) * 0.55
    end

    return base * sensitivityMod * driftMod * consistencyMod
end

-- ============================================================================
-- DEPRAVITY SYSTEM
-- ============================================================================

function Formulae.newDepravity()
    return {
        violence    = 0.0,
        substances  = 0.0,
        sexuality   = 0.0,
        sloth       = 0.0,
        acquisition = 0.0,
        total       = 0.0,  -- weighted average, updated on change
    }
end

-- Weights for total depravity calculation
local DEPRAVITY_WEIGHTS = {
    violence    = 0.30,
    substances  = 0.25,
    sexuality   = 0.20,
    sloth       = 0.10,
    acquisition = 0.15,
}

local function updateDepravityTotal(dep)
    local total = 0.0
    for cat, weight in pairs(DEPRAVITY_WEIGHTS) do
        total = total + (dep[cat] or 0.0) * weight
    end
    dep.total = math.min(1.0, total)
end

-- Accumulate depravity from an action
-- Returns the delta added to the relevant sub-category
function Formulae.addDepravity(dep, action)
    local category = ACTION_CATEGORY[action]
    if not category then return 0.0 end

    local base = DEPRAVITY_RATES[action] or 0.0
    local current = dep[category] or 0.0

    -- Consistency bonus: repeated acts in the same category build faster
    -- First few times = full shock. Hundredth time = normalized.
    -- This models habituation.
    local habituationBoost = 1.0 + (current * 0.4)

    local delta = base * habituationBoost
    dep[category] = math.min(1.0, current + delta)
    updateDepravityTotal(dep)
    return delta
end

-- Decay depravity over time
-- Call once per second in the thermal/descent update
function Formulae.decayDepravity(dep, dt)
    local changed = false
    for cat, rate in pairs(DEPRAVITY_DECAY) do
        if dep[cat] and dep[cat] > 0 then
            dep[cat] = math.max(0.0, dep[cat] - rate * dt)
            changed = true
        end
    end
    if changed then updateDepravityTotal(dep) end
end

-- ============================================================================
-- DEPENDENCY SYSTEM
-- Per-substance tolerance curve
-- ============================================================================

function Formulae.newDependency()
    return {
        alcohol     = 0.0,
        stimulants  = 0.0,
        sedatives   = 0.0,
        other       = 0.0,
    }
end

local DEPENDENCY_BUILD = {
    alcohol    = 0.12,
    stimulants = 0.18,
    sedatives  = 0.10,
    other      = 0.08,
}

local DEPENDENCY_DECAY = {
    alcohol    = 0.00015,   -- ~2 hours real-time to halve
    stimulants = 0.00008,
    sedatives  = 0.00012,
    other      = 0.00020,
}

function Formulae.useDrug(dep, drugType)
    local build = DEPENDENCY_BUILD[drugType] or DEPENDENCY_BUILD.other
    dep[drugType] = math.min(1.0, (dep[drugType] or 0.0) + build)
end

function Formulae.decayDependency(dep, dt)
    for drug, rate in pairs(DEPENDENCY_DECAY) do
        if dep[drug] and dep[drug] > 0 then
            dep[drug] = math.max(0.0, dep[drug] - rate * dt)
        end
    end
end

-- Calculate actual nerve effect of taking a drug
-- Returns nerve delta (positive = relief)
function Formulae.drugEffect(drugType, context)
    context = context or {}
    local depravity   = context.depravity or Formulae.newDepravity()
    local dependency  = context.dependency or Formulae.newDependency()

    -- Base relief per drug type
    local BASE_RELIEF = {
        alcohol    = 8.0,
        stimulants = 12.0,
        sedatives  = 6.0,
        other      = 5.0,
    }
    local base = BASE_RELIEF[drugType] or 5.0

    -- Depravity boost: depraved V gets more relief (substances sub-category)
    local subsDep = depravity.substances or 0.0
    local depBoost = 1.0 + (subsDep * 0.85)

    -- Tolerance penalty: heavy users get diminishing returns
    local tol = dependency[drugType] or 0.0
    local tolPenalty = 1.0 - (tol * 0.65)
    tolPenalty = math.max(0.08, tolPenalty)  -- floor: always gets some effect

    -- Alignment mod: fighting V needs more to feel same effect
    local drift = (context.alignment and context.alignment.drift) or 0.0
    local alignMod = 1.0 - (drift * 0.2)  -- internal conflict reduces effectiveness

    return base * depBoost * tolPenalty * alignMod
end

-- ============================================================================
-- ALIGNMENT SYSTEM
-- intended V (slow) vs current V (fast)
-- drift = internal battle intensity
-- capitulation = intended slowly following current downward
-- ============================================================================

function Formulae.newAlignment()
    return {
        intended  = 1.0,   -- who V wants to be (slow to change)
        current   = 1.0,   -- who V is becoming (fast to change)
        drift     = 0.0,   -- |intended - current| = battle intensity
        momentum  = 0.0,   -- rate of current change
        timeAtDrift = 0.0, -- accumulated time at high drift (capitulation clock)
    }
end

-- recentBehaviorScore: 0.0 = pure depraved actions, 1.0 = pure clean actions
-- Call once per update with behavior averaged over last ~30s
function Formulae.updateAlignment(al, dt, recentBehaviorScore)
    local target = recentBehaviorScore or al.intended

    -- current moves toward recent behavior -- fast
    local currentSpeed = 0.06
    local oldCurrent   = al.current
    al.current  = al.current + (target - al.current) * currentSpeed * dt
    al.current  = math.max(0.0, math.min(1.0, al.current))
    al.momentum = (al.current - oldCurrent) / math.max(0.001, dt)

    -- drift = gap between intended and current
    al.drift = math.abs(al.intended - al.current)

    -- Track time at high drift for capitulation
    if al.drift > 0.25 then
        al.timeAtDrift = al.timeAtDrift + dt
    else
        al.timeAtDrift = math.max(0.0, al.timeAtDrift - dt * 2.0)
    end

    -- Capitulation: intended slowly follows current when drift is sustained
    -- Rate accelerates with time at drift -- V gets tired of fighting
    -- This is the most subtle and devastating mechanic:
    -- No dramatic moment. The gap just... closes. And then she's quiet.
    local capitulationRate = 0.0
    if al.timeAtDrift > 120.0 then
        -- 2+ minutes of sustained conflict -- capitulation begins
        local excess = al.timeAtDrift - 120.0
        capitulationRate = 0.0005 + (excess * 0.000002)
        capitulationRate = math.min(0.003, capitulationRate)

        -- intended drifts toward current
        if al.drift > 0.05 then
            local dir = al.current < al.intended and -1.0 or 1.0
            al.intended = al.intended + dir * capitulationRate * dt
            al.intended = math.max(0.0, math.min(1.0, al.intended))
        end
    end

    return al
end

-- ============================================================================
-- VOICE PROBABILITY -- DIAMOND DISTRIBUTION
-- Rarest at full nerve (calm, no struggle) and near zero (unified, past caring)
-- Most frequent at nerve 30-60 (the battle zone)
-- The drama lives in the middle.
-- ============================================================================

-- nerve: 0.0-1.0 (DF nerve normalized)
-- depravity: depravity table
function Formulae.voiceChance(nerve, depravity)
    depravity = depravity or Formulae.newDepravity()
    local depTotal = depravity.total or 0.0

    -- Depravity shifts the bell center toward lower nerve
    -- Depraved V has more "battle" at lower nerve values
    local center = 0.45 - (depTotal * 0.10)
    local spread = 0.25

    local dist  = math.abs(nerve - center)
    local bell  = 0.35 * math.exp(-(dist * dist) / (2.0 * spread * spread))

    -- Depravity slightly raises overall voice frequency
    -- More depraved V has more internal noise
    local depBoost = 1.0 + (depTotal * 0.18)

    return math.max(0.02, math.min(0.55, bell * depBoost))
end

-- ============================================================================
-- MORAL FLIP DETECTION
-- Post-psychosis: reward structure inverts for aligned actions
-- V doesn't become evil -- she becomes coherent with her new self
-- ============================================================================

function Formulae.isMorallyFlipped(alignment, depravity)
    alignment = alignment or Formulae.newAlignment()
    depravity = depravity or Formulae.newDepravity()

    -- Flip requires:
    -- 1. Both intended AND current are at low values (they've converged at the bottom)
    -- 2. High enough depravity to sustain the new state
    -- 3. Drift has closed (they've stopped fighting)
    local convergedLow = alignment.current < 0.18 and alignment.intended < 0.28
    local depraved     = depravity.total > 0.55
    local stopped      = alignment.drift < 0.15

    return convergedLow and depraved and stopped
end

-- Which depravity sub-categories have flipped for this V
-- Returns table of flipped categories
function Formulae.getFlippedCategories(depravity)
    depravity = depravity or Formulae.newDepravity()
    local flipped = {}
    local FLIP_THRESHOLD = 0.65
    for cat, _ in pairs(DEPRAVITY_WEIGHTS) do
        if (depravity[cat] or 0.0) >= FLIP_THRESHOLD then
            flipped[cat] = true
        end
    end
    return flipped
end

-- ============================================================================
-- VEHICLE COMFORT SYSTEM
-- Favorite vehicle tracked by time. Comfort affects nerve, stress, ambient.
-- ============================================================================

function Formulae.newVehicleHistory()
    return {}   -- keyed by vehicleId
end

local function ensureVehicle(history, vehicleId)
    if not history[vehicleId] then
        history[vehicleId] = {
            totalTime  = 0.0,   -- seconds driven
            recentTime = 0.0,   -- seconds in last session
            isOwned    = false,
            isStolen   = false,
            lastDriven = 0.0,
            favoriteRank = 0,   -- 0=unknown, 1-5 comfort tier
        }
    end
    return history[vehicleId]
end

function Formulae.recordDriving(history, vehicleId, dt, isOwned)
    local v = ensureVehicle(history, vehicleId)
    v.totalTime  = v.totalTime + dt
    v.recentTime = v.recentTime + dt
    v.isOwned    = isOwned or v.isOwned
    v.lastDriven = os.clock()
    v.favoriteRank = Formulae.getVehicleComfortTier(v)
end

function Formulae.getVehicleComfortTier(vehicleRecord)
    if not vehicleRecord then return 0 end
    local hours = vehicleRecord.totalTime / 3600.0

    -- Tier 1: 30 min. Tier 2: 2h. Tier 3: 5h. Tier 4: 10h. Tier 5: 25h+
    if hours >= 25.0 then return 5
    elseif hours >= 10.0 then return 4
    elseif hours >= 5.0  then return 3
    elseif hours >= 2.0  then return 2
    elseif hours >= 0.5  then return 1
    else return 0 end
end

-- Returns nerve bonus for being in your favorite vehicle
-- 0.0 = stranger's car. Up to 3.0 per interval for beloved vehicle.
function Formulae.vehicleComfortBonus(history, vehicleId)
    local v = history and history[vehicleId]
    if not v then return 0.0 end

    local tier     = v.favoriteRank or 0
    local owned    = v.isOwned and 0.5 or 0.0
    local tierBonus = ({0.0, 0.3, 0.6, 1.0, 1.8, 3.0})[tier + 1] or 0.0

    return tierBonus + owned
end

-- Returns stress modifier for sleeping in a vehicle
-- Beloved vehicle = better rest = larger nerve recovery
function Formulae.vehicleSleepBonus(history, vehicleId)
    local comfort = Formulae.vehicleComfortBonus(history, vehicleId)
    return comfort * 2.5   -- sleep multiplier
end

-- ============================================================================
-- LAZINESS / SLOTH COMPLAINT THRESHOLD
-- If sloth depravity is high AND V has been walking too long, return true
-- Caller plays an appropriate complaint audio
-- ============================================================================
function Formulae.isWalkingTooLong(slothDepravity, walkingSeconds)
    if slothDepravity < 0.35 then return false end
    -- Higher sloth depravity = complaint threshold drops
    local threshold = 60.0 * (1.0 - slothDepravity * 0.7)
    threshold = math.max(20.0, threshold)
    return walkingSeconds >= threshold
end

-- ============================================================================
-- STRESS FROM COPS / WANTED SYSTEM
-- Wanted level multiplied by context to produce nerve drain rate
-- ============================================================================
function Formulae.wantedNerveDrain(wantedStars, depravity, isFlipped)
    if wantedStars <= 0 then return 0.0 end
    depravity = depravity or Formulae.newDepravity()

    local base = wantedStars * 1.5   -- per interval
    local violenceDep = depravity.violence or 0.0

    -- Depraved V handles heat better
    local depMod = 1.0 - (violenceDep * 0.4)

    -- Flipped V might enjoy it (zero cost, maybe gain)
    if isFlipped and violenceDep > 0.6 then
        return -base * 0.3   -- negative = nerve GAIN from police chase
    end

    return base * depMod
end

-- ============================================================================
-- CLEAN RUN SCORING
-- Used by survival run evaluator in thermalV12
-- ============================================================================
function Formulae.calcSurvivalScore(runData, context)
    runData  = runData  or {}
    context  = context  or {}

    local avgSpeed   = runData.avgSpeed    or 0
    local topSpeed   = runData.topSpeed    or 0
    local timeInRain = runData.timeInRain  or 0
    local rainMult   = runData.rainMult    or 0
    local closeCalls = runData.closeCalls  or 0
    local isClean    = runData.isClean     and true or false

    if not isClean then return 0.0 end

    local base   = avgSpeed * 0.8 + topSpeed * 0.2
    local rainB  = 1.0 + timeInRain * 0.008 * (1.0 + rainMult * 0.6)
    local callB  = 1.0 + closeCalls * 0.04

    -- Comfort bonus from favorite vehicle (V feels better in familiar car)
    local comfortB = 1.0 + Formulae.vehicleComfortBonus(
        context.vehicleHistory or {},
        context.vehicleId or ""
    ) * 0.05

    return base * rainB * callB * comfortB
end

-- ============================================================================
-- DEPRAVITY INTERACTION WITH HUMANITY
-- How depravity modifies the humanity/nerve cost-benefit of actions
-- ============================================================================

-- Returns multiplier applied to humanity/nerve change for an action
-- At high depravity in relevant category, bad acts cost less,
-- good acts feel less meaningful
function Formulae.humanityModifier(action, depravity)
    depravity = depravity or Formulae.newDepravity()
    local cat  = ACTION_CATEGORY[action]
    local base = BASE_NERVE[action] or 0.0

    if not cat then return 1.0 end

    local catDep = depravity[cat] or 0.0

    if base < 0 then
        -- Depraved acts: penalty shrinks as depravity grows
        return 1.0 - (catDep * 0.55)
    else
        -- Good acts: reward shrinks as depravity in that category grows
        return 1.0 - (catDep * 0.30)
    end
end

-- ============================================================================
-- NIGHT CITY CONTEXTUAL MODIFIERS
-- Location/district awareness for depravity and nerve calculations
-- Uses 0-Engine GetDistrict if available
-- ============================================================================

local DISTRICT_NERVE_MOD = {
    ["watson"]        =  0.0,
    ["westbrook"]     = -0.5,   -- corpo/wealth proximity = existential unease
    ["heywood"]       =  0.5,   -- familiar, hood feel
    ["pacifica"]      = -2.0,   -- hostile territory = stress baseline higher
    ["santo_domingo"] = -0.5,
    ["city_center"]   = -1.0,   -- corpo surveillance = subliminal stress
    ["badlands"]      =  1.5,   -- open road = freedom
}

function Formulae.getDistrictNerveMod(district)
    return DISTRICT_NERVE_MOD[district] or 0.0
end

-- ============================================================================
-- COMBINED STATE SUMMARY
-- Returns a single table other modules can read for current V state
-- ============================================================================

function Formulae.summarizeState(dfNerve, depravity, alignment, dependency)
    depravity  = depravity  or Formulae.newDepravity()
    alignment  = alignment  or Formulae.newAlignment()
    dependency = dependency or Formulae.newDependency()
    dfNerve    = dfNerve    or 100.0

    local nerve        = dfNerve / 100.0   -- normalized 0-1
    local isFlipped    = Formulae.isMorallyFlipped(alignment, depravity)
    local flippedCats  = Formulae.getFlippedCategories(depravity)
    local voiceP       = Formulae.voiceChance(nerve, depravity)

    -- Descent phase (1-6)
    local phase
    if nerve > 0.70 then       phase = 1
    elseif nerve > 0.50 then   phase = 2
    elseif nerve > 0.30 then   phase = 3
    elseif nerve > 0.10 then   phase = 4
    elseif nerve > 0.02 then   phase = 5
    else                       phase = isFlipped and 6 or 5 end

    return {
        nerve          = nerve,
        dfNerve        = dfNerve,
        depravityTotal = depravity.total,
        depravity      = depravity,
        alignment      = alignment,
        dependency     = dependency,
        isFlipped      = isFlipped,
        flippedCats    = flippedCats,
        voiceProbability = voiceP,
        descentPhase   = phase,
        -- Human readable phase name (for debug/boot sequence)
        phaseName      = ({
            "Clear",
            "Slipping",
            "Struggling",
            "Breaking",
            "The Shift",
            "Unity",
        })[phase] or "Unknown",
    }
end

-- ============================================================================
-- INIT
-- ============================================================================
function Formulae.init()
    print("[V12 Formulae] Core calculation engine initialised.")
    print("[V12 Formulae] Systems: Nerve, Depravity(5-cat), Dependency, Alignment,")
    print("[V12 Formulae]          VoiceDiamond, MoralFlip, VehicleComfort, SurvivalScore")
end

return Formulae
