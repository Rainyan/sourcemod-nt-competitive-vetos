#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#define PLUGIN_VERSION "0.1"

#define NEO_MAX_PLAYERS 32

static const String:g_sTag[] = "[MAP PICK]";
static const String:g_sSound_Veto[] = "ui/buttonrollover.wav";
static const String:g_sSound_Pick[] = "ui/buttonclick.wav";
static const String:g_sSound_Results[] = "player/CPcaptured.wav";

#define MAP_VETO_TITLE "MAP PICK"

//#define DEBUG

enum VetoStage {
	VETO_STAGE_FIRST_TEAM_BAN = 0,
	VETO_STAGE_SECOND_TEAM_BAN,
	VETO_STAGE_SECOND_TEAM_PICK,
	VETO_STAGE_FIRST_TEAM_PICK,
	VETO_STAGE_RANDOM_THIRD_MAP,
	
	NUM_STAGES
};

// TODO: config
// TODO: validate map name spelling
#define NUM_MAPS 7
static const String:_maps[NUM_MAPS][] = {
	"nt_ballistrade_ctg",
	"nt_shipment_ctg_comp_rc1",
	"nt_snowfall_ctg_b3",
	"nt_oliostain_ctg_b3",
	"nt_rise_ctg",
	"nt_threadplate_ctg",
	"nt_turmuk_ctg_beta3"
};
static int _is_vetoed_by[NUM_MAPS];
static int _is_picked_by[NUM_MAPS];

static bool _is_veto_active;
static VetoStage _veto_stage = VETO_STAGE_FIRST_TEAM_BAN;
static int _first_veto_team;

ConVar g_hCvar_JinraiName;
ConVar g_hCvar_NsfName;

public Plugin myinfo = {
	name = "NT Tournament Map Picker",
	description = "Helper plugin for doing tournament map picks/vetos.",
	author = "Rain",
	version = PLUGIN_VERSION,
	url = "https://gist.github.com/Rainyan/731f03be5ee0e2b3d018a8b5518c7ea2"
};

// nt_competitive
native bool Competitive_IsLive();

public void OnPluginStart()
{
	CreateConVar("sm_nt_tournament_map_picker_version", PLUGIN_VERSION, "NT Tournament Map Picker plugin version.", FCVAR_DONTRECORD);
	
	RegAdminCmd("sm_vetofirst", Cmd_StartVetoFirst, ADMFLAG_GENERIC, "Admin command to select which team should pick first (skips the coin flip).");
	RegConsoleCmd("sm_veto", Cmd_StartVeto, "Start the map picks/vetos.");
	
	RegAdminCmd("sm_resetveto", Cmd_ResetVeto, ADMFLAG_GENERIC, "Admin command to reset a veto in progress.");
}

public void OnAllPluginsLoaded()
{
	g_hCvar_JinraiName = FindConVar("sm_competitive_jinrai_name");
	g_hCvar_NsfName = FindConVar("sm_competitive_nsf_name");
	if (g_hCvar_JinraiName == null || g_hCvar_NsfName == null) {
		SetFailState("Failed to look up nt_competitive team name cvars");
	}
}

public void OnMapStart()
{
	if (!PrecacheSound(g_sSound_Veto)) {
		SetFailState("Failed to precache sound: \"%s\"", g_sSound_Veto);
	}
	else if (!PrecacheSound(g_sSound_Pick)) {
		SetFailState("Failed to precache sound: \"%s\"", g_sSound_Pick);
	}
	else if (!PrecacheSound(g_sSound_Results)) {
		SetFailState("Failed to precache sound: \"%s\"", g_sSound_Results);
	}
}

public void OnMapEnd()
{
	ClearVeto();
}

public Action Cmd_ResetVeto(int client, int argc)
{
	ClearVeto();
	ReplyToCommand(client, "%s Veto has been reset by admin.", g_sTag);
	return Plugin_Handled;
}

void ClearVeto()
{
	for (int i = 0; i < NUM_MAPS; ++i) {
		_is_vetoed_by[i] = 0;
		_is_picked_by[i] = 0;
	}
	_is_veto_active = false;
	_veto_stage = VETO_STAGE_FIRST_TEAM_BAN;
	_first_veto_team = 0;
}

