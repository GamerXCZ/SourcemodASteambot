#include <sourcemod>
#include <sdktools>
#include <ASteambot>
#include <adminmenu>
#include <morecolors>

#define PLUGIN_AUTHOR 	"Arkarr"
#define PLUGIN_VERSION 	"1.00"
#define MODULE_NAME 	"[ASteambot - Report]"

Handle CVAR_Delay;

int Target[MAXPLAYERS + 1];

float LastUsedReport[MAXPLAYERS + 1];

char configLines[256][192];

public Plugin myinfo = 
{
	name = "[ANY] ASteambot Report", 
	author = PLUGIN_AUTHOR, 
	description = "Report players on server by sending steam messages to admins.", 
	version = PLUGIN_VERSION, 
	url = "http://www.sourcemod.net"
};

public OnPluginStart()
{
	RegConsoleCmd("sm_report", CMD_Report, "Report a player by sending a message to admins through steam chat.");
	
	CVAR_Delay = CreateConVar("sm_asteambot_report_delay", "30.0", "Time, in seconds, to delay the target of sm_rocket's death.", FCVAR_NONE, true, 0.0);
	
	LoadTranslations("common.phrases");
	LoadTranslations("core.phrases");
}

public void OnClientPutInServer(int client)
{
	Target[client] = 0;
	LastUsedReport[client] = GetGameTime();
	for (new z = 1; z <= GetMaxClients(); z++)
	{
		if (Target[z] == client) Target[z] = 0;
	}
}

public Action CMD_Report(int client, int args)
{
	if (LastUsedReport[client] + GetConVarFloat(CVAR_Delay) > GetGameTime())
	{
		ReplyToCommand(client, "%s You must wait %i seconds before submitting another report.", MODULE_NAME, RoundFloat((LastUsedReport[client] + RoundFloat(GetConVarFloat(CVAR_Delay))) - RoundFloat(GetGameTime())));
		return Plugin_Handled;
	}
	
	if (args == 0)
	{
		ChooseTargetMenu(client);
		return Plugin_Handled;
	}
	
	char arg1[128];
	char arg2[256];
	
	if (args == 1)
	{
		GetCmdArg(1, arg1, sizeof(arg1));
		
		Target[client] = FindTarget(client, arg1, true, true);
		if (!IsValidClient(Target[client]))
		{
			ReplyToCommand(client, "%s %t", MODULE_NAME, "No matching client");
			return Plugin_Handled;
		}
		ReasonMenu(client);
	}
	else if (args > 1)
	{
		GetCmdArg(1, arg1, 128);
		GetCmdArgString(arg2, 256);
		ReplaceStringEx(arg2, 256, arg1, "");
		int target = FindTarget(client, arg1, true, true);
		if (!IsValidClient(target))
		{
			ReplyToCommand(client, "[PR] %t", "No matching client");
			return Plugin_Handled;
		}
		
		ReportPlayer(client, target, arg2);
	}
	return Plugin_Handled;
}

stock ReportPlayer(client, target, char[] reason)
{
	if (!IsValidClient(target))
	{
		PrintToChat(client, "[PR] The player you were going to report is no longer in-game.");
		return;
	}
	
	char configFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configFile, sizeof(configFile), "configs/playerreport_logs.txt");
	Handle file = OpenFile(configFile, "at+");
	
	char ID1[50];
	char ID2[50];
	char date[50];
	char time[50];
	
	GetClientAuthId(client, AuthId_Steam2, ID1, sizeof(ID1));
	GetClientAuthId(target, AuthId_Steam2, ID2, sizeof(ID2));
	FormatTime(date, 50, "%m/%d/%Y");
	FormatTime(time, 50, "%H:%M:%S");
	WriteFileLine(file, "User: %N [%s]\nReported: %N [%s]\nDate: %s\nTime: %s\nReason: \"%s\"\n-------\n\n", client, ID1, target, ID2, date, time, reason);
	CloseHandle(file);
	
	PrintToChat(client, "%s Report submitted.", MODULE_NAME);
	for (new z = 1; z <= GetMaxClients(); z++)
	{
		if (!IsValidClient(z)) continue;
		if (CheckCommandAccess(z, "sm_admin", ADMFLAG_GENERIC))
			PrintToChat(z, "%s %N reported %N (Reason: \"%s\")", MODULE_NAME, client, target, reason)
	}
	
	PrintToServer("%s %N reported %N (Reason: \"%s\")", MODULE_NAME, client, target, reason);
	
	char message[100];
	Format(message, sizeof(message), "%s/%s/%s", ID1, ID2, reason);
	ASteambot_SendMesssage(AS_REPORT_PLAYER, message);
	
	LastUsedReport[client] = GetGameTime();
}

