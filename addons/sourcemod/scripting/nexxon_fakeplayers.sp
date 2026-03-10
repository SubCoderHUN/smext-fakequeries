#include <sourcemod>
#include <fakequeries>

public Plugin myinfo =
{
	name = "NexxoN FakePlayers",
	author = "NexxoN",
	description = "Shows fake system players when server is empty, removes them when real players join",
	version = "1.0.0",
	url = "https://github.com/SubCoderHUN/smext-fakequeries"
};

public void OnPluginStart()
{
	FQ_ResetA2sInfo();
	FQ_SetEDF(ExtraData_GamePort | ExtraData_ServerTag | ExtraData_GameID | ExtraData_SteamID);
	FQ_InfoResponseAutoPlayerCount(true);
	FQ_ToggleStatus(true);

	if (GetRealPlayerCount() == 0)
	{
		AddFakePlayers();
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client))
		return;

	// A real player joined — remove all fake players
	FQ_RemoveAllFakePlayer();
}

public void OnClientDisconnect_Post(int client)
{
	// After disconnect, check if server is now empty
	if (GetRealPlayerCount() == 0)
	{
		AddFakePlayers();
	}
}

void AddFakePlayers()
{
	FQ_RemoveAllFakePlayer();
	FQ_AddFakePlayer(1, "[NexxoN - SyStem] - Anti-Cheat", 0, GetEngineTime());
	FQ_AddFakePlayer(2, "[NexxoN - SyStem] - PlayerMonitor", 0, GetEngineTime());
	FQ_AddFakePlayer(3, "[NexxoN - SyStem] - DiscordHook", 0, GetEngineTime());
}

int GetRealPlayerCount()
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
			count++;
	}
	return count;
}
