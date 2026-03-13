-- ============================================================
-- BIBLIOTHÈQUE DES COURBES DE PUISSANCE 
-- Points clés uniquement — interpolation linéaire dans HybridController
-- ============================================================

-- Configuration simple : 3 points + RPM max
-- Le HybridController interpole entre ces points, pas besoin de 100 entrées
local EasyConfig = {
	["E-82 E1"] = {
		MaxRPM = 18,
		-- {vitesse_vent (m/s), puissance (kW)}
		{w=3,  p=0},
		{w=8,  p=800},
		{w=12, p=2000},
		{w=25, p=2000}, -- cut-out
	},
	["E-112/45.114"] = {
		MaxRPM = 13,
		{w=3,  p=0},
		{w=8,  p=1400},
		{w=13, p=4500},
		{w=25, p=4500},
	},
}

-- Attache MaxRPM directement sur chaque table de courbe
for _, curve in pairs(EasyConfig) do
	curve.MaxRPM = curve.MaxRPM or 17.5
end

return EasyConfig