#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
#define MAX_MAPS 64
#define VOTE_DURATION 20
#define WIN_ROUNDS_TRIGGER 14

public Plugin myinfo =
{
	name = "RTV - Round 14 Vote",
	author = "Custom",
	description = "Starts a next map vote when any team reaches 14 round wins. Map changes at match end.",
	version = PLUGIN_VERSION,
	url = ""
};

// Map list
char g_MapList[MAX_MAPS][PLATFORM_MAX_PATH];
int g_MapCount;

// Vote state
bool g_bVoteStarted;
bool g_bVoteFinished;
char g_NextMap[PLATFORM_MAX_PATH];
bool g_bMapChangeNeeded;

// ConVars
ConVar g_cvMapListFile;
ConVar g_cvWinRoundsTrigger;
ConVar g_cvVoteDuration;
ConVar g_cvExcludeMaps;

// Exclude recently played maps
char g_OldMaps[MAX_MAPS][PLATFORM_MAX_PATH];
int g_OldMapCount;

public void OnPluginStart()
{
	g_cvMapListFile = CreateConVar("sm_rtv14_maplist", "maplist.txt", "File containing the map list");
	g_cvWinRoundsTrigger = CreateConVar("sm_rtv14_rounds", "14", "Number of round wins to trigger the vote", _, true, 1.0, true, 15.0);
	g_cvVoteDuration = CreateConVar("sm_rtv14_vote_duration", "20", "Vote duration in seconds", _, true, 10.0, true, 60.0);
	g_cvExcludeMaps = CreateConVar("sm_rtv14_exclude", "3", "Number of recent maps to exclude from vote", _, true, 0.0, true, 10.0);

	HookEvent("round_end", Event_RoundEnd);
	HookEvent("cs_win_panel_match", Event_MatchEnd);

	AutoExecConfig(true, "rockthevote_round14");

	LoadMapList();
}

public void OnMapStart()
{
	g_bVoteStarted = false;
	g_bVoteFinished = false;
	g_bMapChangeNeeded = false;
	g_NextMap[0] = '\0';

	LoadMapList();
}

public void OnMapEnd()
{
	// Track the current map as a recently played map
	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	int exclude = g_cvExcludeMaps.IntValue;
	if (exclude > 0)
	{
		// Shift old maps
		if (g_OldMapCount >= exclude)
		{
			for (int i = 0; i < g_OldMapCount - 1; i++)
			{
				strcopy(g_OldMaps[i], PLATFORM_MAX_PATH, g_OldMaps[i + 1]);
			}
			g_OldMapCount--;
		}
		strcopy(g_OldMaps[g_OldMapCount], PLATFORM_MAX_PATH, currentMap);
		g_OldMapCount++;
	}
}

void LoadMapList()
{
	g_MapCount = 0;

	char filePath[PLATFORM_MAX_PATH];
	g_cvMapListFile.GetString(filePath, sizeof(filePath));

	char fullPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, fullPath, sizeof(fullPath), "configs/%s", filePath);

	if (!FileExists(fullPath))
	{
		// Fallback: try root path
		BuildPath(Path_SM, fullPath, sizeof(fullPath), "%s", filePath);
		if (!FileExists(fullPath))
		{
			LogError("[RTV14] Map list file not found: %s", filePath);
			return;
		}
	}

	File file = OpenFile(fullPath, "r");
	if (file == null)
	{
		LogError("[RTV14] Could not open map list file: %s", fullPath);
		return;
	}

	char line[PLATFORM_MAX_PATH];
	while (file.ReadLine(line, sizeof(line)) && g_MapCount < MAX_MAPS)
	{
		TrimString(line);

		// Skip empty lines and comments
		if (line[0] == '\0' || line[0] == ';' || line[0] == '/' && line[1] == '/')
		{
			continue;
		}

		if (IsMapValid(line))
		{
			strcopy(g_MapList[g_MapCount], PLATFORM_MAX_PATH, line);
			g_MapCount++;
		}
	}

	delete file;
	LogMessage("[RTV14] Loaded %d maps from %s", g_MapCount, filePath);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bVoteStarted || g_bVoteFinished)
	{
		return;
	}

	int trigger = g_cvWinRoundsTrigger.IntValue;

	int ctScore = CS_GetTeamScore(CS_TEAM_CT);
	int tScore = CS_GetTeamScore(CS_TEAM_T);

	if (ctScore >= trigger || tScore >= trigger)
	{
		StartMapVote();
	}
}

public void Event_MatchEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bMapChangeNeeded && g_NextMap[0] != '\0')
	{
		char currentMap[PLATFORM_MAX_PATH];
		GetCurrentMap(currentMap, sizeof(currentMap));

		if (StrEqual(currentMap, g_NextMap, false))
		{
			PrintToChatAll("\x01[\x04RTV\x01] Next map is already the current map. No change needed.");
			return;
		}

		PrintToChatAll("\x01[\x04RTV\x01] Changing map to \x04%s\x01...", g_NextMap);
		CreateTimer(5.0, Timer_ChangeMap);
	}
}

