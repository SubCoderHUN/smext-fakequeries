/**
 * =============================================================================
 * Standalone Rock The Vote + Map Chooser + Nominations
 * All-in-one map voting plugin for CS:GO / Source Engine servers.
 *
 * Features:
 *   - Rock The Vote (players vote to change the map early)
 *   - End-of-map automatic vote
 *   - Map nominations via chat (!nominate / !nom)
 *   - Configurable via CVars and auto-generated .cfg
 *   - Map exclusion (recently played maps)
 *   - Extend map / Don't Change options
 *   - Runoff votes when margin is too close
 *   - Admin commands: sm_mapvote, sm_setnextmap
 *   - Round-based and time-based vote triggers
 *
 * Commands:
 *   say rtv / say !rtv / sm_rtv          - Rock the Vote
 *   say nominate / say !nominate / !nom  - Nominate a map
 *   sm_mapvote (admin)                   - Force a map vote
 *   sm_setnextmap <map> (admin)          - Set next map directly
 *
 * =============================================================================
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <nextmap>

#define PLUGIN_VERSION "1.0.0"

/* ===================== CONSTANTS ===================== */

#define VOTE_EXTEND     "##extend##"
#define VOTE_DONTCHANGE "##dontchange##"
#define MAXTEAMS        10

/* ===================== ENUMS ===================== */

enum MapChange
{
	MapChange_Instant,
	MapChange_RoundEnd,
	MapChange_MapEnd
};

/* ===================== PLUGIN INFO ===================== */

public Plugin myinfo =
{
	name        = "Rock The Vote (Standalone)",
	author      = "AlliedModders LLC, Modified",
	description = "All-in-one RTV, Map Chooser, and Nominations",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/SubCoderHUN/smext-fakequeries"
};

/* ===================== CVARS ===================== */

// RTV
ConVar g_cvRtvNeeded;
ConVar g_cvRtvMinPlayers;
ConVar g_cvRtvInitialDelay;
ConVar g_cvRtvInterval;
ConVar g_cvRtvChangeTime;

// Map Chooser
ConVar g_cvEndOfMapVote;
ConVar g_cvStartTime;
ConVar g_cvStartRounds;
ConVar g_cvStartFrags;
ConVar g_cvExtendTimeStep;
ConVar g_cvExtendRoundStep;
ConVar g_cvExtendFragStep;
ConVar g_cvExcludeMaps;
ConVar g_cvIncludeMaps;
ConVar g_cvNoVoteMode;
ConVar g_cvExtend;
ConVar g_cvDontChange;
ConVar g_cvVoteDuration;
ConVar g_cvRunOff;
ConVar g_cvRunOffPercent;

// Nominations
ConVar g_cvNomExcludeOld;
ConVar g_cvNomExcludeCurrent;

// Game ConVars
ConVar g_cvWinlimit;
ConVar g_cvMaxrounds;
ConVar g_cvFraglimit;
ConVar g_cvBonusRoundTime;

/* ===================== MAP DATA ===================== */

ArrayList g_MapList;
ArrayList g_NominateList;
ArrayList g_NominateOwners;
ArrayList g_OldMapList;
ArrayList g_NextMapList;

int g_mapFileSerial = -1;

/* ===================== VOTE STATE ===================== */

Menu g_VoteMenu;
Handle g_VoteTimer;
Handle g_RetryTimer;

int g_Extends;
int g_TotalRounds;
bool g_HasVoteStarted;
bool g_WaitingForVote;
bool g_MapVoteCompleted;
bool g_ChangeMapAtRoundEnd;
bool g_ChangeMapInProgress;
MapChange g_ChangeTime;

int g_winCount[MAXTEAMS];

/* ===================== RTV STATE ===================== */

bool g_RTVVoted[MAXPLAYERS + 1];
bool g_RTVAllowed;
int g_RTVVoters;
int g_RTVVotes;
int g_RTVVotesNeeded;

/* ===================== NOMINATION STATE ===================== */

Menu g_NominateMenu;
StringMap g_NominateMapStatus;

#define MAPSTATUS_ENABLED     (0)
#define MAPSTATUS_DISABLED    (1 << 0)
#define MAPSTATUS_EXCLUDE_OLD (1 << 1)
#define MAPSTATUS_EXCLUDE_CUR (1 << 2)
#define MAPSTATUS_EXCLUDE_NOM (1 << 3)

/* ===================== PLUGIN LIFECYCLE ===================== */