public Action Cmd_StartVeto(int client, int argc)
{
	if (client == 0) {
		ReplyToCommand(client, "%s This command cannot be executed by the server.", g_sTag);
		return Plugin_Handled;
	}
	else if (_is_veto_active) {
		ReplyToCommand(client, "%s Picks already active.", g_sTag);
		return Plugin_Handled;
	}
	else if (GetClientTeam(client) <= TEAM_SPECTATOR) {
		ReplyToCommand(client, "%s Picks can only be initiated by the players.", g_sTag);
		return Plugin_Handled;
	}
	else if (IsPlayingTeamEmpty()) {
		ReplyToCommand(client, "%s Both teams need to have players in them to start the map picks.", g_sTag);
		return Plugin_Handled;
	}
	else if (Competitive_IsLive()) {
		ReplyToCommand(client, "%s Cannot start the veto when the match is live.", g_sTag);
		return Plugin_Handled;
	}
	
	StartNewVeto();
	
	return Plugin_Handled;
}

public Action Cmd_StartVetoFirst(int client, int argc)
{
	if (_is_veto_active) {
		ReplyToCommand(client, "%s Picks already active. Use !resetveto first.", g_sTag);
		return Plugin_Handled;
	}
	else if (IsPlayingTeamEmpty()) {
		ReplyToCommand(client, "%s Both teams need to have players in them to start the map picks.", g_sTag);
		return Plugin_Handled;
	}
	else if (argc != 1) {
		ReplyToCommand(client, "%s Usage: sm_vetofirst jinrai/nsf", g_sTag);
		return Plugin_Handled;
	}
	else if (Competitive_IsLive()) {
		ReplyToCommand(client, "%s Cannot start the veto when the match is live.", g_sTag);
		return Plugin_Handled;
	}
	
	char team_name[7];
	GetCmdArg(1, team_name, sizeof(team_name));
	int team_that_goes_first;
	if (StrEqual(team_name, "Jinrai", false)) {
		team_that_goes_first = TEAM_JINRAI;
	}
	else if (StrEqual(team_name, "NSF", false)) {
		team_that_goes_first = TEAM_NSF;
	}
	
	if (team_that_goes_first != TEAM_JINRAI && team_that_goes_first != TEAM_NSF) {
		ReplyToCommand(client, "%s Usage: sm_vetofirst jinrai/nsf", g_sTag);
		return Plugin_Handled;
	}
	
	PrintToChatAll("%s Veto has been manually started by admin (%s goes first).", g_sTag, team_name);
	StartNewVeto(team_that_goes_first);
	return Plugin_Handled;
}

