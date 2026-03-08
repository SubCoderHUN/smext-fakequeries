/**
 * =============================================================================
 * Discord Server Status - Standalone Webhook Plugin
 *
 * Sends a single, always-up-to-date embed to a Discord channel via webhook.
 * On every player join/disconnect/map change, the old message is deleted
 * and a new one is sent so only ONE status message exists in the channel.
 *
 * Shows: server name, map, player count, player list, IP address.
 * All embed text is in Hungarian.
 *
 * Only dependency: SteamWorks extension (.dll/.so on server)
 *   https://github.com/KyleSanderson/SteamWorks
 *
 * Uses steamworks_http.inc (included) to avoid SteamWorks.inc compile bugs.
 *
 * =============================================================================
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <steamworks_http>

#define PLUGIN_VERSION "1.0.0"

/* Discord rate-limit safety: minimum seconds between updates */
#define UPDATE_COOLDOWN 5.0

/* Max JSON buffer */
#define JSON_BUFFER_SIZE 4096

public Plugin myinfo =
{
	name        = "Discord Server Status",
	author      = "Custom",
	description = "Discord webhook - szerver státusz embed (HU)",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/SubCoderHUN/smext-fakequeries"
};

/* ===================== CVARS ===================== */

ConVar g_cvWebhookURL;
ConVar g_cvServerIP;
ConVar g_cvBotUsername;
ConVar g_cvBotAvatar;
ConVar g_cvEmbedColor;
ConVar g_cvFooterText;
ConVar g_cvFooterIcon;
ConVar g_cvThumbnail;

/* ===================== STATE ===================== */

char g_szLastMessageID[128];
bool g_bUpdatePending;
Handle g_hUpdateTimer;

/* ===================== LIFECYCLE ===================== */

public void OnPluginStart()
{
	g_cvWebhookURL = CreateConVar("sm_discord_webhook", "", "Discord webhook URL (teljes URL)", FCVAR_PROTECTED);
	g_cvServerIP   = CreateConVar("sm_discord_server_ip", "", "Szerver IP:Port megjeleniteshez (pl. 123.45.67.89:27015)");
	g_cvBotUsername = CreateConVar("sm_discord_bot_name", "Szerver Státusz", "Webhook bot megjelenítési neve");
	g_cvBotAvatar  = CreateConVar("sm_discord_bot_avatar", "", "Webhook bot avatar URL (opcionális)");
	g_cvEmbedColor = CreateConVar("sm_discord_embed_color", "3447003", "Embed szín (decimális, alapértelmezett=kék 0x3498DB)");
	g_cvFooterText = CreateConVar("sm_discord_footer", "", "Embed lábléc szöveg (üres = hostname)");
	g_cvFooterIcon = CreateConVar("sm_discord_footer_icon", "", "Embed lábléc ikon URL (opcionális)");
	g_cvThumbnail  = CreateConVar("sm_discord_thumbnail", "", "Embed bélyegkép URL (opcionális)");

	AutoExecConfig(true, "discord_status");

	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);

	RegAdminCmd("sm_discord_test", Command_Test, ADMFLAG_ROOT, "Discord státusz embed teszt küldése");

	g_szLastMessageID[0] = '\0';
	g_bUpdatePending = false;
	g_hUpdateTimer = null;
}