public void OnPluginStart()
{
	LoadTranslations("rockthevote.phrases");

	int arraySize = ByteCountToCells(PLATFORM_MAX_PATH);
	g_MapList = new ArrayList(arraySize);
	g_NominateList = new ArrayList(arraySize);
	g_NominateOwners = new ArrayList();
	g_OldMapList = new ArrayList(arraySize);
	g_NextMapList = new ArrayList(arraySize);
	g_NominateMapStatus = new StringMap();

	// RTV ConVars
	g_cvRtvNeeded = CreateConVar("sm_rtv_needed", "0.60", "Percentage of players needed to rock the vote (0.60 = 60%)", _, true, 0.05, true, 1.0);
	g_cvRtvMinPlayers = CreateConVar("sm_rtv_minplayers", "0", "Minimum players required before RTV is enabled", _, true, 0.0, true, float(MAXPLAYERS));
	g_cvRtvInitialDelay = CreateConVar("sm_rtv_initialdelay", "30.0", "Delay (seconds) before first RTV can be held after map start", _, true, 0.0);
	g_cvRtvInterval = CreateConVar("sm_rtv_interval", "240.0", "Cooldown (seconds) after a failed RTV before another can be held", _, true, 0.0);
	g_cvRtvChangeTime = CreateConVar("sm_rtv_changetime", "0", "When to change map after successful RTV: 0=Instant, 1=RoundEnd, 2=MapEnd", _, true, 0.0, true, 2.0);

	// MapChooser ConVars
	g_cvEndOfMapVote = CreateConVar("sm_mapvote_endvote", "1", "Run an end-of-map vote", _, true, 0.0, true, 1.0);
	g_cvStartTime = CreateConVar("sm_mapvote_start", "3.0", "Minutes remaining to start the end-of-map vote", _, true, 1.0);
	g_cvStartRounds = CreateConVar("sm_mapvote_startround", "2.0", "Rounds remaining to start the end-of-map vote", _, true, 0.0);
	g_cvStartFrags = CreateConVar("sm_mapvote_startfrags", "5.0", "Frags remaining to start the end-of-map vote", _, true, 1.0);
	g_cvExtendTimeStep = CreateConVar("sm_extendmap_timestep", "15", "Additional minutes per map extension", _, true, 5.0);
	g_cvExtendRoundStep = CreateConVar("sm_extendmap_roundstep", "5", "Additional rounds per map extension", _, true, 1.0);
	g_cvExtendFragStep = CreateConVar("sm_extendmap_fragstep", "10", "Additional frags per map extension", _, true, 5.0);
	g_cvExcludeMaps = CreateConVar("sm_mapvote_exclude", "5", "Number of past maps to exclude from votes", _, true, 0.0);
	g_cvIncludeMaps = CreateConVar("sm_mapvote_include", "5", "Number of maps to include in the vote", _, true, 2.0, true, 6.0);
	g_cvNoVoteMode = CreateConVar("sm_mapvote_novote", "1", "Pick a random map if no votes are received", _, true, 0.0, true, 1.0);
	g_cvExtend = CreateConVar("sm_mapvote_extend", "0", "Number of map extensions allowed (0 = disabled)", _, true, 0.0);
	g_cvDontChange = CreateConVar("sm_mapvote_dontchange", "1", "Add a 'Don't Change' option to early votes (RTV)", _, true, 0.0, true, 1.0);
	g_cvVoteDuration = CreateConVar("sm_mapvote_voteduration", "20", "Duration of the map vote (seconds)", _, true, 5.0);
	g_cvRunOff = CreateConVar("sm_mapvote_runoff", "0", "Hold a runoff vote if winning choice has less than required margin", _, true, 0.0, true, 1.0);
	g_cvRunOffPercent = CreateConVar("sm_mapvote_runoffpercent", "50", "Minimum vote percentage to avoid a runoff", _, true, 0.0, true, 100.0);

	// Nomination ConVars
	g_cvNomExcludeOld = CreateConVar("sm_nominate_excludeold", "1", "Exclude recently played maps from nominations", _, true, 0.0, true, 1.0);
	g_cvNomExcludeCurrent = CreateConVar("sm_nominate_excludecurrent", "1", "Exclude the current map from nominations", _, true, 0.0, true, 1.0);

	// Admin commands
	RegAdminCmd("sm_mapvote", Command_ForceMapVote, ADMFLAG_CHANGEMAP, "Force a map vote to start now");
	RegAdminCmd("sm_setnextmap", Command_SetNextmap, ADMFLAG_CHANGEMAP, "Set the next map directly");

	// RTV commands
	RegConsoleCmd("sm_rtv", Command_RTV, "Rock the Vote");

	// Nomination commands
	RegConsoleCmd("sm_nominate", Command_Nominate, "Nominate a map for the next vote");
	RegConsoleCmd("sm_nom", Command_Nominate, "Nominate a map for the next vote");

	// Chat triggers
	AddCommandListener(Listener_Say, "say");
	AddCommandListener(Listener_Say, "say_team");

	// Game ConVars
	g_cvWinlimit = FindConVar("mp_winlimit");
	g_cvMaxrounds = FindConVar("mp_maxrounds");
	g_cvFraglimit = FindConVar("mp_fraglimit");
	g_cvBonusRoundTime = FindConVar("mp_bonusroundtime");

	// Hook game events
	if (g_cvWinlimit || g_cvMaxrounds)
	{
		char folder[64];
		GetGameFolderName(folder, sizeof(folder));

		if (strcmp(folder, "tf") == 0)
		{
			HookEvent("teamplay_win_panel", Event_TeamPlayWinPanel);
			HookEvent("teamplay_restart_round", Event_TFRestartRound);
			HookEvent("arena_win_panel", Event_TeamPlayWinPanel);
		}
		else if (strcmp(folder, "nucleardawn") == 0)
		{
			HookEvent("round_win", Event_RoundEnd);
		}
		else
		{
			HookEvent("round_end", Event_RoundEnd);
		}
	}

	if (g_cvFraglimit)
	{
		HookEvent("player_death", Event_PlayerDeath);
	}

	AutoExecConfig(true, "rockthevote");

	if (g_cvBonusRoundTime)
	{
		g_cvBonusRoundTime.SetBounds(ConVarBound_Upper, true, 30.0);
	}
}

/* ===================== MAP / CONFIG HOOKS ===================== */

