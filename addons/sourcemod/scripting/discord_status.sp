/**
 * =============================================================================
 * Discord Server Status - Standalone Webhook Plugin
 *
 * Sends an embed to a Discord channel via webhook showing:
 *   - Server name, map, player count, IP address
 * Updates dynamically on player join/disconnect and map change.
 * Deletes the previous message so only one status message exists.
 *
 * Requires: SteamWorks extension
 *   https://github.com/KyleSanderson/SteamWorks
 *
 * =============================================================================
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <SteamWorks>

#define PLUGIN_VERSION "1.0.0"

/* Discord rate-limit safety: minimum seconds between updates */
#define UPDATE_COOLDOWN 5.0

/* Max JSON buffer */
#define JSON_BUFFER_SIZE 4096

public Plugin myinfo =
{
	name        = "Discord Server Status",
	author      = "Custom",
	description = "Discord webhook embed showing live server status (Hungarian)",
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
	g_cvWebhookURL = CreateConVar("sm_discord_webhook", "", "Discord webhook URL", FCVAR_PROTECTED);
	g_cvServerIP = CreateConVar("sm_discord_server_ip", "", "Server IP:Port to display (e.g. 123.45.67.89:27015)");
	g_cvBotUsername = CreateConVar("sm_discord_bot_name", "Szerver Státusz", "Webhook bot display name");
	g_cvBotAvatar = CreateConVar("sm_discord_bot_avatar", "", "Webhook bot avatar URL (optional)");
	g_cvEmbedColor = CreateConVar("sm_discord_embed_color", "3447003", "Embed color (decimal, default=blue 0x3498DB)");
	g_cvFooterText = CreateConVar("sm_discord_footer", "Szerver Státusz", "Embed footer text");
	g_cvFooterIcon = CreateConVar("sm_discord_footer_icon", "", "Embed footer icon URL (optional)");
	g_cvThumbnail = CreateConVar("sm_discord_thumbnail", "", "Embed thumbnail URL (optional)");

	AutoExecConfig(true, "discord_status");

	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);

	g_szLastMessageID[0] = '\0';
	g_bUpdatePending = false;
	g_hUpdateTimer = null;
}

