/**
 * =============================================================================
 * Next Map Vote Plugin for CS2
 * Triggers a map vote when any team reaches 14 round wins.
 * The map only changes at the end of the match.
 *
 * Features:
 *   - Automatic vote when a team hits 14 round wins
 *   - Map nominations via chat (!nominate / !nom)
 *   - Map exclusion (recently played maps)
 *   - Runoff votes when margin is too close
 *   - Admin commands: sm_mapvote, sm_setnextmap
 *
 * Commands:
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

#define PLUGIN_VERSION "2.0.0"

/* ===================== CONSTANTS ===================== */

#define VOTE_DONTCHANGE "##dontchange##"
#define MAXTEAMS        10
#define WIN_TRIGGER     14

/* ===================== PLUGIN INFO ===================== */

public Plugin myinfo =
{
	name        = "Next Map Vote (Round 14)",
	author      = "AlliedModders LLC, Modified",
	description = "Starts a map vote when any team reaches 14 round wins. Changes map at match end.",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/SubCoderHUN/smext-fakequeries"
};

/* ===================== CVARS ===================== */

ConVar g_cvExcludeMaps;
ConVar g_cvIncludeMaps;
ConVar g_cvNoVoteMode;
ConVar g_cvVoteDuration;
ConVar g_cvRunOff;
ConVar g_cvRunOffPercent;
ConVar g_cvWinTrigger;

// Nomination ConVars
ConVar g_cvNomExcludeOld;
ConVar g_cvNomExcludeCurrent;

/* ===================== MAP DATA ===================== */

ArrayList g_MapList;
ArrayList g_NominateList;
ArrayList g_NominateOwners;
ArrayList g_OldMapList;
ArrayList g_NextMapList;

int g_mapFileSerial = -1;

/* ===================== VOTE STATE ===================== */

Menu g_VoteMenu;
Handle g_RetryTimer;

bool g_HasVoteStarted;
bool g_WaitingForVote;
bool g_MapVoteCompleted;

int g_winCount[MAXTEAMS];

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

	// ConVars
	g_cvWinTrigger = CreateConVar("sm_mapvote_wintrigger", "14", "Number of round wins to trigger map vote", _, true, 1.0);
	g_cvExcludeMaps = CreateConVar("sm_mapvote_exclude", "5", "Number of past maps to exclude from votes", _, true, 0.0);
	g_cvIncludeMaps = CreateConVar("sm_mapvote_include", "5", "Number of maps to include in the vote", _, true, 2.0, true, 6.0);
	g_cvNoVoteMode = CreateConVar("sm_mapvote_novote", "1", "Pick a random map if no votes are received", _, true, 0.0, true, 1.0);
	g_cvVoteDuration = CreateConVar("sm_mapvote_voteduration", "20", "Duration of the map vote (seconds)", _, true, 5.0);
	g_cvRunOff = CreateConVar("sm_mapvote_runoff", "0", "Hold a runoff vote if winning choice has less than required margin", _, true, 0.0, true, 1.0);
	g_cvRunOffPercent = CreateConVar("sm_mapvote_runoffpercent", "50", "Minimum vote percentage to avoid a runoff", _, true, 0.0, true, 100.0);

	// Nomination ConVars
	g_cvNomExcludeOld = CreateConVar("sm_nominate_excludeold", "1", "Exclude recently played maps from nominations", _, true, 0.0, true, 1.0);
	g_cvNomExcludeCurrent = CreateConVar("sm_nominate_excludecurrent", "1", "Exclude the current map from nominations", _, true, 0.0, true, 1.0);

	// Admin commands
	RegAdminCmd("sm_mapvote", Command_ForceMapVote, ADMFLAG_CHANGEMAP, "Force a map vote to start now");
	RegAdminCmd("sm_setnextmap", Command_SetNextmap, ADMFLAG_CHANGEMAP, "Set the next map directly");

	// Nomination commands
	RegConsoleCmd("sm_nominate", Command_Nominate, "Nominate a map for the next vote");
	RegConsoleCmd("sm_nom", Command_Nominate, "Nominate a map for the next vote");

	// Chat triggers
	AddCommandListener(Listener_Say, "say");
	AddCommandListener(Listener_Say, "say_team");

	// Hook round end event for CS2
	HookEvent("round_end", Event_RoundEnd);

	AutoExecConfig(true, "nextmapvote");
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

	g_MapVoteCompleted = false;
	g_HasVoteStarted = false;

	g_NominateList.Clear();
	g_NominateOwners.Clear();

	for (int i = 0; i < MAXTEAMS; i++)
	{
		g_winCount[i] = 0;
	}
}