public void OnConfigsExecuted()
{
	if (ReadMapList(g_MapList, g_mapFileSerial, "default", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER) != null)
	{
		if (g_mapFileSerial == -1)
		{
			LogError("Unable to create a valid map list.");
		}
	}

	BuildNominateMenu();
	CreateNextVote();
	SetupTimeleftTimer();

	g_TotalRounds = 0;
	g_Extends = 0;
	g_MapVoteCompleted = false;
	g_HasVoteStarted = false;

	g_NominateList.Clear();
	g_NominateOwners.Clear();

	for (int i = 0; i < MAXTEAMS; i++)
	{
		g_winCount[i] = 0;
	}

	// Reset RTV state
	g_RTVVotes = 0;
	g_RTVVoters = 0;
	g_RTVAllowed = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_RTVVoted[i] = false;
	}

	// Count current voters
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			g_RTVVoters++;
		}
	}
	RecalculateRTVNeeded();

	// Initial delay timer for RTV
	CreateTimer(g_cvRtvInitialDelay.FloatValue, Timer_RTVAllow, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
	g_HasVoteStarted = false;
	g_WaitingForVote = false;
	g_ChangeMapAtRoundEnd = false;
	g_ChangeMapInProgress = false;
	g_VoteTimer = null;
	g_RetryTimer = null;
	g_RTVAllowed = false;

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	RemoveStringFromArray(g_OldMapList, map);
	g_OldMapList.PushString(map);

	while (g_OldMapList.Length > g_cvExcludeMaps.IntValue)
	{
		g_OldMapList.Erase(0);
	}
}

public void OnMapTimeLeftChanged()
{
	if (g_MapList.Length)
	{
		SetupTimeleftTimer();
	}
}

/* ===================== CLIENT HOOKS ===================== */

public void OnClientConnected(int client)
{
	if (IsFakeClient(client))
		return;

	g_RTVVoted[client] = false;
	g_RTVVoters++;
	RecalculateRTVNeeded();
}

public void OnClientDisconnect(int client)
{
	if (IsFakeClient(client))
		return;

	if (g_RTVVoted[client])
	{
		g_RTVVotes--;
		g_RTVVoted[client] = false;
	}
	g_RTVVoters--;
	RecalculateRTVNeeded();

	// Remove nomination
	int index = g_NominateOwners.FindValue(client);
	if (index != -1)
	{
		g_NominateList.Erase(index);
		g_NominateOwners.Erase(index);
	}
}

/* ===================== CHAT LISTENER ===================== */

public Action Listener_Say(int client, const char[] command, int argc)
{
	if (!client || !IsClientInGame(client))
		return Plugin_Continue;

	char text[64];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	TrimString(text);

	if (strcmp(text, "rtv", false) == 0 ||
		strcmp(text, "!rtv", false) == 0 ||
		strcmp(text, "rockthevote", false) == 0 ||
		strcmp(text, "!rockthevote", false) == 0)
	{
		AttemptRTV(client);
		return Plugin_Continue;
	}

	if (strcmp(text, "nominate", false) == 0 ||
		strcmp(text, "!nominate", false) == 0 ||
		strcmp(text, "nom", false) == 0 ||
		strcmp(text, "!nom", false) == 0)
	{
		OpenNominateMenu(client);
		return Plugin_Continue;
	}

	// Check for "!nominate <mapname>" or "nominate <mapname>"
	if (strncmp(text, "!nominate ", 10, false) == 0 ||
		strncmp(text, "nominate ", 9, false) == 0 ||
		strncmp(text, "!nom ", 5, false) == 0 ||
		strncmp(text, "nom ", 4, false) == 0)
	{
		char mapname[PLATFORM_MAX_PATH];
		int offset = 0;
		if (strncmp(text, "!nominate ", 10, false) == 0) offset = 10;
		else if (strncmp(text, "nominate ", 9, false) == 0) offset = 9;
		else if (strncmp(text, "!nom ", 5, false) == 0) offset = 5;
		else if (strncmp(text, "nom ", 4, false) == 0) offset = 4;

		strcopy(mapname, sizeof(mapname), text[offset]);
		TrimString(mapname);

		if (strlen(mapname) > 0)
		{
			AttemptNominateByName(client, mapname);
		}
		return Plugin_Continue;
	}

	return Plugin_Continue;
}

/* ===================== RTV LOGIC ===================== */

public Action Command_RTV(int client, int args)
{
	if (!client || !IsClientInGame(client))
		return Plugin_Handled;

	AttemptRTV(client);
	return Plugin_Handled;
}

void AttemptRTV(int client)
{
	if (!g_RTVAllowed)
	{
		PrintToChat(client, "[SM] %t", "RTV Not Allowed");
		return;
	}

	if (g_MapVoteCompleted)
	{
		PrintToChat(client, "[SM] %t", "RTV Ended");
		return;
	}

	if (g_HasVoteStarted)
	{
		PrintToChat(client, "[SM] %t", "RTV Started");
		return;
	}

	if (GetClientCount(true) < g_cvRtvMinPlayers.IntValue)
	{
		PrintToChat(client, "[SM] %t", "Minimal Players Not Met");
		return;
	}

	if (g_RTVVoted[client])
	{
		PrintToChat(client, "[SM] %t", "Already Voted", g_RTVVotes, g_RTVVotesNeeded);
		return;
	}

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));

	g_RTVVotes++;
	g_RTVVoted[client] = true;

	PrintToChatAll("[SM] %t", "RTV Requested", name, g_RTVVotes, g_RTVVotesNeeded);

	if (g_RTVVotes >= g_RTVVotesNeeded)
	{
		StartRTVVote();
	}
}

