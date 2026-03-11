-- ============================================================
-- BIBLIOTHÈQUE DES ÉOLIENNES : DÉBUT / MILIEU / MAX + RPM
-- ============================================================

local EasyConfig = {

    ["E-82 E1"] = {
		VentDemarrage = 3,       -- Vent de départ (produit 0 kW)
		VentMilieu = 8,          -- Vent intermédiaire
		PuissanceMilieu = 800,  -- Puissance forcée au vent intermédiaire (kW)
		VentMax = 12,            -- Vent où elle est à fond
		PuissanceMax = 2000,     -- Puissance maximale (kW)
		MaxRPM = 18            -- ⚙️ NOUVEAU : Vitesse de rotation max (RPM)
	},

	["E-112/45.114"] = {
		VentDemarrage = 3,
		VentMilieu = 8,
		PuissanceMilieu = 1400,
		VentMax = 13,
		PuissanceMax = 4500,
		MaxRPM = 13
	}

}

-- ============================================================
-- ⚙️ GÉNÉRATEUR AUTOMATIQUE (Lignes droites entre tes 3 points)
-- ============================================================
local PowerCurves = {}

for modelName, config in pairs(EasyConfig) do
	local generatedCurve = {}

	-- On attache le MaxRPM directement à la courbe générée !
	generatedCurve.MaxRPM = config.MaxRPM or 17.5 -- 17.5 par défaut si on oublie de le mettre

	for vent = 0, 99 do
		local puissance = 0

		if vent <= config.VentDemarrage then
			puissance = 0
		elseif vent >= config.VentMax then
			puissance = config.PuissanceMax
		elseif vent < config.VentMilieu then
			local progression = (vent - config.VentDemarrage) / (config.VentMilieu - config.VentDemarrage)
			puissance = config.PuissanceMilieu * progression
		else
			local progression = (vent - config.VentMilieu) / (config.VentMax - config.VentMilieu)
			puissance = config.PuissanceMilieu + ((config.PuissanceMax - config.PuissanceMilieu) * progression)
		end

		puissance = math.floor(puissance)
		table.insert(generatedCurve, {w = vent, p = puissance})
	end

	PowerCurves[modelName] = generatedCurve
end

return PowerCurves
