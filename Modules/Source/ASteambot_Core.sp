#include <sourcemod>
#include <sdktools>
#include <socket>
#include <ASteambot>

#pragma dynamic 131072

#define PLUGIN_AUTHOR 	"Arkarr"
#define PLUGIN_VERSION 	"3.0"
#define MODULE_NAME 	"[ASteambot - Core]"

Handle modules;
Handle clientSocket;
Handle CVAR_SteambotServerIP;
Handle CVAR_SteambotServerPort;
Handle CVAR_SteambotTCPPassword;
Handle TimerReconnect;
Handle g_fwdASteambotMessage;

char steambotIP[100];
char steambotPort[10];
char steambotPassword[25];

int moduleID;
int serverID;

bool connected;

public Plugin myinfo = 
{
	name = "[ANY] ASteambot Core", 
	author = PLUGIN_AUTHOR, 
	description = "The core module for ASteambot.", 
	version = PLUGIN_VERSION, 
	url = "http://www.sourcemod.net"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{   
	modules = CreateArray();

	CreateNative("ASteambot_RegisterModule", Native_RegisterModule);
	CreateNative("ASteambot_RemoveModule", Native_RemoveModule);
	CreateNative("ASteambot_IsConnected", Native_IsConnected);
	CreateNative("ASteambot_SendMesssage", Native_SendMesssage);
	CreateNative("ASteambot_CreateTradeOffer", Native_CreateTradeOffer);
	
	RegPluginLibrary("ASteambot");

	return APLRes_Success;
}

//////////////
//  NATIVE  //
//////////////
public Native_RegisterModule(Handle plugin, int numParams)
{
	char mName[40];
	GetNativeString(1, mName, sizeof(mName));
	
	Handle module = CreateArray(30);
	PushArrayCell(module, plugin);
	PushArrayString(module, mName);
	PushArrayCell(module, moduleID);

	PushArrayCell(modules, module);
	
	moduleID++;
	
	return 1;
}

public Native_RemoveModule(Handle plugin, int numParams)
{
	for(int i = 0; i < GetArraySize(modules); i++)
	{
		Handle module = GetArrayCell(modules, i);
		
		if(GetArrayCell(module, 0) == plugin)
		{
			RemoveFromArray(modules, i);
			
			return 1;
		}
	}
	
	return 0;
}

public int Native_IsConnected(Handle plugin, int numParams)
{
	return connected;
}

public int Native_SendMesssage(Handle plugin, int numParams)
{
	char message[950];
	int messageType = GetNativeCell(1);
	GetNativeString(2, message, sizeof(message));
	Handle module = GetModuleByPlugin(plugin);
	
	if(module != INVALID_HANDLE)
		SendMessage(GetArrayCell(module, 2), messageType, message, sizeof(message));
	else
		PrintToServer("%s ERROR: Module not found ! Is it registred?", MODULE_NAME);
}

public int Native_CreateTradeOffer(Handle plugin, int numParams)
{
	char message[9999]; //bad
	
	int client = GetNativeCell(1);
	Handle ItemList = GetNativeCell(2);
	Handle module = GetModuleByPlugin(plugin);
	
	char clientSteamID[40];
	GetClientAuthId(client, AuthId_Steam2, clientSteamID, sizeof(clientSteamID));
	
	Format(message, sizeof(message), "%s/", clientSteamID)
	
	char item[30];
	for (int i = 0; i < GetArraySize(ItemList); i++)
	{
		GetArrayString(ItemList, i, item, sizeof(item));
		
		if(i+1 != GetArraySize(ItemList))
			Format(item, sizeof(item), "%s,", item);
		else
			Format(item, sizeof(item), "%s", item);
			
		StrCat(message, sizeof(message), item);
	}
	
	SendMessage(GetArrayCell(module, 2), AS_CREATE_TRADEOFFER, message, sizeof(message));
}

public void OnPluginStart()
{
	g_fwdASteambotMessage = CreateGlobalForward("ASteambot_Message", ET_Ignore, Param_Cell, Param_String, Param_Cell);

	CVAR_SteambotServerIP = CreateConVar("sm_steambot_server_ip", "XXX.XXX.XXX.XXX", "The ip of the server where the steambot is hosted.");
	CVAR_SteambotServerPort = CreateConVar("sm_steambot_server_port", "4765", "The port of the server where the steambot is hosted, WATCH OUT ! In version 1.0 of the bot, the port is hardcoded and is 11000 !!");
	CVAR_SteambotTCPPassword = CreateConVar("sm_steambot_tcp_password", "XYZ", "The password to allow TCP data to be read / send (TCPPassword in settings.json)");
	
	AutoExecConfig(true, "asteambot_core", "asteambot");
}

public void OnConfigsExecuted()
{
	GetConVarString(CVAR_SteambotServerIP, steambotIP, sizeof(steambotIP));
	GetConVarString(CVAR_SteambotServerPort, steambotPort, sizeof(steambotPort));
	GetConVarString(CVAR_SteambotTCPPassword, steambotPassword, sizeof(steambotPassword));
	
	AttemptSteamBotConnection();
}

public void AttemptSteamBotConnection()
{
	connected = false;
	clientSocket = SocketCreate(SOCKET_TCP, OnClientSocketError);
	PrintToServer("%s - Attempt to connect to %s:%i ...", MODULE_NAME, steambotIP, StringToInt(steambotPort));
	SocketConnect(clientSocket, OnClientSocketConnected, OnChildSocketReceive, OnChildSocketDisconnected, steambotIP, StringToInt(steambotPort));
}

/////////////
// SOCKET  //
/////////////
public OnClientSocketConnected(Handle socket, any arg)
{
	PrintToServer("%s - CONNECTED to the steambot.", MODULE_NAME);
	
	char data[200];
	char map[100];
	
	int pieces[4];
	int longip = GetConVarInt(FindConVar("hostip"));
	
	pieces[0] = (longip >> 24) & 0x000000FF;
	pieces[1] = (longip >> 16) & 0x000000FF;
	pieces[2] = (longip >> 8) & 0x000000FF;
	pieces[3] = longip & 0x000000FF;
	
	Format(data, sizeof(data), "%s-1,-1|%i&%d.%d.%d.%d", steambotPassword, AS_REGISTER_SERVER, pieces[0], pieces[1], pieces[2], pieces[3]);
	
	Format(data, sizeof(data), "%s|%i", data, GetConVarInt(FindConVar("hostport")));
	
	GetHostName(map, sizeof(map));
	Format(data, sizeof(data), "%s|%s<EOF>", data, map);
	
	SocketSend(clientSocket, data, sizeof(data));
	
	EndTimer();
	
	connected = true;
}

public OnClientSocketError(Handle socket, const int errorType, const int errorNum, any ary)
{
	connected = false;
	LogError("%s - socket error %d (errno %d)", MODULE_NAME, errorType, errorNum);
	CloseHandle(socket);
	
	if (TimerReconnect == INVALID_HANDLE)
		TimerReconnect = CreateTimer(10.0, TMR_TryReconnection, _, TIMER_REPEAT);
}

public OnChildSocketReceive(Handle socket, char[] receiveData, const int dataSize, any hFile)
{
	if(StrContains(receiveData, steambotPassword) == -1)
		return;
	
	ReplaceString(receiveData, dataSize, steambotPassword, "");
	ReplaceString(receiveData, dataSize, "<EOF>", "");
	
	char[][] mc_data = new char[2][dataSize];
	char[][] moduleID_code = new char[2][10];
	
	ExplodeString(receiveData, "|", mc_data, 2, dataSize);
	ExplodeString(mc_data[0], ")", moduleID_code, 2, dataSize);

	if(StrEqual(moduleID_code[1], "SRVID"))
	{
		serverID = StringToInt(mc_data[1]);
	}
	else
	{
		if(GetArraySize(modules) != 0)
		{
			int mID = StringToInt(mc_data[0]);
			int code = StringToInt(moduleID_code[1]);
			
			if(mID == -2)
			{
				Call_StartForward(g_fwdASteambotMessage);
				Call_PushCell(code);
				Call_PushString(mc_data[1]);
				Call_PushCell(dataSize);
				Call_Finish();
			}
			else
			{
				Handle module = GetModuleByID(mID);
				if(module != INVALID_HANDLE)
				{
					Call_StartFunction(GetArrayCell(module, 0), GetFunctionByName(GetArrayCell(module, 0), "ASteambot_Message"));
					Call_PushCell(code);
					Call_PushString(mc_data[1]);
					Call_PushCell(dataSize);
					Call_Finish();
				}
			}
		}		
	}
}

public Handle GetModuleByPlugin(Handle plugin)
{
	for(int i = 0; i < GetArraySize(modules); i++)
	{
		Handle module = GetArrayCell(modules, i);
		
		if(GetArrayCell(module, 0) == plugin)
			return module;
	}
	
	return INVALID_HANDLE;
}

public Handle GetModuleByID(int id)
{
	for(int i = 0; i < GetArraySize(modules); i++)
	{
		Handle module = GetArrayCell(modules, i);
		
		if(GetArrayCell(module, 2) == id)
			return module;
	}
	
	return INVALID_HANDLE;
}

public OnChildSocketDisconnected(Handle socket, any hFile)
{
	PrintToServer("%s - DISCONNECTED to the steambot.", MODULE_NAME);
	connected = false;
	CloseHandle(socket);
	
	if(TimerReconnect == INVALID_HANDLE)
		TimerReconnect = CreateTimer(10.0, TMR_TryReconnection, _, TIMER_REPEAT);
}

///////////
// TIMER //
///////////
public Action TMR_TryReconnection(Handle timer, any none)
{
	AttemptSteamBotConnection();
}

///////////
// STOCK //
///////////
stock void SendMessage(int mid, int messageType, char[] message, int msgSize)
{
	Format(message, msgSize, "%s%i,%i|%i&%s<EOF>", steambotPassword, serverID, mid, messageType, message);
	
	SocketSend(clientSocket, message, msgSize);
}

public void EndTimer()
{
	if (TimerReconnect != INVALID_HANDLE)
	{
		KillTimer(TimerReconnect);
		TimerReconnect = INVALID_HANDLE;
	}
}

stock void GetHostName(char[] str, size)
{
	Handle hHostName;
	
	if (hHostName == INVALID_HANDLE)
		if ((hHostName = FindConVar("hostname")) == INVALID_HANDLE)
		return;
	
	GetConVarString(hHostName, str, size);
} 