void StartRTVVote()
{
	PrintToChatAll("[SM] %t", "RTV Vote Ready");

	MapChange when;
	switch (g_cvRtvChangeTime.IntValue)
	{
		case 0: when = MapChange_Instant;
		case 1: when = MapChange_RoundEnd;
		case 2: when = MapChange_MapEnd;
		default: when = MapChange_Instant;
	}

	InitiateVote(when);
}

void RecalculateRTVNeeded()
{
	g_RTVVotesNeeded = RoundToCeil(float(g_RTVVoters) * g_cvRtvNeeded.FloatValue);

	if (g_RTVVotesNeeded < 1)
		g_RTVVotesNeeded = 1;
}

public Action Timer_RTVAllow(Handle timer)
{
	g_RTVAllowed = true;
	return Plugin_Stop;
}

/* ===================== NOMINATION LOGIC ===================== */

public Action Command_Nominate(int client, int args)
{
	if (!client || !IsClientInGame(client))
		return Plugin_Handled;

	if (args > 0)
	{
		char mapname[PLATFORM_MAX_PATH];
		GetCmdArgString(mapname, sizeof(mapname));
		TrimString(mapname);
		AttemptNominateByName(client, mapname);
	}
	else
	{
		OpenNominateMenu(client);
	}

	return Plugin_Handled;
}

void OpenNominateMenu(int client)
{
	if (g_MapVoteCompleted)
	{
		PrintToChat(client, "[SM] %t", "RTV Ended");
		return;
	}

	if (g_NominateMenu == null)
	{
		PrintToChat(client, "[SM] No maps available for nomination.");
		return;
	}

	g_NominateMenu.Display(client, MENU_TIME_FOREVER);
}

void AttemptNominateByName(int client, const char[] mapname)
{
	if (g_MapVoteCompleted)
	{
		PrintToChat(client, "[SM] %t", "RTV Ended");
		return;
	}

	// Find matching maps
	char resolvedMap[PLATFORM_MAX_PATH];
	ArrayList matches = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	for (int i = 0; i < g_MapList.Length; i++)
	{
		char entry[PLATFORM_MAX_PATH];
		g_MapList.GetString(i, entry, sizeof(entry));

		if (StrContains(entry, mapname, false) != -1)
		{
			matches.PushString(entry);
		}
	}

	if (matches.Length == 0)
	{
		PrintToChat(client, "[SM] No maps found matching \"%s\".", mapname);
		delete matches;
		return;
	}

	if (matches.Length == 1)
	{
		matches.GetString(0, resolvedMap, sizeof(resolvedMap));
		delete matches;
		NominateMap(client, resolvedMap);
		return;
	}

	// Check for exact match first
	for (int i = 0; i < matches.Length; i++)
	{
		char entry[PLATFORM_MAX_PATH];
		matches.GetString(i, entry, sizeof(entry));
		if (strcmp(entry, mapname, false) == 0)
		{
			delete matches;
			NominateMap(client, entry);
			return;
		}
	}

	// Multiple matches - show a menu
	Menu menu = new Menu(MenuHandler_NominateSearch);
	menu.SetTitle("Multiple maps found:");

	int count = matches.Length;
	if (count > 10) count = 10;

	for (int i = 0; i < count; i++)
	{
		char entry[PLATFORM_MAX_PATH];
		matches.GetString(i, entry, sizeof(entry));
		char displayName[PLATFORM_MAX_PATH];
		GetMapDisplayName(entry, displayName, sizeof(displayName));
		menu.AddItem(entry, displayName);
	}

	if (matches.Length > 10)
	{
		PrintToChat(client, "[SM] Found %d maps, showing first 10. Be more specific.", matches.Length);
	}

	menu.Display(client, MENU_TIME_FOREVER);
	delete matches;
}

public int MenuHandler_NominateSearch(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char map[PLATFORM_MAX_PATH];
		menu.GetItem(param2, map, sizeof(map));
		NominateMap(param1, map);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void NominateMap(int client, const char[] map)
{
	char resolvedMap[PLATFORM_MAX_PATH];
	strcopy(resolvedMap, sizeof(resolvedMap), map);

	if (FindMap(resolvedMap, resolvedMap, sizeof(resolvedMap)) == FindMap_NotFound)
	{
		PrintToChat(client, "[SM] Map \"%s\" was not found.", map);
		return;
	}

	// Check if already nominated
	if (g_NominateList.FindString(resolvedMap) != -1)
	{
		PrintToChat(client, "[SM] Map \"%s\" is already nominated.", map);
		return;
	}

	// Check current map
	if (g_cvNomExcludeCurrent.BoolValue)
	{
		char currentMap[PLATFORM_MAX_PATH];
		GetCurrentMap(currentMap, sizeof(currentMap));
		if (strcmp(resolvedMap, currentMap, false) == 0)
		{
			PrintToChat(client, "[SM] You cannot nominate the current map.");
			return;
		}
	}

	// Check recently played
	if (g_cvNomExcludeOld.BoolValue)
	{
		char oldMap[PLATFORM_MAX_PATH];
		for (int i = 0; i < g_OldMapList.Length; i++)
		{
			g_OldMapList.GetString(i, oldMap, sizeof(oldMap));
			if (strcmp(resolvedMap, oldMap, false) == 0)
			{
				PrintToChat(client, "[SM] Map \"%s\" was recently played.", map);
				return;
			}
		}
	}

	// Replace existing nomination by this client
	int ownerIndex = g_NominateOwners.FindValue(client);
	if (ownerIndex != -1)
	{
		g_NominateList.Erase(ownerIndex);
		g_NominateOwners.Erase(ownerIndex);
	}

	// Check if nomination list is full
	if (g_NominateList.Length >= g_cvIncludeMaps.IntValue)
	{
		PrintToChat(client, "[SM] The nomination list is full.");
		return;
	}

	g_NominateList.PushString(resolvedMap);
	g_NominateOwners.Push(client);

	char displayName[PLATFORM_MAX_PATH];
	GetMapDisplayName(resolvedMap, displayName, sizeof(displayName));

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));

	PrintToChatAll("[SM] %s nominated %s.", name, displayName);

	// Rebuild nomination menu to reflect new status
	BuildNominateMenu();
}