public void OnMapStart()
{
	g_szLastMessageID[0] = '\0';
	CreateTimer(10.0, Timer_MapStartUpdate, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_MapStartUpdate(Handle timer)
{
	ScheduleUpdate();
	return Plugin_Stop;
}

public void OnClientPostAdminCheck(int client)
{
	if (!IsFakeClient(client))
	{
		ScheduleUpdate();
	}
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	if (client > 0 && !IsFakeClient(client))
	{
		ScheduleUpdate();
	}
}

public Action Command_Test(int client, int args)
{
	g_bUpdatePending = false;
	if (g_hUpdateTimer != null)
	{
		KillTimer(g_hUpdateTimer);
		g_hUpdateTimer = null;
	}
	ScheduleUpdate();
	ReplyToCommand(client, "[Discord] Teszt üzenet küldése...");
	return Plugin_Handled;
}

/* ===================== UPDATE SCHEDULING ===================== */

void ScheduleUpdate()
{
	if (g_bUpdatePending)
		return;

	g_bUpdatePending = true;

	if (g_hUpdateTimer != null)
	{
		KillTimer(g_hUpdateTimer);
		g_hUpdateTimer = null;
	}

	g_hUpdateTimer = CreateTimer(UPDATE_COOLDOWN, Timer_SendUpdate, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SendUpdate(Handle timer)
{
	g_hUpdateTimer = null;
	g_bUpdatePending = false;

	char webhookURL[512];
	g_cvWebhookURL.GetString(webhookURL, sizeof(webhookURL));

	if (strlen(webhookURL) == 0)
	{
		LogError("[Discord] sm_discord_webhook nincs beállítva!");
		return Plugin_Stop;
	}

	// If we have a previous message, delete it first then send new one
	if (strlen(g_szLastMessageID) > 0)
	{
		DeleteLastMessage(webhookURL);
	}
	else
	{
		SendStatusEmbed(webhookURL);
	}

	return Plugin_Stop;
}

/* ===================== DELETE PREVIOUS MESSAGE ===================== */

void DeleteLastMessage(const char[] webhookURL)
{
	char deleteURL[768];
	Format(deleteURL, sizeof(deleteURL), "%s/messages/%s", webhookURL, g_szLastMessageID);

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodDELETE, deleteURL);
	if (request == null)
	{
		LogError("[Discord] Nem sikerült a DELETE kérés létrehozása.");
		g_szLastMessageID[0] = '\0';

		char url[512];
		g_cvWebhookURL.GetString(url, sizeof(url));
		SendStatusEmbed(url);
		return;
	}

	SteamWorks_SetHTTPCallbacks(request, OnDeleteComplete);
	SteamWorks_SendHTTPRequest(request);
}

public int OnDeleteComplete(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode)
{
	delete request;
	g_szLastMessageID[0] = '\0';

	char webhookURL[512];
	g_cvWebhookURL.GetString(webhookURL, sizeof(webhookURL));

	if (strlen(webhookURL) > 0)
	{
		SendStatusEmbed(webhookURL);
	}

	return 0;
}

/* ===================== SEND EMBED ===================== */

void SendStatusEmbed(const char[] webhookURL)
{
	// ---- Gather server info ----
	char serverName[256];
	char mapName[128];
	char serverIP[64];
	char botName[128];
	char botAvatar[512];
	char footerText[256];
	char footerIcon[512];
	char thumbnail[512];

	ConVar cvHostname = FindConVar("hostname");
	if (cvHostname != null)
		cvHostname.GetString(serverName, sizeof(serverName));
	else
		strcopy(serverName, sizeof(serverName), "Ismeretlen szerver");

	GetCurrentMap(mapName, sizeof(mapName));
	g_cvServerIP.GetString(serverIP, sizeof(serverIP));
	g_cvBotUsername.GetString(botName, sizeof(botName));
	g_cvBotAvatar.GetString(botAvatar, sizeof(botAvatar));
	g_cvFooterText.GetString(footerText, sizeof(footerText));
	g_cvFooterIcon.GetString(footerIcon, sizeof(footerIcon));
	g_cvThumbnail.GetString(thumbnail, sizeof(thumbnail));

	int embedColor = g_cvEmbedColor.IntValue;

	// Auto-detect IP if not set
	if (strlen(serverIP) == 0)
	{
		int ips[4];
		int iIP = FindConVar("hostip").IntValue;
		ips[0] = (iIP >> 24) & 0x000000FF;
		ips[1] = (iIP >> 16) & 0x000000FF;
		ips[2] = (iIP >> 8) & 0x000000FF;
		ips[3] = iIP & 0x000000FF;
		int iPort = FindConVar("hostport").IntValue;
		Format(serverIP, sizeof(serverIP), "%d.%d.%d.%d:%d", ips[0], ips[1], ips[2], ips[3], iPort);
	}

	// Footer fallback to hostname
	if (strlen(footerText) == 0)
	{
		Format(footerText, sizeof(footerText), "%s | %s", serverName, serverIP);
	}

	// ---- Count real players ----
	int playerCount = 0;
	int maxPlayers = GetMaxHumanPlayers();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
			playerCount++;
	}

	// ---- Build player list ----
	char playerList[1024];
	playerList[0] = '\0';
	int listed = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			char pName[MAX_NAME_LENGTH * 2];
			char rawName[MAX_NAME_LENGTH];
			GetClientName(i, rawName, sizeof(rawName));
			EscapeJSON(rawName, pName, sizeof(pName));

			if (listed > 0)
				StrCat(playerList, sizeof(playerList), ", ");

			StrCat(playerList, sizeof(playerList), pName);
			listed++;

			if (listed >= 20)
			{
				int remaining = playerCount - listed;
				if (remaining > 0)
				{
					char more[64];
					Format(more, sizeof(more), " ... és még %d játékos", remaining);
					StrCat(playerList, sizeof(playerList), more);
				}
				break;
			}
		}
	}

	if (listed == 0)
		strcopy(playerList, sizeof(playerList), "Nincs játékos a szerveren");

	// ---- Status emoji ----
	char statusEmoji[16];
	if (playerCount == 0)
		strcopy(statusEmoji, sizeof(statusEmoji), "\\u{1F534}");   // red
	else if (playerCount >= maxPlayers)
		strcopy(statusEmoji, sizeof(statusEmoji), "\\u{1F7E1}");   // yellow
	else
		strcopy(statusEmoji, sizeof(statusEmoji), "\\u{1F7E2}");   // green

	// ---- Escape strings for JSON ----
	char safeServerName[512];
	char safeMapName[256];
	char safeBotName[256];
	char safeFooterText[512];

	EscapeJSON(serverName, safeServerName, sizeof(safeServerName));
	EscapeJSON(mapName, safeMapName, sizeof(safeMapName));
	EscapeJSON(botName, safeBotName, sizeof(safeBotName));
	EscapeJSON(footerText, safeFooterText, sizeof(safeFooterText));

	// ---- Build JSON ----
	char json[JSON_BUFFER_SIZE];
	int pos = 0;

	// Opening + username
	pos += FormatToBuffer(json, sizeof(json), pos, "{\"username\":\"%s\"", safeBotName);

	// Avatar (optional)
	if (strlen(botAvatar) > 0)
		pos += FormatToBuffer(json, sizeof(json), pos, ",\"avatar_url\":\"%s\"", botAvatar);

	// Embeds array start + title + color
	pos += FormatToBuffer(json, sizeof(json), pos,
		",\"embeds\":[{\"title\":\"%s %s\",\"color\":%d",
		statusEmoji, safeServerName, embedColor);

	// Thumbnail (optional)
	if (strlen(thumbnail) > 0)
		pos += FormatToBuffer(json, sizeof(json), pos, ",\"thumbnail\":{\"url\":\"%s\"}", thumbnail);

	// Fields
	pos += FormatToBuffer(json, sizeof(json), pos,
		",\"fields\":["
		"{\"name\":\"\\u{1F5FA}\\u{FE0F} Pálya\",\"value\":\"``%s``\",\"inline\":true},"
		"{\"name\":\"\\u{1F465} Játékosok\",\"value\":\"%s **%d/%d**\",\"inline\":true},",
		safeMapName,
		statusEmoji, playerCount, maxPlayers);

	// Connect field (optional)
	if (strlen(serverIP) > 0)
	{
		pos += FormatToBuffer(json, sizeof(json), pos,
			"{\"name\":\"\\u{1F310} Csatlakozás\",\"value\":\"``%s``\",\"inline\":false},",
			serverIP);
	}

	// Player list field
	pos += FormatToBuffer(json, sizeof(json), pos,
		"{\"name\":\"\\u{1F4CB} Játékos lista\",\"value\":\"%s\",\"inline\":false}]",
		playerList);

	// Footer
	if (strlen(footerIcon) > 0)
	{
		pos += FormatToBuffer(json, sizeof(json), pos,
			",\"footer\":{\"text\":\"%s\",\"icon_url\":\"%s\"}",
			safeFooterText, footerIcon);
	}
	else
	{
		pos += FormatToBuffer(json, sizeof(json), pos,
			",\"footer\":{\"text\":\"%s\"}",
			safeFooterText);
	}

	// Close embed + embeds array + root
	pos += FormatToBuffer(json, sizeof(json), pos, "}]}");

	// ---- Send HTTP POST ----
	char postURL[768];
	Format(postURL, sizeof(postURL), "%s?wait=true", webhookURL);

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, postURL);
	if (request == null)
	{
		LogError("[Discord] Nem sikerült a POST kérés létrehozása.");
		return;
	}

	SteamWorks_SetHTTPRequestHeaderValue(request, "Content-Type", "application/json; charset=UTF-8");
	SteamWorks_SetHTTPRequestRawPostBody(request, "application/json; charset=UTF-8", json, strlen(json));
	SteamWorks_SetHTTPCallbacks(request, OnSendComplete);
	SteamWorks_SendHTTPRequest(request);
}

