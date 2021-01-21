#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#define PLUGIN_VERSION "0.2"

#define NEO_MAX_PLAYERS 32
#define MAX_CUSTOM_TEAM_NAME_LEN 64

static const String:g_sTag[] = "[MAP PICK]";
static const String:g_sSound_Veto[] = "ui/buttonrollover.wav";
static const String:g_sSound_Pick[] = "ui/buttonclick.wav";
static const String:g_sSound_Results[] = "player/CPcaptured.wav";

#define MAP_VETO_TITLE "MAP PICK"

// Debug flag for forcing all the vetos on the Jinrai team side.
//#define DEBUG_ALL_VETOS_BY_JINRAI

enum VetoStage {
	VETO_STAGE_FIRST_TEAM_BAN = 0,
	VETO_STAGE_SECOND_TEAM_BAN,
	VETO_STAGE_SECOND_TEAM_PICK,
	VETO_STAGE_FIRST_TEAM_PICK,
	VETO_STAGE_RANDOM_THIRD_MAP,
	
	NUM_STAGES
};

// TODO: Move map pool out of code into a config file, and allow any sized map pool.
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
static bool _wants_to_start_veto_jinrai;
static bool _wants_to_start_veto_nsf;

static VetoStage _veto_stage = VETO_STAGE_FIRST_TEAM_BAN;

static int _first_veto_team;

ConVar g_hCvar_JinraiName = null;
ConVar g_hCvar_NsfName = null;

public Plugin myinfo = {
	name = "NT Tournament Map Picker",
	description = "Helper plugin for doing tournament map picks/vetos.",
	author = "Rain",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rainyan/sourcemod-nt-competitive-vetos"
};

// nt_competitive
native bool Competitive_IsLive();

public void OnPluginStart()
{
	// TODO: Currently using a basic Panel approach for some of the maps listing stuff.
	// Refactoring the Panels to Menus would provide pagination support for larger map pools.
#if NUM_MAPS >= 9
#error Pagination of >=9 maps pool is currently unsupported. See code comment at this error for more info.
#endif
	
	CreateConVar("sm_nt_tournament_map_picker_version", PLUGIN_VERSION, "NT Tournament Map Picker plugin version.", FCVAR_DONTRECORD);
	
	RegAdminCmd("sm_vetofirst", Cmd_StartVetoFirst, ADMFLAG_GENERIC, "Admin command to select which team should pick first (skips the coin flip).");
	
	RegConsoleCmd("sm_veto", Cmd_StartVeto, "Start the map picks/vetos.");
	RegConsoleCmd("sm_unveto", Cmd_CancelVeto, "Start the map picks/vetos.");
	
	RegAdminCmd("sm_resetveto", Cmd_ResetVeto, ADMFLAG_GENERIC, "Admin command to reset a veto in progress.");
}