void BuildNominateMenu()
{
	delete g_NominateMenu;
	g_NominateMapStatus.Clear();

	g_NominateMenu = new Menu(MenuHandler_Nominate, MENU_ACTIONS_ALL);
	g_NominateMenu.SetTitle("Nominate a Map");

	char map[PLATFORM_MAX_PATH];
	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	for (int i = 0; i < g_MapList.Length; i++)
	{
		g_MapList.GetString(i, map, sizeof(map));

		char resolvedMap[PLATFORM_MAX_PATH];
		strcopy(resolvedMap, sizeof(resolvedMap), map);
		if (FindMap(resolvedMap, resolvedMap, sizeof(resolvedMap)) == FindMap_NotFound)
			continue;

		int status = MAPSTATUS_ENABLED;

		if (g_cvNomExcludeCurrent.BoolValue && strcmp(resolvedMap, currentMap, false) == 0)
		{
			status |= MAPSTATUS_DISABLED | MAPSTATUS_EXCLUDE_CUR;
		}

		if (g_cvNomExcludeOld.BoolValue)
		{
			char oldMap[PLATFORM_MAX_PATH];
			for (int j = 0; j < g_OldMapList.Length; j++)
			{
				g_OldMapList.GetString(j, oldMap, sizeof(oldMap));
				if (strcmp(resolvedMap, oldMap, false) == 0)
				{
					status |= MAPSTATUS_DISABLED | MAPSTATUS_EXCLUDE_OLD;
					break;
				}
			}
		}

		if (g_NominateList.FindString(resolvedMap) != -1)
		{
			status |= MAPSTATUS_DISABLED | MAPSTATUS_EXCLUDE_NOM;
		}

		char displayName[PLATFORM_MAX_PATH];
		GetMapDisplayName(resolvedMap, displayName, sizeof(displayName));

		g_NominateMenu.AddItem(resolvedMap, displayName);
		g_NominateMapStatus.SetValue(resolvedMap, status);
	}

	g_NominateMenu.ExitButton = true;
}

public int MenuHandler_Nominate(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map));
			NominateMap(param1, map);
		}

		case MenuAction_DrawItem:
		{
			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map));

			int status;
			if (g_NominateMapStatus.GetValue(map, status))
			{
				if (status & MAPSTATUS_DISABLED)
				{
					return ITEMDRAW_DISABLED;
				}
			}

			return ITEMDRAW_DEFAULT;
		}

		case MenuAction_DisplayItem:
		{
			char map[PLATFORM_MAX_PATH];
			char displayName[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map), _, displayName, sizeof(displayName));

			int status;
			if (g_NominateMapStatus.GetValue(map, status))
			{
				if (status & MAPSTATUS_EXCLUDE_CUR)
				{
					char buffer[PLATFORM_MAX_PATH + 32];
					Format(buffer, sizeof(buffer), "%s (Current)", displayName);
					return RedrawMenuItem(buffer);
				}
				else if (status & MAPSTATUS_EXCLUDE_OLD)
				{
					char buffer[PLATFORM_MAX_PATH + 32];
					Format(buffer, sizeof(buffer), "%s (Recently Played)", displayName);
					return RedrawMenuItem(buffer);
				}
				else if (status & MAPSTATUS_EXCLUDE_NOM)
				{
					char buffer[PLATFORM_MAX_PATH + 32];
					Format(buffer, sizeof(buffer), "%s (Nominated)", displayName);
					return RedrawMenuItem(buffer);
				}
			}

			return 0;
		}
	}

	return 0;
}

/* ===================== MAP CHOOSER LOGIC ===================== */

void SetupTimeleftTimer()
{
	int time;
	if (GetMapTimeLeft(time) && time > 0)
	{
		int startTime = g_cvStartTime.IntValue * 60;
		if (time - startTime < 0 && g_cvEndOfMapVote.BoolValue && !g_MapVoteCompleted && !g_HasVoteStarted)
		{
			InitiateVote(MapChange_MapEnd);
		}
		else
		{
			if (g_VoteTimer != null)
			{
				KillTimer(g_VoteTimer);
				g_VoteTimer = null;
			}

			DataPack data;
			g_VoteTimer = CreateDataTimer(float(time - startTime), Timer_StartMapVote, data, TIMER_FLAG_NO_MAPCHANGE);
			data.WriteCell(view_as<int>(MapChange_MapEnd));
			data.Reset();
		}
	}
}

public Action Timer_StartMapVote(Handle timer, DataPack data)
{
	if (timer == g_RetryTimer)
	{
		g_WaitingForVote = false;
		g_RetryTimer = null;
	}
	else
	{
		g_VoteTimer = null;
	}

	if (!g_MapList.Length || !g_cvEndOfMapVote.BoolValue || g_MapVoteCompleted || g_HasVoteStarted)
	{
		return Plugin_Stop;
	}

	MapChange when = view_as<MapChange>(data.ReadCell());
	InitiateVote(when);

	return Plugin_Stop;
}