public int OnSendComplete(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode)
{
	if (failure || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		LogError("[Discord] Webhook küldés sikertelen. HTTP státusz: %d", statusCode);
		delete request;
		return 0;
	}

	// Read response to extract message ID
	int bodySize;
	SteamWorks_GetHTTPResponseBodySize(request, bodySize);

	char[] body = new char[bodySize + 1];
	SteamWorks_GetHTTPResponseBodyData(request, body, bodySize + 1);

	delete request;

	// Extract "id":"..." from JSON response
	ExtractMessageID(body, g_szLastMessageID, sizeof(g_szLastMessageID));

	return 0;
}

/* ===================== HELPERS ===================== */

void EscapeJSON(const char[] input, char[] output, int maxlen)
{
	int j = 0;
	for (int i = 0; input[i] != '\0' && j < maxlen - 2; i++)
	{
		switch (input[i])
		{
			case '"':
			{
				if (j + 2 >= maxlen) { output[j] = '\0'; return; }
				output[j++] = '\\';
				output[j++] = '"';
			}
			case '\\':
			{
				if (j + 2 >= maxlen) { output[j] = '\0'; return; }
				output[j++] = '\\';
				output[j++] = '\\';
			}
			case '\n':
			{
				if (j + 2 >= maxlen) { output[j] = '\0'; return; }
				output[j++] = '\\';
				output[j++] = 'n';
			}
			case '\r':
			{
				if (j + 2 >= maxlen) { output[j] = '\0'; return; }
				output[j++] = '\\';
				output[j++] = 'r';
			}
			case '\t':
			{
				if (j + 2 >= maxlen) { output[j] = '\0'; return; }
				output[j++] = '\\';
				output[j++] = 't';
			}
			default:
			{
				output[j++] = input[i];
			}
		}
	}
	output[j] = '\0';
}

void ExtractMessageID(const char[] json, char[] id, int maxlen)
{
	int pos = StrContains(json, "\"id\":\"");
	if (pos == -1)
	{
		id[0] = '\0';
		return;
	}

	pos += 6; // skip past "id":"

	int j = 0;
	for (int i = pos; json[i] != '\0' && json[i] != '"' && j < maxlen - 1; i++)
	{
		id[j++] = json[i];
	}
	id[j] = '\0';
}

int FormatToBuffer(char[] buffer, int bufferSize, int offset, const char[] format, any ...)
{
	int written = VFormat(buffer[offset], bufferSize - offset, format, 4);
	return written;
}