public void OnMapEnd()
{
	g_HasVoteStarted = false;
	g_WaitingForVote = false;
	g_RetryTimer = null;

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	RemoveStringFromArray(g_OldMapList, map);
	g_OldMapList.PushString(map);

	while (g_OldMapList.Length > g_cvExcludeMaps.IntValue)
	{
		g_OldMapList.Erase(0);
	}
}

/* ===================== CLIENT HOOKS ===================== */

public void OnClientDisconnect(int client)
{
	if (IsFakeClient(client))
		return;

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

/* ===================== MAP VOTE LOGIC ===================== */

void InitiateVote()
{
	g_WaitingForVote = true;

	if (IsVoteInProgress())
	{
		g_RetryTimer = CreateTimer(5.0, Timer_RetryVote, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	if (g_MapVoteCompleted)
	{
		return;
	}

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

	if (g_VoteMenu.ItemCount == 0)
	{
		g_HasVoteStarted = false;
		delete g_VoteMenu;
		return;
	}

	int voteDuration = g_cvVoteDuration.IntValue;
	g_VoteMenu.ExitButton = false;
	g_VoteMenu.DisplayVoteToAll(voteDuration);

	LogAction(-1, -1, "Voting for next map has started (a team reached %d wins).", g_cvWinTrigger.IntValue);
	PrintToChatAll("[SM] A team reached %d round wins! Voting for next map has started.", g_cvWinTrigger.IntValue);

	// Rebuild nomination menu
	BuildNominateMenu();
}

public Action Timer_RetryVote(Handle timer)
{
	g_RetryTimer = null;

	if (!g_MapList.Length || g_MapVoteCompleted || g_HasVoteStarted)
	{
		return Plugin_Stop;
	}

	InitiateVote();
	return Plugin_Stop;
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
				if (strcmp(map, VOTE_DONTCHANGE, false) == 0)
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

				if (strcmp(map, VOTE_DONTCHANGE, false) != 0)
				{
					int item = GetRandomInt(0, count - 1);
					menu.GetItem(item, map, sizeof(map));

					while (strcmp(map, VOTE_DONTCHANGE, false) == 0)
					{
						item = GetRandomInt(0, count - 1);
						menu.GetItem(item, map, sizeof(map));
					}

					SetNextMap(map);
					g_MapVoteCompleted = true;

					char displayName[PLATFORM_MAX_PATH];
					GetMapDisplayName(map, displayName, sizeof(displayName));
					PrintToChatAll("[SM] %t", "No Votes");
					PrintToChatAll("[SM] Next map will be: %s (changes at match end).", displayName);
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

	if (strcmp(map, VOTE_DONTCHANGE, false) == 0)
	{
		int percent = RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES]) / float(num_votes) * 100.0);
		PrintToChatAll("[SM] %t", "Current Map Stays");
		LogAction(-1, -1, "Voting for next map has finished. 'No Change' was the winner");

		g_HasVoteStarted = false;
	}
	else
	{
		// Always set next map - map changes at match end only
		SetNextMap(map);

		g_HasVoteStarted = false;
		g_MapVoteCompleted = true;

		int percent = RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES]) / float(num_votes) * 100.0);
		PrintToChatAll("[SM] Next map will be: %s (%d%% of %d votes). Map changes at match end!", displayName, percent, num_votes);
		LogAction(-1, -1, "Voting for next map has finished. Nextmap: %s (will change at match end).", map);
	}
}

/* ===================== ADMIN COMMANDS ===================== */

public Action Command_ForceMapVote(int client, int args)
{
	if (g_MapVoteCompleted)
	{
		ReplyToCommand(client, "[SM] A map vote has already been completed.");
		return Plugin_Handled;
	}

	if (g_HasVoteStarted)
	{
		ReplyToCommand(client, "[SM] A map vote is already in progress.");
		return Plugin_Handled;
	}

	InitiateVote();
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

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	int winner = event.GetInt("winner");

	// Ignore no-winner or draw rounds (0 = no team, 1 = draw/spectator)
	if (winner <= 1)
		return;

	if (winner >= MAXTEAMS)
	{
		SetFailState("Mod exceeds maximum team count.");
	}

	g_winCount[winner]++;

	// Check if any team reached the win trigger
	if (!g_MapList.Length || g_HasVoteStarted || g_MapVoteCompleted)
		return;

	int trigger = g_cvWinTrigger.IntValue;

	if (g_winCount[winner] >= trigger)
	{
		InitiateVote();
	}
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