void InitiateVote(MapChange when)
{
	g_WaitingForVote = true;

	if (IsVoteInProgress())
	{
		DataPack data;
		g_RetryTimer = CreateDataTimer(5.0, Timer_StartMapVote, data, TIMER_FLAG_NO_MAPCHANGE);
		data.WriteCell(view_as<int>(when));
		data.Reset();
		return;
	}

	if (g_MapVoteCompleted && g_ChangeMapInProgress)
	{
		return;
	}

	g_ChangeTime = when;
	g_WaitingForVote = false;
	g_HasVoteStarted = true;

	g_VoteMenu = new Menu(Handler_MapVoteMenu, MENU_ACTIONS_ALL);
	g_VoteMenu.SetTitle("Vote Nextmap");
	g_VoteMenu.VoteResultCallback = Handler_MapVoteFinished;

	char map[PLATFORM_MAX_PATH];
	int nominateCount = g_NominateList.Length;
	int voteSize = g_cvIncludeMaps.IntValue;
	int nominationsToAdd = nominateCount >= voteSize ? voteSize : nominateCount;

	// Add nominated maps first
	for (int i = 0; i < nominationsToAdd; i++)
	{
		char displayName[PLATFORM_MAX_PATH];
		g_NominateList.GetString(i, map, sizeof(map));
		GetMapDisplayName(map, displayName, sizeof(displayName));
		g_VoteMenu.AddItem(map, displayName);
		RemoveStringFromArray(g_NextMapList, map);
	}

	// Clear nominations
	g_NominateOwners.Clear();
	g_NominateList.Clear();

	// Fill remaining slots with random maps
	int added = nominationsToAdd;
	int count = 0;
	int availableMaps = g_NextMapList.Length;

	while (added < voteSize)
	{
		if (count >= availableMaps)
			break;

		g_NextMapList.GetString(count, map, sizeof(map));
		count++;

		char displayName[PLATFORM_MAX_PATH];
		GetMapDisplayName(map, displayName, sizeof(displayName));
		g_VoteMenu.AddItem(map, displayName);
		added++;
	}

	// Add special options
	if ((when == MapChange_Instant || when == MapChange_RoundEnd) && g_cvDontChange.BoolValue)
	{
		g_VoteMenu.AddItem(VOTE_DONTCHANGE, "Don't Change");
	}
	else if (g_cvExtend.BoolValue && g_Extends < g_cvExtend.IntValue)
	{
		g_VoteMenu.AddItem(VOTE_EXTEND, "Extend Map");
	}

	if (g_VoteMenu.ItemCount == 0)
	{
		g_HasVoteStarted = false;
		delete g_VoteMenu;
		return;
	}

	int voteDuration = g_cvVoteDuration.IntValue;
	g_VoteMenu.ExitButton = false;
	g_VoteMenu.DisplayVoteToAll(voteDuration);

	LogAction(-1, -1, "Voting for next map has started.");
	PrintToChatAll("[SM] Voting for next map has started.");

	// Rebuild nomination menu
	BuildNominateMenu();
}

public int Handler_MapVoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			g_VoteMenu = null;
			delete menu;
		}

		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Vote for the next map!");
			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(buffer);
		}

		case MenuAction_DisplayItem:
		{
			if (menu.ItemCount - 1 == param2)
			{
				char map[PLATFORM_MAX_PATH], buffer[255];
				menu.GetItem(param2, map, sizeof(map));
				if (strcmp(map, VOTE_EXTEND, false) == 0)
				{
					Format(buffer, sizeof(buffer), "Extend Current Map");
					return RedrawMenuItem(buffer);
				}
				else if (strcmp(map, VOTE_DONTCHANGE, false) == 0)
				{
					Format(buffer, sizeof(buffer), "Don't Change");
					return RedrawMenuItem(buffer);
				}
			}
		}

		case MenuAction_VoteCancel:
		{
			if (param1 == VoteCancel_NoVotes && g_cvNoVoteMode.BoolValue)
			{
				int count = menu.ItemCount;
				char map[PLATFORM_MAX_PATH];
				menu.GetItem(0, map, sizeof(map));

				if (strcmp(map, VOTE_EXTEND, false) != 0 && strcmp(map, VOTE_DONTCHANGE, false) != 0)
				{
					int item = GetRandomInt(0, count - 1);
					menu.GetItem(item, map, sizeof(map));

					while (strcmp(map, VOTE_EXTEND, false) == 0 || strcmp(map, VOTE_DONTCHANGE, false) == 0)
					{
						item = GetRandomInt(0, count - 1);
						menu.GetItem(item, map, sizeof(map));
					}

					SetNextMap(map);
					g_MapVoteCompleted = true;

					char displayName[PLATFORM_MAX_PATH];
					GetMapDisplayName(map, displayName, sizeof(displayName));
					PrintToChatAll("[SM] %t", "No Votes");
				}
			}

			g_HasVoteStarted = false;
		}
	}

	return 0;
}

