/**
 * =============================================================================
 * Kovetkezo Palya Szavazas Plugin CS2-hoz
 * Palya szavazast indit, amikor barmelyik csapat eleri a 14 korgyozelmet.
 * A palya csak a meccs vegen valtozik.
 *
 * Funkciok:
 *   - Automatikus szavazas, ha egy csapat eleri a 14 korgyozelmet
 *   - Rock the Vote (!rtv) - jatekosok altal kezdemenyezett szavazas
 *   - Palya jeloles chaten keresztul (!nominate / !nom)
 *   - Palya kizaras (nemreg jatszott palyak)
 *   - Ujraszavazas, ha tul szoros az eredmeny
 *   - Admin parancsok: sm_mapvote, sm_setnextmap
 *
 * Parancsok:
 *   say !rtv / rtv                       - Rock the Vote
 *   say nominate / say !nominate / !nom  - Palya jelolese
 *   sm_mapvote (admin)                   - Szavazas kenyszeritese
 *   sm_setnextmap <palya> (admin)        - Kovetkezo palya beallitasa
 *
 * =============================================================================
 */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <nextmap>
#include <multicolors>
#define PLUGIN_VERSION "2.0.0"
#define PREFIX "{darkred}[{default}NexxoN - SyStem{darkred}]{default}"
/* ===================== KONSTANSOK ===================== */
#define VOTE_DONTCHANGE "##dontchange##"
#define MAXTEAMS        10
#define WIN_TRIGGER     14
/* ===================== PLUGIN INFO ===================== */
public Plugin myinfo =
{
	name        = "Kovetkezo Palya Szavazas (14. Kor)",
	author      = "AlliedModders LLC, Modositva",
	description = "Palya szavazast indit, ha barmelyik csapat eleri a 14 korgyozelmet. Palya a meccs vegen valtozik.",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/SubCoderHUN/smext-fakequeries"
};
/* ===================== CVAROK ===================== */
ConVar g_cvExcludeMaps;
ConVar g_cvIncludeMaps;
ConVar g_cvNoVoteMode;
ConVar g_cvVoteDuration;
ConVar g_cvRunOff;
ConVar g_cvRunOffPercent;
ConVar g_cvWinTrigger;
// Jeloles CVariok
ConVar g_cvNomExcludeOld;
ConVar g_cvNomExcludeCurrent;
// RTV CVariok
ConVar g_cvRTVPercent;
ConVar g_cvRTVDelay;
/* ===================== PALYA ADATOK ===================== */
ArrayList g_MapList;
ArrayList g_NominateList;
ArrayList g_NominateOwners;
ArrayList g_OldMapList;
ArrayList g_NextMapList;
int g_mapFileSerial = -1;
/* ===================== SZAVAZAS ALLAPOT ===================== */
Menu g_VoteMenu;
Handle g_RetryTimer;
bool g_HasVoteStarted;
bool g_WaitingForVote;
bool g_MapVoteCompleted;
int g_winCount[MAXTEAMS];
/* ===================== RTV ALLAPOT ===================== */
bool g_bPlayerRTV[MAXPLAYERS + 1];
int g_iRTVCount;
float g_fMapStartTime;
/* ===================== JELOLES ALLAPOT ===================== */
Menu g_NominateMenu;
StringMap g_NominateMapStatus;
#define MAPSTATUS_ENABLED     (0)
#define MAPSTATUS_DISABLED    (1 << 0)
#define MAPSTATUS_EXCLUDE_OLD (1 << 1)
#define MAPSTATUS_EXCLUDE_CUR (1 << 2)
#define MAPSTATUS_EXCLUDE_NOM (1 << 3)
/* ===================== PLUGIN ELETCIKLUS ===================== */
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
	// CVariok
	g_cvWinTrigger = CreateConVar("sm_mapvote_wintrigger", "14", "Korgyozelmek szama a szavazas inditasahoz", _, true, 1.0);
	g_cvExcludeMaps = CreateConVar("sm_mapvote_exclude", "5", "Kizart korabbi palyak szama", _, true, 0.0);
	g_cvIncludeMaps = CreateConVar("sm_mapvote_include", "5", "Szavazasban szereplo palyak szama", _, true, 2.0, true, 6.0);
	g_cvNoVoteMode = CreateConVar("sm_mapvote_novote", "1", "Veletlenszeru palya valasztas, ha senki nem szavaz", _, true, 0.0, true, 1.0);
	g_cvVoteDuration = CreateConVar("sm_mapvote_voteduration", "20", "Szavazas idotartama (masodperc)", _, true, 5.0);
	g_cvRunOff = CreateConVar("sm_mapvote_runoff", "0", "Ujraszavazas, ha a gyoztes nem eri el a minimalis aranyt", _, true, 0.0, true, 1.0);
	g_cvRunOffPercent = CreateConVar("sm_mapvote_runoffpercent", "50", "Minimalis szavazati arany az ujraszavazas elkerulesehez", _, true, 0.0, true, 100.0);
	// Jeloles CVariok
	g_cvNomExcludeOld = CreateConVar("sm_nominate_excludeold", "1", "Nemreg jatszott palyak kizarasa a jelolesbol", _, true, 0.0, true, 1.0);
	g_cvNomExcludeCurrent = CreateConVar("sm_nominate_excludecurrent", "1", "Jelenlegi palya kizarasa a jelolesbol", _, true, 0.0, true, 1.0);
	// RTV CVariok
	g_cvRTVPercent = CreateConVar("sm_rtv_percent", "60", "Jatekosok szazaleka az RTV inditasahoz", _, true, 1.0, true, 100.0);
	g_cvRTVDelay = CreateConVar("sm_rtv_delay", "120.0", "Varakozasi ido masodpercben a palya indulasa utan az !rtv engedelyezeseig", _, true, 0.0, true, 600.0);
	// Admin parancsok
	RegAdminCmd("sm_mapvote", Command_ForceMapVote, ADMFLAG_CHANGEMAP, "Palya szavazas azonnali inditasa");
	RegAdminCmd("sm_setnextmap", Command_SetNextmap, ADMFLAG_CHANGEMAP, "Kovetkezo palya kozvetlen beallitasa");
	// Jeloles parancsok
	RegConsoleCmd("sm_nominate", Command_Nominate, "Palya jelolese a kovetkezo szavazasra");
	RegConsoleCmd("sm_nom", Command_Nominate, "Palya jelolese a kovetkezo szavazasra");
	// RTV parancs
	RegConsoleCmd("sm_rtv", Command_RTV, "Rock the Vote - szavazas a palyavaltoztatasra");
	// Chat triggerek
	AddCommandListener(Listener_Say, "say");
	AddCommandListener(Listener_Say, "say_team");
	// Round end event hook CS2-hoz
	HookEvent("round_end", Event_RoundEnd);
	AutoExecConfig(true, "nextmapvote");
}
/* ===================== PALYA / CONFIG HOOKOK ===================== */
public void OnConfigsExecuted()
{
	if (ReadMapList(g_MapList, g_mapFileSerial, "default", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER) != null)
	{
		if (g_mapFileSerial == -1)
		{
			LogError("Nem sikerult ervenyes palyalistat letrehozni.");
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
	// RTV allapot visszaallitasa
	g_iRTVCount = 0;
	g_fMapStartTime = GetGameTime();
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bPlayerRTV[i] = false;
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
/* ===================== KLIENS HOOKOK ===================== */
public void OnClientDisconnect(int client)
{
	if (IsFakeClient(client))
		return;
	// Jeloles eltavolitasa
	int index = g_NominateOwners.FindValue(client);
	if (index != -1)
	{
		g_NominateList.Erase(index);
		g_NominateOwners.Erase(index);
	}
	// RTV szavazat eltavolitasa
	if (g_bPlayerRTV[client])
	{
		g_bPlayerRTV[client] = false;
		g_iRTVCount--;
	}
}
/* ===================== CHAT FIGYELESE ===================== */
public Action Listener_Say(int client, const char[] command, int argc)
{
	if (!client || !IsClientInGame(client))
		return Plugin_Continue;
	char text[64];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	TrimString(text);
	// RTV chat triggerek
	if (strcmp(text, "rtv", false) == 0 ||
		strcmp(text, "!rtv", false) == 0)
	{
		Command_RTV(client, 0);
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
	// "!nominate <palyanev>" vagy "nominate <palyanev>" ellenorzese
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
/* ===================== RTV LOGIKA ===================== */
public Action Command_RTV(int client, int args)
{
	if (!client || !IsClientInGame(client))
		return Plugin_Handled;
	if (g_MapVoteCompleted)
	{
		CPrintToChat(client, "%s A kovetkezo palya mar el lett dontve.", PREFIX);
		return Plugin_Handled;
	}
	if (g_HasVoteStarted)
	{
		CPrintToChat(client, "%s Mar folyamatban van egy palya szavazas.", PREFIX);
		return Plugin_Handled;
	}
	float delay = g_cvRTVDelay.FloatValue;
	float elapsed = GetGameTime() - g_fMapStartTime;
	if (elapsed < delay)
	{
		int remaining = RoundToCeil(delay - elapsed);
		CPrintToChat(client, "%s Meg {green}%d{default} masodpercet kell varnod, mielott hasznalhatod az RTV-t.", PREFIX, remaining);
		return Plugin_Handled;
	}
	if (g_bPlayerRTV[client])
	{
		int playersNeeded = GetRTVPlayersNeeded();
		int remaining = playersNeeded - g_iRTVCount;
		if (remaining > 0)
			CPrintToChat(client, "%s Mar szavaztal az RTV-re. (Meg {green}%d{default} jatekos kell)", PREFIX, remaining);
		else
			CPrintToChat(client, "%s Mar szavaztal az RTV-re.", PREFIX);
		return Plugin_Handled;
	}
	g_bPlayerRTV[client] = true;
	g_iRTVCount++;
	int playersNeeded = GetRTVPlayersNeeded();
	int remaining = playersNeeded - g_iRTVCount;
	char playerName[MAX_NAME_LENGTH];
	GetClientName(client, playerName, sizeof(playerName));
	if (remaining <= 0)
	{
		CPrintToChatAll("%s {green}%s{default} szavazott! Eleg jatekos szavazott - palya szavazas indul...", PREFIX, playerName);
		InitiateVote();
	}
	else
	{
		CPrintToChatAll("%s {green}%s{default} palyavaltoztatast szeretne! (Meg {green}%d{default} jatekos kell)", PREFIX, playerName, remaining);
	}
	return Plugin_Handled;
}
int GetRTVPlayersNeeded()
{
	int playerCount = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			playerCount++;
		}
	}
	int needed = RoundToCeil(float(playerCount) * g_cvRTVPercent.FloatValue / 100.0);
	if (needed < 1)
	{
		needed = 1;
	}
	return needed;
}
/* ===================== JELOLES LOGIKA ===================== */
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
		CPrintToChat(client, "%s A kovetkezo palya mar el lett dontve.", PREFIX);
		return;
	}
	if (g_NominateMenu == null)
	{
		CPrintToChat(client, "%s Nincsenek elerheto palyak jelolesre.", PREFIX);
		return;
	}
	g_NominateMenu.Display(client, MENU_TIME_FOREVER);
}
void AttemptNominateByName(int client, const char[] mapname)
{
	if (g_MapVoteCompleted)
	{
		CPrintToChat(client, "%s A kovetkezo palya mar el lett dontve.", PREFIX);
		return;
	}
	// Egyezo palyak keresese
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
		CPrintToChat(client, "%s Nem talalhato palya \"{green}%s{default}\" nevre.", PREFIX, mapname);
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
	// Pontos egyezes ellenorzese
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
	// Tobb talalat - menu megjelenites
	Menu menu = new Menu(MenuHandler_NominateSearch);
	menu.SetTitle("Tobb palya talalhato:");
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
		CPrintToChat(client, "%s {green}%d{default} palya talalhato, az elso 10 megjelenik. Legy pontosabb.", PREFIX, matches.Length);
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
		CPrintToChat(client, "%s A(z) \"{green}%s{default}\" palya nem talalhato.", PREFIX, map);
		return;
	}
	// Mar jelolt-e
	if (g_NominateList.FindString(resolvedMap) != -1)
	{
		CPrintToChat(client, "%s A(z) \"{green}%s{default}\" palya mar jelolve van.", PREFIX, map);
		return;
	}
	// Jelenlegi palya ellenorzese
	if (g_cvNomExcludeCurrent.BoolValue)
	{
		char currentMap[PLATFORM_MAX_PATH];
		GetCurrentMap(currentMap, sizeof(currentMap));
		if (strcmp(resolvedMap, currentMap, false) == 0)
		{
			CPrintToChat(client, "%s Nem jelolheted a jelenlegi palyat.", PREFIX);
			return;
		}
	}
	// Nemreg jatszott palyak ellenorzese
	if (g_cvNomExcludeOld.BoolValue)
	{
		char oldMap[PLATFORM_MAX_PATH];
		for (int i = 0; i < g_OldMapList.Length; i++)
		{
			g_OldMapList.GetString(i, oldMap, sizeof(oldMap));
			if (strcmp(resolvedMap, oldMap, false) == 0)
			{
				CPrintToChat(client, "%s A(z) \"{green}%s{default}\" palyat nemreg jatszottak.", PREFIX, map);
				return;
			}
		}
	}
	// Korabbi jeloles csereje, ha van
	int ownerIndex = g_NominateOwners.FindValue(client);
	if (ownerIndex != -1)
	{
		g_NominateList.Erase(ownerIndex);
		g_NominateOwners.Erase(ownerIndex);
	}
	// Jelolesi lista tele van-e
	if (g_NominateList.Length >= g_cvIncludeMaps.IntValue)
	{
		CPrintToChat(client, "%s A jelolesi lista megtelt.", PREFIX);
		return;
	}
	g_NominateList.PushString(resolvedMap);
	g_NominateOwners.Push(client);
	char displayName[PLATFORM_MAX_PATH];
	GetMapDisplayName(resolvedMap, displayName, sizeof(displayName));
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	CPrintToChatAll("%s {green}%s{default} jelolte a(z) {green}%s{default} palyat.", PREFIX, name, displayName);
	// Jelolesi menu ujraepitese
	BuildNominateMenu();
}
void BuildNominateMenu()
{
	delete g_NominateMenu;
	g_NominateMapStatus.Clear();
	g_NominateMenu = new Menu(MenuHandler_Nominate, MENU_ACTIONS_ALL);
	g_NominateMenu.SetTitle("Palya jelolese");
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
					Format(buffer, sizeof(buffer), "%s (Jelenlegi)", displayName);
					return RedrawMenuItem(buffer);
				}
				else if (status & MAPSTATUS_EXCLUDE_OLD)
				{
					char buffer[PLATFORM_MAX_PATH + 32];
					Format(buffer, sizeof(buffer), "%s (Nemreg jatszott)", displayName);
					return RedrawMenuItem(buffer);
				}
				else if (status & MAPSTATUS_EXCLUDE_NOM)
				{
					char buffer[PLATFORM_MAX_PATH + 32];
					Format(buffer, sizeof(buffer), "%s (Jelolve)", displayName);
					return RedrawMenuItem(buffer);
				}
			}
			return 0;
		}
	}
	return 0;
}
/* ===================== PALYA SZAVAZAS LOGIKA ===================== */
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
	g_VoteMenu.SetTitle("Szavazz a kovetkezo palyara");
	g_VoteMenu.VoteResultCallback = Handler_MapVoteFinished;
	char map[PLATFORM_MAX_PATH];
	int nominateCount = g_NominateList.Length;
	int voteSize = g_cvIncludeMaps.IntValue;
	int nominationsToAdd = nominateCount >= voteSize ? voteSize : nominateCount;
	// Jelolt palyak hozzaadasa eloszor
	for (int i = 0; i < nominationsToAdd; i++)
	{
		char displayName[PLATFORM_MAX_PATH];
		g_NominateList.GetString(i, map, sizeof(map));
		GetMapDisplayName(map, displayName, sizeof(displayName));
		g_VoteMenu.AddItem(map, displayName);
		RemoveStringFromArray(g_NextMapList, map);
	}
	// Jelolesek torlese
	g_NominateOwners.Clear();
	g_NominateList.Clear();
	// Fennmarado helyek feltoltese veletlenszeru palyakkal
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
	LogAction(-1, -1, "Palya szavazas elindult.");
	CPrintToChatAll("%s A kovetkezo palya szavazas elindult!", PREFIX);
	// Jelolesi menu ujraepitese
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
			Format(buffer, sizeof(buffer), "Szavazz a kovetkezo palyara!");
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
					Format(buffer, sizeof(buffer), "Ne valtoztasd");
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
					CPrintToChatAll("%s Senki nem szavazott.", PREFIX);
					CPrintToChatAll("%s A kovetkezo palya: {green}%s{default} (meccs vegen valt).", PREFIX, displayName);
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
			// Ujraszavazas
			g_VoteMenu = new Menu(Handler_MapVoteMenu, MENU_ACTIONS_ALL);
			g_VoteMenu.SetTitle("Ujraszavazas - Kovetkezo Palya");
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
			CPrintToChatAll("%s Egyik palya sem erte el a %.0f%%-ot (%s [%.0f%%] es %s [%.0f%%]), ujraszavazas indul.",
				PREFIX, g_cvRunOffPercent.FloatValue, info1, map1percent, info2, map2percent);
			LogMessage("A palya szavazas dontetlennel vegzodott, ujraszavazas indul");
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
		CPrintToChatAll("%s A jelenlegi palya marad!", PREFIX);
		LogAction(-1, -1, "Palya szavazas befejezodott. 'Ne valtoztasd' nyert.");
		g_HasVoteStarted = false;
	}
	else
	{
		// Kovetkezo palya beallitasa - palya csak meccs vegen valtozik
		SetNextMap(map);
		g_HasVoteStarted = false;
		g_MapVoteCompleted = true;
		int percent = RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES]) / float(num_votes) * 100.0);
		CPrintToChatAll("%s A kovetkezo palya: {green}%s{default} ({green}%d%%{default}, %d szavazatbol). A palya a meccs vegen valtozik!", PREFIX, displayName, percent, num_votes);
		LogAction(-1, -1, "Palya szavazas befejezodott. Kovetkezo palya: %s (meccs vegen valt).", map);
	}
}
/* ===================== ADMIN PARANCSOK ===================== */
public Action Command_ForceMapVote(int client, int args)
{
	if (g_MapVoteCompleted)
	{
		CPrintToChat(client, "%s A palya szavazas mar lezarult.", PREFIX);
		return Plugin_Handled;
	}
	if (g_HasVoteStarted)
	{
		CPrintToChat(client, "%s Mar folyamatban van egy palya szavazas.", PREFIX);
		return Plugin_Handled;
	}
	InitiateVote();
	return Plugin_Handled;
}
public Action Command_SetNextmap(int client, int args)
{
	if (args < 1)
	{
		CPrintToChat(client, "%s Hasznalat: sm_setnextmap <palya>", PREFIX);
		return Plugin_Handled;
	}
	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];
	GetCmdArg(1, map, sizeof(map));
	if (FindMap(map, displayName, sizeof(displayName)) == FindMap_NotFound)
	{
		CPrintToChat(client, "%s A(z) \"{green}%s{default}\" palya nem talalhato.", PREFIX, map);
		return Plugin_Handled;
	}
	GetMapDisplayName(displayName, displayName, sizeof(displayName));
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	CPrintToChatAll("%s {green}%s{default} atallitotta a kovetkezo palyat: {green}%s{default}.", PREFIX, name, displayName);
	LogAction(client, -1, "\"%L\" atallitotta a kovetkezo palyat: \"%s\"", client, map);
	SetNextMap(map);
	g_MapVoteCompleted = true;
	return Plugin_Handled;
}
/* ===================== JATEK ESEMENYEK ===================== */
public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	int winner = event.GetInt("winner");
	// Nyertes nelkuli vagy dontetlen korok figyelmen kivul hagyasa
	if (winner <= 1)
		return;
	if (winner >= MAXTEAMS)
	{
		SetFailState("A mod meghaladja a maximalis csapat szamot.");
	}
	g_winCount[winner]++;
	// Ellenorzes, hogy barmelyik csapat elerte-e a gyozelmi kuszubot
	if (!g_MapList.Length || g_HasVoteStarted || g_MapVoteCompleted)
		return;
	int trigger = g_cvWinTrigger.IntValue;
	if (g_winCount[winner] >= trigger)
	{
		InitiateVote();
	}
}
/* ===================== SEGEDFUGGVENYEK ===================== */
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
	// Jelenlegi palya eltavolitasa
	GetCurrentMap(map, sizeof(map));
	RemoveStringFromArray(tempMaps, map);
	// Nemreg jatszott palyak eltavolitasa
	if (g_cvExcludeMaps.IntValue && tempMaps.Length > g_cvExcludeMaps.IntValue)
	{
		for (int i = 0; i < g_OldMapList.Length; i++)
		{
			g_OldMapList.GetString(i, map, sizeof(map));
			RemoveStringFromArray(tempMaps, map);
		}
	}
	// Veletlenszeru palyak valasztasa a szavazasi poolba
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