public Action Timer_ChangeMap(Handle timer)
{
	if (g_NextMap[0] != '\0')
	{
		ForceChangeLevel(g_NextMap, "RTV Round 14 Vote");
	}

	return Plugin_Stop;
}

void StartMapVote()
{
	if (g_MapCount < 2)
	{
		LogError("[RTV14] Not enough maps in map list to start a vote (need at least 2).");
		return;
	}

	if (IsVoteInProgress())
	{
		// Retry after a short delay if another vote is running
		CreateTimer(5.0, Timer_RetryVote);
		return;
	}

	g_bVoteStarted = true;

	// Build candidate list (exclude current map and recent maps)
	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	char candidates[6][PLATFORM_MAX_PATH];
	int candidateCount = 0;
	int maxCandidates = 5; // Max options in a SourceMod menu vote

	// Shuffle the map list using Fisher-Yates on indices
	int indices[MAX_MAPS];
	for (int i = 0; i < g_MapCount; i++)
	{
		indices[i] = i;
	}
	for (int i = g_MapCount - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i);
		int temp = indices[i];
		indices[i] = indices[j];
		indices[j] = temp;
	}

	for (int i = 0; i < g_MapCount && candidateCount < maxCandidates; i++)
	{
		int idx = indices[i];

		// Skip current map
		if (StrEqual(g_MapList[idx], currentMap, false))
		{
			continue;
		}

		// Skip recently played maps
		bool isOld = false;
		for (int j = 0; j < g_OldMapCount; j++)
		{
			if (StrEqual(g_MapList[idx], g_OldMaps[j], false))
			{
				isOld = true;
				break;
			}
		}
		if (isOld)
		{
			continue;
		}

		strcopy(candidates[candidateCount], PLATFORM_MAX_PATH, g_MapList[idx]);
		candidateCount++;
	}

	if (candidateCount < 2)
	{
		// If too many excluded, allow old maps but still exclude current
		for (int i = 0; i < g_MapCount && candidateCount < maxCandidates; i++)
		{
			int idx = indices[i];
			if (StrEqual(g_MapList[idx], currentMap, false))
			{
				continue;
			}

			// Check if already added
			bool alreadyAdded = false;
			for (int j = 0; j < candidateCount; j++)
			{
				if (StrEqual(candidates[j], g_MapList[idx], false))
				{
					alreadyAdded = true;
					break;
				}
			}
			if (!alreadyAdded)
			{
				strcopy(candidates[candidateCount], PLATFORM_MAX_PATH, g_MapList[idx]);
				candidateCount++;
			}
		}
	}

	if (candidateCount < 2)
	{
		LogError("[RTV14] Not enough candidate maps after filtering.");
		g_bVoteStarted = false;
		return;
	}

	int duration = g_cvVoteDuration.IntValue;

	Menu vote = new Menu(Handler_MapVote, MENU_ACTIONS_DEFAULT | MenuAction_VoteCancel | MenuAction_VoteEnd);
	vote.SetTitle("Vote for the next map:");
	vote.ExitButton = false;

	for (int i = 0; i < candidateCount; i++)
	{
		vote.AddItem(candidates[i], candidates[i]);
	}

	vote.DisplayVoteToAll(duration);

	PrintToChatAll("\x01[\x04RTV\x01] A team has reached \x04%d\x01 round wins! Vote for the next map!", g_cvWinRoundsTrigger.IntValue);
}

public Action Timer_RetryVote(Handle timer)
{
	if (!g_bVoteFinished && g_bVoteStarted)
	{
		g_bVoteStarted = false;
		StartMapVote();
	}

	return Plugin_Stop;
}

public int Handler_MapVote(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_VoteEnd:
		{
			char winner[PLATFORM_MAX_PATH];
			char display[PLATFORM_MAX_PATH];
			int votes, totalVotes;

			menu.GetItem(param1, winner, sizeof(winner), _, display, sizeof(display));
			GetMenuVoteInfo(param2, votes, totalVotes);

			strcopy(g_NextMap, sizeof(g_NextMap), winner);
			g_bVoteFinished = true;
			g_bMapChangeNeeded = true;

			int percent = 0;
			if (totalVotes > 0)
			{
				percent = RoundToFloor(float(votes) / float(totalVotes) * 100.0);
			}

			PrintToChatAll("\x01[\x04RTV\x01] \x04%s\x01 won the vote! (%d%% of %d votes)", display, percent, totalVotes);
			PrintToChatAll("\x01[\x04RTV\x01] The map will change to \x04%s\x01 at the end of the match.", display);
		}
		case MenuAction_VoteCancel:
		{
			g_bVoteFinished = true;
			g_bVoteStarted = false;
			PrintToChatAll("\x01[\x04RTV\x01] Map vote was cancelled. No map change.");
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}

	return 0;
}