public void Handler_MapVoteFinished(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (g_cvRunOff.BoolValue && num_items > 1)
	{
		float winningvotes = float(item_info[0][VOTEINFO_ITEM_VOTES]);
		float required = num_votes * (g_cvRunOffPercent.FloatValue / 100.0);

		if (winningvotes < required)
		{
			// Runoff vote
			g_VoteMenu = new Menu(Handler_MapVoteMenu, MENU_ACTIONS_ALL);
			g_VoteMenu.SetTitle("Runoff Vote Nextmap");
			g_VoteMenu.VoteResultCallback = Handler_VoteFinishedGeneric;

			char map[PLATFORM_MAX_PATH];
			char info1[PLATFORM_MAX_PATH];
			char info2[PLATFORM_MAX_PATH];

			menu.GetItem(item_info[0][VOTEINFO_ITEM_INDEX], map, sizeof(map), _, info1, sizeof(info1));
			g_VoteMenu.AddItem(map, info1);
			menu.GetItem(item_info[1][VOTEINFO_ITEM_INDEX], map, sizeof(map), _, info2, sizeof(info2));
			g_VoteMenu.AddItem(map, info2);

			int voteDuration = g_cvVoteDuration.IntValue;
			g_VoteMenu.ExitButton = false;
			g_VoteMenu.DisplayVoteToAll(voteDuration);

			float map1percent = float(item_info[0][VOTEINFO_ITEM_VOTES]) / float(num_votes) * 100.0;
			float map2percent = float(item_info[1][VOTEINFO_ITEM_VOTES]) / float(num_votes) * 100.0;

			PrintToChatAll("[SM] No map got over %.0f%% votes (%s [%.0f%%] & %s [%.0f%%]), starting runoff vote.",
				g_cvRunOffPercent.FloatValue, info1, map1percent, info2, map2percent);
			LogMessage("Voting for next map was indecisive, beginning runoff vote");

			return;
		}
	}

	Handler_VoteFinishedGeneric(menu, num_votes, num_clients, client_info, num_items, item_info);
}

public void Handler_VoteFinishedGeneric(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];
	menu.GetItem(item_info[0][VOTEINFO_ITEM_INDEX], map, sizeof(map), _, displayName, sizeof(displayName));

	if (strcmp(map, VOTE_EXTEND, false) == 0)
	{
		g_Extends++;

		int time;
		if (GetMapTimeLimit(time))
		{
			if (time > 0)
			{
				ExtendMapTimeLimit(g_cvExtendTimeStep.IntValue * 60);
			}
		}

		if (g_cvWinlimit)
		{
			int winlimit = g_cvWinlimit.IntValue;
			if (winlimit)
			{
				g_cvWinlimit.IntValue = winlimit + g_cvExtendRoundStep.IntValue;
			}
		}

		if (g_cvMaxrounds)
		{
			int maxrounds = g_cvMaxrounds.IntValue;
			if (maxrounds)
			{
				g_cvMaxrounds.IntValue = maxrounds + g_cvExtendRoundStep.IntValue;
			}
		}

		if (g_cvFraglimit)
		{
			int fraglimit = g_cvFraglimit.IntValue;
			if (fraglimit)
			{
				g_cvFraglimit.IntValue = fraglimit + g_cvExtendFragStep.IntValue;
			}
		}

		int percent = RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES]) / float(num_votes) * 100.0);
		PrintToChatAll("[SM] The current map has been extended. (Received %d%% of %d votes)", percent, num_votes);
		LogAction(-1, -1, "Voting for next map has finished. The current map has been extended.");

		g_HasVoteStarted = false;
		CreateNextVote();
		SetupTimeleftTimer();
	}
	else if (strcmp(map, VOTE_DONTCHANGE, false) == 0)
	{
		int percent = RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES]) / float(num_votes) * 100.0);
		PrintToChatAll("[SM] %t", "Current Map Stays");
		LogAction(-1, -1, "Voting for next map has finished. 'No Change' was the winner");

		g_HasVoteStarted = false;
		CreateNextVote();
		SetupTimeleftTimer();
	}
	else
	{
		if (g_ChangeTime == MapChange_MapEnd)
		{
			SetNextMap(map);
		}
		else if (g_ChangeTime == MapChange_Instant)
		{
			DataPack dp;
			CreateDataTimer(2.0, Timer_ChangeMap, dp);
			dp.WriteString(map);
			g_ChangeMapInProgress = false;
		}
		else // MapChange_RoundEnd
		{
			SetNextMap(map);
			g_ChangeMapAtRoundEnd = true;
		}

		g_HasVoteStarted = false;
		g_MapVoteCompleted = true;

		int percent = RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES]) / float(num_votes) * 100.0);
		PrintToChatAll("[SM] %t", "Changing Maps", displayName);
		LogAction(-1, -1, "Voting for next map has finished. Nextmap: %s.", map);
	}
}

/* ===================== ADMIN COMMANDS ===================== */

public Action Command_ForceMapVote(int client, int args)
{
	InitiateVote(MapChange_MapEnd);
	return Plugin_Handled;
}

public Action Command_SetNextmap(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setnextmap <map>");
		return Plugin_Handled;
	}

	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];
	GetCmdArg(1, map, sizeof(map));

	if (FindMap(map, displayName, sizeof(displayName)) == FindMap_NotFound)
	{
		ReplyToCommand(client, "[SM] Map \"%s\" was not found.", map);
		return Plugin_Handled;
	}

	GetMapDisplayName(displayName, displayName, sizeof(displayName));

	ShowActivity2(client, "[SM] ", "Changed nextmap to \"%s\".", displayName);
	LogAction(client, -1, "\"%L\" changed nextmap to \"%s\"", client, map);

	SetNextMap(map);
	g_MapVoteCompleted = true;

	return Plugin_Handled;
}

