local FormatModule = {}
local ABV = {'','K','M','B','T','qd','Qn','sx','Sp','O','N','de','Ud','DD','tdD','qdD','QnD','sxD','SpD','OcD','NvD','Vgn','UVg','DVg','TVg','qtV','QnV','SeV','SPG','OVG','NVG','TGN','UTG','DTG','tsTG','qtTG','QnTG','ssTG','SpTG','OcTG','NoAG','UnAG','DuAG','TeAG','QdAG','QnAG','SxAG','SpAG','OcAG','NvAG','CT'}
FormatModule.Round = function(Number)
	
	return math.floor(Number + 0.5)
end

function Format(Int)
	return string.format("%02i", Int)
end
FormatModule.Abbreviate = function(Number)
	
	if Number < 1000 then
		Number = FormatModule.Round(Number)
		return tostring(Number)
	end
	for i=1, #ABV do
		if tonumber(Number) < 10^(i*3) then
			return tostring(math.floor(Number/((10^((i-1)*3))/100))/(100))..ABV[i]
		end
	end
	return(FormatModule.Round(Number))

end

FormatModule.Commas = function(Number)
	
	local Formatted = Number
	while true do  
		Formatted, k = string.gsub(Formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if (k==0) then
			break
		end
	end
	return Formatted
	
end

FormatModule.Time = function(Seconds)
	
	
	
	local Minutes = (Seconds - Seconds%60)/60
	Seconds = Seconds - Minutes*60
	local Hours = (Minutes - Minutes%60)/60
	Minutes = Minutes - Hours*60
	return Format(Hours)..":"..Format(Minutes)..":"..Format(Seconds)
end

FormatModule.ConvertToHMS = function(Seconds)
	local Minutes = (Seconds - Seconds%60)/60
	Seconds = Seconds - Minutes*60
	local Hours = (Minutes - Minutes%60)/60
	Minutes = Minutes - Hours*60
	if Hours >= 10 then
		return Format(Hours)..":"..Format(Minutes)..":"..Format(Seconds)
	elseif Hours >= 1 then
		return tostring(Hours)..":"..Format(Minutes)..":"..Format(Seconds)
	elseif Minutes >= 10 then
		return Format(Minutes)..":"..Format(Seconds)
	elseif Minutes < 10 and Minutes >= 1 then
		return tostring(Minutes)..":"..Format(Seconds)
	else
		return tostring(Seconds).."s"
	end
end

return FormatModule