public void ChooseTargetMenu(int client)
{
	Handle smMenu = CreateMenu(ChooseTargetMenuHandler);
	SetGlobalTransTarget(client);
	char text[128];
	Format(text, 128, "Report player:", client);
	SetMenuTitle(smMenu, text);
	SetMenuExitBackButton(smMenu, true);
	
	AddTargetsToMenu2(smMenu, client, COMMAND_FILTER_NO_BOTS);
	
	DisplayMenu(smMenu, client, MENU_TIME_FOREVER);
}

public int ChooseTargetMenuHandler(Handle menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		int userid;
		int target;
		
		GetMenuItem(menu, param2, info, sizeof(info));
		userid = StringToInt(info);

		if ((target = GetClientOfUserId(userid)) == 0)PrintToChat(client, "%s %t", MODULE_NAME, "Player no longer available");
		else
		{
			if (client == target) ReplyToCommand(client, "%s Why would you report yourself?", MODULE_NAME);
			else
			{
				Target[client] = target;
				ReasonMenu(client);
			}
		}
	}
}

public void ReasonMenu(int client)
{
	Handle smMenu = CreateMenu(ReasonMenuHandler);
	
	SetGlobalTransTarget(client);
	
	char text[128];
	Format(text, 128, "Select reason:");
	
	SetMenuTitle(smMenu, text);
	
	int lines;
	lines = ReadConfig("playerreport_reasons");
	
	for (new z = 0; z <= lines - 1; z++)
		AddMenuItem(smMenu, configLines[z], configLines[z]);
		
	DisplayMenu(smMenu, client, MENU_TIME_FOREVER);
}

public int ReasonMenuHandler(Handle menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Cancel && item == MenuCancel_ExitBack) CloseHandle(menu);
	if (action == MenuAction_Select)
	{
		char selection[128];
		GetMenuItem(menu, item, selection, 128);
		ReportPlayer(client, Target[client], selection);
	}
}

stock bool IsValidClient(client)
{
	if (client <= 0 || client > MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	if (IsClientSourceTV(client) || IsClientReplay(client)) return false;
	return true;
}

stock ReadConfig(char[] configName)
{
	char configFile[PLATFORM_MAX_PATH];
	char line[192];
	int i = 0;
	int totalLines = 0;
	
	BuildPath(Path_SM, configFile, sizeof(configFile), "configs/%s.txt", configName);
	
	Handle file = OpenFile(configFile, "rt");
	
	if(file != INVALID_HANDLE)
	{
		while (!IsEndOfFile(file))
		{
			if (!ReadFileLine(file, line, sizeof(line)))
				break;
			
			TrimString(line);
			if(strlen(line) > 0)
			{
				FormatEx(configLines[i], 192, "%s", line);
				totalLines++;
			}
			
			i++;
			
			if(i >= sizeof(configLines))
			{
				LogError("%s config contains too many entries!", configName);
				break;
			}
		}
				
		CloseHandle(file);
	}
	else LogError("[SM] ERROR: Config sourcemod/configs/%s.txt does not exist.", configName);
	
	return totalLines;
}