void StartNewVeto(int team_goes_first = 0)
{
	if (_is_veto_active) {
		ThrowError("Called while another veto is already active");
	}
	else if (ResetPicksIfShould()) {
		return;
	}
	
	ClearVeto();
	_is_veto_active = true;
	
	if (team_goes_first == 0) {
		DoCoinFlip();
	}
	else {
		_first_veto_team = team_goes_first;
		CreateTimer(0.1, Timer_StartVeto, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void DoCoinFlip(int coinflip_stage = 0)
{	
	if (ResetPicksIfShould()) {
		return;
	}
	
	if (coinflip_stage == 0) {
		EmitSoundToAll(g_sSound_Results);
	}
	
	Panel panel = new Panel();
	panel.SetTitle(MAP_VETO_TITLE);
	
	char coinflip_anim[][] = { "-", "\\", "|", "/" };
	
	if (coinflip_stage < sizeof(coinflip_anim) * 2) {
		char text[19];
		Format(text, sizeof(text), "Flipping coin... %s", coinflip_anim[coinflip_stage % sizeof(coinflip_anim)]);
		panel.DrawText(" ");
		panel.DrawText(text);
		
		CreateTimer(0.33, Timer_CoinFlip, coinflip_stage + 1, TIMER_FLAG_NO_MAPCHANGE);
	}
	else {
#if defined DEBUG
		_first_veto_team = TEAM_JINRAI;
#else
		SetRandomSeed(GetTime());
		_first_veto_team = GetRandomInt(TEAM_JINRAI, TEAM_NSF);
#endif
		char team_name[64];
		
		GetConVarString((_first_veto_team == TEAM_JINRAI) ? g_hCvar_JinraiName : g_hCvar_NsfName, team_name, sizeof(team_name));
		
		char text[20 + 64];
		Format(text, sizeof(text), "Team %s vetoes first.", team_name);
		
		panel.DrawText(text);
		
		CreateTimer(2.0, Timer_StartVeto, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client) || IsFakeClient(client)) {
			continue;
		}
		panel.Send(client, MenuHandler_DoNothing, 2);
	}
	delete panel;
}

public Action Timer_StartVeto(Handle timer)
{
	if (ResetPicksIfShould()) {
		return Plugin_Stop;
	}
	
	CreateTimer(1.0, Timer_ReShowMenu, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action Timer_ReShowMenu(Handle timer)
{
	if (!_is_veto_active) {
		return Plugin_Stop;
	}
	DoVeto();
	return Plugin_Continue;
}

void DoVeto()
{
	if (ResetPicksIfShould()) {
		return;
	}
	
	if (_veto_stage >= VETO_STAGE_RANDOM_THIRD_MAP) {
		int maps[3];
		int num_maps = 0;
		for (int i = 0; i < NUM_MAPS; ++i) {
			if (_is_picked_by[i] == 0 && _is_vetoed_by[i] == 0) {
				maps[num_maps++] = i;
			}
		}
		if (num_maps == 0) {
			ThrowError("Failed to pick random map");
		}
		SetRandomSeed(GetTime());
		int third_map = maps[GetRandomInt(0, num_maps - 1)];
		_is_picked_by[third_map] = TEAM_SPECTATOR;
		
		PrintToChatAll("[PICK] Third map is: %s", _maps[third_map]);
		PrintToConsoleAll("[PICK] Third map is: %s", _maps[third_map]);
		LogToGame("[PICK] Third map is: %s", _maps[third_map]);
		
		AnnounceMaps();
		ClearVeto();
		return;
	}
	
	int picking_team = GetPickingTeam();
	// Stack all the picks to Jinrai for debugging
#if defined DEBUG
	picking_team = TEAM_JINRAI;
#endif
	
	if (picking_team != TEAM_JINRAI && picking_team != TEAM_NSF) {
		ThrowError("Invalid team: %d", picking_team);
	}
	
	Menu picker_menu = new Menu(MenuHandler_DoPick);
	Panel spec_panel = new Panel();
	
	spec_panel.SetTitle(MAP_VETO_TITLE);
	spec_panel.DrawText(" ");
	
	char jinrai_name[64];
	char nsf_name[64];
	g_hCvar_JinraiName.GetString(jinrai_name, sizeof(jinrai_name));
	g_hCvar_NsfName.GetString(nsf_name, sizeof(nsf_name));
	if (strlen(jinrai_name) == 0) {
		strcopy(jinrai_name, sizeof(jinrai_name), "Jinrai");
	}
	if (strlen(nsf_name) == 0) {
		strcopy(nsf_name, sizeof(nsf_name), "NSF");
	}
	
	switch (_veto_stage)
	{
		case VETO_STAGE_FIRST_TEAM_BAN:
		{
			picker_menu.SetTitle("Your team's map VETO:");
			
			spec_panel.DrawText("Waiting for veto by:");
			spec_panel.DrawText((picking_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
		}
		case VETO_STAGE_SECOND_TEAM_BAN:
		{
			picker_menu.SetTitle("Your team's map VETO:");
			
			spec_panel.DrawText("Waiting for veto by:");
			spec_panel.DrawText((picking_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
		}
		case VETO_STAGE_SECOND_TEAM_PICK:
		{
			picker_menu.SetTitle("Your team's map PICK:");
			
			spec_panel.DrawText("Waiting for pick by:");
			spec_panel.DrawText((picking_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
		}
		case VETO_STAGE_FIRST_TEAM_PICK:
		{
			picker_menu.SetTitle("Your team's map PICK:");
			
			spec_panel.DrawText("Waiting for pick by:");
			spec_panel.DrawText((picking_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
		}
	}
	spec_panel.DrawText(" ");
	
	char buffer[128];
	for (int i = 0; i < sizeof(_maps); ++i) {
		if (i >= 9) {
			SetFailState("Pagination of >9 maps pool is unsupported"); // TODO
		}
		
		if (_is_vetoed_by[i] == 0 && _is_picked_by[i] == 0) {
			picker_menu.AddItem(_maps[i], _maps[i], ITEMDRAW_DEFAULT);
			spec_panel.DrawText(_maps[i]);
		}
		else if (_is_vetoed_by[i] != 0) {
			Format(buffer, sizeof(buffer), "%s (VETO of %s)", _maps[i], (_is_vetoed_by[i] == TEAM_JINRAI) ? jinrai_name : nsf_name);
			picker_menu.AddItem("null", buffer, ITEMDRAW_DISABLED);
			spec_panel.DrawText(buffer);
		}
		else if (_is_picked_by[i] != 0) {
			Format(buffer, sizeof(buffer), "%s (PICK of %s)", _maps[i], (_is_picked_by[i] == TEAM_JINRAI) ? jinrai_name : nsf_name);
			picker_menu.AddItem("null", buffer, ITEMDRAW_DISABLED);
			spec_panel.DrawText(buffer);
		}
	}
	
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client) || IsFakeClient(client)) {
			continue;
		}
		
		if (GetClientTeam(client) == picking_team) {
			picker_menu.Display(client, 2);
		}
		else {
			spec_panel.Send(client, MenuHandler_DoNothing, 2);
		}
	}
	delete spec_panel;
}

public Action Timer_CoinFlip(Handle timer, int coinflip_stage)
{
	if (!_is_veto_active || ResetPicksIfShould()) {
		return Plugin_Stop;
	}
	DoCoinFlip(coinflip_stage);
	return Plugin_Stop;
}

public int MenuHandler_DoNothing(Menu menu, MenuAction action, int param1, int param2)
{
	return 0;
}

public int MenuHandler_DoPick(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_End || ResetPicksIfShould()) {
		delete menu;
	}
	else if (client > 0 && client <= MaxClients && IsClientInGame(client) && action == MenuAction_Select) {
		int client_team = GetClientTeam(client);
		if (client_team == GetPickingTeam()) {
			char jinrai_name[64];
			char nsf_name[64];
			g_hCvar_JinraiName.GetString(jinrai_name, sizeof(jinrai_name));
			g_hCvar_NsfName.GetString(nsf_name, sizeof(nsf_name));
			
#if defined DEBUG
			PrintToChatAll("MenuHandler_DoPick: Client %d selected %d", client, selection);
#endif
			char chosen_map[64];
			if (!menu.GetItem(selection, chosen_map, sizeof(chosen_map))) {
				ThrowError("Failed to retrieve selection (%d)", selection);
			}
			int map_index = GetChosenMapIndex(chosen_map);
			if (map_index == -1) {
				ThrowError("Couldn't find map: \"%s\"", chosen_map);
			}
			
			if (_veto_stage == VETO_STAGE_FIRST_TEAM_BAN || _veto_stage == VETO_STAGE_SECOND_TEAM_BAN) {
				_is_vetoed_by[map_index] = client_team;
				
				int other_clients[NEO_MAX_PLAYERS + 1];
				int num_other_clients = GetClientsExceptOne(client, other_clients, sizeof(other_clients));
				EmitSound(other_clients, num_other_clients, g_sSound_Veto);
				
				PrintToChatAll("[VETO] %s vetoes: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, chosen_map);
				PrintToConsoleAll("[VETO] Team %s vetoes: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, chosen_map);
				LogToGame("[VETO] Team %s vetoes: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, chosen_map);
			}
			else if (_veto_stage == VETO_STAGE_FIRST_TEAM_PICK || _veto_stage == VETO_STAGE_SECOND_TEAM_PICK) {
				_is_picked_by[map_index] = client_team;
				
				int other_clients[NEO_MAX_PLAYERS + 1];
				int num_other_clients = GetClientsExceptOne(client, other_clients, sizeof(other_clients));
				EmitSound(other_clients, num_other_clients, g_sSound_Pick);
				
				PrintToChatAll("[PICK] %s picks: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, chosen_map);
				PrintToConsoleAll("[PICK] Team %s picks: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, chosen_map);
				LogToGame("[PICK] Team %s picks: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, chosen_map);
			}
			else {
				ThrowError("Unexpected veto stage: %d", _veto_stage);
			}
			++_veto_stage;
			DoVeto();
		}
	}
}

int GetChosenMapIndex(const char[] map)
{
	for (int i = 0; i < NUM_MAPS; ++i) {
		if (StrEqual(_maps[i], map)) {
			return i;
		}
	}
	return -1;
}

int GetOpposingTeam(int team)
{
#if defined DEBUG
	return TEAM_JINRAI;
#else
	return (team == TEAM_JINRAI) ? TEAM_NSF : TEAM_JINRAI;
#endif
}

int GetPickingTeam()
{
	if (_veto_stage == VETO_STAGE_FIRST_TEAM_BAN || _veto_stage == VETO_STAGE_FIRST_TEAM_PICK) {
		return _first_veto_team;
	}
	if (_veto_stage == VETO_STAGE_SECOND_TEAM_BAN || _veto_stage == VETO_STAGE_SECOND_TEAM_PICK) {
		return GetOpposingTeam(_first_veto_team);
	}
	return 0;
}

bool ResetPicksIfShould()
{
	if (Competitive_IsLive()) {
		PrintToChatAll("%s Game is already live, cancelling pending map picks.", g_sTag);
		PrintToConsoleAll("%s Game is already live, cancelling pending map picks.", g_sTag);
		LogToGame("%s Game is already live, cancelling pending map picks.", g_sTag);
		ClearVeto();
		return true;
	}
	if (IsPlayingTeamEmpty()) {
		PrintToChatAll("%s Team is empty, cancelling map picks.", g_sTag);
		PrintToConsoleAll("%s Team is empty, cancelling map picks.", g_sTag);
		LogToGame("%s Team is empty, cancelling map picks.", g_sTag);
		ClearVeto();
		return true;
	}
	return false;
}

bool IsPlayingTeamEmpty()
{
#if defined DEBUG
	return GetNumPlayersInTeam(TEAM_JINRAI) == 0;
#else
	return GetNumPlayersInTeam(TEAM_JINRAI) == 0 || GetNumPlayersInTeam(TEAM_NSF) == 0;
#endif
}

int GetNumPlayersInTeam(int team)
{
	int num_players = 0;
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client)) {
			continue;
		}
		if (GetClientTeam(client) == team) {
			++num_players;
		}
	}
	return num_players;
}

int GetClientsExceptOne(int excluded_client, int[] out_clients, int max_clients)
{
	int num_clients = 0;
	for (int client = 1; client <= MaxClients; ++client) {
		if (num_clients >= max_clients) {
			break;
		}
		if (!IsClientInGame(client)) {
			continue;
		}
		if (client == excluded_client) {
			continue;
		}
		out_clients[num_clients++] = client;
	}
	return num_clients;
}

void AnnounceMaps()
{
	if (ResetPicksIfShould()) {
		return;
	}
	
	if (_first_veto_team != TEAM_JINRAI && _first_veto_team != TEAM_NSF) {
		ThrowError("Invalid first team: %d", _first_veto_team);
	}
	
	int first_map, second_map, third_map;
	for (int i = 0; i < NUM_MAPS; ++i) {
		if (_is_picked_by[i] == GetOpposingTeam(_first_veto_team)) {
			first_map = i;
		}
		else if (_is_picked_by[i] == _first_veto_team) {
			second_map = i;
		}
		else if (_is_picked_by[i] == TEAM_SPECTATOR) {
			third_map = i;
		}
	}
	
	Panel panel = new Panel();
	
	panel.SetTitle("Map pick results:");
	panel.DrawText(" ");
	
	char jinrai_name[64];
	char nsf_name[64];
	g_hCvar_JinraiName.GetString(jinrai_name, sizeof(jinrai_name));
	g_hCvar_NsfName.GetString(nsf_name, sizeof(nsf_name));
	
	char buffer[128];
	
	PrintToConsoleAll("\n== MAP PICK RESULTS ==");
	LogToGame("\n== MAP PICK RESULTS ==");
	Format(buffer, sizeof(buffer), "Map 1: %s", _maps[first_map]);
	panel.DrawText(buffer);
	PrintToConsoleAll("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
	LogToGame("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
	
	Format(buffer, sizeof(buffer), "Map 2: %s", _maps[second_map]);
	panel.DrawText(buffer);
	PrintToConsoleAll("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? nsf_name: jinrai_name);
	LogToGame("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? nsf_name: jinrai_name);
	
	Format(buffer, sizeof(buffer), "Map 3: %s", _maps[third_map]);
	panel.DrawText(buffer);
	PrintToConsoleAll("  - %s (random pick)\n", buffer);
	LogToGame("  - %s (random pick)\n", buffer);
	
	panel.DrawText(" ");
	panel.DrawItem("Exit");
	
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client) || IsFakeClient(client)) {
			continue;
		}
		panel.Send(client, MenuHandler_DoNothing, MENU_TIME_FOREVER);
	}
	delete panel;
	
	EmitSoundToAll(g_sSound_Results);
	
	CreateTimer(5.0, Timer_MapChangeInfoHelper);
}

public Action Timer_MapChangeInfoHelper(Handle timer)
{
	char[] msg = "[SM] If no admins are present, you can nominate & rtv in chat to change the maps according to the map picks.";
	PrintToChatAll("%s", msg);
	PrintToConsoleAll("%s", msg);
	return Plugin_Stop;
}