public void OnMapStart()
{
	g_szLastMessageID[0] = '\0';
	ScheduleUpdate();
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

/* ===================== UPDATE SCHEDULING ===================== */

void ScheduleUpdate()
{
	if (g_bUpdatePending)
		return;

	g_bUpdatePending = true;

	if (g_hUpdateTimer != null)
	{
		KillTimer(g_hUpdateTimer);
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
		return Plugin_Stop;

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
		LogError("[Discord] Failed to create DELETE request.");
		g_szLastMessageID[0] = '\0';
		char webhookCopy[512];
		g_cvWebhookURL.GetString(webhookCopy, sizeof(webhookCopy));
		SendStatusEmbed(webhookCopy);
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
}

/* ===================== SEND EMBED ===================== */

void SendStatusEmbed(const char[] webhookURL)
{
	// Gather server info
	char serverName[256];
	char mapName[128];
	char serverIP[64];
	char botName[128];
	char botAvatar[512];
	char footerText[256];
	char footerIcon[512];
	char thumbnail[512];

	// Get server hostname
	ConVar cvHostname = FindConVar("hostname");
	if (cvHostname != null)
	{
		cvHostname.GetString(serverName, sizeof(serverName));
	}
	else
	{
		strcopy(serverName, sizeof(serverName), "Ismeretlen szerver");
	}

	GetCurrentMap(mapName, sizeof(mapName));
	g_cvServerIP.GetString(serverIP, sizeof(serverIP));
	g_cvBotUsername.GetString(botName, sizeof(botName));
	g_cvBotAvatar.GetString(botAvatar, sizeof(botAvatar));
	g_cvFooterText.GetString(footerText, sizeof(footerText));
	g_cvFooterIcon.GetString(footerIcon, sizeof(footerIcon));
	g_cvThumbnail.GetString(thumbnail, sizeof(thumbnail));

	int embedColor = g_cvEmbedColor.IntValue;

	// Count real players
	int playerCount = 0;
	int maxPlayers = GetMaxHumanPlayers();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			playerCount++;
		}
	}

	// Build player list
	char playerList[1024];
	playerList[0] = '\0';
	int listed = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			char playerName[MAX_NAME_LENGTH];
			GetClientName(i, playerName, sizeof(playerName));
			EscapeJSON(playerName, playerName, sizeof(playerName));

			if (listed > 0)
			{
				StrCat(playerList, sizeof(playerList), ", ");
			}

			StrCat(playerList, sizeof(playerList), playerName);
			listed++;

			if (listed >= 20)
			{
				int remaining = playerCount - listed;
				if (remaining > 0)
				{
					char moreText[64];
					Format(moreText, sizeof(moreText), " ... és még %d játékos", remaining);
					StrCat(playerList, sizeof(playerList), moreText);
				}
				break;
			}
		}
	}

	if (listed == 0)
	{
		strcopy(playerList, sizeof(playerList), "Nincs játékos a szerveren");
	}

	// Escape all strings for JSON
	char safeServerName[512];
	char safeMapName[256];
	char safeBotName[256];
	char safeFooterText[512];
	char safePlayerList[2048];

	strcopy(safeServerName, sizeof(safeServerName), serverName);
	EscapeJSON(safeServerName, safeServerName, sizeof(safeServerName));

	strcopy(safeMapName, sizeof(safeMapName), mapName);
	EscapeJSON(safeMapName, safeMapName, sizeof(safeMapName));

	strcopy(safeBotName, sizeof(safeBotName), botName);
	EscapeJSON(safeBotName, safeBotName, sizeof(safeBotName));

	strcopy(safeFooterText, sizeof(safeFooterText), footerText);
	EscapeJSON(safeFooterText, safeFooterText, sizeof(safeFooterText));

	strcopy(safePlayerList, sizeof(safePlayerList), playerList);

	// Status indicator
	char statusEmoji[16];
	if (playerCount == 0)
	{
		strcopy(statusEmoji, sizeof(statusEmoji), "🔴");
	}
	else if (playerCount >= maxPlayers)
	{
		strcopy(statusEmoji, sizeof(statusEmoji), "🟡");
	}
	else
	{
		strcopy(statusEmoji, sizeof(statusEmoji), "🟢");
	}

	// Build JSON payload
	char json[JSON_BUFFER_SIZE];

	// Build footer JSON
	char footerJSON[768];
	if (strlen(footerIcon) > 0)
	{
		Format(footerJSON, sizeof(footerJSON),
			"\"footer\":{\"text\":\"%s\",\"icon_url\":\"%s\"},",
			safeFooterText, footerIcon);
	}
	else
	{
		Format(footerJSON, sizeof(footerJSON),
			"\"footer\":{\"text\":\"%s\"},",
			safeFooterText);
	}

	// Build thumbnail JSON
	char thumbnailJSON[512];
	if (strlen(thumbnail) > 0)
	{
		Format(thumbnailJSON, sizeof(thumbnailJSON),
			"\"thumbnail\":{\"url\":\"%s\"},", thumbnail);
	}
	else
	{
		thumbnailJSON[0] = '\0';
	}

	// Build avatar JSON
	char avatarJSON[768];
	if (strlen(botAvatar) > 0)
	{
		Format(avatarJSON, sizeof(avatarJSON),
			"\"avatar_url\":\"%s\",", botAvatar);
	}
	else
	{
		avatarJSON[0] = '\0';
	}

	// Connect field
	char connectField[256];
	if (strlen(serverIP) > 0)
	{
		Format(connectField, sizeof(connectField),
			"{\"name\":\"🌐 Csatlakozás\",\"value\":\"``%s``\",\"inline\":false},",
			serverIP);
	}
	else
	{
		connectField[0] = '\0';
	}

	Format(json, sizeof(json),
		"{"
		"\"username\":\"%s\","
		"%s"
		"\"embeds\":[{"
			"\"title\":\"%s %s\","
			"\"color\":%d,"
			"\"fields\":["
				"{\"name\":\"🗺️ Pálya\",\"value\":\"``%s``\",\"inline\":true},"
				"{\"name\":\"👥 Játékosok\",\"value\":\"%s %d/%d\",\"inline\":true},"
				"%s"
				"{\"name\":\"📋 Játékos lista\",\"value\":\"%s\",\"inline\":false}"
			"],"
			"%s"
			"%s"
			"\"timestamp\":\"\""
		"}]"
		"}",
		safeBotName,
		avatarJSON,
		statusEmoji, safeServerName,
		embedColor,
		safeMapName,
		statusEmoji, playerCount, maxPlayers,
		connectField,
		safePlayerList,
		thumbnailJSON,
		footerJSON
	);

	// Send POST request with ?wait=true to get message ID back
	char postURL[768];
	Format(postURL, sizeof(postURL), "%s?wait=true", webhookURL);

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, postURL);
	if (request == null)
	{
		LogError("[Discord] Failed to create POST request.");
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
		LogError("[Discord] Failed to send webhook. HTTP status: %d", statusCode);
		delete request;
		return 0;
	}

	// Read the response to extract message ID
	int bodySize;
	SteamWorks_GetHTTPResponseBodySize(request, bodySize);

	char[] body = new char[bodySize + 1];
	SteamWorks_GetHTTPResponseBodyData(request, body, bodySize + 1);

	delete request;

	// Extract "id" from JSON response: {"id":"1234567890",...}
	ExtractMessageID(body, g_szLastMessageID, sizeof(g_szLastMessageID));

	return 0;
}

/* ===================== JSON HELPERS ===================== */

void EscapeJSON(const char[] input, char[] output, int maxlen)
{
	int j = 0;
	for (int i = 0; input[i] != '\0' && j < maxlen - 2; i++)
	{
		switch (input[i])
		{
			case '"':
			{
				if (j + 2 >= maxlen) break;
				output[j++] = '\\';
				output[j++] = '"';
			}
			case '\\':
			{
				if (j + 2 >= maxlen) break;
				output[j++] = '\\';
				output[j++] = '\\';
			}
			case '\n':
			{
				if (j + 2 >= maxlen) break;
				output[j++] = '\\';
				output[j++] = 'n';
			}
			case '\r':
			{
				if (j + 2 >= maxlen) break;
				output[j++] = '\\';
				output[j++] = 'r';
			}
			case '\t':
			{
				if (j + 2 >= maxlen) break;
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
	// Find "id":" in the response
	int pos = StrContains(json, "\"id\":\"");
	if (pos == -1)
	{
		id[0] = '\0';
		return;
	}

	// Skip past "id":"
	pos += 6;

	int j = 0;
	for (int i = pos; json[i] != '\0' && json[i] != '"' && j < maxlen - 1; i++)
	{
		id[j++] = json[i];
	}
	id[j] = '\0';
}