/* ===================== GAME EVENTS ===================== */

public void Event_TFRestartRound(Event event, const char[] name, bool dontBroadcast)
{
	g_TotalRounds = 0;
}

public void Event_TeamPlayWinPanel(Event event, const char[] name, bool dontBroadcast)
{
	if (g_ChangeMapAtRoundEnd)
	{
		g_ChangeMapAtRoundEnd = false;
		CreateTimer(2.0, Timer_ChangeMap, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE);
		g_ChangeMapInProgress = true;
	}

	int bluescore = event.GetInt("blue_score");
	int redscore = event.GetInt("red_score");

	if (event.GetInt("round_complete") == 1 || StrEqual(name, "arena_win_panel"))
	{
		g_TotalRounds++;

		if (!g_MapList.Length || g_HasVoteStarted || g_MapVoteCompleted || !g_cvEndOfMapVote.BoolValue)
			return;

		CheckMaxRounds(g_TotalRounds);

		switch (event.GetInt("winning_team"))
		{
			case 3: CheckWinLimit(bluescore);
			case 2: CheckWinLimit(redscore);
		}
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_ChangeMapAtRoundEnd)
	{
		g_ChangeMapAtRoundEnd = false;
		CreateTimer(2.0, Timer_ChangeMap, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE);
		g_ChangeMapInProgress = true;
	}

	int winner;
	if (strcmp(name, "round_win") == 0)
		winner = event.GetInt("team");
	else
		winner = event.GetInt("winner");

	if (winner == 0 || winner == 1 || !g_cvEndOfMapVote.BoolValue)
		return;

	if (winner >= MAXTEAMS)
	{
		SetFailState("Mod exceeds maximum team count.");
	}

	g_TotalRounds++;
	g_winCount[winner]++;

	if (!g_MapList.Length || g_HasVoteStarted || g_MapVoteCompleted)
		return;

	CheckWinLimit(g_winCount[winner]);
	CheckMaxRounds(g_TotalRounds);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_MapList.Length || !g_cvFraglimit || g_HasVoteStarted || g_MapVoteCompleted)
		return;

	if (!g_cvFraglimit.IntValue || !g_cvEndOfMapVote.BoolValue)
		return;

	int fragger = GetClientOfUserId(event.GetInt("attacker"));
	if (!fragger)
		return;

	if (GetClientFrags(fragger) >= (g_cvFraglimit.IntValue - g_cvStartFrags.IntValue))
	{
		InitiateVote(MapChange_MapEnd);
	}
}

void CheckWinLimit(int winner_score)
{
	if (g_cvWinlimit)
	{
		int winlimit = g_cvWinlimit.IntValue;
		if (winlimit)
		{
			if (winner_score >= (winlimit - g_cvStartRounds.IntValue))
			{
				InitiateVote(MapChange_MapEnd);
			}
		}
	}
}

void CheckMaxRounds(int roundcount)
{
	if (g_cvMaxrounds)
	{
		int maxrounds = g_cvMaxrounds.IntValue;
		if (maxrounds)
		{
			if (roundcount >= (maxrounds - g_cvStartRounds.IntValue))
			{
				InitiateVote(MapChange_MapEnd);
			}
		}
	}
}

/* ===================== MAP CHANGE TIMER ===================== */

public Action Timer_ChangeMap(Handle hTimer, DataPack dp)
{
	g_ChangeMapInProgress = false;

	char map[PLATFORM_MAX_PATH];

	if (dp == null || dp == view_as<DataPack>(INVALID_HANDLE))
	{
		if (!GetNextMap(map, sizeof(map)))
		{
			return Plugin_Stop;
		}
	}
	else
	{
		dp.Reset();
		dp.ReadString(map, sizeof(map));
	}

	ForceChangeLevel(map, "Map Vote");

	return Plugin_Stop;
}

/* ===================== HELPERS ===================== */

bool RemoveStringFromArray(ArrayList array, const char[] str)
{
	int index = array.FindString(str);
	if (index != -1)
	{
		array.Erase(index);
		return true;
	}
	return false;
}

void CreateNextVote()
{
	g_NextMapList.Clear();

	char map[PLATFORM_MAX_PATH];
	ArrayList tempMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	for (int i = 0; i < g_MapList.Length; i++)
	{
		g_MapList.GetString(i, map, sizeof(map));
		if (FindMap(map, map, sizeof(map)) != FindMap_NotFound)
		{
			tempMaps.PushString(map);
		}
	}

	// Remove current map
	GetCurrentMap(map, sizeof(map));
	RemoveStringFromArray(tempMaps, map);

	// Remove recently played maps
	if (g_cvExcludeMaps.IntValue && tempMaps.Length > g_cvExcludeMaps.IntValue)
	{
		for (int i = 0; i < g_OldMapList.Length; i++)
		{
			g_OldMapList.GetString(i, map, sizeof(map));
			RemoveStringFromArray(tempMaps, map);
		}
	}

	// Pick random maps for the vote pool
	int limit = (g_cvIncludeMaps.IntValue < tempMaps.Length ? g_cvIncludeMaps.IntValue : tempMaps.Length);
	for (int i = 0; i < limit; i++)
	{
		int b = GetRandomInt(0, tempMaps.Length - 1);
		tempMaps.GetString(b, map, sizeof(map));
		g_NextMapList.PushString(map);
		tempMaps.Erase(b);
	}

	delete tempMaps;
}