public void OnAllPluginsLoaded()
{
	g_hCvar_JinraiName = FindConVar("sm_competitive_jinrai_name");
	g_hCvar_NsfName = FindConVar("sm_competitive_nsf_name");
	if (g_hCvar_JinraiName == null || g_hCvar_NsfName == null) {
		SetFailState("Failed to look up nt_competitive team name cvars. Is nt_competitive plugin enabled?");
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
	_wants_to_start_veto_jinrai = false;
	_wants_to_start_veto_nsf = false;
	
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
		ReplyToCommand(client, "%s Map picks/veto is already active.", g_sTag);
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	
	if (team <= TEAM_SPECTATOR) {
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
	
	char team_name[MAX_CUSTOM_TEAM_NAME_LEN];
	GetCompetitiveTeamName(team, team_name, sizeof(team_name));
	
	if (team == TEAM_JINRAI) {
		if (_wants_to_start_veto_jinrai) {
			ReplyToCommand(client, "%s Already ready for veto. Please use !unveto if you wish to cancel.", g_sTag);
			return Plugin_Handled;
		}
		else {
			_wants_to_start_veto_jinrai = true;
			PrintToChatAll("%s Team %s is ready to start map picks/veto.", g_sTag, team_name);
		}
	}
	else {
		if (_wants_to_start_veto_nsf) {
			ReplyToCommand(client, "%s Already ready for veto. Please use !unveto if you wish to cancel.", g_sTag);
			return Plugin_Handled;
		}
		else {
			_wants_to_start_veto_nsf = true;
			PrintToChatAll("%s Team %s is ready to start map picks/veto.", g_sTag, team_name);
		}
	}
	
	if (!CheckIfReadyToStartVeto()) {
		char other_team_name[MAX_CUSTOM_TEAM_NAME_LEN];
		GetCompetitiveTeamName(GetOpposingTeam(team), other_team_name, sizeof(other_team_name));
		
		PrintToChatAll("%s Waiting for team %s to confirm with !veto.", g_sTag, other_team_name);
	}
	
	return Plugin_Handled;
}

public Action Cmd_CancelVeto(int client, int argc)
{
	if (client == 0) {
		ReplyToCommand(client, "%s This command cannot be executed by the server.", g_sTag);
		return Plugin_Handled;
	}
	else if (_is_veto_active) {
		ReplyToCommand(client, "%s Map picks/veto is already active.", g_sTag);
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	
	if (team <= TEAM_SPECTATOR) {
		ReplyToCommand(client, "%s Picks can only be initiated by the players.", g_sTag);
		return Plugin_Handled;
	}
	else if (Competitive_IsLive()) {
		ReplyToCommand(client, "%s Match is already live; cannot modify a veto right now.", g_sTag);
		return Plugin_Handled;
	}
	
	char team_name[MAX_CUSTOM_TEAM_NAME_LEN];
	GetCompetitiveTeamName(team, team_name, sizeof(team_name));
	
	if (team == TEAM_JINRAI) {
		if (!_wants_to_start_veto_jinrai) {
			ReplyToCommand(client, "%s Already not ready for veto. Please use !veto if you wish to start a veto.", g_sTag);
			return Plugin_Handled;
		}
		else {
			_wants_to_start_veto_jinrai = false;
			PrintToChatAll("%s Team %s is no longer ready for !veto.", g_sTag, team_name);
		}
	}
	else {
		if (!_wants_to_start_veto_nsf) {
			ReplyToCommand(client, "%s Already not ready for veto. Please use !veto if you wish to start a veto.", g_sTag);
			return Plugin_Handled;
		}
		else {
			_wants_to_start_veto_nsf = false;
			PrintToChatAll("%s Team %s is no longer ready for !veto.", g_sTag, team_name);
		}
	}
	
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
	
	char cmd_name[32];
	GetCmdArg(0, cmd_name, sizeof(cmd_name));
	
	if (argc != 1) {
		ReplyToCommand(client, "%s Usage: %s jinrai/nsf (don't use a team custom name)", g_sTag, cmd_name);
		return Plugin_Handled;
	}
	else if (Competitive_IsLive()) {
		ReplyToCommand(client, "%s Cannot start the veto when the match is live.", g_sTag);
		return Plugin_Handled;
	}
	
	char team_name[7]; // "Jinrai" + '\0'
	GetCmdArg(1, team_name, sizeof(team_name));
	int team_that_goes_first;
	if (StrEqual(team_name, "Jinrai", false)) {
		team_that_goes_first = TEAM_JINRAI;
	}
	else if (StrEqual(team_name, "NSF", false)) {
		team_that_goes_first = TEAM_NSF;
	}
	
	if (team_that_goes_first != TEAM_JINRAI && team_that_goes_first != TEAM_NSF) {
		ReplyToCommand(client, "%s Usage: %s jinrai/nsf", g_sTag, cmd_name);
		return Plugin_Handled;
	}
	
	_wants_to_start_veto_jinrai = true;
	_wants_to_start_veto_nsf = true;
	StartNewVeto(team_that_goes_first);
	
	PrintToChatAll("%s Veto has been manually started by admin (team %s goes first).",
		g_sTag,
		(team_that_goes_first == TEAM_JINRAI) ? "Jinrai" : "NSF"); // Not reusing the name buffer to ensure Nice Capitalization.
	
	return Plugin_Handled;
}

bool CheckIfReadyToStartVeto()
{
	if (_is_veto_active || !_wants_to_start_veto_jinrai || !_wants_to_start_veto_nsf) {
		return false;
	}
	StartNewVeto();
	return true;
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
	
	PrintToChatAll("%s Starting map picks/veto...", g_sTag);
	EmitSoundToAll(g_sSound_Results);
	
	if (team_goes_first == 0) {
		DoCoinFlip();
	}
	else {
		_first_veto_team = team_goes_first;
		CreateTimer(0.1, Timer_StartVeto, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void DoCoinFlip(const int coinflip_stage = 0)
{	
	if (ResetPicksIfShould()) {
		return;
	}
	
	Panel panel = new Panel();
	panel.SetTitle(MAP_VETO_TITLE);
	
	// Characters to represent the "coin flip" spinning around, for some appropriate suspense.
	char coinflip_anim[][] = { "-", "\\", "|", "/" };
	// How many 180 coin flips for the full animation, ie. 3 = 1.5 full rotations.
#define NUM_COINFLIP_ANIMATION_ROTATIONS 3
	
	if (coinflip_stage < sizeof(coinflip_anim) * NUM_COINFLIP_ANIMATION_ROTATIONS) {
		char text[19];
		Format(text, sizeof(text), "Flipping coin... %s", coinflip_anim[coinflip_stage % sizeof(coinflip_anim)]);
		panel.DrawText(" ");
		panel.DrawText(text);
		
		CreateTimer(0.33, Timer_CoinFlip, coinflip_stage + 1, TIMER_FLAG_NO_MAPCHANGE);
	}
	else {
#if defined DEBUG_ALL_VETOS_BY_JINRAI
		_first_veto_team = TEAM_JINRAI;
#else
		SetRandomSeed(GetTime());
		_first_veto_team = GetRandomInt(TEAM_JINRAI, TEAM_NSF);
#endif
		char team_name[MAX_CUSTOM_TEAM_NAME_LEN];
		GetCompetitiveTeamName(_first_veto_team, team_name, sizeof(team_name));
		
		char text[20 + MAX_CUSTOM_TEAM_NAME_LEN];
		// Still adding the "Flipping coin..." part here for visual continuity from the coin flipping stage.
		Format(text, sizeof(text), "Flipping coin... Team %s vetoes first.", team_name);
		
		panel.DrawText(" ");
		panel.DrawText(text);
		
		PrintToConsoleAll("%s %s", g_sTag, text);
		LogToGame("%s %s", g_sTag, text);
		
#define COINFLIP_RESULTS_SHOW_DURATION 5
		CreateTimer(COINFLIP_RESULTS_SHOW_DURATION * 1.0, Timer_StartVeto, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client) || IsFakeClient(client)) {
			continue;
		}
		panel.Send(client, MenuHandler_DoNothing, COINFLIP_RESULTS_SHOW_DURATION);
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
#if defined DEBUG_ALL_VETOS_BY_JINRAI
	picking_team = TEAM_JINRAI;
#endif
	
	if (picking_team != TEAM_JINRAI && picking_team != TEAM_NSF) {
		ThrowError("Invalid team: %d", picking_team);
	}
	
	Menu picker_menu = new Menu(MenuHandler_DoPick);
	Panel spec_panel = new Panel();
	
	spec_panel.SetTitle(MAP_VETO_TITLE);
	spec_panel.DrawText(" ");
	
	char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
	char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
	GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
	GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));
	
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
	
	char buffer[PLATFORM_MAX_PATH + MAX_CUSTOM_TEAM_NAME_LEN + 12];
	for (int i = 0; i < sizeof(_maps); ++i) {
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
	if (action == MenuAction_End) {
		delete menu;
	}
}

// Note that the callback params are guaranteed to actually represent clien & selection only in some MenuActions;
// assuming (action == MenuAction_Select) in this context.
public int MenuHandler_DoPick(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_End) {
		delete menu;
	}
	
	bool veto_was_cancelled = ResetPicksIfShould();
	
	if (!veto_was_cancelled && client > 0 && client <= MaxClients &&
		IsClientInGame(client) && !IsFakeClient(client) && action == MenuAction_Select)
	{
		int client_team = GetClientTeam(client);
		if (client_team == GetPickingTeam()) {
			char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
			char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
			g_hCvar_JinraiName.GetString(jinrai_name, sizeof(jinrai_name));
			g_hCvar_NsfName.GetString(nsf_name, sizeof(nsf_name));
			
			char chosen_map[PLATFORM_MAX_PATH];
			if (!menu.GetItem(selection, chosen_map, sizeof(chosen_map))) {
				ThrowError("Failed to retrieve selection (%d)", selection);
			}
			int map_index = GetChosenMapIndex(chosen_map);
			if (map_index == -1) {
				ThrowError("Couldn't find map: \"%s\"", chosen_map);
			}
			
			char client_name[MAX_NAME_LENGTH];
			GetClientName(client, client_name, sizeof(client_name));
			
			if (_veto_stage == VETO_STAGE_FIRST_TEAM_BAN || _veto_stage == VETO_STAGE_SECOND_TEAM_BAN) {
				_is_vetoed_by[map_index] = client_team;
				
				int other_clients[NEO_MAX_PLAYERS + 1];
				int num_other_clients = GetClientsExceptOne(client, other_clients, sizeof(other_clients));
				EmitSound(other_clients, num_other_clients, g_sSound_Veto);
				
				PrintToChatAll("[VETO] Team %s (player %s) vetoes map: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
				PrintToConsoleAll("[VETO] Team %s (player %s) vetoes map: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
				LogToGame("[VETO] Team %s (player %s) vetoes map: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
			}
			else if (_veto_stage == VETO_STAGE_FIRST_TEAM_PICK || _veto_stage == VETO_STAGE_SECOND_TEAM_PICK) {
				_is_picked_by[map_index] = client_team;
				
				int other_clients[NEO_MAX_PLAYERS + 1];
				int num_other_clients = GetClientsExceptOne(client, other_clients, sizeof(other_clients));
				EmitSound(other_clients, num_other_clients, g_sSound_Pick);
				
				PrintToChatAll("[PICK] Team %s (player %s) picks map: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
				PrintToConsoleAll("[PICK] Team %s (player %s) picks map: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
				LogToGame("[PICK] Team %s (player %s) picks map: %s", (client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
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
#if defined DEBUG_ALL_VETOS_BY_JINRAI
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
#if defined DEBUG_ALL_VETOS_BY_JINRAI
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

void GetCompetitiveTeamName(const int team, char[] out_name, const int max_len)
{
	if (team != TEAM_JINRAI && team != TEAM_NSF) {
		ThrowError("Unexpected team index: %d", team);
	}
	
	GetConVarString((team == TEAM_JINRAI) ? g_hCvar_JinraiName : g_hCvar_NsfName, out_name, max_len);
	
	if (strlen(out_name) == 0) {
		strcopy(out_name, max_len, (team == TEAM_JINRAI) ? "Jinrai" : "NSF");
	}
}